// Claude API proxy for the SYNAPSE-2076 web build, deployed as a Cloudflare Worker.
//
// It is the game's shared LLM backend: every copy of the web build sends its
// requests here, and the Worker adds the Anthropic API key (a secret), picks the
// model and keeps a daily request budget. GitHub Pages is public static hosting,
// so the web build can never carry the key itself. Anyone who reads the web
// build can find this URL, so the Worker defends itself with an origin
// allowlist, an optional access code, a model allowlist, a max_tokens cap,
// request-shape limits, a per-minute rate limit and daily request limits.
// See ../README.md for the security model and deployment.
//
// It never logs request bodies, API keys or access codes.

const UPSTREAM = "https://api.anthropic.com";
const ANTHROPIC_VERSION = "2023-06-01";

const MAX_BODY_BYTES = 64 * 1024;
// A "Call the ..." negotiation sends its whole conversation: up to six player
// messages and the replies between them.
const MAX_MESSAGES = 16;
const MESSAGE_ROLES = new Set(["user", "assistant"]);
const MAX_PROMPT_CHARS = 48_000;
const MAX_JSON_DEPTH = 32;
// The game asks for 2048: Claude's adaptive thinking counts toward max_tokens.
const DEFAULT_MAX_TOKENS_CAP = 2048;
// output_config may only carry a thinking effort, and not the expensive levels.
const ALLOWED_EFFORTS = new Set(["low", "medium", "high"]);
// Models that answer output_config.effort with a 400; the proxy drops the field for them.
const NO_EFFORT_PREFIXES = ["claude-haiku", "claude-3", "claude-instant", "claude-2"];
const NO_EFFORT_MODELS = ["claude-sonnet-4", "claude-sonnet-4-5", "claude-opus-4", "claude-opus-4-1"];
// Requests per UTC day. A full 100-turn campaign sends about 330 (three faction
// decisions a turn plus the crisis writer). "0" switches a limit off.
const DEFAULT_DAILY_REQUESTS = 1000;
const DEFAULT_DAILY_REQUESTS_PER_PLAYER = 400;
// The one UsageMeter instance that counts every request.
const METER_NAME = "global";
const METER_URL = "https://usage-meter.internal/check";

// Top-level Messages API fields that reach Anthropic. Everything else (tools,
// stream, thinking, mcp_servers, container, ...) is dropped.
const FORWARDED_FIELDS = [
  "model",
  "max_tokens",
  "system",
  "messages",
  "temperature",
  "top_p",
  "top_k",
  "stop_sequences",
  "metadata",
  "output_config",
];

const CORS_ALLOW_METHODS = "GET, POST, OPTIONS";
const CORS_ALLOW_HEADERS =
  "content-type, x-api-key, anthropic-version, anthropic-dangerous-direct-browser-access, authorization";
const CORS_MAX_AGE = "600";

// Upstream response headers passed on to the client. The rest (organization
// id, rate-limit details, cookies) stay with the proxy.
const RELAYED_RESPONSE_HEADERS = ["request-id", "retry-after"];

const ROUTES = new Map([
  ["/", { method: "GET", api: false }],
  ["/v1/models", { method: "GET", api: true }],
  ["/v1/messages", { method: "POST", api: true }],
]);

export default {
  async fetch(request, env, _ctx) {
    const config = readConfig(env ?? {});
    const origin = request.headers.get("Origin");
    // Browsers always send the serialized origin, so an exact match is enough.
    const corsOrigin = origin !== null && config.allowedOrigins.has(origin) ? origin : null;
    try {
      return await route(request, config, origin, corsOrigin);
    } catch (err) {
      console.error(`synapse-llm-proxy: unexpected ${err?.name ?? "error"}`);
      return errorResponse(500, "The proxy failed unexpectedly.", corsOrigin);
    }
  },
};

