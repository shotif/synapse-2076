# Shared LLM backend (Claude API proxy)

A Cloudflare Worker that every copy of the SYNAPSE-2076 web build uses as its language model. You set it up once; players only switch the LLM on or off in the game.

The web build is static files on GitHub Pages. Anything in it is public, so it can never hold an Anthropic API key. This Worker keeps the key as a Cloudflare secret, picks the model and keeps a daily request budget, and the game calls the Worker instead of `api.anthropic.com`. Anyone who reads the web build can find the Worker's URL, so the Worker defends itself with an origin allowlist, an optional access code, a model allowlist, a `max_tokens` cap, request-size limits, a per-minute rate limit and daily request limits.

Without the Worker, the web build plays every faction with its built-in rules. Desktop builds and local models don't need it.

## Set it up

1. In the [Anthropic Console](https://console.anthropic.com/), create a workspace for the game, give it a monthly spend limit, and create an API key in it.
2. In Cloudflare (the free plan works), open Workers & Pages once so it asks you to pick a workers.dev subdomain. Then create an API token from the "Edit Cloudflare Workers" template and note your account ID.
3. In the GitHub repository, under Settings → Secrets and variables → Actions → Secrets, add `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` and `ANTHROPIC_API_KEY`.
4. Under Actions, run **LLM proxy**. Its job summary shows the backend's address, `https://synapse-llm-proxy.<your-subdomain>.workers.dev/v1/messages`.
5. Under Settings → Secrets and variables → Actions → Variables, set `SYNAPSE_LLM_ENDPOINT` to that address, then run **Deploy to GitHub Pages** (or push to `main`).

From then on every player's game uses the backend while their LLM switch is on (it starts on). To change the model or the limits later, set the repository variables below and run **LLM proxy** again; the game needs no new build.

## What a campaign costs

A faction decision is about 1,000 input tokens and a few hundred output tokens. A full 100-turn campaign sends about 330 requests: three faction decisions a turn, a crisis card Claude writes every third turn, and one request per message when a player calls a faction leader. On Claude Sonnet 5.5 ($2 per million input tokens and $10 per million output tokens when this was written) that is roughly half a cent a request, or $2–3 for a full campaign. Check current prices before you raise the limits.

The default limits are 1,000 requests per UTC day for everyone together (about $5 of game traffic) and 400 per player (one full campaign). When a limit is reached, the game falls back to its built-in rules and says so until the next UTC day. A single request can cost more than the game's do (up to 48,000 characters in and 2,048 tokens out, at most about 12 cents), so a script that fills the daily limit could spend up to about $120 in a day: keep the spend limit in step 1.

## What the game sees

The Worker speaks the native Anthropic Messages API:

| Request | Result |
|---|---|
| `GET /` | A plain-text health line: running, whether an access code is required, whether the API key is set, the model, the daily limits and today's count |
| `GET /v1/models` | The backend's model, looked up with the real key: `{"data": [<model>], "has_more": false, ...}`. The game uses it as its connection check. |
| `POST /v1/messages` | Checked, trimmed, counted and forwarded to `https://api.anthropic.com/v1/messages` |
| `OPTIONS` (CORS preflight) | `204` for an allowed origin, `403` for any other origin |

The web build points at `https://synapse-llm-proxy.<your-subdomain>.workers.dev/v1/messages` and sends no `model`: the first entry of `ALLOWED_MODELS` answers. If an access code is set, players open the game once with `#llm-key=<code>` after its address; the game keeps the code on that device and sends it as `x-api-key`. Other clients can send `Authorization: Bearer <code>` instead.

Upstream status codes and JSON bodies pass through unchanged. Errors the proxy produces itself use Anthropic's error shape, `{"type": "error", "error": {"type": "...", "message": "..."}}`, so the game handles both the same way. A `429` from the proxy adds `"limit"`: `"minute"` (the rate limiter), `"player"` or `"daily"` (everyone), with a `retry-after` header.

## What the proxy checks

For `POST /v1/messages`, in order:

1. The `Origin` header, if present, must be in `ALLOWED_ORIGINS`, or the answer is `403`.
2. If the `RATE_LIMITER` binding exists, the client IP must be under its limit (`429`).
3. A request without an `Origin` header is refused (`403`) unless `ACCESS_CODE` is set, and then it must pass step 4.
4. If `ACCESS_CODE` is set, the request must carry it (`401`). The comparison is constant-time.
5. The body must be at most 64 KiB (`413`) and a JSON object (`400`).
6. `model`, when the request names one, must be one of `ALLOWED_MODELS` (`400`). A request without a model gets the first one.
7. `messages` must be an array of 1 to 16 objects, each with the role `user` or `assistant` (`400`). A "Call a leader" negotiation sends its whole conversation: up to six player messages and the replies between them.
8. `system` and each message's `content` must be text: a string or `text` blocks (`400`). Image and document blocks are refused, because URL, file and PDF sources can bring in far more tokens than the character limit allows.
9. `system` plus all message content may hold at most 48,000 characters (`413`).
10. Today's limits must leave room (`429`). Only a request that passed every check above is counted.

Only `model`, `max_tokens`, `system`, `messages`, `temperature`, `top_p`, `top_k`, `stop_sequences`, `metadata` and `output_config` are forwarded. `output_config` may only be `{"effort": "low" | "medium" | "high"}` (`400` otherwise); the game sends `low` so Claude keeps its thinking short, and the proxy drops it for a model that takes no effort (Claude Haiku 4.5, Claude 3 and early Claude 4 models). Everything else (`tools`, `stream`, `thinking`, `mcp_servers`, `container`, ...) is dropped. `max_tokens` is clamped to `MAX_TOKENS_CAP` and set to the cap when it is missing or invalid.

Requests to Anthropic carry only `x-api-key` (the real key), `anthropic-version: 2023-06-01` and, for `POST`, `content-type: application/json`. No client header reaches Anthropic: not cookies, not the access code. If Anthropic can't be reached, the proxy answers `502`.

`GET /v1/models` goes through the same origin, rate-limit and access-code checks, and answers `429` once a daily limit is reached, without counting itself. A model that the key cannot use gives `500`, so the game stays offline instead of failing every request. `GET /` is rate-limited too.

## Security model

Know what each control does and what it doesn't do.

- **Origin allowlist.** Browsers attach the page's origin to every request and won't let a page read a response unless the proxy names that origin. Other websites therefore can't spend your key through their visitors' browsers. It does nothing against a script, which can send any `Origin` header it likes.
- **Requests without an Origin header** (curl, scripts) are refused unless an access code is set and supplied. This stops casual use of the URL as a free API. It is not a security boundary, because `Origin` is easy to fake.
- **Daily limits.** Every request passes through one counter (a Durable Object), so the counts are exact across Cloudflare's locations: `DAILY_REQUESTS` for everyone together and `DAILY_REQUESTS_PER_PLAYER` for each client IP address, per UTC day. They bound what the proxy can spend in a day even when someone scripts it. Players behind one address (a household, a school) share its allowance, and someone who changes addresses gets a new one, but never beyond the everyone-wide limit. The counter stores a hash of the day and the address, never the address, and forgets the previous day's entries. If the counter can't be reached, the proxy refuses requests (`503`) rather than spend uncounted.
- **Access code.** Optional. With `ACCESS_CODE` set, every API request must carry it, which keeps the backend to people you give the code. Players' browsers store it, so share it only with people you trust and change it when it leaks. Never put it in the web build, the repository or a public variable.
- **Model allowlist, `max_tokens` cap, text-only content and size limits** bound the cost of a single request.
- **Rate limiter.** `wrangler.toml` binds 60 requests per 60 seconds per client IP (one game turn sends three, plus one when Claude writes a crisis card and one per message in a negotiation). Cloudflare counts per location and approximately, so it slows a single client down but not a distributed one.
- **Spend limit.** The workspace spend limit in the Anthropic Console is the last, hard ceiling. If the proxy is abused, spending stops at the limit and nothing else in your organization is affected. Revoke the key there if you need to shut the proxy off immediately.
- **No request logging.** The Worker never logs request bodies, keys or access codes. Cloudflare still sees request metadata, and Workers Logs record more if you turn on observability.

## Configuration

| Name | Kind | Default | Meaning |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | secret | none, required | Key for every upstream call. Without it, API requests get `500`. |
| `ACCESS_CODE` | secret | unset | When set, API requests must send it as `x-api-key` or `Authorization: Bearer`. An empty value means no access code. Use a long random value, for example `openssl rand -hex 16`. |
| `ALLOWED_ORIGINS` | var | `https://shotif.github.io` | Comma-separated origins allowed to call the proxy from a browser. Paths and trailing slashes are ignored, so a page URL works too. Add `http://localhost:8060` to test a local web export. |
| `ALLOWED_MODELS` | var | `claude-sonnet-5-5` | Comma-separated exact model ids. The first one answers requests that name none (the web build's). If empty, every request is rejected. |
| `MAX_TOKENS_CAP` | var | `2048` | Upper bound for `max_tokens`, and the value used when a request omits it. Thinking counts toward it. |
| `DAILY_REQUESTS` | var | `1000` | Requests per UTC day for everyone together. `0` switches the limit off. |
| `DAILY_REQUESTS_PER_PLAYER` | var | `400` | Requests per UTC day for each client IP address. `0` switches the limit off. |
| `RATE_LIMITER` | binding | 60 requests / 60 s per IP | Workers rate limiting binding in `wrangler.toml`. Optional. |
| `USAGE` | binding | the `UsageMeter` Durable Object | Counts the daily limits. Required while a daily limit is on; without it, API requests get `500`. |

Secrets live in Cloudflare's secret store and take effect without a redeploy. Vars come from `[vars]` in `wrangler.toml` unless the deploy overrides them.

## Deploy by hand

You need a Cloudflare account (the free plan works, Durable Objects included) with a workers.dev subdomain, which the dashboard asks you to pick the first time you open Workers & Pages. You also need Node.js 22 or newer.

```bash
cd proxy
npx wrangler@4 login
npx wrangler@4 deploy
npx wrangler@4 secret put ANTHROPIC_API_KEY
npx wrangler@4 secret put ACCESS_CODE   # optional
```

`deploy` prints the Worker URL, `https://synapse-llm-proxy.<your-subdomain>.workers.dev`, and creates the `UsageMeter` Durable Object from the migration in `wrangler.toml`. The game's endpoint is that URL followed by `/v1/messages`. Until `ANTHROPIC_API_KEY` is set, API requests get `500`.

To change the vars, edit `[vars]` in `wrangler.toml` and deploy again, or override them once:

```bash
npx wrangler@4 deploy --var ALLOWED_MODELS:claude-sonnet-5-5 DAILY_REQUESTS:500
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
  -d '{"max_tokens": 64, "messages": [{"role": "user", "content": "Say hello."}]}'
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
| `SYNAPSE_PROXY_ALLOWED_MODELS` | the `SYNAPSE_LLM_MODEL` variable, else `claude-sonnet-5-5` | `ALLOWED_MODELS` (the first one serves the game) |
| `SYNAPSE_PROXY_MAX_TOKENS` | `2048` | `MAX_TOKENS_CAP` |
| `SYNAPSE_PROXY_DAILY_REQUESTS` | `1000` | `DAILY_REQUESTS` |
| `SYNAPSE_PROXY_DAILY_REQUESTS_PER_PLAYER` | `400` | `DAILY_REQUESTS_PER_PLAYER` |

These override `[vars]` in `wrangler.toml`.

A run:

1. Runs `node --test` in `proxy/`.
2. Stops with an error if `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` or `ANTHROPIC_API_KEY` is missing, or a setting is malformed.
3. Uploads the secrets with `wrangler secret bulk`, then runs `wrangler deploy`. On the first run the Worker doesn't exist yet, so Wrangler creates a placeholder Worker to hold the secrets and the deploy replaces it.
4. Deletes a leftover `ACCESS_CODE` secret if `SYNAPSE_PROXY_ACCESS_CODE` is unset.
5. Calls `GET /` and writes the Worker URL, the value for the `SYNAPSE_LLM_ENDPOINT` repository variable (`<worker url>/v1/messages`) and the active settings to the job summary.

Copy that value into the `SYNAPSE_LLM_ENDPOINT` repository variable and run **Deploy to GitHub Pages** once.

## Tests and local runs

```bash
cd proxy
node --test
```

The tests use Node's built-in test runner and need no install. They stub `fetch` and the `USAGE` namespace (with the real `UsageMeter` over an in-memory store), so they never call Anthropic or Cloudflare.

To run the Worker locally, put the key in `.dev.vars` (git-ignored) inside `proxy/` and start Wrangler from there. Low limits make the `429` easy to see:

```bash
printf 'ANTHROPIC_API_KEY=sk-ant-...\nDAILY_REQUESTS=3\nDAILY_REQUESTS_PER_PLAYER=2\n' > .dev.vars
npx wrangler@4 dev
```
