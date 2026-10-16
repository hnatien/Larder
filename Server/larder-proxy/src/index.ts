import Anthropic from "@anthropic-ai/sdk";
import { createApp } from "./app.js";
import { APPLE_APP_ATTESTATION_ROOT_CA_PEM, APPLE_ROOT_CA_G3_PEM } from "./auth/appleRoot.js";
import type { Env } from "./env.js";
import { json } from "./http.js";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (!env.ANTHROPIC_API_KEY) {
      console.error(JSON.stringify({ event: "config_invalid", variables: ["ANTHROPIC_API_KEY"] }));
      return json(500, { error: "server_misconfigured" }, crypto.randomUUID());
    }
    const app = createApp({
      anthropic: new Anthropic({ apiKey: env.ANTHROPIC_API_KEY }),
      kv: env.QUOTAS,
      now: () => new Date(),
      env,
      trustedRootPEMs: [APPLE_ROOT_CA_G3_PEM],
      appAttestRootPEMs: [APPLE_APP_ATTESTATION_ROOT_CA_PEM],
    });
    return app.fetch(request);
  },
};
