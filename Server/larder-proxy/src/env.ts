import { z } from "zod";
import type { AnthropicLike } from "./model.js";

/** Minimal KV surface the proxy uses; Cloudflare's KVNamespace satisfies it. */
export interface KVNamespaceLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

/** Raw Worker bindings: vars from wrangler.toml plus secrets set with `wrangler secret put`. */
export interface Env {
  QUOTAS: KVNamespaceLike;
  MODEL_FAST?: string;
  MODEL_CAPABLE?: string;
  ALLOW_DEV_ATTESTATION?: string;
  FREE_DAILY_LIMIT?: string;
  PLUS_DAILY_LIMIT?: string;
  BUNDLE_ID?: string;
  ANTHROPIC_API_KEY?: string;
  SESSION_SIGNING_KEY?: string;
  DEV_CLIENT_SECRET?: string;
}

const DailyLimit = z.string().regex(/^\d{1,6}$/).transform(Number);

const ConfigSchema = z.object({
  MODEL_FAST: z.string().min(1),
  MODEL_CAPABLE: z.string().min(1),
  ALLOW_DEV_ATTESTATION: z.enum(["true", "false"]).transform((value) => value === "true"),
  FREE_DAILY_LIMIT: DailyLimit,
  PLUS_DAILY_LIMIT: DailyLimit,
  BUNDLE_ID: z.string().min(1),
  SESSION_SIGNING_KEY: z.string().min(32),
  DEV_CLIENT_SECRET: z.string().min(1).optional(),
});

/** Validated configuration derived from `Env`. */
export interface Config {
  modelFast: string;
  modelCapable: string;
  allowDevAttestation: boolean;
  freeDailyLimit: number;
  plusDailyLimit: number;
  bundleId: string;
  sessionSigningKey: string;
  devClientSecret: string | undefined;
}

/** Thrown when bindings are missing or malformed; carries only the offending variable names. */
export class ConfigError extends Error {
  constructor(readonly variables: string[]) {
    super(`Invalid configuration: ${variables.join(", ")}`);
    this.name = "ConfigError";
  }
}

/** Validates the Worker bindings, throwing `ConfigError` naming (never echoing) bad variables. */
export function parseConfig(env: Env): Config {
  const result = ConfigSchema.safeParse(env);
  if (!result.success) {
    throw new ConfigError([...new Set(result.error.issues.map((issue) => String(issue.path[0])))]);
  }
  const value = result.data;
  return {
    modelFast: value.MODEL_FAST,
    modelCapable: value.MODEL_CAPABLE,
    allowDevAttestation: value.ALLOW_DEV_ATTESTATION,
    freeDailyLimit: value.FREE_DAILY_LIMIT,
    plusDailyLimit: value.PLUS_DAILY_LIMIT,
    bundleId: value.BUNDLE_ID,
    sessionSigningKey: value.SESSION_SIGNING_KEY,
    devClientSecret: value.DEV_CLIENT_SECRET,
  };
}

/** Everything `createApp` needs; injected so tests can replace the model client, KV and clock. */
export interface AppDeps {
  anthropic: AnthropicLike;
  kv: KVNamespaceLike;
  now: () => Date;
  env: Env;
  trustedRootPEMs: readonly string[];
}
