import { z } from "zod";
import { bytesEqual, fromBase64, fromBase64Url, fromUtf8, utf8 } from "../encoding.js";
import { importPublicKey, isSignedBy, parseCertificate, pemToDer, type Certificate } from "./x509.js";

/** Header carrying the App Store Server API signed transaction (JWS) for the current subscription. */
export const ENTITLEMENT_HEADER = "x-larder-entitlement";

/** Product identifiers that grant Larder Plus. */
export const PLUS_PRODUCT_IDS: ReadonlySet<string> = new Set(["com.larder.plus.monthly", "com.larder.plus.annual"]);

// Apple marker extensions, as checked by Apple's App Store Server Library.
const LEAF_MARKER_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_MARKER_OID = "1.2.840.113635.100.6.2.1";

/** Why a transaction did or did not grant Plus; safe to log. */
export type EntitlementReason =
  | "verified"
  | "missing"
  | "malformed"
  | "untrusted_root"
  | "invalid_chain"
  | "certificate_expired"
  | "invalid_signature"
  | "wrong_bundle"
  | "expired"
  | "revoked"
  | "unknown_product";

/** Outcome of entitlement resolution. Anything other than a verified Plus transaction is the free tier. */
export interface Entitlement {
  tier: "plus" | "free";
  reason: EntitlementReason;
}

const HeaderSchema = z.object({
  alg: z.literal("ES256"),
  x5c: z.array(z.string().min(1)).length(3),
});

const PayloadSchema = z.object({
  bundleId: z.string(),
  productId: z.string(),
  expiresDate: z.number().optional(),
  revocationDate: z.number().optional(),
});

const free = (reason: EntitlementReason): Entitlement => ({ tier: "free", reason });

/**
 * Verifies a signed transaction: x5c chain leaf -> intermediate -> trusted root (exact DER match),
 * certificate validity and Apple marker OIDs, the ES256 JWS signature, then bundle, expiry,
 * revocation and product. Never throws; any failure resolves to the free tier.
 */
export async function verifySignedTransaction(
  jws: string | null,
  options: { now: Date; appleRootPEMs: readonly string[]; bundleId: string },
): Promise<Entitlement> {
  if (!jws) return free("missing");
  const parts = jws.split(".");
  if (parts.length !== 3) return free("malformed");
  const [headerPart, payloadPart, signaturePart] = parts as [string, string, string];

  let header: z.infer<typeof HeaderSchema>;
  let payload: z.infer<typeof PayloadSchema>;
  let chain: Certificate[];
  let signature: Uint8Array<ArrayBuffer>;
  try {
    const headerResult = HeaderSchema.safeParse(JSON.parse(fromUtf8(fromBase64Url(headerPart))));
    const payloadResult = PayloadSchema.safeParse(JSON.parse(fromUtf8(fromBase64Url(payloadPart))));
    if (!headerResult.success || !payloadResult.success) return free("malformed");
    header = headerResult.data;
    payload = payloadResult.data;
    chain = header.x5c.map((entry) => parseCertificate(fromBase64(entry)));
    signature = fromBase64Url(signaturePart);
  } catch {
    return free("malformed");
  }

  const [leaf, intermediate, root] = chain as [Certificate, Certificate, Certificate];
  let trustedRoots: Uint8Array[];
  try {
    trustedRoots = options.appleRootPEMs.map(pemToDer);
  } catch {
    return free("untrusted_root");
  }
  if (!trustedRoots.some((trusted) => bytesEqual(trusted, root.der))) return free("untrusted_root");
  if (!leaf.extensions.has(LEAF_MARKER_OID) || !intermediate.extensions.has(INTERMEDIATE_MARKER_OID)) {
    return free("invalid_chain");
  }
  const nowMs = options.now.getTime();
  if (chain.some((cert) => cert.notBefore.getTime() > nowMs || cert.notAfter.getTime() < nowMs)) {
    return free("certificate_expired");
  }

  try {
    if (!(await isSignedBy(intermediate, root)) || !(await isSignedBy(leaf, intermediate))) {
      return free("invalid_chain");
    }
    if (leaf.curve !== "P-256" || signature.length !== 64) return free("invalid_signature");
    const verified = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      await importPublicKey(leaf),
      signature,
      utf8(`${headerPart}.${payloadPart}`),
    );
    if (!verified) return free("invalid_signature");
  } catch {
    return free("invalid_chain");
  }

  if (payload.bundleId !== options.bundleId) return free("wrong_bundle");
  if (payload.revocationDate !== undefined) return free("revoked");
  if (payload.expiresDate === undefined || payload.expiresDate <= nowMs) return free("expired");
  if (!PLUS_PRODUCT_IDS.has(payload.productId)) return free("unknown_product");
  return { tier: "plus", reason: "verified" };
}
