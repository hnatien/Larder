# larder-proxy

A Cloudflare Worker that sits between the Larder iOS app and the Claude API. It holds the Anthropic key, issues short-lived sessions to App Attest-verified devices, resolves the person's tier from their App Store transaction, meters calls per session per day, and turns each assist request into one structured-output call. The deterministic planner on the device makes every decision; this proxy only asks the model to explain or parse.

## Endpoints

All endpoints take and return JSON. Every response carries `content-type: application/json` and an `x-request-id`. Request and response shapes are Zod schemas in `src/schemas.ts`; the iOS client mirrors them.

| Route | Tier | Model (var) | Effort | Max tokens |
|---|---|---|---|---|
| `POST /v1/challenge` | none | none | | |
| `POST /v1/session` | none | none | | |
| `POST /v1/assist/explain` | free | `MODEL_FAST` | low | 2048 |
| `POST /v1/assist/parse-pantry` | free | `MODEL_FAST` | low | 1024 |
| `POST /v1/assist/parse-recipe` | Plus | `MODEL_CAPABLE` | medium | 1024 |
| `POST /v1/assist/adjust` | Plus | `MODEL_CAPABLE` | medium | 2048 |

Session flow: `POST /v1/challenge` returns `{ challenge, expiresAt }`. The device signs `clientDataHash = SHA-256(UTF-8 challenge)` and posts one of:

- `{ "kind": "appAttest", keyId, attestationObject, challenge }` the first time, with a new Secure Enclave key (`keyId` and `attestationObject` in standard base64, as `DCAppAttestService` returns them);
- `{ "kind": "appAssert", keyId, assertion, challenge }` for every later session;
- `{ "kind": "dev", clientSecret }` in development only.

Session errors: 401 `challenge_invalid` (forged or older than 5 minutes; fetch a new one), 401 `attestation_rejected` (the reason is logged, never returned), 401 `unknown_key` (the client should attest a new key), 409 `key_already_attested`, 500 `server_misconfigured` when `APPLE_TEAM_ID` is unset.

Request flow for assist routes: session (401) → entitlement (402 `plus_required` on Plus routes) → body validation (400 with Zod issues) → daily quota (429 `quota_exceeded` with `resetsAt`) → model call → quota increment → route-specific output checks.

Model outcomes: `stop_reason: "refusal"` → 422 `{ error: "declined", category }`; `"max_tokens"` → 502 `truncated`; output that fails the response schema → 502 `unparseable`; SDK `RateLimitError` → 429, `AuthenticationError` → 500 `internal_error` (logged), `APIConnectionError` → 503, other `APIError` → 502. Only successful calls count against the quota.

`/v1/assist/adjust` never applies a removal of a medical-axis constraint (allergens and intolerances live on that axis) or a replace that makes one anything other than hard. Those come back as 422 `protected_constraint`. The system prompt states the same rule.

### Examples

```sh
# 1. Get a session (dev attestation; needs ALLOW_DEV_ATTESTATION=true). Devices use /v1/challenge + App Attest.
curl -s -X POST http://localhost:8787/v1/session \
  -H 'content-type: application/json' \
  -d '{"attestation":{"kind":"dev","clientSecret":"<DEV_CLIENT_SECRET>"}}'
# {"token":"<token>","expiresAt":"2026-10-16T13:00:00.000Z"}

# 2. Explain a plan
curl -s -X POST http://localhost:8787/v1/assist/explain \
  -H 'content-type: application/json' -H 'authorization: Bearer <token>' \
  -d '{"plan":{"days":[{"date":"2026-10-19","meals":[{"slot":"dinner","recipeTitle":"Spinach dal","minutes":25,"reasonCodes":[{"code":"usesExpiring","params":{"food":"spinach"}}]}]}]},
       "shelfBalance":{"groupsLight":["produce"],"groupsHeavy":[]},
       "profileSummary":{"goal":"lessWaste","householdSize":2,"maxCookMinutes":30,"showsNumbers":false}}'

# 3. Parse a pantry note
curl -s -X POST http://localhost:8787/v1/assist/parse-pantry \
  -H 'content-type: application/json' -H 'authorization: Bearer <token>' \
  -d '{"text":"2 tins chickpeas, half a bag of spinach in the fridge"}'

# 4. Parse a recipe (Plus: send the StoreKit transaction JWS)
curl -s -X POST http://localhost:8787/v1/assist/parse-recipe \
  -H 'content-type: application/json' -H 'authorization: Bearer <token>' \
  -H 'x-larder-entitlement: <jwsRepresentation>' \
  -d '{"text":"Spinach dal. Serves 4. 200 g red lentils..."}'

# 5. Adjust constraints (Plus)
curl -s -X POST http://localhost:8787/v1/assist/adjust \
  -H 'content-type: application/json' -H 'authorization: Bearer <token>' \
  -H 'x-larder-entitlement: <jwsRepresentation>' \
  -d '{"instruction":"No fish on weeknights","currentConstraints":[],"planContext":{"days":[]}}'
```

## Running locally

```sh
npm install
cp .dev.vars.example .dev.vars   # fill in values; .dev.vars is gitignored
npx wrangler dev                 # http://localhost:8787, local KV
npm test                         # vitest
npm run typecheck                # tsc --noEmit
```

