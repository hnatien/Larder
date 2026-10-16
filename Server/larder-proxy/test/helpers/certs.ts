// Builds an Apple-shaped x5c chain (root P-384, intermediate P-384, leaf P-256) and signs JWS
// transactions with it. All keys are generated per run; no private key is checked in.
import { toBase64, toBase64Url } from "../../src/encoding.js";
import {
  bitString,
  generalizedTime,
  integer,
  nullValue,
  octetString,
  oid,
  sequence,
  set,
  tlv,
  utcTime,
  utf8String,
} from "./der.js";

export const LEAF_MARKER_OID = "1.2.840.113635.100.6.11.1";
export const INTERMEDIATE_MARKER_OID = "1.2.840.113635.100.6.2.1";
const ECDSA_SHA256 = "1.2.840.10045.4.3.2";
const ECDSA_SHA384 = "1.2.840.10045.4.3.3";

type Curve = "P-256" | "P-384";

export interface TestCert {
  der: Uint8Array;
  keys: CryptoKeyPair;
  name: string;
}

export interface CertOptions {
  name: string;
  curve: Curve;
  issuer?: TestCert;
  hash?: "SHA-256" | "SHA-384";
  extensionOids?: string[];
  /** Extensions with real values (DER placed inside extnValue). */
  extensionValues?: { oid: string; value: Uint8Array }[];
  /** Use these keys instead of generating a pair. */
  keys?: CryptoKeyPair;
  notBefore?: Date;
  notAfter?: Date;
  useUtcTime?: boolean;
  signingKeyOverride?: CryptoKey;
}

const nameOf = (common: string) => sequence(set(sequence(oid("2.5.4.3"), utf8String(common))));

export function rawToDerSignature(raw: Uint8Array): Uint8Array {
  const half = raw.length / 2;
  return sequence(integer(raw.subarray(0, half)), integer(raw.subarray(half)));
}

export async function generateKeys(curve: Curve): Promise<CryptoKeyPair> {
  return (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, ["sign", "verify"])) as CryptoKeyPair;
}

export async function makeCert(options: CertOptions): Promise<TestCert> {
  const keys = options.keys ?? (await generateKeys(options.curve));
  const hash = options.hash ?? "SHA-256";
  const algorithm = sequence(oid(hash === "SHA-256" ? ECDSA_SHA256 : ECDSA_SHA384));
  const time = options.useUtcTime ? utcTime : generalizedTime;
  const spki = new Uint8Array((await crypto.subtle.exportKey("spki", keys.publicKey)) as ArrayBuffer);
  const extensions = [
    ...(options.extensionOids ?? []).map((id) => sequence(oid(id), octetString(nullValue()))),
    ...(options.extensionValues ?? []).map((extension) => sequence(oid(extension.oid), octetString(extension.value))),
  ];
  const tbs = sequence(
    tlv(0xa0, integer(new Uint8Array([2]))),
    integer(crypto.getRandomValues(new Uint8Array(8))),
    algorithm,
    nameOf(options.issuer?.name ?? options.name),
    sequence(
      time(options.notBefore ?? new Date("2020-01-01T00:00:00Z")),
      time(options.notAfter ?? new Date("2040-01-01T00:00:00Z")),
    ),
    nameOf(options.name),
    spki,
    ...(extensions.length > 0 ? [tlv(0xa3, sequence(...extensions))] : []),
  );
  const signer = options.signingKeyOverride ?? options.issuer?.keys.privateKey ?? keys.privateKey;
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash }, signer, new Uint8Array(tbs)));
  return { der: sequence(tbs, algorithm, bitString(rawToDerSignature(raw))), keys, name: options.name };
}

export function toPem(der: Uint8Array): string {
  const body = toBase64(der).match(/.{1,64}/g)?.join("\n") ?? "";
  return `-----BEGIN CERTIFICATE-----\n${body}\n-----END CERTIFICATE-----`;
}

export interface TestChain {
  root: TestCert;
  intermediate: TestCert;
  leaf: TestCert;
  rootPem: string;
}

export async function makeChain(overrides: { leaf?: Partial<CertOptions>; intermediate?: Partial<CertOptions> } = {}): Promise<TestChain> {
  const root = await makeCert({ name: "Test Root CA", curve: "P-384", hash: "SHA-384", useUtcTime: true });
  const intermediate = await makeCert({
    name: "Test Intermediate",
    curve: "P-384",
    hash: "SHA-384",
    issuer: root,
    extensionOids: [INTERMEDIATE_MARKER_OID],
    ...overrides.intermediate,
  });
  const leaf = await makeCert({
    name: "Test Leaf",
    curve: "P-256",
    hash: "SHA-256",
    issuer: intermediate,
    extensionOids: [LEAF_MARKER_OID],
    ...overrides.leaf,
  });
  return { root, intermediate, leaf, rootPem: toPem(root.der) };
}

export async function signTransaction(
  chain: TestChain,
  payload: Record<string, unknown>,
  header: Record<string, unknown> = {},
): Promise<string> {
  const encode = (value: unknown) => toBase64Url(new TextEncoder().encode(JSON.stringify(value)));
  const headerPart = encode({
    alg: "ES256",
    x5c: [chain.leaf.der, chain.intermediate.der, chain.root.der].map(toBase64),
    ...header,
  });
  const payloadPart = encode(payload);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    chain.leaf.keys.privateKey,
    new TextEncoder().encode(`${headerPart}.${payloadPart}`),
  );
  return `${headerPart}.${payloadPart}.${toBase64Url(new Uint8Array(signature))}`;
}

