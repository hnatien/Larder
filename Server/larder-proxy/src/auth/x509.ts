import { fromBase64 } from "../encoding.js";
import { DerError, Tag, children, decodeBitString, decodeOid, decodeTime, expectTag, readRoot, type DerNode } from "./der.js";

const EC_PUBLIC_KEY = "1.2.840.10045.2.1";
const CURVES: Record<string, { name: "P-256" | "P-384"; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};
const SIGNATURE_HASHES: Record<string, "SHA-256" | "SHA-384"> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};

/** The parts of an X.509 certificate needed to verify an ECDSA chain. */
export interface Certificate {
  der: Uint8Array;
  tbs: Uint8Array;
  signatureHash: "SHA-256" | "SHA-384";
  signature: Uint8Array;
  spki: Uint8Array;
  curve: "P-256" | "P-384";
  curveSize: number;
  notBefore: Date;
  notAfter: Date;
  extensionOids: ReadonlySet<string>;
}

/** Converts a single-certificate PEM block to DER. */
export function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const match = /-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----/.exec(pem);
  if (!match?.[1]) throw new DerError("Not a PEM certificate");
  return fromBase64(match[1].replace(/\s+/g, ""));
}

/** Parses a DER certificate whose subject key and signature are ECDSA on P-256 or P-384. */
export function parseCertificate(der: Uint8Array): Certificate {
  const [tbsNode, algorithmNode, signatureNode] = children(expectTag(readRoot(der), Tag.sequence));
  const tbs = expectTag(tbsNode, Tag.sequence);
  const tbsFields = children(tbs);
  const offset = tbsFields[0]?.tag === Tag.context0 ? 1 : 0;
  const validity = children(expectTag(tbsFields[offset + 3], Tag.sequence));
  const spkiNode = expectTag(tbsFields[offset + 5], Tag.sequence);
  const [spkiAlgorithm] = children(spkiNode);
  const [keyType, curveOid] = children(expectTag(spkiAlgorithm, Tag.sequence));
  if (!keyType || decodeOid(keyType) !== EC_PUBLIC_KEY || !curveOid) throw new DerError("Not an EC public key");
  const curve = CURVES[decodeOid(curveOid)];
  if (!curve) throw new DerError("Unsupported curve");
  const [signatureOid] = children(expectTag(algorithmNode, Tag.sequence));
  if (!signatureOid) throw new DerError("Missing signature algorithm");
  const signatureHash = SIGNATURE_HASHES[decodeOid(signatureOid)];
  if (!signatureHash) throw new DerError("Unsupported signature algorithm");
  const [notBefore, notAfter] = validity;
  if (!notBefore || !notAfter) throw new DerError("Missing validity");
  return {
    der,
    tbs: tbs.bytes,
    signatureHash,
    signature: decodeBitString(expectTag(signatureNode, Tag.bitString)),
    spki: spkiNode.bytes,
    curve: curve.name,
    curveSize: curve.size,
    notBefore: decodeTime(notBefore),
    notAfter: decodeTime(notAfter),
    extensionOids: extensionOids(tbsFields.slice(offset + 6)),
  };
}

function extensionOids(trailing: DerNode[]): Set<string> {
  const wrapper = trailing.find((node) => node.tag === Tag.context3);
  const oids = new Set<string>();
  if (!wrapper) return oids;
  const [list] = children(wrapper);
  for (const extension of children(expectTag(list, Tag.sequence))) {
    const [oid] = children(expectTag(extension, Tag.sequence));
    if (!oid) throw new DerError("Empty extension");
    oids.add(decodeOid(oid));
  }
  return oids;
}

/** Imports the certificate's public key for ECDSA verification. */
export function importPublicKey(certificate: Certificate): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "spki",
    new Uint8Array(certificate.spki),
    { name: "ECDSA", namedCurve: certificate.curve },
    false,
    ["verify"],
  );
}

/** True when `subject`'s signature verifies under `issuer`'s public key. */
export async function isSignedBy(subject: Certificate, issuer: Certificate): Promise<boolean> {
  const key = await importPublicKey(issuer);
  return crypto.subtle.verify(
    { name: "ECDSA", hash: subject.signatureHash },
    key,
    derSignatureToRaw(subject.signature, issuer.curveSize),
    new Uint8Array(subject.tbs),
  );
}

/** Converts an ASN.1 `SEQUENCE { r INTEGER, s INTEGER }` ECDSA signature to the fixed-width r||s form WebCrypto expects. */
export function derSignatureToRaw(signature: Uint8Array, size: number): Uint8Array<ArrayBuffer> {
  const [r, s] = children(expectTag(readRoot(signature), Tag.sequence));
  const raw = new Uint8Array(size * 2);
  [r, s].forEach((node, index) => {
    let value = expectTag(node, Tag.integer).value;
    while (value.length > 1 && value[0] === 0) value = value.subarray(1);
    if (value.length > size) throw new DerError("Signature integer too large");
    raw.set(value, index * size + size - value.length);
  });
  return raw;
}