async function route(request, config, origin, corsOrigin) {
  if (request.method === "OPTIONS") {
    return preflight(origin, corsOrigin);
  }
  // A page on a site outside ALLOWED_ORIGINS. Scripts can forge Origin, so this
  // only stops other websites from using the proxy through their visitors.
  if (origin !== null && corsOrigin === null) {
    return errorResponse(403, "This origin is not allowed to use the proxy.", null);
  }

  const { pathname } = new URL(request.url);
  const spec = ROUTES.get(pathname);
  if (!spec) {
    return errorResponse(404, "Not found. The proxy serves GET /v1/models and POST /v1/messages.", corsOrigin);
  }
  if (request.method !== spec.method) {
    return errorResponse(405, `Use ${spec.method} for ${pathname}.`, corsOrigin, {
      allow: `${spec.method}, OPTIONS`,
    });
  }
  // Rate limiting runs before the access-code check so that guessing codes is throttled too.
  const throttled = await rateLimit(request, config, corsOrigin);
  if (throttled) {
    return throttled;
  }
  if (!spec.api) {
    return health(config, corsOrigin);
  }
  const denied = await authenticate(request, config, origin, corsOrigin);
  if (denied) {
    return denied;
  }
  if (!config.apiKey) {
    return errorResponse(
      500,
      "The proxy has no Anthropic API key. The operator must set the ANTHROPIC_API_KEY secret (npx wrangler secret put ANTHROPIC_API_KEY).",
      corsOrigin,
    );
  }
  return pathname === "/v1/models"
    ? listModels(request, config, corsOrigin)
    : createMessage(request, config, corsOrigin);
}

// The UTC day ("2026-10-05") that the daily limits count, and the seconds until the next one.
function utcDay(now) {
  return new Date(now).toISOString().slice(0, 10);
}

function secondsUntilNextDay(now) {
  const date = new Date(now);
  const midnight = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1);
  return Math.max(1, Math.ceil((midnight - now) / 1000));
}

