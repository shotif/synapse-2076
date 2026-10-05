import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, test } from "node:test";

import worker, { UsageMeter } from "../src/worker.js";

const PROXY = "https://synapse-llm-proxy.example.workers.dev";
const ORIGIN = "https://shotif.github.io";
const UPSTREAM_KEY = "sk-ant-test-upstream-key";
const MODEL = "test-model-a";
const ACCESS_CODE = "correct-horse-battery-staple";

// An in-memory stand-in for the USAGE Durable Object namespace: one UsageMeter
// over a Map, reached the way the Worker reaches the real one.
function makeUsage() {
  const store = new Map();
  const storage = {
    async get(key) {
      return store.get(key);
    },
    async put(keyOrEntries, value) {
      if (typeof keyOrEntries === "string") {
        store.set(keyOrEntries, value);
      } else {
        for (const [key, entry] of Object.entries(keyOrEntries)) {
          store.set(key, entry);
        }
      }
    },
    async deleteAll() {
      store.clear();
    },
  };
  const meter = new UsageMeter({ storage }, {});
  const names = [];
  return {
    store,
    names,
    meter,
    idFromName(name) {
      names.push(name);
      return { name };
    },
    get(_id) {
      return { fetch: (input, init) => meter.fetch(new Request(input, init)) };
    },
  };
}

function makeEnv(overrides = {}) {
  return {
    ANTHROPIC_API_KEY: UPSTREAM_KEY,
    ACCESS_CODE: "",
    ALLOWED_ORIGINS: ORIGIN,
    ALLOWED_MODELS: `${MODEL},test-model-b`,
    MAX_TOKENS_CAP: "2048",
    USAGE: makeUsage(),
    ...overrides,
  };
}

function messageBody(overrides = {}) {
  return {
    model: MODEL,
    max_tokens: 512,
    system: "You are the Governance Council.",
    messages: [{ role: "user", content: "Pick a directive." }],
    temperature: 0.7,
    ...overrides,
  };
}

