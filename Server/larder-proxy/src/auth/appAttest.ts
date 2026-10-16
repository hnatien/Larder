import { bytesEqual, concatBytes, utf8 } from "../encoding.js";
import { cborBytes, cborMap, decodeCbor, CborError } from "./cbor.js";
import { DerError, Tag, children, expectTag, readRoot } from "./der.js";
import { derSignatureToRaw, isSignedBy, parseCertificate, pemToDer, type Certificate } from "./x509.js";

/** Credential certificate extension holding the attestation nonce. */
export const APP_ATTEST_NONCE_OID = "1.2.840.113635.100.8.2";

/** `appattestdevelop` for the development environment, `appattest` plus seven zero bytes for production. */
const AAGUIDS = {
  development: utf8("appattestdevelop"),
  production: concatBytes(utf8("appattest"), new Uint8Array(7)),
} as const;

// Authenticator data: rpIdHash (32) | flags (1) | signCount (4) | aaguid (16) | credentialIdLength (2) | credentialId.
const RP_ID_HASH_END = 32;
const FLAGS_OFFSET = 32;
const COUNTER_OFFSET = 33;
const AAGUID_OFFSET = 37;
const CREDENTIAL_LENGTH_OFFSET = 53;
const CREDENTIAL_ID_OFFSET = 55;
const ATTESTED_CREDENTIAL_FLAG = 0x40;

export type AppAttestEnvironment = keyof typeof AAGUIDS;

/** Why an attestation or assertion was rejected; safe to log, never returned to the client. */
export type AppAttestFailure =
  | "malformed"
  | "wrong_format"
  | "untrusted_root"
  | "invalid_chain"
  | "certificate_expired"
  | "nonce_mismatch"
  | "key_id_mismatch"
  | "wrong_app"
  | "wrong_environment"
  | "bad_counter"
  | "invalid_signature";

/** What the server keeps per attested key: the credential certificate's SPKI and the last seen counter. */
export interface AttestedKey {
  spki: Uint8Array;
  counter: number;
}

export interface AppAttestContext {
  /** `<Team ID>.<bundle id>`, whose SHA-256 must be the authenticator data's rpIdHash. */
  appId: string;
  environment: AppAttestEnvironment;
  rootPEMs: readonly string[];
  now: Date;
}

type Outcome<T> = ({ ok: true } & T) | { ok: false; reason: AppAttestFailure };

/**
 * Verifies an App Attest attestation object, following Apple's "Validating apps that connect to your
 * server": credential certificate chain to the App Attestation root, nonce extension equal to
 * SHA-256(authData || clientDataHash), key id equal to SHA-256 of the credential public key, rpIdHash,
 * zero counter, environment AAGUID and credential id. Never throws.
 */
export async function verifyAttestation(
  input: { keyId: Uint8Array; attestationObject: Uint8Array; clientDataHash: Uint8Array },
  context: AppAttestContext,
): Promise<Outcome<{ key: AttestedKey }>> {
  let credential: Certificate;
  let intermediate: Certificate;
  let authData: Uint8Array;
  try {
    const object = cborMap(decodeCbor(input.attestationObject), "attestation");
    if (object.get("fmt") !== "apple-appattest") return { ok: false, reason: "wrong_format" };
    const statement = cborMap(object.get("attStmt"), "attStmt");
    const x5c = statement.get("x5c");
    if (!Array.isArray(x5c) || x5c.length !== 2 || !x5c.every((entry) => entry instanceof Uint8Array)) {
      return { ok: false, reason: "malformed" };
    }
    [credential, intermediate] = (x5c as Uint8Array[]).map(parseCertificate) as [Certificate, Certificate];
    authData = cborBytes(object, "authData");
  } catch (error) {
    if (error instanceof CborError || error instanceof DerError) return { ok: false, reason: "malformed" };
    throw error;
  }
  if (authData.length < CREDENTIAL_ID_OFFSET) return { ok: false, reason: "malformed" };

  const chain = await verifyChain(credential, intermediate, context);
  if (chain) return { ok: false, reason: chain };

  const nonce = await sha256(concatBytes(authData, input.clientDataHash));
  const embedded = credential.extensions.get(APP_ATTEST_NONCE_OID);
  if (!embedded || !bytesEqual(readNonce(embedded) ?? new Uint8Array(), nonce)) {
    return { ok: false, reason: "nonce_mismatch" };
  }
  if (credential.curve !== "P-256" || !bytesEqual(await sha256(credential.publicKey), input.keyId)) {
    return { ok: false, reason: "key_id_mismatch" };
  }
  if (!bytesEqual(authData.subarray(0, RP_ID_HASH_END), await sha256(utf8(context.appId)))) {
    return { ok: false, reason: "wrong_app" };
  }
  if (readCounter(authData) !== 0) return { ok: false, reason: "bad_counter" };
  if (!bytesEqual(authData.subarray(AAGUID_OFFSET, CREDENTIAL_LENGTH_OFFSET), AAGUIDS[context.environment])) {
    return { ok: false, reason: "wrong_environment" };
  }
  const flags = authData[FLAGS_OFFSET] ?? 0;
  const credentialLength = ((authData[CREDENTIAL_LENGTH_OFFSET] ?? 0) << 8) | (authData[CREDENTIAL_LENGTH_OFFSET + 1] ?? 0);
  const credentialId = authData.subarray(CREDENTIAL_ID_OFFSET, CREDENTIAL_ID_OFFSET + credentialLength);
  if ((flags & ATTESTED_CREDENTIAL_FLAG) === 0 || !bytesEqual(credentialId, input.keyId)) {
    return { ok: false, reason: "key_id_mismatch" };
  }
  return { ok: true, key: { spki: credential.spki, counter: 0 } };
}

