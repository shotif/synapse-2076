// Claude API proxy for the SYNAPSE-2076 web build, deployed as a Cloudflare Worker.
//
// GitHub Pages is public static hosting, so the web build can never carry an
// Anthropic API key. This Worker keeps the key as a secret and forwards a narrow
// slice of the Messages API. Anyone who reads the web build can find this URL,
// so the Worker defends itself with an origin allowlist, an optional access
// code, a model allowlist, a max_tokens cap and request-shape limits.
// See ../README.md for the security model and deployment.
//
// It never logs request bodies, API keys or access codes.

const UPSTREAM = "https://api.anthropic.com";
const ANTHROPIC_VERSION = "2023-06-01";

const MAX_BODY_BYTES = 64 * 1024;
const MAX_MESSAGES = 8;
const MAX_PROMPT_CHARS = 48_000;
const MAX_JSON_DEPTH = 32;
const DEFAULT_MAX_TOKENS_CAP = 1024;

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
  if (!spec.api) {
    return health(config, corsOrigin);
  }

  // Rate limiting runs before the access-code check so that guessing codes is throttled too.
  const denied =
    (await rateLimit(request, config, corsOrigin)) ?? (await authenticate(request, config, origin, corsOrigin));
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

function health(config, corsOrigin) {
  const text = [
    "synapse-llm-proxy is running.",
    `Access code required: ${config.accessCode === null ? "no" : "yes"}.`,
    `Anthropic API key configured: ${config.apiKey ? "yes" : "no"}.`,
    "Endpoints: GET /v1/models, POST /v1/messages.",
  ].join("\n");
  const headers = baseHeaders(corsOrigin);
  headers.set("content-type", "text/plain; charset=utf-8");
  return new Response(`${text}\n`, { status: 200, headers });
}

async function rateLimit(request, config, corsOrigin) {
  const limiter = config.rateLimiter;
  if (!limiter || typeof limiter.limit !== "function") {
    return null;
  }
  const key = request.headers.get("CF-Connecting-IP") || "anon";
  const { success } = await limiter.limit({ key });
  return success ? null : errorResponse(429, "Too many requests. Wait a minute and try again.", corsOrigin);
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

function listModels(request, config, corsOrigin) {
  const target = new URL("/v1/models", UPSTREAM);
  const query = new URL(request.url).searchParams;
  for (const name of ["limit", "after_id", "before_id"]) {
    const value = query.get(name);
    if (value && /^[A-Za-z0-9._:-]{1,128}$/.test(value)) {
      target.searchParams.set(name, value);
    }
  }
  return forward(target, { method: "GET", headers: upstreamHeaders(config, false) }, corsOrigin);
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
  if (typeof body.model !== "string" || !config.allowedModels.has(body.model)) {
    const shown = typeof body.model === "string" ? JSON.stringify(body.model.slice(0, 100)) : "missing";
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

  const forwarded = pickFields(body, config.maxTokensCap);
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
// game handles proxy and API errors the same way.
function errorResponse(status, message, corsOrigin, extraHeaders = {}) {
  const headers = baseHeaders(corsOrigin);
  for (const [name, value] of Object.entries(extraHeaders)) {
    headers.set(name, value);
  }
  headers.set("content-type", "application/json");
  const body = { type: "error", error: { type: errorType(status), message } };
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
  return {
    apiKey: typeof env.ANTHROPIC_API_KEY === "string" ? env.ANTHROPIC_API_KEY.trim() : "",
    // Empty means no access code. A whitespace-only code stays required and matches nothing (fails closed).
    accessCode: rawAccessCode === "" ? null : rawAccessCode.trim(),
    allowedOrigins: new Set(splitList(env.ALLOWED_ORIGINS).map(canonicalOrigin).filter(Boolean)),
    allowedModels: new Set(splitList(env.ALLOWED_MODELS)),
    maxTokensCap: parseMaxTokensCap(env.MAX_TOKENS_CAP),
    rateLimiter: env.RATE_LIMITER,
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

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
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
