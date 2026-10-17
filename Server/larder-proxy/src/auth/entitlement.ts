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

/** The `environment` of transactions signed locally by StoreKit testing in Xcode. */
const XCODE_ENVIRONMENT = "Xcode";

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
  | "unknown_product"
  | "xcode_not_allowed";

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
  environment: z.string().optional(),
  expiresDate: z.number().optional(),
  revocationDate: z.number().optional(),
});

const free = (reason: EntitlementReason): Entitlement => ({ tier: "free", reason });

/**
 * Verifies a signed transaction: x5c chain leaf -> intermediate -> trusted root (exact DER match),
 * certificate validity and Apple marker OIDs, the ES256 JWS signature, then bundle, expiry,
 * revocation and product. A transaction from StoreKit testing in Xcode is signed by a local
 * certificate that chains to no Apple root, so with `allowXcodeTransactions` its signature is
 * skipped, as Apple's App Store Server Library does for that environment; the payload checks still
 * apply. Never throws; any failure resolves to the free tier.
 */
export async function verifySignedTransaction(
  jws: string | null,
  options: { now: Date; appleRootPEMs: readonly string[]; bundleId: string; allowXcodeTransactions: boolean },
): Promise<Entitlement> {
  if (!jws) return free("missing");
  const parts = jws.split(".");
  if (parts.length !== 3) return free("malformed");
  const [headerPart, payloadPart, signaturePart] = parts as [string, string, string];

  let payload: z.infer<typeof PayloadSchema>;
  try {
    const payloadResult = PayloadSchema.safeParse(JSON.parse(fromUtf8(fromBase64Url(payloadPart))));
    if (!payloadResult.success) return free("malformed");
    payload = payloadResult.data;
  } catch {
    return free("malformed");
  }

  const nowMs = options.now.getTime();
  if (payload.environment === XCODE_ENVIRONMENT) {
    if (!options.allowXcodeTransactions) return free("xcode_not_allowed");
  } else {
    const failure = await verifyAppleSignature(headerPart, payloadPart, signaturePart, options.appleRootPEMs, nowMs);
    if (failure) return free(failure);
  }

  if (payload.bundleId !== options.bundleId) return free("wrong_bundle");
  if (payload.revocationDate !== undefined) return free("revoked");
  if (payload.expiresDate === undefined || payload.expiresDate <= nowMs) return free("expired");
  if (!PLUS_PRODUCT_IDS.has(payload.productId)) return free("unknown_product");
  return { tier: "plus", reason: "verified" };
}

/** Checks the x5c chain up to a trusted root and the JWS signature; returns why it failed, if it did. */
async function verifyAppleSignature(
  headerPart: string,
  payloadPart: string,
  signaturePart: string,
  appleRootPEMs: readonly string[],
  nowMs: number,
): Promise<EntitlementReason | undefined> {
  let chain: Certificate[];
  let signature: Uint8Array<ArrayBuffer>;
  try {
    const headerResult = HeaderSchema.safeParse(JSON.parse(fromUtf8(fromBase64Url(headerPart))));
    if (!headerResult.success) return "malformed";
    chain = headerResult.data.x5c.map((entry) => parseCertificate(fromBase64(entry)));
    signature = fromBase64Url(signaturePart);
  } catch {
    return "malformed";
  }

  const [leaf, intermediate, root] = chain as [Certificate, Certificate, Certificate];
  let trustedRoots: Uint8Array[];
  try {
    trustedRoots = appleRootPEMs.map(pemToDer);
  } catch {
    return "untrusted_root";
  }
  if (!trustedRoots.some((trusted) => bytesEqual(trusted, root.der))) return "untrusted_root";
  if (!leaf.extensions.has(LEAF_MARKER_OID) || !intermediate.extensions.has(INTERMEDIATE_MARKER_OID)) {
    return "invalid_chain";
  }
  if (chain.some((cert) => cert.notBefore.getTime() > nowMs || cert.notAfter.getTime() < nowMs)) {
    return "certificate_expired";
  }

  try {
    if (!(await isSignedBy(intermediate, root)) || !(await isSignedBy(leaf, intermediate))) {
      return "invalid_chain";
    }
    if (leaf.curve !== "P-256" || signature.length !== 64) return "invalid_signature";
    const verified = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      await importPublicKey(leaf),
      signature,
      utf8(`${headerPart}.${payloadPart}`),
    );
    if (!verified) return "invalid_signature";
  } catch {
    return "invalid_chain";
  }
  return undefined;
}
