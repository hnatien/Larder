import { describe, expect, it } from "vitest";
import { checkQuota, QUOTA_TTL_SECONDS, recordUsage } from "../src/quota.js";
import { sha256Hex } from "../src/encoding.js";
import { MemoryKV } from "./helpers/memoryKv.js";
import { NOW } from "./helpers/fixtures.js";

describe("quota", () => {
  it("keys counters by hashed subject and UTC day, never the raw subject", async () => {
    const kv = new MemoryKV();
    const status = await checkQuota(kv, "subject-1", 3, NOW);
    expect(status.key).toBe(`quota:${await sha256Hex("subject-1")}:2026-10-16`);
    expect(status.key).not.toContain("subject-1");
  });

  it("allows until the limit, then blocks with the next UTC midnight as reset", async () => {
    const kv = new MemoryKV();
    for (let i = 0; i < 2; i++) await recordUsage(kv, await checkQuota(kv, "s", 2, NOW));
    const status = await checkQuota(kv, "s", 2, NOW);
    expect(status).toMatchObject({ allowed: false, used: 2, limit: 2, resetsAt: "2026-10-17T00:00:00.000Z" });
  });

  it("writes counters with a two-day TTL", async () => {
    const kv = new MemoryKV();
    const status = await checkQuota(kv, "s", 2, NOW);
    await recordUsage(kv, status);
    expect(kv.store.get(status.key)).toEqual({ value: "1", expirationTtl: QUOTA_TTL_SECONDS });
    expect(QUOTA_TTL_SECONDS).toBe(172_800);
  });

  it("starts a fresh counter on the next UTC day", async () => {
    const kv = new MemoryKV();
    await recordUsage(kv, await checkQuota(kv, "s", 1, NOW));
    const tomorrow = new Date("2026-10-17T00:00:01Z");
    expect((await checkQuota(kv, "s", 1, tomorrow)).allowed).toBe(true);
  });

  it("treats a corrupt counter as zero so the next success overwrites it", async () => {
    const kv = new MemoryKV();
    const { key } = await checkQuota(kv, "s", 1, NOW);
    await kv.put(key, "garbage");
    expect((await checkQuota(kv, "s", 1, NOW)).used).toBe(0);
  });

  it("blocks everything when the limit is zero", async () => {
    expect((await checkQuota(new MemoryKV(), "s", 0, NOW)).allowed).toBe(false);
  });
});
