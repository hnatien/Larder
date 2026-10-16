// Builds App Attest attestation objects and assertions shaped like Apple's, signed by a throwaway
// root -> intermediate -> credential chain generated per run. No private key is checked in.
import { APP_ATTEST_NONCE_OID } from "../../src/auth/appAttest.js";
import { clientDataHash } from "../../src/auth/challenge.js";
import { concatBytes, toBase64, utf8 } from "../../src/encoding.js";
import { generateKeys, makeCert, rawToDerSignature, toPem, type TestCert } from "./certs.js";
import { octetString, sequence, tlv } from "./der.js";

// Minimal CBOR encoder: unsigned ints, bytes, text, arrays and text-keyed maps.
export type CborInput = number | Uint8Array | string | CborInput[] | Map<string, CborInput>;

function head(major: number, value: number): Uint8Array {
  if (value < 24) return new Uint8Array([(major << 5) | value]);
  if (value < 0x100) return new Uint8Array([(major << 5) | 24, value]);
  if (value < 0x10000) return new Uint8Array([(major << 5) | 25, value >> 8, value & 0xff]);
  const out = new Uint8Array(5);
  out[0] = (major << 5) | 26;
  new DataView(out.buffer).setUint32(1, value);
  return out;
}

export function encodeCbor(value: CborInput): Uint8Array {
  if (typeof value === "number") return head(0, value);
  if (value instanceof Uint8Array) return concatBytes(head(2, value.length), value);
  if (typeof value === "string") {
    const bytes = utf8(value);
    return concatBytes(head(3, bytes.length), bytes);
  }
  if (Array.isArray(value)) return concatBytes(head(4, value.length), ...value.map(encodeCbor));
  const entries = [...value.entries()].flatMap(([key, item]) => [encodeCbor(key), encodeCbor(item)]);
  return concatBytes(head(5, value.size), ...entries);
}

export const PRODUCTION_AAGUID = concatBytes(utf8("appattest"), new Uint8Array(7));
export const DEVELOPMENT_AAGUID = utf8("appattestdevelop");

export async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)));
}

function counterBytes(counter: number): Uint8Array {
  const out = new Uint8Array(4);
  new DataView(out.buffer).setUint32(0, counter);
  return out;
}

export interface AttestCA {
  root: TestCert;
  intermediate: TestCert;
  rootPem: string;
}

export async function makeAttestCA(): Promise<AttestCA> {
  const root = await makeCert({ name: "Test App Attestation Root CA", curve: "P-384", hash: "SHA-384" });
  const intermediate = await makeCert({ name: "Test App Attestation CA 1", curve: "P-384", hash: "SHA-384", issuer: root });
  return { root, intermediate, rootPem: toPem(root.der) };
}

/** A device key: the credential key pair and its key id, SHA-256 of the uncompressed public point. */
export interface DeviceKey {
  keys: CryptoKeyPair;
  keyId: Uint8Array;
}

export async function makeDeviceKey(): Promise<DeviceKey> {
  const keys = await generateKeys("P-256");
  const point = new Uint8Array((await crypto.subtle.exportKey("raw", keys.publicKey)) as ArrayBuffer);
  return { keys, keyId: await sha256(point) };
}

export interface AttestationOverrides {
  appId?: string;
  aaguid?: Uint8Array;
  counter?: number;
  flags?: number;
  credentialId?: Uint8Array;
  /** Nonce bound into the certificate; defaults to the correct one. */
  nonce?: Uint8Array;
  fmt?: string;
  credentialNotAfter?: Date;
  /** Issue the credential certificate from this cert instead of the CA intermediate. */
  credentialIssuer?: TestCert;
  /** x5c override, e.g. to drop or add certificates. */
  x5c?: (credential: Uint8Array, intermediate: Uint8Array) => Uint8Array[];
}

/** Returns a base64 attestation object for `device`, bound to `challenge`, as DCAppAttestService would. */
export async function makeAttestation(
  ca: AttestCA,
  device: DeviceKey,
  challenge: string,
  appId: string,
  overrides: AttestationOverrides = {},
): Promise<string> {
  const credentialId = overrides.credentialId ?? device.keyId;
  const authData = concatBytes(
    await sha256(utf8(overrides.appId ?? appId)),
    new Uint8Array([overrides.flags ?? 0x40]),
    counterBytes(overrides.counter ?? 0),
    overrides.aaguid ?? PRODUCTION_AAGUID,
    new Uint8Array([credentialId.length >> 8, credentialId.length & 0xff]),
    credentialId,
    encodeCbor(new Map<string, CborInput>([["kty", 2]])),
  );
  const nonce = overrides.nonce ?? (await sha256(concatBytes(authData, await clientDataHash(challenge))));
  const credential = await makeCert({
    name: "Test Credential",
    curve: "P-256",
    hash: "SHA-256",
    issuer: overrides.credentialIssuer ?? ca.intermediate,
    keys: device.keys,
    notAfter: overrides.credentialNotAfter,
    extensionValues: [{ oid: APP_ATTEST_NONCE_OID, value: sequence(tlv(0xa1, octetString(nonce))) }],
  });
  const x5c = overrides.x5c?.(credential.der, ca.intermediate.der) ?? [credential.der, ca.intermediate.der];
  const object = new Map<string, CborInput>([
    ["fmt", overrides.fmt ?? "apple-appattest"],
    ["attStmt", new Map<string, CborInput>([["x5c", x5c], ["receipt", new Uint8Array([1, 2, 3])]])],
    ["authData", authData],
  ]);
  return toBase64(encodeCbor(object));
}

/** Returns a base64 assertion over `challenge` signed by `signer` (defaults to the device key). */
export async function makeAssertion(
  device: DeviceKey,
  challenge: string,
  appId: string,
  counter: number,
  signer: CryptoKey = device.keys.privateKey,
): Promise<string> {
  const authenticatorData = concatBytes(await sha256(utf8(appId)), new Uint8Array([0]), counterBytes(counter));
  const nonce = await sha256(concatBytes(authenticatorData, await clientDataHash(challenge)));
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signer, new Uint8Array(nonce)));
  const object = new Map<string, CborInput>([
    ["signature", rawToDerSignature(raw)],
    ["authenticatorData", authenticatorData],
  ]);
  return toBase64(encodeCbor(object));
}
