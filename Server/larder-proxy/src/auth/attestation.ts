import { z } from "zod";
import { bytesEqual, utf8 } from "../encoding.js";
import { errorReply, type ErrorReply } from "../http.js";

/** Body of `POST /v1/session`. */
export const AttestationSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("dev"), clientSecret: z.string().min(1).max(512) }),
  z.object({
    kind: z.literal("appAttest"),
    keyId: z.string().min(1),
    attestationObject: z.string().min(1),
    challenge: z.string().min(1),
  }),
]);

export const SessionRequestSchema = z.object({ attestation: AttestationSchema });

export type Attestation = z.infer<typeof AttestationSchema>;

/** Proves a request comes from a genuine Larder client. `null` means accepted. */
export interface Attestor {
  verify(attestation: Attestation): Promise<ErrorReply | null>;
}

/** Shared-secret attestation for local development and CI; disabled unless explicitly allowed. */
export class DevAttestor implements Attestor {
  constructor(private readonly options: { enabled: boolean; clientSecret: string | undefined }) {}

  async verify(attestation: Attestation): Promise<ErrorReply | null> {
    if (attestation.kind !== "dev") return errorReply(400, "wrong_attestation_kind");
    if (!this.options.enabled) return errorReply(403, "dev_attestation_disabled");
    if (!this.options.clientSecret) return errorReply(500, "server_misconfigured");
    const matches = await constantTimeEqual(attestation.clientSecret, this.options.clientSecret);
    return matches ? null : errorReply(401, "attestation_rejected");
  }
}

/** App Attest verification is not implemented yet; this keeps the interface in place and says so. */
export class AppAttestAttestor implements Attestor {
  async verify(): Promise<ErrorReply | null> {
    return errorReply(501, "app_attest_not_implemented", {
      message: "App Attest verification is not implemented in this proxy yet. Use dev attestation in development.",
    });
  }
}

// Hashing first gives equal-length inputs, so the comparison time does not depend on the secret's length or content.
async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  const [hashA, hashB] = await Promise.all([
    crypto.subtle.digest("SHA-256", utf8(a)),
    crypto.subtle.digest("SHA-256", utf8(b)),
  ]);
  return bytesEqual(new Uint8Array(hashA), new Uint8Array(hashB));
}