No Cloudflare account is needed for any of the above. Tests use a fake Anthropic client, an in-memory KV, and a certificate chain generated at test time, so no keys or private material are in the repository.

## Configuration

Vars live in `wrangler.toml`: `MODEL_FAST`, `MODEL_CAPABLE`, `ALLOW_DEV_ATTESTATION` (keep `"false"` in production), `FREE_DAILY_LIMIT`, `PLUS_DAILY_LIMIT`, `BUNDLE_ID` (the app's bundle id, `com.larder.Larder`; it is checked in App Store transactions and is half of the App Attest App ID), `APPLE_TEAM_ID` (the other half; required for App Attest) and `APP_ATTEST_ENVIRONMENT` (`production` or `development`, matching the app entitlement; default `production`). The `QUOTAS` namespace also stores App Attest keys. Replace the placeholder `QUOTAS` KV namespace ids with real ones (`wrangler kv namespace create QUOTAS`) before deploying.

Secrets are never written to a file in this directory. Set them per environment:

```sh
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put SESSION_SIGNING_KEY   # at least 32 random characters
npx wrangler secret put DEV_CLIENT_SECRET     # only used when ALLOW_DEV_ATTESTATION is "true"
```

Invalid or missing configuration returns 500 `server_misconfigured` and logs the variable names, never their values.

## What is implemented and what is not

Implemented:
- HMAC-SHA256 session tokens (1 hour, `tier: "anonymous"`), verified in constant time.
- Dev attestation with a constant-time secret comparison, off unless explicitly enabled.
- App Attest, following Apple's "Validating apps that connect to your server". Attestation: the attestation object's CBOR (`src/auth/cbor.ts`), the x5c chain credential → intermediate → Apple App Attestation Root CA (embedded in `src/auth/appleRoot.ts`, SHA-256 `1CB9823B…C932`), certificate validity, the nonce extension (`1.2.840.113635.100.8.2`) equal to SHA-256(authData ‖ clientDataHash), key id equal to SHA-256 of the credential public key and to the credential id, rpIdHash equal to SHA-256(`<APPLE_TEAM_ID>.<BUNDLE_ID>`), counter zero and the environment's AAGUID. The key's SPKI and counter go to KV (`appattest:key:<keyId>`, no expiry). Assertion: ECDSA P-256 signature over SHA-256(authenticatorData ‖ clientDataHash) with the stored key, rpIdHash, and a counter above the stored one, which is then saved. Challenges are stateless (random, expiry and an HMAC under `SESSION_SIGNING_KEY` with its own prefix), so the unauthenticated challenge endpoint writes nothing; replays are stopped by the registered-key and counter checks.
- App Attest sessions carry a subject derived from the key id (`subjectForKey`, a version 8 UUID of a hash), so a device keeps one daily quota across sessions. Dev sessions keep a random subject.
- Entitlement from the `x-larder-entitlement` header: ES256 JWS with an x5c chain checked leaf → intermediate → Apple Root CA - G3 (exact DER match against the embedded root), certificate validity, Apple's marker extensions on leaf and intermediate, then bundle id, expiry, revocation and product (`com.larder.plus.monthly`, `com.larder.plus.annual`). Anything else is the free tier, never an error. A small DER reader in `src/auth/der.ts` covers just what this needs.
- Per-subject daily quotas in KV (`quota:<sha256(sub)>:<yyyy-mm-dd>`, 2-day TTL).
- One structured log line per model call: route, model, status, latency, input, output, cache-read and cache-creation tokens. No prompt or output content is logged.

Not implemented:
- App Attest fraud-metric receipts. The attestation receipt is not stored or sent to Apple's receipt endpoint, so the risk metric is unused.
- Strict counter ordering across Cloudflare locations. KV is eventually consistent, so two assertions from one key reaching different locations within about a minute could both pass; each still needs its own fresh challenge and the device's private key.
- A real-device run. App Attest is unavailable on the Simulator; the verifier is tested against a generated chain with Apple's structure, not a genuine Apple attestation.
- Online certificate revocation checks (OCSP) for the x5c chain.
- Atomic quota counting. KV has no atomic increment, so concurrent calls can overshoot a limit slightly.

## Prompt caching

Each route's system prompt is a constant in `src/prompts/` and goes first as the only system block with `cache_control: { type: "ephemeral" }`. It never contains dates, ids or per-user text; the profile summary and the request go in the user turn. The output format object is built once per route so the request prefix stays byte-identical. `test/prompts.test.ts` guards these properties. Watch `cacheReadInputTokens` in the logs.

## Cost

From `docs/BLUEPRINT.md` section 5, at 30 requests per user-month (about 3k tokens in, 800 out): about $0.02 per user-month on Haiku 5.5 and $0.33-0.42 on Sonnet 5.5. A mixed routing lands near $0.10-0.15 per active user-month, inside the $4.17/month annual price. Routes read their model from `MODEL_FAST` / `MODEL_CAPABLE`, so an eval of about 200 labelled cases per task can move a route without a code change.

## Data retention

Requests carry derived flags and numbers, not names, emails, locations, exact weight or birth dates. Anthropic deletes API inputs and outputs within 30 days and does not train on them without permission. Zero data retention is available per organisation by agreement and covers the Messages API and prompt caching; request it once Larder is on a paid plan (Batch is not eligible). See `docs/research/04-nutrition-and-recommendation-engine.md`.
