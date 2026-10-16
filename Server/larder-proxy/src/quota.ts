import type { KVNamespaceLike } from "./env.js";
import { sha256Hex } from "./encoding.js";

/** Counters live two days so a day's key outlives its UTC day in every timezone. */
export const QUOTA_TTL_SECONDS = 2 * 24 * 60 * 60;

/** Result of a quota check; `key` and `used` feed `recordUsage` after a successful model call. */
export interface QuotaStatus {
  allowed: boolean;
  key: string;
  used: number;
  limit: number;
  resetsAt: string;
}

/** Reads today's (UTC) counter for a session subject. The subject is hashed so KV never stores it. */
export async function checkQuota(kv: KVNamespaceLike, subject: string, limit: number, now: Date): Promise<QuotaStatus> {
  const day = now.toISOString().slice(0, 10);
  const key = `quota:${await sha256Hex(subject)}:${day}`;
  const stored = Number.parseInt((await kv.get(key)) ?? "0", 10);
  const used = Number.isFinite(stored) && stored > 0 ? stored : 0;
  const resetsAt = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)).toISOString();
  return { allowed: used < limit, key, used, limit, resetsAt };
}

/**
 * Records one successful call. KV has no atomic increment, so two concurrent calls can both read the
 * same count; the limit is a cost guard, not a billing meter, and can be exceeded by that race.
 */
export async function recordUsage(kv: KVNamespaceLike, status: QuotaStatus): Promise<void> {
  await kv.put(status.key, String(status.used + 1), { expirationTtl: QUOTA_TTL_SECONDS });
}