/**
 * Verifies an App Attest assertion against a stored key: ECDSA P-256 / SHA-256 signature over
 * SHA-256(authenticatorData || clientDataHash), rpIdHash, and a counter strictly above the stored one.
 * Returns the new counter to store. Never throws.
 */
export async function verifyAssertion(
  input: { assertion: Uint8Array; clientDataHash: Uint8Array; key: AttestedKey },
  context: Pick<AppAttestContext, "appId">,
): Promise<Outcome<{ counter: number }>> {
  let signature: Uint8Array;
  let authenticatorData: Uint8Array;
  try {
    const object = cborMap(decodeCbor(input.assertion), "assertion");
    signature = derSignatureToRaw(cborBytes(object, "signature"), 32);
    authenticatorData = cborBytes(object, "authenticatorData");
  } catch (error) {
    if (error instanceof CborError || error instanceof DerError) return { ok: false, reason: "malformed" };
    throw error;
  }
  if (authenticatorData.length < AAGUID_OFFSET) return { ok: false, reason: "malformed" };

  const nonce = await sha256(concatBytes(authenticatorData, input.clientDataHash));
  let verified: boolean;
  try {
    const key = await crypto.subtle.importKey(
      "spki",
      new Uint8Array(input.key.spki),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    verified = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, signature, nonce);
  } catch {
    return { ok: false, reason: "invalid_signature" };
  }
  if (!verified) return { ok: false, reason: "invalid_signature" };
  if (!bytesEqual(authenticatorData.subarray(0, RP_ID_HASH_END), await sha256(utf8(context.appId)))) {
    return { ok: false, reason: "wrong_app" };
  }
  const counter = readCounter(authenticatorData);
  if (counter <= input.key.counter) return { ok: false, reason: "bad_counter" };
  return { ok: true, counter };
}

async function verifyChain(
  credential: Certificate,
  intermediate: Certificate,
  context: AppAttestContext,
): Promise<AppAttestFailure | null> {
  let roots: Certificate[];
  try {
    roots = context.rootPEMs.map((pem) => parseCertificate(pemToDer(pem)));
  } catch {
    return "untrusted_root";
  }
  const nowMs = context.now.getTime();
  const current = (cert: Certificate) => cert.notBefore.getTime() <= nowMs && cert.notAfter.getTime() >= nowMs;
  try {
    let anchored = false;
    for (const root of roots) {
      if (current(root) && (await isSignedBy(intermediate, root))) anchored = true;
    }
    if (!anchored) return "untrusted_root";
    if (!(await isSignedBy(credential, intermediate))) return "invalid_chain";
  } catch {
    return "invalid_chain";
  }
  if (!current(credential) || !current(intermediate)) return "certificate_expired";
  return null;
}

// extnValue is SEQUENCE { [1] EXPLICIT OCTET STRING nonce }.
function readNonce(extensionValue: Uint8Array): Uint8Array | null {
  try {
    const tagged = children(expectTag(readRoot(extensionValue), Tag.sequence)).find((node) => node.tag === Tag.context1);
    const [octets] = children(expectTag(tagged, Tag.context1));
    return expectTag(octets, Tag.octetString).value;
  } catch {
    return null;
  }
}

function readCounter(authData: Uint8Array): number {
  return new DataView(authData.buffer, authData.byteOffset + COUNTER_OFFSET, 4).getUint32(0);
}

async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)));
}
