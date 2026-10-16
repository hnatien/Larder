import type { KVNamespaceLike } from "../../src/env.js";

export class MemoryKV implements KVNamespaceLike {
  readonly store = new Map<string, { value: string; expirationTtl?: number }>();

  async get(key: string): Promise<string | null> {
    return this.store.get(key)?.value ?? null;
  }

  async put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void> {
    this.store.set(key, { value, expirationTtl: options?.expirationTtl });
  }
}