// A player is a client IP address, hashed with the day so that the meter never
// stores an address and yesterday's entries cannot be linked to today's.
async function playerKey(request, day) {
  const ip = request.headers.get("CF-Connecting-IP");
  if (!ip) {
    return "anon";
  }
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${day}|${ip}`));
  return [...new Uint8Array(digest).slice(0, 12)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function limitsOn(config) {
  return config.dailyRequests > 0 || config.dailyRequestsPerPlayer > 0;
}

// Asks the UsageMeter whether today's limits leave room for one more request
// and, when `count` is true, counts it. Returns null when the request may go
// ahead, otherwise the response to send instead (429 once a limit is reached).
async function checkUsage(request, config, corsOrigin, count) {
  if (!limitsOn(config)) {
    return null;
  }
  const now = Date.now();
  const day = utcDay(now);
  const answer = await askMeter(config, {
    day,
    player: await playerKey(request, day),
    dailyLimit: config.dailyRequests,
    playerLimit: config.dailyRequestsPerPlayer,
    count,
  });
  if (answer.error) {
    return answer.error(corsOrigin);
  }
  if (answer.allowed) {
    return null;
  }
  const message =
    answer.limit === "daily"
      ? "The game's shared LLM has used today's request budget. It starts again at 00:00 UTC."
      : "This player has used today's share of the game's shared LLM. It starts again at 00:00 UTC.";
  return errorResponse(429, message, corsOrigin, { "retry-after": String(secondsUntilNextDay(now)) }, {
    limit: answer.limit,
  });
}

// Returns the meter's answer ({allowed, limit, total, player}) or {error: (corsOrigin) => Response}.
async function askMeter(config, question) {
  const namespace = config.usage;
  if (!namespace || typeof namespace.idFromName !== "function") {
    return {
      error: (corsOrigin) =>
        errorResponse(
          500,
          "Daily limits are set (DAILY_REQUESTS, DAILY_REQUESTS_PER_PLAYER) but the USAGE Durable Object binding is missing. Deploy with proxy/wrangler.toml, or set both limits to 0.",
          corsOrigin,
        ),
    };
  }
  try {
    const meter = namespace.get(namespace.idFromName(METER_NAME));
    const response = await meter.fetch(METER_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(question),
    });
    if (!response.ok) {
      throw new Error(`meter answered HTTP ${response.status}`);
    }
    const answer = await response.json();
    if (typeof answer?.allowed !== "boolean") {
      throw new Error("meter answer without allowed");
    }
    return answer;
  } catch (err) {
    console.error(`synapse-llm-proxy: usage meter failed (${err?.name ?? "error"})`);
    // Fails closed: without the count, the budget cannot be kept.
    return {
      error: (corsOrigin) =>
        errorResponse(503, "The proxy could not check today's usage. Try again shortly.", corsOrigin, {
          "retry-after": "60",
        }),
    };
  }
}

// Counts the requests of one UTC day for the whole proxy: one instance
// (idFromName("global")) holds "day", "total" and a "p:<player>" count per
// player, and drops them all when the day changes. A Durable Object handles one
// event at a time and holds new ones while it waits on storage, so reading and
// writing a count cannot interleave with another request.
export class UsageMeter {
  constructor(state, _env) {
    this.storage = state.storage;
  }

  async fetch(request) {
    let question;
    try {
      question = await request.json();
    } catch {
      return new Response(JSON.stringify({ error: "the body must be JSON" }), { status: 400 });
    }
    if (!isPlainObject(question) || typeof question.day !== "string" || typeof question.player !== "string") {
      return new Response(JSON.stringify({ error: "day and player are required" }), { status: 400 });
    }
    const answer = await this.check(question);
    return new Response(JSON.stringify(answer), { headers: { "content-type": "application/json" } });
  }

  async check({ day, player, dailyLimit = 0, playerLimit = 0, count = false }) {
    if ((await this.storage.get("day")) !== day) {
      await this.storage.deleteAll();
      await this.storage.put("day", day);
    }
    const key = `p:${player}`;
    const total = (await this.storage.get("total")) ?? 0;
    const mine = (await this.storage.get(key)) ?? 0;
    let limit = null;
    if (dailyLimit > 0 && total >= dailyLimit) {
      limit = "daily";
    } else if (playerLimit > 0 && mine >= playerLimit) {
      limit = "player";
    }
    if (limit === null && count) {
      await this.storage.put({ total: total + 1, [key]: mine + 1 });
      return { allowed: true, limit, total: total + 1, player: mine + 1 };
    }
    return { allowed: limit === null, limit, total, player: mine };
  }
}

function preflight(origin, corsOrigin) {
  if (corsOrigin) {
    return new Response(null, { status: 204, headers: baseHeaders(corsOrigin) });
  }
  if (origin !== null) {
    return errorResponse(403, "This origin is not allowed to use the proxy.", null);
  }
  // Plain OPTIONS from a non-browser client: describe the methods, nothing else.
  const headers = baseHeaders(null);
  headers.set("allow", CORS_ALLOW_METHODS);
  return new Response(null, { status: 204, headers });
}

async function health(config, corsOrigin) {
  const lines = [
    "synapse-llm-proxy is running.",
    `Access code required: ${config.accessCode === null ? "no" : "yes"}.`,
    `Anthropic API key configured: ${config.apiKey ? "yes" : "no"}.`,
    config.defaultModel
      ? `Model: ${config.defaultModel} (for requests that name none; allowed: ${[...config.allowedModels].join(", ")}).`
      : "Model: none (ALLOWED_MODELS is empty).",
  ];
  if (limitsOn(config)) {
    const shown = (limit) => (limit > 0 ? String(limit) : "no limit");
    lines.push(
      `Daily limits (UTC): ${shown(config.dailyRequests)} requests for everyone, ${shown(config.dailyRequestsPerPlayer)} per player.`,
    );
    const answer = await askMeter(config, { day: utcDay(Date.now()), player: "health", count: false });
    lines.push(answer.error ? "Used today: unknown (the usage meter is unavailable)." : `Used today: ${answer.total} requests.`);
  } else {
    lines.push("Daily limits: none.");
  }
  lines.push("Endpoints: GET /v1/models, POST /v1/messages.");
  const headers = baseHeaders(corsOrigin);
  headers.set("content-type", "text/plain; charset=utf-8");
  return new Response(`${lines.join("\n")}\n`, { status: 200, headers });
}

async function rateLimit(request, config, corsOrigin) {
  const limiter = config.rateLimiter;
  if (!limiter || typeof limiter.limit !== "function") {
    return null;
  }
  const key = request.headers.get("CF-Connecting-IP") || "anon";
  const { success } = await limiter.limit({ key });
  return success
    ? null
    : errorResponse(429, "Too many requests. Wait a minute and try again.", corsOrigin, { "retry-after": "60" }, {
        limit: "minute",
      });
}

async function authenticate(request, config, origin, corsOrigin) {
  if (config.accessCode === null) {
    if (origin === null) {
      return errorResponse(
        403,
        "Requests without an Origin header need an access code, and this proxy has none configured.",
        null,
      );
    }
    return null;
  }
  if (await presentsAccessCode(request, config.accessCode)) {
    return null;
  }
  return errorResponse(401, "Missing or wrong access code. Send it in the x-api-key header.", corsOrigin);
}

async function presentsAccessCode(request, expected) {
  const candidates = [];
  const apiKey = request.headers.get("x-api-key");
  if (apiKey) {
    candidates.push(apiKey.trim());
  }
  const bearer = /^bearer\s+(.+)$/i.exec((request.headers.get("authorization") ?? "").trim());
  if (bearer) {
    candidates.push(bearer[1].trim());
  }
  let matched = false;
  for (const candidate of candidates) {
    // An empty candidate never matches, even when the configured code trims to "".
    if (candidate !== "" && (await sameText(candidate, expected))) {
      matched = true;
    }
  }
  return matched;
}

// Constant-time comparison: hash both sides so neither the content nor the
// length of the access code leaks through timing.
async function sameText(a, b) {
  const encoder = new TextEncoder();
  const [hashA, hashB] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(a)),
    crypto.subtle.digest("SHA-256", encoder.encode(b)),
  ]);
  const x = new Uint8Array(hashA);
  const y = new Uint8Array(hashB);
  let diff = 0;
  for (let i = 0; i < x.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff === 0;
}

// The model list a client sees: the one model the proxy uses for requests that
// name none, looked up with the real key, so this doubles as the game's
// connection check (a bad key, a retired model or a spent budget fail it).
async function listModels(request, config, corsOrigin) {
  const model = config.defaultModel;
  if (!model) {
    return errorResponse(
      500,
      "This proxy has no allowed models configured (ALLOWED_MODELS is empty), so it rejects every request.",
      corsOrigin,
    );
  }
  const spent = await checkUsage(request, config, corsOrigin, false);
  if (spent) {
    return spent;
  }
  const target = new URL(`/v1/models/${encodeURIComponent(model)}`, UPSTREAM);
  const response = await forward(target, { method: "GET", headers: upstreamHeaders(config, false) }, corsOrigin);
  if (response.status === 404) {
    await response.body?.cancel().catch(() => {});
    return errorResponse(
      500,
      `The proxy's model ${model} is not available to its API key. The operator must fix ALLOWED_MODELS.`,
      corsOrigin,
    );
  }
  if (response.status !== 200) {
    return response;
  }
  let info;
  try {
    info = await response.json();
  } catch {
    return errorResponse(502, "The Anthropic API answered the model lookup with invalid JSON.", corsOrigin);
  }
  const id = isPlainObject(info) && typeof info.id === "string" ? info.id : model;
  const entry = isPlainObject(info) ? { ...info, id } : { id, type: "model" };
  const headers = new Headers(response.headers);
  return new Response(JSON.stringify({ data: [entry], has_more: false, first_id: id, last_id: id }), {
    status: 200,
    headers,
  });
}

