import { createApp } from "../../src/app.js";
import { issueSessionToken } from "../../src/auth/session.js";
import type { Env } from "../../src/env.js";
import { FakeAnthropic } from "./fakeAnthropic.js";
import { MemoryKV } from "./memoryKv.js";

export const NOW = new Date("2026-10-16T12:00:00Z");
export const BUNDLE_ID = "com.larder.Larder";
export const TEAM_ID = "ABCDE12345";

/** Random per run so no secret-shaped values live in the repository. */
export const SIGNING_KEY = `${crypto.randomUUID()}${crypto.randomUUID()}`;
export const DEV_SECRET = crypto.randomUUID();

export function testEnv(overrides: Partial<Env> = {}): Env {
  return {
    QUOTAS: new MemoryKV(),
    MODEL_FAST: "claude-haiku-5-5",
    MODEL_CAPABLE: "claude-sonnet-5-5",
    ALLOW_DEV_ATTESTATION: "true",
    FREE_DAILY_LIMIT: "3",
    PLUS_DAILY_LIMIT: "60",
    BUNDLE_ID,
    APPLE_TEAM_ID: TEAM_ID,
    SESSION_SIGNING_KEY: SIGNING_KEY,
    DEV_CLIENT_SECRET: DEV_SECRET,
    ...overrides,
  };
}

export function makeHarness(
  options: { env?: Partial<Env>; trustedRootPEMs?: string[]; appAttestRootPEMs?: string[]; now?: Date } = {},
) {
  const anthropic = new FakeAnthropic();
  const kv = new MemoryKV();
  const env = testEnv(options.env);
  const app = createApp({
    anthropic,
    kv,
    now: () => options.now ?? NOW,
    env,
    trustedRootPEMs: options.trustedRootPEMs ?? [],
    appAttestRootPEMs: options.appAttestRootPEMs ?? [],
  });
  return { app, anthropic, kv, env };
}

export async function sessionToken(now: Date = NOW, key: string = SIGNING_KEY): Promise<string> {
  return (await issueSessionToken(key, now)).token;
}

export function post(
  app: ReturnType<typeof createApp>,
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
  return app.fetch(
    new Request(`https://proxy.test${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", ...headers },
      body: typeof body === "string" ? body : JSON.stringify(body),
    }),
  );
}

export async function authed(token?: string): Promise<Record<string, string>> {
  return { authorization: `Bearer ${token ?? (await sessionToken())}` };
}
