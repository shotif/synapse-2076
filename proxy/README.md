# Claude API proxy

An optional Cloudflare Worker that lets the public web build of SYNAPSE-2076 use the Claude API.

The web build is static files on GitHub Pages. Anything in it is public, so it can never hold an Anthropic API key. This Worker keeps the key as a Cloudflare secret, and the game calls the Worker instead of `api.anthropic.com`. Anyone who reads the web build can find the Worker's URL, so the Worker defends itself with an origin allowlist, an optional access code, a model allowlist, a `max_tokens` cap and request-size limits.

The proxy is optional. Desktop builds and local models don't need it.

## What the game sees

The Worker speaks the native Anthropic Messages API:

| Request | Result |
|---|---|
| `GET /` | A plain-text health line: running, whether an access code is required, whether the API key is set |
| `GET /v1/models` | Forwarded to `https://api.anthropic.com/v1/models` |
| `POST /v1/messages` | Checked, trimmed and forwarded to `https://api.anthropic.com/v1/messages` |
| `OPTIONS` (CORS preflight) | `204` for an allowed origin, `403` for any other origin |

Point the game's LLM endpoint at `https://synapse-llm-proxy.<your-subdomain>.workers.dev/v1/messages`. If an access code is set, players enter it where the game asks for an API key; the game sends it as `x-api-key`. Other clients can send `Authorization: Bearer <code>` instead.

Upstream status codes and JSON bodies pass through unchanged. Errors the proxy produces itself use Anthropic's error shape, `{"type": "error", "error": {"type": "...", "message": "..."}}`, so the game handles both the same way.

## What the proxy checks

For `POST /v1/messages`, in order:

1. The `Origin` header, if present, must be in `ALLOWED_ORIGINS`, or the answer is `403`.
2. If the `RATE_LIMITER` binding exists, the client IP must be under its limit (`429`).
3. A request without an `Origin` header is refused (`403`) unless `ACCESS_CODE` is set, and then it must pass step 4.
4. If `ACCESS_CODE` is set, the request must carry it (`401`). The comparison is constant-time.
5. The body must be at most 64 KiB (`413`) and a JSON object (`400`).
6. `model` must be one of `ALLOWED_MODELS` (`400`).
7. `messages` must be an array of 1 to 8 objects (`400`).
8. `system` and each message's `content` must be text: a string or `text` blocks (`400`). Image and document blocks are refused, because URL, file and PDF sources can bring in far more tokens than the character limit allows.
9. `system` plus all message content may hold at most 48,000 characters (`413`).

Only `model`, `max_tokens`, `system`, `messages`, `temperature`, `top_p`, `top_k`, `stop_sequences`, `metadata` and `output_config` are forwarded. `output_config` may only be `{"effort": "low" | "medium" | "high"}` (`400` otherwise); the game sends `low` so Claude keeps its thinking short. Everything else (`tools`, `stream`, `thinking`, `mcp_servers`, `container`, ...) is dropped. `max_tokens` is clamped to `MAX_TOKENS_CAP` and set to the cap when it is missing or invalid.

Requests to Anthropic carry only `x-api-key` (the real key), `anthropic-version: 2023-06-01` and, for `POST`, `content-type: application/json`. No client header reaches Anthropic: not cookies, not the access code. If Anthropic can't be reached, the proxy answers `502`.

`GET /v1/models` goes through the same origin, rate-limit and access-code checks. Only its `limit`, `after_id` and `before_id` query parameters are passed on.

## Security model

Know what each control does and what it doesn't do.

- **Origin allowlist.** Browsers attach the page's origin to every request and won't let a page read a response unless the proxy names that origin. Other websites therefore can't spend your key through their visitors' browsers. It does nothing against a script, which can send any `Origin` header it likes.
- **Access code.** This is the real gate. With `ACCESS_CODE` set, every API request must carry it. Anyone who has the code can use the proxy, and players' browsers may store it, so share it only with people you trust and change it when it leaks. Never put it in the web build, the repository or a public variable. Without an access code, anyone who sends an allowed `Origin` header can use the proxy.
- **Requests without an Origin header** (curl, scripts) are refused unless an access code is set and supplied. This stops casual use of the URL as a free API. It is not a security boundary, because `Origin` is easy to fake.
- **Model allowlist, `max_tokens` cap, text-only content and size limits** bound the cost of a single request. They don't limit how many requests arrive.
- **Rate limiter.** `wrangler.toml` binds 60 requests per 60 seconds per client IP (one game turn sends three). Cloudflare counts per location and approximately, so it slows a single client down but not a distributed one. Without the binding, the proxy runs unthrottled.
- **Spend limit.** This is the only hard ceiling on cost. Create a separate workspace in the Anthropic Console, give it a monthly spend limit, and create the proxy's API key in that workspace. If the proxy is abused, spending stops at the limit and nothing else in your organization is affected. Revoke the key there if you need to shut the proxy off immediately.
- **No request logging.** The Worker never logs request bodies, keys or access codes. Cloudflare still sees request metadata, and Workers Logs record more if you turn on observability.

## Configuration