async function createMessage(request, config, corsOrigin) {
  if (Number(request.headers.get("content-length")) > MAX_BODY_BYTES) {
    return errorResponse(413, `The request body is larger than ${MAX_BODY_BYTES} bytes.`, corsOrigin);
  }
  const bytes = await readBody(request, MAX_BODY_BYTES);
  if (bytes === null) {
    return errorResponse(413, `The request body is larger than ${MAX_BODY_BYTES} bytes.`, corsOrigin);
  }
  let body;
  try {
    body = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return errorResponse(400, "The request body is not valid JSON.", corsOrigin);
  }
  if (!isPlainObject(body)) {
    return errorResponse(400, "The request body must be a JSON object.", corsOrigin);
  }

  if (config.allowedModels.size === 0) {
    return errorResponse(
      400,
      "This proxy has no allowed models configured (ALLOWED_MODELS is empty), so it rejects every request.",
      corsOrigin,
    );
  }
  // The backend picks the model: a request that names none gets the first allowed one.
  const model = body.model === undefined || body.model === null || body.model === "" ? config.defaultModel : body.model;
  if (typeof model !== "string" || !config.allowedModels.has(model)) {
    const shown = typeof model === "string" ? JSON.stringify(model.slice(0, 100)) : typeof model;
    return errorResponse(
      400,
      `model: ${shown} is not allowed by this proxy. Allowed: ${[...config.allowedModels].join(", ")}.`,
      corsOrigin,
    );
  }
  const { messages } = body;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
    return errorResponse(400, `messages: must be a non-empty array of at most ${MAX_MESSAGES} entries.`, corsOrigin);
  }
  if (!messages.every(isPlainObject)) {
    return errorResponse(400, "messages: every entry must be an object.", corsOrigin);
  }
  const badRole = messages.findIndex((message) => !MESSAGE_ROLES.has(message.role));
  if (badRole !== -1) {
    return errorResponse(400, `messages.${badRole}.role: must be "user" or "assistant".`, corsOrigin);
  }
  // Text only. Image and document blocks (URL, file or base64 sources) can pull in far
  // more tokens than the character cap below accounts for.
  if (body.system !== undefined && !isTextContent(body.system)) {
    return errorResponse(400, "system: only text is allowed through this proxy (a string or text blocks).", corsOrigin);
  }
  const nonText = messages.findIndex((message) => !isTextContent(message.content));
  if (nonText !== -1) {
    return errorResponse(
      400,
      `messages.${nonText}.content: only text is allowed through this proxy (a string or text blocks).`,
      corsOrigin,
    );
  }

  if (body.output_config !== undefined && !isEffortOnly(body.output_config)) {
    return errorResponse(
      400,
      'output_config: only {"effort": "low" | "medium" | "high"} is allowed through this proxy.',
      corsOrigin,
    );
  }

  const forwarded = pickFields(body, config.maxTokensCap);
  forwarded.model = model;
  // The client may not know which model it gets, so an effort the model cannot take is dropped here.
  if (forwarded.output_config !== undefined && !supportsEffort(model)) {
    delete forwarded.output_config;
  }
  if (nestedTooDeep(forwarded)) {
    return errorResponse(400, "The request JSON is nested too deeply.", corsOrigin);
  }
  const chars = textChars(forwarded.system) + messages.reduce((sum, message) => sum + textChars(message.content), 0);
  if (chars > MAX_PROMPT_CHARS) {
    return errorResponse(
      413,
      `system and messages hold ${chars} characters; the proxy allows ${MAX_PROMPT_CHARS}.`,
      corsOrigin,
    );
  }

  // Counted last, so that a request the proxy turns away never uses up the budget.
  const spent = await checkUsage(request, config, corsOrigin, true);
  if (spent) {
    return spent;
  }

  return forward(
    new URL("/v1/messages", UPSTREAM),
    { method: "POST", headers: upstreamHeaders(config, true), body: JSON.stringify(forwarded) },
    corsOrigin,
  );
}

