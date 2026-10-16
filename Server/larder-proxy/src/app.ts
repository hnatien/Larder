import type { z } from "zod";
import { AppAttestAttestor, DevAttestor, SessionRequestSchema, type Attestor } from "./auth/attestation.js";
import { issueChallenge } from "./auth/challenge.js";
import { ENTITLEMENT_HEADER, verifySignedTransaction } from "./auth/entitlement.js";
import { issueSessionToken, requireSession } from "./auth/session.js";
import { ConfigError, parseConfig, type AppDeps, type Config } from "./env.js";
import { errorReply, json, type ErrorReply } from "./http.js";
import { callModel } from "./model.js";
import { checkQuota, recordUsage } from "./quota.js";
import { adjustRoute } from "./routes/adjust.js";
import { explainRoute } from "./routes/explain.js";
import { parsePantryRoute } from "./routes/parsePantry.js";
import { parseRecipeRoute } from "./routes/parseRecipe.js";
import type { AssistRoute } from "./routes/route.js";

interface Context {
  request: Request;
  requestId: string;
  config: Config;
  deps: AppDeps;
}

type Handler = (context: Context) => Promise<ErrorReply | { status: 200; body: unknown }>;

const routes: Record<string, Handler> = {
  "/v1/challenge": handleChallenge,
  "/v1/session": handleSession,
  "/v1/assist/explain": (context) => handleAssist(explainRoute, context),
  "/v1/assist/parse-pantry": (context) => handleAssist(parsePantryRoute, context),
  "/v1/assist/parse-recipe": (context) => handleAssist(parseRecipeRoute, context),
  "/v1/assist/adjust": (context) => handleAssist(adjustRoute, context),
};

/** Builds the Worker's fetch handler from injected dependencies. */
export function createApp(deps: AppDeps): { fetch(request: Request): Promise<Response> } {
  return {
    async fetch(request) {
      const requestId = crypto.randomUUID();
      const handler = routes[new URL(request.url).pathname];
      if (!handler) return json(404, { error: "not_found" }, requestId);
      if (request.method !== "POST") return json(405, { error: "method_not_allowed" }, requestId);
      try {
        const config = parseConfig(deps.env);
        const reply = await handler({ request, requestId, config, deps });
        return json(reply.status, reply.body, requestId);
      } catch (error) {
        if (error instanceof ConfigError) {
          console.error(JSON.stringify({ event: "config_invalid", requestId, variables: error.variables }));
          return json(500, { error: "server_misconfigured" }, requestId);
        }
        console.error(
          JSON.stringify({ event: "unhandled_error", requestId, name: error instanceof Error ? error.name : "unknown" }),
        );
        return json(500, { error: "internal_error" }, requestId);
      }
    },
  };
}

async function readBody<T>(request: Request, schema: z.ZodType<T>): Promise<{ ok: true; body: T } | { ok: false; reply: ErrorReply }> {
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return { ok: false, reply: errorReply(400, "invalid_json") };
  }
  const result = schema.safeParse(raw);
  if (!result.success) {
    const issues = result.error.issues.map((issue) => ({
      path: issue.path.map(String).join("."),
      code: issue.code,
      message: issue.message,
    }));
    return { ok: false, reply: errorReply(400, "invalid_request", { issues }) };
  }
  return { ok: true, body: result.data };
}

async function handleChallenge({ config, deps }: Context) {
  return { status: 200 as const, body: await issueChallenge(config.sessionSigningKey, deps.now()) };
}

async function handleSession({ request, requestId, config, deps }: Context) {
  const parsed = await readBody(request, SessionRequestSchema);
  if (!parsed.ok) return parsed.reply;
  const attestation = parsed.body.attestation;
  const now = deps.now();
  const attestor: Attestor =
    attestation.kind === "dev"
      ? new DevAttestor({ enabled: config.allowDevAttestation, clientSecret: config.devClientSecret })
      : new AppAttestAttestor({
          kv: deps.kv,
          signingKey: config.sessionSigningKey,
          teamId: config.appleTeamId,
          bundleId: config.bundleId,
          environment: config.appAttestEnvironment,
          rootPEMs: deps.appAttestRootPEMs,
          now,
        });
  const result = await attestor.verify(attestation);
  if (!result.accepted) {
    if (result.reason) {
      console.warn(JSON.stringify({ event: "attestation_rejected", requestId, kind: attestation.kind, reason: result.reason }));
    }
    return result.reply;
  }
  const { token, claims } = await issueSessionToken(config.sessionSigningKey, now, result.subject);
  return { status: 200 as const, body: { token, expiresAt: new Date(claims.exp * 1000).toISOString() } };
}

async function handleAssist<Req, Res>(route: AssistRoute<Req, Res>, { request, requestId, config, deps }: Context) {
  const now = deps.now();
  const session = await requireSession(request, config.sessionSigningKey, now);
  if (!session.ok) return errorReply(401, "unauthorized");

  const entitlement = await verifySignedTransaction(request.headers.get(ENTITLEMENT_HEADER), {
    now,
    appleRootPEMs: deps.trustedRootPEMs,
    bundleId: config.bundleId,
  });
  if (route.requiresPlus && entitlement.tier !== "plus") return errorReply(402, "plus_required");

  const parsed = await readBody(request, route.requestSchema);
  if (!parsed.ok) return parsed.reply;

  const limit = entitlement.tier === "plus" ? config.plusDailyLimit : config.freeDailyLimit;
  const quota = await checkQuota(deps.kv, session.claims.sub, limit, now);
  if (!quota.allowed) return errorReply(429, "quota_exceeded", { resetsAt: quota.resetsAt });

  const model = route.model(config);
  const result = await callModel(deps.anthropic, route.buildRequest(parsed.body, model), {
    requestId,
    route: route.name,
    model,
  });
  if (!result.ok) return result.reply;
  await recordUsage(deps.kv, quota);

  const rejection = route.checkOutput?.(result.output);
  if (rejection) return rejection;
  return { status: 200 as const, body: result.output };
}