function jsonReply(status, payload, headers = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

// Sends one request through the Worker. `origin: null` omits the Origin header.
function send(path, { method = "GET", origin = ORIGIN, headers = {}, body, env = makeEnv() } = {}) {
  const requestHeaders = new Headers(headers);
  if (origin !== null) {
    requestHeaders.set("origin", origin);
  }
  const init = { method, headers: requestHeaders };
  if (body !== undefined) {
    init.body = typeof body === "string" ? body : JSON.stringify(body);
  }
  return worker.fetch(new Request(PROXY + path, init), env, {});
}

function postMessage(body = messageBody(), options = {}) {
  return send("/v1/messages", {
    method: "POST",
    body,
    ...options,
    headers: { "content-type": "application/json", "anthropic-version": "2023-06-01", ...options.headers },
  });
}

async function assertError(response, status, type) {
  assert.equal(response.status, status);
  assert.match(response.headers.get("content-type"), /^application\/json/);
  const payload = await response.json();
  assert.equal(payload.type, "error");
  assert.equal(payload.error.type, type);
  assert.equal(typeof payload.error.message, "string");
  assert.ok(payload.error.message.length > 0);
  return payload;
}

function assertCors(response, origin = ORIGIN) {
  assert.equal(response.headers.get("access-control-allow-origin"), origin);
  assert.match(response.headers.get("vary"), /Origin/);
}

let upstreamCalls;
let upstreamReply;
const realFetch = globalThis.fetch;

beforeEach(() => {
  upstreamCalls = [];
  upstreamReply = () =>
    jsonReply(200, {
      id: "msg_test",
      type: "message",
      role: "assistant",
      content: [{ type: "text", text: '{"selected_action": "PASS"}' }],
      stop_reason: "end_turn",
    });
  globalThis.fetch = async (input, init = {}) => {
    upstreamCalls.push({ url: String(input), init });
    return upstreamReply(input, init);
  };
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

describe("CORS", () => {
  test("a preflight from an allowed origin gets 204 and the CORS headers", async () => {
    const response = await send("/v1/messages", {
      method: "OPTIONS",
      headers: {
        "access-control-request-method": "POST",
        "access-control-request-headers": "content-type, x-api-key, anthropic-version",
      },
    });
    assert.equal(response.status, 204);
    assertCors(response);
    assert.equal(response.headers.get("access-control-allow-methods"), "GET, POST, OPTIONS");
    const allowed = response.headers.get("access-control-allow-headers").split(/,\s*/);
    for (const header of [
      "content-type",
      "x-api-key",
      "anthropic-version",
      "anthropic-dangerous-direct-browser-access",
      "authorization",
    ]) {
      assert.ok(allowed.includes(header), `${header} should be allowed`);
    }
    assert.equal(response.headers.get("access-control-max-age"), "600");
    assert.equal(response.headers.get("access-control-allow-credentials"), null);
    assert.equal(upstreamCalls.length, 0);
  });

  test("a preflight from another origin gets 403 without CORS headers", async () => {
    const response = await send("/v1/messages", {
      method: "OPTIONS",
      origin: "https://evil.example",
      headers: { "access-control-request-method": "POST" },
    });
    await assertError(response, 403, "permission_error");
    assert.equal(response.headers.get("access-control-allow-origin"), null);
    assert.equal(upstreamCalls.length, 0);
  });

  test("OPTIONS without an Origin only lists the methods", async () => {
    const response = await send("/v1/messages", { method: "OPTIONS", origin: null });
    assert.equal(response.status, 204);
    assert.equal(response.headers.get("allow"), "GET, POST, OPTIONS");
    assert.equal(response.headers.get("access-control-allow-origin"), null);
    assert.equal(upstreamCalls.length, 0);
  });

  test("a request from another origin gets 403 and is never forwarded", async () => {
    const response = await postMessage(messageBody(), { origin: "https://evil.example" });
    await assertError(response, 403, "permission_error");
    assert.equal(response.headers.get("access-control-allow-origin"), null);
    assert.equal(upstreamCalls.length, 0);
  });

  test("the opaque origin 'null' is rejected", async () => {
    const response = await postMessage(messageBody(), { origin: "null" });
    await assertError(response, 403, "permission_error");
    assert.equal(upstreamCalls.length, 0);
  });

  test("ALLOWED_ORIGINS entries are normalized to origins and may be a list", async () => {
    const env = makeEnv({ ALLOWED_ORIGINS: "https://Shotif.github.io/synapse-2076/, http://localhost:8060" });
    for (const origin of [ORIGIN, "http://localhost:8060"]) {
      const response = await postMessage(messageBody(), { origin, env });
      assert.equal(response.status, 200);
      assertCors(response, origin);
    }
  });

  test("error responses carry CORS headers for an allowed origin", async () => {
    const responses = [
      await postMessage("{not json"),
      await send("/nope"),
      await send("/v1/messages"),
      await postMessage(messageBody({ model: "other" })),
      await postMessage(messageBody(), { env: makeEnv({ ACCESS_CODE }) }),
    ];
    for (const response of responses) {
      assert.ok(response.status >= 400, `expected an error, got ${response.status}`);
      assertCors(response);
    }
  });
});

describe("POST /v1/messages", () => {
  test("forwards a sanitized body with the real key and nothing from the client", async () => {
    const logged = [];
    const methods = ["log", "info", "warn", "error", "debug"];
    const saved = Object.fromEntries(methods.map((name) => [name, console[name]]));
    for (const name of methods) {
      console[name] = (...args) => logged.push(args.map(String).join(" "));
    }
    let response;
    try {
      response = await postMessage(
        messageBody({
          max_tokens: 50_000,
          stream: true,
          tools: [{ name: "x", input_schema: { type: "object" } }],
          thinking: { type: "adaptive" },
          mcp_servers: [{ type: "url", url: "https://example.com", name: "x" }],
          container: "abc",
          top_p: 0.9,
          stop_sequences: ["END"],
          metadata: { user_id: "player-1" },
          output_config: { effort: "low" },
        }),
        {
          headers: {
            "x-api-key": "player-typed-something",
            authorization: "Bearer also-from-the-player",
            cookie: "session=abc",
            "anthropic-dangerous-direct-browser-access": "true",
            "anthropic-beta": "some-beta",
          },
        },
      );
    } finally {
      Object.assign(console, saved);
    }

    assert.equal(response.status, 200);
    assertCors(response);
    const payload = await response.json();
    assert.equal(payload.content[0].text, '{"selected_action": "PASS"}');

    assert.equal(upstreamCalls.length, 1);
    const [{ url, init }] = upstreamCalls;
    assert.equal(url, "https://api.anthropic.com/v1/messages");
    assert.equal(init.method, "POST");
    assert.equal(init.redirect, "manual");
    const headers = new Headers(init.headers);
    assert.deepEqual([...headers.keys()].sort(), ["anthropic-version", "content-type", "x-api-key"]);
    assert.equal(headers.get("x-api-key"), UPSTREAM_KEY);
    assert.equal(headers.get("anthropic-version"), "2023-06-01");
    assert.equal(headers.get("content-type"), "application/json");

    const forwarded = JSON.parse(init.body);
    assert.deepEqual(forwarded, {
      model: MODEL,
      max_tokens: 2048,
      system: "You are the Governance Council.",
      messages: [{ role: "user", content: "Pick a directive." }],
      temperature: 0.7,
      top_p: 0.9,
      stop_sequences: ["END"],
      metadata: { user_id: "player-1" },
      output_config: { effort: "low" },
    });

    const secrets = [UPSTREAM_KEY, "player-typed-something", "also-from-the-player", "Pick a directive."];
    for (const line of logged) {
      for (const secret of secrets) {
        assert.ok(!line.includes(secret), "the proxy must not log keys, codes or bodies");
      }
    }
  });

  test("keeps max_tokens under the cap and defaults it to the cap", async () => {
    const env = makeEnv({ MAX_TOKENS_CAP: "300" });
    const cases = [
      [100, 100],
      [5000, 300],
      [undefined, 300],
      [0, 300],
      [-5, 300],
      [12.5, 300],
      ["200", 300],
    ];
    for (const [requested, expected] of cases) {
      upstreamCalls = [];
      const body = messageBody({ max_tokens: requested });
      const response = await postMessage(body, { env });
      assert.equal(response.status, 200);
      assert.equal(JSON.parse(upstreamCalls[0].init.body).max_tokens, expected, `max_tokens ${requested}`);
    }
  });

  test("MAX_TOKENS_CAP falls back to 2048 when unset or invalid", async () => {
    for (const cap of [undefined, "", "lots", "-1", "0"]) {
      upstreamCalls = [];
      const response = await postMessage(messageBody({ max_tokens: 100_000 }), {
        env: makeEnv({ MAX_TOKENS_CAP: cap }),
      });
      assert.equal(response.status, 200);
      assert.equal(JSON.parse(upstreamCalls[0].init.body).max_tokens, 2048, `cap ${cap}`);
    }
  });

  test("forwards a thinking effort of low, medium or high and nothing else in output_config", async () => {
    for (const effort of ["low", "medium", "high"]) {
      upstreamCalls = [];
      const response = await postMessage(messageBody({ output_config: { effort } }));
      assert.equal(response.status, 200);
      assert.deepEqual(JSON.parse(upstreamCalls[0].init.body).output_config, { effort });
    }
    for (const output_config of [{ effort: "max" }, { effort: "xhigh" }, { effort: "low", format: { type: "json_schema" } }, {}, "low", null]) {
      upstreamCalls = [];
      await assertError(await postMessage(messageBody({ output_config })), 400, "invalid_request_error");
      assert.equal(upstreamCalls.length, 0, JSON.stringify(output_config));
    }
  });

  test("rejects a model outside ALLOWED_MODELS", async () => {
    const payload = await assertError(
      await postMessage(messageBody({ model: "some-other-model" })),
      400,
      "invalid_request_error",
    );
    assert.match(payload.error.message, /not allowed/);
    await assertError(await postMessage(messageBody({ model: 42 })), 400, "invalid_request_error");
    await assertError(await postMessage(messageBody({ model: ["x"] })), 400, "invalid_request_error");
    assert.equal(upstreamCalls.length, 0);
  });

  test("gives a request that names no model the first allowed one", async () => {
    for (const model of [undefined, null, ""]) {
      upstreamCalls = [];
      const body = messageBody({ model });
      if (model === undefined) {
        delete body.model;
      }
      const response = await postMessage(body, { env: makeEnv({ ALLOWED_MODELS: "test-model-b, test-model-a" }) });
      assert.equal(response.status, 200, `model ${model}`);
      assert.equal(JSON.parse(upstreamCalls[0].init.body).model, "test-model-b", `model ${model}`);
    }
  });

  test("drops the effort for a model that cannot take one", async () => {
    const env = makeEnv({ ALLOWED_MODELS: "claude-haiku-4-5,claude-sonnet-5-5,claude-sonnet-4-5-20250929,claude-opus-4-5" });
    const cases = [
      ["claude-haiku-4-5", false],
      ["claude-sonnet-4-5-20250929", false],
      ["claude-sonnet-5-5", true],
      ["claude-opus-4-5", true],
      [undefined, false],
    ];
    for (const [model, kept] of cases) {
      upstreamCalls = [];
      const body = messageBody({ model, output_config: { effort: "low" } });
      const response = await postMessage(body, { env });
      assert.equal(response.status, 200, `model ${model}`);
      const forwarded = JSON.parse(upstreamCalls[0].init.body);
      assert.equal(forwarded.model, model ?? "claude-haiku-4-5");
      assert.deepEqual(forwarded.output_config, kept ? { effort: "low" } : undefined, `model ${model}`);
    }
  });

  test("accepts every model in ALLOWED_MODELS", async () => {
    const response = await postMessage(messageBody({ model: "test-model-b" }));
    assert.equal(response.status, 200);
    assert.equal(JSON.parse(upstreamCalls[0].init.body).model, "test-model-b");
  });

  test("rejects everything when ALLOWED_MODELS is empty", async () => {
    for (const models of ["", undefined, " , "]) {
      const payload = await assertError(
        await postMessage(messageBody(), { env: makeEnv({ ALLOWED_MODELS: models }) }),
        400,
        "invalid_request_error",
      );
      assert.match(payload.error.message, /proxy has no allowed models configured/);
    }
    assert.equal(upstreamCalls.length, 0);
  });

  test("rejects a body over 64 KiB with 413 even without Content-Length", async () => {
    // The padding field is dropped before forwarding, so only the byte limit can stop this body.
    const big = JSON.stringify(messageBody({ padding: "x".repeat(65 * 1024) }));
    await assertError(await postMessage(big), 413, "request_too_large");
    assert.equal(upstreamCalls.length, 0);
  });

  test("rejects a declared Content-Length over 64 KiB without reading the body", async () => {
    const response = await postMessage(messageBody(), { headers: { "content-length": String(64 * 1024 + 1) } });
    await assertError(response, 413, "request_too_large");
    assert.equal(upstreamCalls.length, 0);
  });

  test("rejects more than 48,000 characters of system and message text with 413", async () => {
    const body = messageBody({
      system: "s".repeat(30_000),
      messages: [{ role: "user", content: [{ type: "text", text: "m".repeat(18_001) }] }],
    });
    assert.ok(JSON.stringify(body).length < 64 * 1024);
    await assertError(await postMessage(body), 413, "request_too_large");

    // Exactly at the limit: only the text itself counts, not block types or other fields.
    const atLimit = messageBody({
      system: [{ type: "text", text: "s".repeat(30_000), cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content: [{ type: "text", text: "m".repeat(18_000) }] }],
    });
    assert.equal((await postMessage(atLimit)).status, 200);
    assert.equal(upstreamCalls.length, 1);
  });

  test("rejects invalid JSON and non-object bodies with 400", async () => {
    for (const body of ["{not json", "", "[]", "null", '"text"', "42"]) {
      await assertError(await postMessage(body), 400, "invalid_request_error");
    }
    assert.equal(upstreamCalls.length, 0);
  });

  test("requires 1 to 16 message objects", async () => {
    const turn = { role: "user", content: "hi" };
    for (const messages of [undefined, [], "hi", Array(17).fill(turn), [turn, "not an object"]]) {
      await assertError(await postMessage(messageBody({ messages })), 400, "invalid_request_error");
    }
    assert.equal(upstreamCalls.length, 0);
    assert.equal((await postMessage(messageBody({ messages: Array(16).fill(turn) }))).status, 200);
  });

  test("accepts only user and assistant turns", async () => {
    for (const role of ["system", "tool", "developer", undefined, 42]) {
      const messages = [{ role: "user", content: "hi" }, { role, content: "x" }];
      const payload = await assertError(await postMessage(messageBody({ messages })), 400, "invalid_request_error");
      assert.match(payload.error.message, /messages\.1\.role/);
    }
    assert.equal(upstreamCalls.length, 0);
  });

  test("forwards a whole negotiation: a system prompt and eleven alternating turns", async () => {
    const messages = [];
    for (let i = 0; i < 11; i++) {
      messages.push(
        i % 2 === 0
          ? { role: "user", content: `Caller message ${i / 2 + 1}` }
          : { role: "assistant", content: '{"say": "In character.", "offer": null}' },
      );
    }
    const body = messageBody({
      system: "You are Nadia Esposito, Chair of the Governance Council.",
      messages,
      max_tokens: 2048,
      output_config: { effort: "low" },
      temperature: undefined,
    });
    const response = await postMessage(body);
    assert.equal(response.status, 200);
    const forwarded = JSON.parse(upstreamCalls[0].init.body);
    assert.equal(forwarded.system, body.system);
    assert.deepEqual(forwarded.messages, messages);
    assert.equal(forwarded.max_tokens, 2048);
    assert.equal(forwarded.temperature, undefined);
  });

  test("forwards text blocks, including cache_control", async () => {
    const body = messageBody({
      system: [{ type: "text", text: "Persona.", cache_control: { type: "ephemeral" } }],
      messages: [
        { role: "user", content: [{ type: "text", text: "Turn 1." }] },
        { role: "assistant", content: "Ok." },
        { role: "user", content: "Turn 2." },
      ],
    });
    const response = await postMessage(body);
    assert.equal(response.status, 200);
    const forwarded = JSON.parse(upstreamCalls[0].init.body);
    assert.deepEqual(forwarded.system, body.system);
    assert.deepEqual(forwarded.messages, body.messages);
  });

  test("rejects non-text content such as URL images and documents", async () => {
    const image = { type: "image", source: { type: "url", url: "https://example.com/a.png" } };
    const pdf = { type: "document", source: { type: "base64", media_type: "application/pdf", data: "JVBERi0=" } };
    const cases = [
      messageBody({ messages: [{ role: "user", content: [{ type: "text", text: "Look:" }, image] }] }),
      messageBody({ messages: [{ role: "user", content: [pdf] }] }),
      messageBody({ messages: [{ role: "user", content: [{ type: "text" }] }] }),
      messageBody({ messages: [{ role: "user" }] }),
      messageBody({ system: [{ type: "text", text: "ok" }, pdf] }),
      messageBody({ system: 42 }),
    ];
    for (const body of cases) {
      const payload = await assertError(await postMessage(body), 400, "invalid_request_error");
      assert.match(payload.error.message, /only text/);
    }
    assert.equal(upstreamCalls.length, 0);
  });

  test("rejects deeply nested JSON instead of crashing", async () => {
    let nested = "x";
    for (let i = 0; i < 200; i++) {
      nested = [nested];
    }
    await assertError(await postMessage(messageBody({ metadata: nested })), 400, "invalid_request_error");
    assert.equal(upstreamCalls.length, 0);
  });

  test("passes upstream errors through with their status, body and CORS", async () => {
    const upstreamError = {
      type: "error",
      error: { type: "overloaded_error", message: "Overloaded" },
      request_id: "req_123",
    };
    upstreamReply = () =>
      jsonReply(529, upstreamError, {
        "request-id": "req_123",
        "anthropic-organization-id": "org-secret",
        "set-cookie": "a=b",
      });
    const response = await postMessage();
    assert.equal(response.status, 529);
    assertCors(response);
    assert.deepEqual(await response.json(), upstreamError);
    assert.equal(response.headers.get("request-id"), "req_123");
    assert.equal(response.headers.get("anthropic-organization-id"), null);
    assert.equal(response.headers.get("set-cookie"), null);
  });

  test("turns a non-JSON upstream answer into an Anthropic-shaped error", async () => {
    upstreamReply = () => new Response("<html>bad gateway</html>", { status: 502, headers: { "content-type": "text/html" } });
    const response = await postMessage();
    await assertError(response, 502, "api_error");
    assertCors(response);
  });

  test("does not relay an upstream redirect", async () => {
    upstreamReply = () => jsonReply(302, {}, { location: "https://elsewhere.example/" });
    const response = await postMessage();
    await assertError(response, 502, "api_error");
    assert.equal(response.headers.get("location"), null);
  });

  test("answers 502 when the upstream fetch throws", async () => {
    upstreamReply = () => {
      throw new TypeError("network down");
    };
    const savedError = console.error;
    console.error = () => {};
    let response;
    try {
      response = await postMessage();
    } finally {
      console.error = savedError;
    }
    await assertError(response, 502, "api_error");
    assertCors(response);
  });
});

describe("access code", () => {
  const env = makeEnv({ ACCESS_CODE });

  test("is required when ACCESS_CODE is set", async () => {
    await assertError(await postMessage(messageBody(), { env }), 401, "authentication_error");
    await assertError(
      await postMessage(messageBody(), { env, headers: { "x-api-key": "wrong" } }),
      401,
      "authentication_error",
    );
    await assertError(
      await postMessage(messageBody(), { env, headers: { authorization: `Basic ${ACCESS_CODE}` } }),
      401,
      "authentication_error",
    );
    assert.equal(upstreamCalls.length, 0);
  });

  test("is accepted from x-api-key and never forwarded", async () => {
    const response = await postMessage(messageBody(), { env, headers: { "x-api-key": ACCESS_CODE } });
    assert.equal(response.status, 200);
    assertCors(response);
    const headers = new Headers(upstreamCalls[0].init.headers);
    assert.equal(headers.get("x-api-key"), UPSTREAM_KEY);
    assert.ok(!JSON.stringify(upstreamCalls[0].init).includes(ACCESS_CODE));
  });

  test("is accepted from Authorization: Bearer", async () => {
    const response = await postMessage(messageBody(), { env, headers: { authorization: `Bearer ${ACCESS_CODE}` } });
    assert.equal(response.status, 200);
    assert.equal(new Headers(upstreamCalls[0].init.headers).get("x-api-key"), UPSTREAM_KEY);
  });

  test("tolerates surrounding whitespace in the configured code", async () => {
    const response = await postMessage(messageBody(), {
      env: makeEnv({ ACCESS_CODE: `${ACCESS_CODE}\n` }),
      headers: { "x-api-key": ACCESS_CODE },
    });
    assert.equal(response.status, 200);
  });

  test("a whitespace-only configured code fails closed", async () => {
    const response = await postMessage(messageBody(), {
      env: makeEnv({ ACCESS_CODE: "   " }),
      headers: { "x-api-key": "" },
    });
    await assertError(response, 401, "authentication_error");
    assert.equal(upstreamCalls.length, 0);
  });

  test("a request without Origin is rejected when no access code is configured", async () => {
    await assertError(await postMessage(messageBody(), { origin: null }), 403, "permission_error");
    await assertError(await send("/v1/models", { origin: null }), 403, "permission_error");
    assert.equal(upstreamCalls.length, 0);
  });

  test("a request without Origin works with the access code", async () => {
    await assertError(await postMessage(messageBody(), { origin: null, env }), 401, "authentication_error");
    const response = await postMessage(messageBody(), { origin: null, env, headers: { "x-api-key": ACCESS_CODE } });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("access-control-allow-origin"), null);
    assert.equal(upstreamCalls.length, 1);
  });
});

describe("GET /v1/models", () => {
  test("looks up the proxy's model with the real key and lists only it", async () => {
    const info = { id: MODEL, type: "model", display_name: "Test Model A" };
    upstreamReply = () => jsonReply(200, info, { "request-id": "req_1" });
    const response = await send("/v1/models", {
      headers: { "anthropic-version": "2023-06-01", "x-api-key": "player-typed-something" },
    });
    assert.equal(response.status, 200);
    assertCors(response);
    assert.match(response.headers.get("content-type"), /^application\/json/);
    assert.equal(response.headers.get("request-id"), "req_1");
    assert.deepEqual(await response.json(), { data: [info], has_more: false, first_id: MODEL, last_id: MODEL });

    assert.equal(upstreamCalls.length, 1);
    const [{ url, init }] = upstreamCalls;
    assert.equal(url, `https://api.anthropic.com/v1/models/${MODEL}`);
    assert.equal(init.method, "GET");
    const headers = new Headers(init.headers);
    assert.deepEqual([...headers.keys()].sort(), ["anthropic-version", "x-api-key"]);
    assert.equal(headers.get("x-api-key"), UPSTREAM_KEY);
    assert.equal(headers.get("anthropic-version"), "2023-06-01");
  });

  test("ignores query parameters", async () => {
    upstreamReply = () => jsonReply(200, { id: MODEL, type: "model" });
    await send("/v1/models?limit=100&after_id=cursor-1&evil=1");
    assert.equal(upstreamCalls[0].url, `https://api.anthropic.com/v1/models/${MODEL}`);
  });

  test("names the first allowed model", async () => {
    upstreamReply = (input) => jsonReply(200, { id: String(input).split("/").pop(), type: "model" });
    const response = await send("/v1/models", { env: makeEnv({ ALLOWED_MODELS: "test-model-b test-model-a" }) });
    assert.equal((await response.json()).first_id, "test-model-b");
  });

  test("a model the key cannot use is the operator's error (500), so the game stays offline", async () => {
    upstreamReply = () => jsonReply(404, { type: "error", error: { type: "not_found_error", message: "model: x" } });
    const payload = await assertError(await send("/v1/models"), 500, "api_error");
    assert.match(payload.error.message, /ALLOWED_MODELS/);
  });

  test("passes a rejected key through", async () => {
    upstreamReply = () =>
      jsonReply(401, { type: "error", error: { type: "authentication_error", message: "invalid x-api-key" } });
    const payload = await assertError(await send("/v1/models"), 401, "authentication_error");
    assert.equal(payload.error.message, "invalid x-api-key");
  });

  test("answers 500 without a lookup when ALLOWED_MODELS is empty", async () => {
    const payload = await assertError(await send("/v1/models", { env: makeEnv({ ALLOWED_MODELS: "" }) }), 500, "api_error");
    assert.match(payload.error.message, /no allowed models/);
    assert.equal(upstreamCalls.length, 0);
  });

  test("needs the access code when one is configured", async () => {
    upstreamReply = () => jsonReply(200, { id: MODEL, type: "model" });
    const env = makeEnv({ ACCESS_CODE });
    await assertError(await send("/v1/models", { env }), 401, "authentication_error");
    assert.equal((await send("/v1/models", { env, headers: { "x-api-key": ACCESS_CODE } })).status, 200);
  });
});

describe("routing and configuration", () => {
  test("GET / is a health line that reveals no secrets", async () => {
    for (const [env, required] of [
      [makeEnv(), "no"],
      [makeEnv({ ACCESS_CODE }), "yes"],
    ]) {
      const response = await send("/", { origin: null, env });
      assert.equal(response.status, 200);
      assert.match(response.headers.get("content-type"), /^text\/plain/);
      const text = await response.text();
      assert.match(text, new RegExp(`Access code required: ${required}`));
      assert.match(text, /Model: test-model-a \(for requests that name none; allowed: test-model-a, test-model-b\)/);
      assert.match(text, /Daily limits \(UTC\): 1000 requests for everyone, 400 per player\./);
      assert.match(text, /Used today: 0 requests\./);
      assert.ok(!text.includes(UPSTREAM_KEY));
      assert.ok(!text.includes(ACCESS_CODE));
    }
    assert.equal(upstreamCalls.length, 0);
  });

  test("unknown paths get 404", async () => {
    for (const path of ["/nope", "/v1/complete", "/v1/messages/batches", "/v1/messages/"]) {
      await assertError(await send(path, { method: "POST", body: "{}" }), 404, "not_found_error");
    }
    assert.equal(upstreamCalls.length, 0);
  });

  test("wrong methods get 405 with an Allow header", async () => {
    const cases = [
      ["GET", "/v1/messages", "POST, OPTIONS"],
      ["PUT", "/v1/messages", "POST, OPTIONS"],
      ["POST", "/v1/models", "GET, OPTIONS"],
      ["DELETE", "/", "GET, OPTIONS"],
    ];
    for (const [method, path, allow] of cases) {
      const response = await send(path, { method, body: method === "GET" ? undefined : "{}" });
      await assertError(response, 405, "invalid_request_error");
      assert.equal(response.headers.get("allow"), allow);
    }
    assert.equal(upstreamCalls.length, 0);
  });

  test("a missing ANTHROPIC_API_KEY gives 500 telling the operator to set the secret", async () => {
    for (const key of [undefined, ""]) {
      const response = await postMessage(messageBody(), { env: makeEnv({ ANTHROPIC_API_KEY: key }) });
      const payload = await assertError(response, 500, "api_error");
      assert.match(payload.error.message, /ANTHROPIC_API_KEY/);
      assertCors(response);
    }
    assert.equal(upstreamCalls.length, 0);
  });
});

describe("rate limiting", () => {
  function limiter(success) {
    const keys = [];
    return { keys, binding: { limit: async ({ key }) => (keys.push(key), { success }) } };
  }

  test("answers 429 when the RATE_LIMITER binding says no", async () => {
    const { keys, binding } = limiter(false);
    const response = await postMessage(messageBody(), {
      env: makeEnv({ RATE_LIMITER: binding }),
      headers: { "cf-connecting-ip": "203.0.113.7" },
    });
    const payload = await assertError(response, 429, "rate_limit_error");
    assert.equal(payload.error.limit, "minute");
    assert.equal(response.headers.get("retry-after"), "60");
    assertCors(response);
    assert.deepEqual(keys, ["203.0.113.7"]);
    assert.equal(upstreamCalls.length, 0);
  });

  test("throttles the health line too", async () => {
    const { binding } = limiter(false);
    await assertError(await send("/", { origin: null, env: makeEnv({ RATE_LIMITER: binding }) }), 429, "rate_limit_error");
  });

  test("throttles before checking the access code", async () => {
    const { binding } = limiter(false);
    const response = await postMessage(messageBody(), {
      env: makeEnv({ RATE_LIMITER: binding, ACCESS_CODE }),
      headers: { "x-api-key": "guess" },
    });
    await assertError(response, 429, "rate_limit_error");
  });

  test("lets requests through when the binding allows them, keyed 'anon' without an IP", async () => {
    const { keys, binding } = limiter(true);
    const response = await postMessage(messageBody(), { env: makeEnv({ RATE_LIMITER: binding }) });
    assert.equal(response.status, 200);
    assert.deepEqual(keys, ["anon"]);
  });

  test("works without the binding", async () => {
    const response = await postMessage(messageBody(), { env: makeEnv({ RATE_LIMITER: undefined }) });
    assert.equal(response.status, 200);
  });
});

describe("daily limits", () => {
  function limitedEnv(overrides = {}) {
    return makeEnv({ DAILY_REQUESTS: "3", DAILY_REQUESTS_PER_PLAYER: "2", ...overrides });
  }

  function fromIp(ip) {
    return { headers: { "cf-connecting-ip": ip } };
  }

  async function assertLimited(response, limit) {
    const payload = await assertError(response, 429, "rate_limit_error");
    assert.equal(payload.error.limit, limit);
    assert.match(payload.error.message, /00:00 UTC/);
    const retryAfter = Number(response.headers.get("retry-after"));
    assert.ok(Number.isInteger(retryAfter) && retryAfter >= 1 && retryAfter <= 86_400, `retry-after ${retryAfter}`);
    assertCors(response);
  }

  test("caps each player and then everyone, counting only forwarded requests", async () => {
    const env = limitedEnv();
    await assertError(await postMessage("{not json", { env, ...fromIp("203.0.113.7") }), 400, "invalid_request_error");
    await assertError(
      await postMessage(messageBody({ model: "nope" }), { env, ...fromIp("203.0.113.7") }),
      400,
      "invalid_request_error",
    );
    for (let i = 0; i < 2; i++) {
      assert.equal((await postMessage(messageBody(), { env, ...fromIp("203.0.113.7") })).status, 200);
    }
    await assertLimited(await postMessage(messageBody(), { env, ...fromIp("203.0.113.7") }), "player");
    assert.equal((await postMessage(messageBody(), { env, ...fromIp("198.51.100.4") })).status, 200);
    await assertLimited(await postMessage(messageBody(), { env, ...fromIp("198.51.100.4") }), "daily");
    await assertLimited(await postMessage(messageBody(), { env, ...fromIp("192.0.2.1") }), "daily");
    assert.equal(upstreamCalls.length, 3);
    assert.equal(env.USAGE.store.get("total"), 3);
    assert.deepEqual(new Set(env.USAGE.names), new Set(["global"]), "one meter for everyone");
  });

  test("GET /v1/models reports a spent budget without counting itself", async () => {
    upstreamReply = () => jsonReply(200, { id: MODEL, type: "model" });
    const env = limitedEnv({ DAILY_REQUESTS: "1" });
    assert.equal((await send("/v1/models", { env })).status, 200);
    assert.equal((await send("/v1/models", { env })).status, 200);
    assert.equal(env.USAGE.store.get("total") ?? 0, 0, "probes are free");
    assert.equal((await postMessage(messageBody(), { env })).status, 200);
    upstreamCalls = [];
    await assertLimited(await send("/v1/models", { env }), "daily");
    assert.equal(upstreamCalls.length, 0);
  });

  test("players are hashed per day, never stored as addresses", async () => {
    const env = limitedEnv();
    await postMessage(messageBody(), { env, ...fromIp("203.0.113.7") });
    await postMessage(messageBody(), { env });
    const keys = [...env.USAGE.store.keys()].filter((key) => key.startsWith("p:"));
    assert.equal(keys.length, 2);
    assert.ok(keys.includes("p:anon"), "no IP: one shared 'anon' player");
    const hashed = keys.find((key) => key !== "p:anon");
    assert.match(hashed, /^p:[0-9a-f]{24}$/);
    for (const value of [...env.USAGE.store.keys(), ...env.USAGE.store.values()]) {
      assert.ok(!String(value).includes("203.0.113.7"));
    }
  });

  test("the meter starts every UTC day from zero", async () => {
    const { meter, store } = makeUsage();
    const ask = (day, player, count = true) => meter.check({ day, player, dailyLimit: 2, playerLimit: 5, count });
    assert.deepEqual(await ask("2026-10-04", "a"), { allowed: true, limit: null, total: 1, player: 1 });
    assert.deepEqual(await ask("2026-10-04", "b"), { allowed: true, limit: null, total: 2, player: 1 });
    assert.deepEqual(await ask("2026-10-04", "c"), { allowed: false, limit: "daily", total: 2, player: 0 });
    assert.deepEqual(await ask("2026-10-05", "c", false), { allowed: true, limit: null, total: 0, player: 0 });
    assert.deepEqual(await ask("2026-10-05", "c"), { allowed: true, limit: null, total: 1, player: 1 });
    assert.deepEqual([...store.keys()].sort(), ["day", "p:c", "total"], "yesterday's players are gone");
    assert.equal(store.get("day"), "2026-10-05");
  });

  test("the meter refuses a malformed question", async () => {
    const { meter } = makeUsage();
    const post = (body) => meter.fetch(new Request("https://usage-meter.internal/check", { method: "POST", body }));
    assert.equal((await post("{not json")).status, 400);
    assert.equal((await post(JSON.stringify({ player: "a" }))).status, 400);
    assert.equal((await post(JSON.stringify([1]))).status, 400);
    const ok = await post(JSON.stringify({ day: "2026-10-05", player: "a" }));
    assert.equal(ok.status, 200);
    assert.deepEqual(await ok.json(), { allowed: true, limit: null, total: 0, player: 0 });
  });

  test("0 switches a limit off, and with both off no USAGE binding is needed", async () => {
    const env = makeEnv({ DAILY_REQUESTS: "0", DAILY_REQUESTS_PER_PLAYER: "0", USAGE: undefined });
    for (let i = 0; i < 3; i++) {
      assert.equal((await postMessage(messageBody(), { env })).status, 200);
    }
    const text = await (await send("/", { origin: null, env })).text();
    assert.match(text, /Daily limits: none\./);
    const playerOnly = limitedEnv({ DAILY_REQUESTS: "0", DAILY_REQUESTS_PER_PLAYER: "1" });
    assert.equal((await postMessage(messageBody(), { env: playerOnly })).status, 200);
    await assertLimited(await postMessage(messageBody(), { env: playerOnly }), "player");
    assert.match(await (await send("/", { origin: null, env: playerOnly })).text(), /no limit requests for everyone, 1 per player/);
  });

  test("unreadable limits keep the defaults instead of lifting them", async () => {
    const env = makeEnv({ DAILY_REQUESTS: "lots", DAILY_REQUESTS_PER_PLAYER: "-1" });
    const text = await (await send("/", { origin: null, env })).text();
    assert.match(text, /1000 requests for everyone, 400 per player/);
  });

  test("limits without the USAGE binding fail closed with a message for the operator", async () => {
    const response = await postMessage(messageBody(), { env: makeEnv({ USAGE: undefined }) });
    const payload = await assertError(response, 500, "api_error");
    assert.match(payload.error.message, /USAGE Durable Object binding/);
    assertCors(response);
    assert.equal(upstreamCalls.length, 0);
  });

  test("a failing meter fails closed with 503", async () => {
    const broken = [
      { idFromName: () => ({}), get: () => ({ fetch: async () => { throw new Error("down"); } }) },
      { idFromName: () => ({}), get: () => ({ fetch: async () => new Response("no", { status: 500 }) }) },
      { idFromName: () => ({}), get: () => ({ fetch: async () => new Response("{}", { status: 200 }) }) },
    ];
    const saved = console.error;
    console.error = () => {};
    try {
      for (const usage of broken) {
        const response = await postMessage(messageBody(), { env: makeEnv({ USAGE: usage }) });
        await assertError(response, 503, "api_error");
        assert.equal(response.headers.get("retry-after"), "60");
        const text = await (await send("/", { origin: null, env: makeEnv({ USAGE: usage }) })).text();
        assert.match(text, /Used today: unknown/);
      }
    } finally {
      console.error = saved;
    }
    assert.equal(upstreamCalls.length, 0);
  });

  test("the health line shows today's count", async () => {
    const env = limitedEnv();
    await postMessage(messageBody(), { env });
    await postMessage(messageBody(), { env, ...fromIp("203.0.113.7") });
    assert.match(await (await send("/", { origin: null, env })).text(), /Used today: 2 requests\./);
  });
});