function pickFields(body, maxTokensCap) {
  const out = {};
  for (const field of FORWARDED_FIELDS) {
    if (Object.hasOwn(body, field)) {
      out[field] = body[field];
    }
  }
  const requested = body.max_tokens;
  out.max_tokens =
    Number.isInteger(requested) && requested > 0 ? Math.min(requested, maxTokensCap) : maxTokensCap;
  return out;
}

// Characters of text in content that already passed isTextContent (or is absent).
function textChars(content) {
  if (typeof content === "string") {
    return content.length;
  }
  return Array.isArray(content) ? content.reduce((sum, block) => sum + block.text.length, 0) : 0;
}

// True when `value` nests deeper than MAX_JSON_DEPTH. Iterative, so hostile input
// cannot overflow the stack here or later in JSON.stringify.
function nestedTooDeep(value) {
  const stack = [[value, 0]];
  while (stack.length > 0) {
    const [item, depth] = stack.pop();
    if (item !== null && typeof item === "object") {
      if (depth >= MAX_JSON_DEPTH) {
        return true;
      }
      for (const child of Object.values(item)) {
        stack.push([child, depth + 1]);
      }
    }
  }
  return false;
}

// Reads at most `limit` bytes. Returns null when the body is larger, without
// buffering the rest, so a missing or false Content-Length cannot get around the cap.
async function readBody(request, limit) {
  if (!request.body) {
    return new Uint8Array(0);
  }
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel().catch(() => {});
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function upstreamHeaders(config, withBody) {
  // Built from scratch: no client header (cookies, the access code, ...) ever reaches Anthropic.
  const headers = { "x-api-key": config.apiKey, "anthropic-version": ANTHROPIC_VERSION };
  if (withBody) {
    headers["content-type"] = "application/json";
  }
  return headers;
}

async function forward(url, init, corsOrigin) {
  let upstream;
  try {
    // "manual" so a redirect can never carry the API key to another host.
    upstream = await fetch(url.toString(), { ...init, redirect: "manual" });
  } catch (err) {
    console.error(`synapse-llm-proxy: upstream request failed (${err?.name ?? "error"})`);
    return errorResponse(502, "The proxy could not reach the Anthropic API. Try again shortly.", corsOrigin);
  }

  const relayed = {};
  for (const name of RELAYED_RESPONSE_HEADERS) {
    const value = upstream.headers.get(name);
    if (value) {
      relayed[name] = value;
    }
  }
  const contentType = upstream.headers.get("content-type") ?? "";
  const isRedirect = upstream.status >= 300 && upstream.status < 400;
  if (isRedirect || !/\bjson\b/i.test(contentType)) {
    // Not an Anthropic JSON answer (for example an HTML error page from a network in between).
    await upstream.body?.cancel().catch(() => {});
    const status = upstream.status >= 400 ? upstream.status : 502;
    return errorResponse(
      status,
      `The Anthropic API answered HTTP ${upstream.status} without a JSON body.`,
      corsOrigin,
      relayed,
    );
  }

  const headers = baseHeaders(corsOrigin);
  for (const [name, value] of Object.entries(relayed)) {
    headers.set(name, value);
  }
  headers.set("content-type", contentType);
  return new Response(upstream.body, { status: upstream.status, headers });
}

function baseHeaders(corsOrigin) {
  const headers = new Headers({
    "cache-control": "no-store",
    vary: "Origin",
    "x-content-type-options": "nosniff",
  });
  if (corsOrigin) {
    headers.set("access-control-allow-origin", corsOrigin);
    headers.set("access-control-allow-methods", CORS_ALLOW_METHODS);
    headers.set("access-control-allow-headers", CORS_ALLOW_HEADERS);
    headers.set("access-control-max-age", CORS_MAX_AGE);
  }
  return headers;
}

// Every error the proxy itself produces uses Anthropic's error shape, so the
// game handles proxy and API errors the same way. A 429 from the proxy adds
// error.limit: "minute", "daily" (everyone) or "player".
function errorResponse(status, message, corsOrigin, extraHeaders = {}, extraFields = {}) {
  const headers = baseHeaders(corsOrigin);
  for (const [name, value] of Object.entries(extraHeaders)) {
    headers.set(name, value);
  }
  headers.set("content-type", "application/json");
  const body = { type: "error", error: { type: errorType(status), message, ...extraFields } };
  return new Response(JSON.stringify(body), { status, headers });
}

function errorType(status) {
  switch (status) {
    case 400:
      return "invalid_request_error";
    case 401:
      return "authentication_error";
    case 402:
      return "billing_error";
    case 403:
      return "permission_error";
    case 404:
      return "not_found_error";
    case 413:
      return "request_too_large";
    case 429:
      return "rate_limit_error";
    case 529:
      return "overloaded_error";
    default:
      return status >= 500 ? "api_error" : "invalid_request_error";
  }
}

function readConfig(env) {
  const rawAccessCode = typeof env.ACCESS_CODE === "string" ? env.ACCESS_CODE : "";
  const allowedModels = new Set(splitList(env.ALLOWED_MODELS));
  return {
    apiKey: typeof env.ANTHROPIC_API_KEY === "string" ? env.ANTHROPIC_API_KEY.trim() : "",
    // Empty means no access code. A whitespace-only code stays required and matches nothing (fails closed).
    accessCode: rawAccessCode === "" ? null : rawAccessCode.trim(),
    allowedOrigins: new Set(splitList(env.ALLOWED_ORIGINS).map(canonicalOrigin).filter(Boolean)),
    allowedModels,
    // The first allowed model serves the requests that name none.
    defaultModel: allowedModels.size > 0 ? [...allowedModels][0] : null,
    maxTokensCap: parseMaxTokensCap(env.MAX_TOKENS_CAP),
    dailyRequests: parseDailyLimit(env.DAILY_REQUESTS, DEFAULT_DAILY_REQUESTS),
    dailyRequestsPerPlayer: parseDailyLimit(env.DAILY_REQUESTS_PER_PLAYER, DEFAULT_DAILY_REQUESTS_PER_PLAYER),
    rateLimiter: env.RATE_LIMITER,
    usage: env.USAGE,
  };
}

function splitList(value) {
  if (value === undefined || value === null) {
    return [];
  }
  return String(value)
    .split(/[\s,]+/)
    .filter((entry) => entry !== "");
}

// "https://Example.github.io/repo/" -> "https://example.github.io"; anything that is not an http(s) URL is ignored.
function canonicalOrigin(entry) {
  try {
    const url = new URL(entry);
    return url.protocol === "https:" || url.protocol === "http:" ? url.origin : null;
  } catch {
    return null;
  }
}

function parseMaxTokensCap(value) {
  const text = value === undefined || value === null ? "" : String(value).trim();
  return /^[1-9][0-9]{0,6}$/.test(text) ? Number(text) : DEFAULT_MAX_TOKENS_CAP;
}

// A whole number of requests; "0" switches the limit off. Anything unreadable
// keeps the default rather than lifting the limit.
function parseDailyLimit(value, fallback) {
  const text = value === undefined || value === null ? "" : String(value).trim();
  return /^(0|[1-9][0-9]{0,8})$/.test(text) ? Number(text) : fallback;
}

// Whether `model` accepts output_config.effort. Haiku 4.5 and the Claude 3 /
// early Claude 4 models answer it with a 400 (LLMService.supports_effort in the
// game holds the same list).
function supportsEffort(model) {
  const id = model.trim().toLowerCase();
  if (NO_EFFORT_PREFIXES.some((prefix) => id.startsWith(prefix))) {
    return false;
  }
  // Exact ids, or the id plus an 8-digit snapshot date ("claude-sonnet-4-5-20250929").
  return !NO_EFFORT_MODELS.some((older) => id === older || (id.startsWith(`${older}-`) && /^\d{8}$/.test(id.slice(older.length + 1))));
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

// {"effort": "low" | "medium" | "high"} and nothing else.
function isEffortOnly(value) {
  return isPlainObject(value) && Object.keys(value).length === 1 && ALLOWED_EFFORTS.has(value.effort);
}

// A string, or an array of {"type": "text", "text": "..."} blocks.
function isTextContent(value) {
  if (typeof value === "string") {
    return true;
  }
  return (
    Array.isArray(value) &&
    value.every((block) => isPlainObject(block) && block.type === "text" && typeof block.text === "string")
  );
}