| Name | Kind | Default | Meaning |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | secret | none, required | Key for every upstream call. Without it, API requests get `500`. |
| `ACCESS_CODE` | secret | unset | When set, API requests must send it as `x-api-key` or `Authorization: Bearer`. An empty value means no access code. Use a long random value, for example `openssl rand -hex 16`. |
| `ALLOWED_ORIGINS` | var | `https://shotif.github.io` | Comma-separated origins allowed to call the proxy from a browser. Paths and trailing slashes are ignored, so a page URL works too. Add `http://localhost:8060` to test a local web export. |
| `ALLOWED_MODELS` | var | the model in `wrangler.toml` | Comma-separated exact model ids. If empty, every message request is rejected. |
| `MAX_TOKENS_CAP` | var | `2048` | Upper bound for `max_tokens`, and the value used when a request omits it. Thinking counts toward it. |
| `RATE_LIMITER` | binding | 60 requests / 60 s per IP | Workers rate limiting binding in `wrangler.toml`. Optional. |

Secrets live in Cloudflare's secret store and take effect without a redeploy. Vars come from `[vars]` in `wrangler.toml` unless the deploy overrides them.

## Deploy by hand

You need a Cloudflare account (the free plan works) with a workers.dev subdomain, which the dashboard asks you to pick the first time you open Workers & Pages. You also need Node.js 22 or newer.

```bash
cd proxy
npx wrangler@4 login
npx wrangler@4 deploy
npx wrangler@4 secret put ANTHROPIC_API_KEY
npx wrangler@4 secret put ACCESS_CODE   # optional
```

`deploy` prints the Worker URL, `https://synapse-llm-proxy.<your-subdomain>.workers.dev`. The game's endpoint is that URL followed by `/v1/messages`. Until `ANTHROPIC_API_KEY` is set, API requests get `500`.

To change the vars, edit `[vars]` in `wrangler.toml` and deploy again, or override them once:

```bash
npx wrangler@4 deploy --var ALLOWED_ORIGINS:https://you.github.io MAX_TOKENS_CAP:512
```

To drop the access code, run `npx wrangler@4 secret delete ACCESS_CODE`.

Check the deployment:

```bash
curl https://synapse-llm-proxy.<your-subdomain>.workers.dev/

curl https://synapse-llm-proxy.<your-subdomain>.workers.dev/v1/messages \
  -H "origin: https://shotif.github.io" \
  -H "content-type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: <access code, if set>" \
  -d '{"model": "<an allowed model>", "max_tokens": 64, "messages": [{"role": "user", "content": "Say hello."}]}'
```

## Deploy with GitHub Actions

The **LLM proxy** workflow (`.github/workflows/llm-proxy.yml`) only runs when you start it from the Actions tab. It runs the tests, then deploys with `cloudflare/wrangler-action@v3` and Wrangler 4.

Repository secrets (Settings → Secrets and variables → Actions → Secrets):

| Secret | Required | Use |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | yes | A Cloudflare API token made from the "Edit Cloudflare Workers" template |
| `CLOUDFLARE_ACCOUNT_ID` | yes | Your Cloudflare account ID |
| `ANTHROPIC_API_KEY` | yes | Uploaded as the Worker secret `ANTHROPIC_API_KEY` |
| `SYNAPSE_PROXY_ACCESS_CODE` | no | Uploaded as the Worker secret `ACCESS_CODE`. When it is unset, the run deletes any `ACCESS_CODE` left by an earlier deploy, so the proxy runs without one. |

Repository variables (same page, Variables tab):

| Variable | Default | Sets |
|---|---|---|
| `SYNAPSE_PROXY_ALLOWED_ORIGINS` | `https://<repository owner, lowercased>.github.io` | `ALLOWED_ORIGINS` |
| `SYNAPSE_PROXY_ALLOWED_MODELS` | the `SYNAPSE_LLM_MODEL` variable, else the model in `wrangler.toml` | `ALLOWED_MODELS` |
| `SYNAPSE_PROXY_MAX_TOKENS` | `2048` | `MAX_TOKENS_CAP` |

These override `[vars]` in `wrangler.toml`.

A run:

1. Runs `node --test` in `proxy/`.
2. Stops with an error if `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` or `ANTHROPIC_API_KEY` is missing.
3. Uploads the secrets with `wrangler secret bulk`, then runs `wrangler deploy`. On the first run the Worker doesn't exist yet, so Wrangler creates a placeholder Worker to hold the secrets and the deploy replaces it.
4. Deletes a leftover `ACCESS_CODE` secret if `SYNAPSE_PROXY_ACCESS_CODE` is unset.
5. Calls `GET /` and writes the Worker URL, the value for the `SYNAPSE_LLM_ENDPOINT` repository variable (`<worker url>/v1/messages`) and the active settings to the job summary.

Copy that value into the `SYNAPSE_LLM_ENDPOINT` repository variable.

## Tests and local runs

```bash
cd proxy
node --test
```

The tests use Node's built-in test runner and need no install. They stub `fetch`, so they never call Anthropic.

To run the Worker locally, put the key in `.dev.vars` (git-ignored) inside `proxy/` and start Wrangler from there:

```bash
printf 'ANTHROPIC_API_KEY=sk-ant-...\n' > .dev.vars
npx wrangler@4 dev
```
