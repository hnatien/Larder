// A deliberately small DER reader covering only what the X.509 chain checks for App Store JWS and App Attest need.

/** Raised for any structural problem in DER input. */
export class DerError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DerError";
  }
}

/** One tag-length-value element. `bytes` is the whole TLV, `value` its contents. */
export interface DerNode {
  tag: number;
  bytes: Uint8Array;
  value: Uint8Array;
}

export const Tag = {
  integer: 0x02,
  bitString: 0x03,
  octetString: 0x04,
  oid: 0x06,
  utcTime: 0x17,
  generalizedTime: 0x18,
  sequence: 0x30,
  set: 0x31,
  context0: 0xa0,
  context1: 0xa1,
  context3: 0xa3,
} as const;

/** Reads the TLV starting at `offset`. Rejects high tag numbers, indefinite and oversized lengths. */
export function readNode(input: Uint8Array, offset = 0): DerNode {
  const tag = input[offset];
  const first = input[offset + 1];
  if (tag === undefined || first === undefined) throw new DerError("Truncated header");
  if ((tag & 0x1f) === 0x1f) throw new DerError("High tag numbers are not supported");
  let length = first;
  let header = 2;
  if (first & 0x80) {
    const count = first & 0x7f;
    if (count === 0 || count > 4) throw new DerError("Unsupported length encoding");
    length = 0;
    for (let i = 0; i < count; i++) {
      const byte = input[offset + 2 + i];
      if (byte === undefined) throw new DerError("Truncated length");
      length = length * 256 + byte;
    }
    header += count;
  }
  const end = offset + header + length;
  if (end > input.length) throw new DerError("Length exceeds input");
  return { tag, bytes: input.subarray(offset, end), value: input.subarray(offset + header, end) };
}

/** Reads a single TLV that must span the whole input. */
export function readRoot(input: Uint8Array): DerNode {
  const node = readNode(input);
  if (node.bytes.length !== input.length) throw new DerError("Trailing bytes after element");
  return node;
}

/** Splits a constructed node into its direct children. */
export function children(node: DerNode): DerNode[] {
  if ((node.tag & 0x20) === 0) throw new DerError("Not a constructed element");
  const result: DerNode[] = [];
  let offset = 0;
  while (offset < node.value.length) {
    const child = readNode(node.value, offset);
    result.push(child);
    offset += child.bytes.length;
  }
  return result;
}

/** Asserts the node's tag and returns it. */
export function expectTag(node: DerNode | undefined, tag: number): DerNode {
  if (!node || node.tag !== tag) throw new DerError(`Expected tag 0x${tag.toString(16)}`);
  return node;
}

/** Decodes an OBJECT IDENTIFIER to dotted form. */
export function decodeOid(node: DerNode): string {
  const bytes = expectTag(node, Tag.oid).value;
  const arcs: number[] = [];
  let current = 0;
  for (const byte of bytes) {
    current = current * 128 + (byte & 0x7f);
    if ((byte & 0x80) === 0) {
      arcs.push(current);
      current = 0;
    }
  }
  const first = arcs[0];
  if (first === undefined || (bytes[bytes.length - 1] as number) & 0x80) throw new DerError("Malformed OID");
  const top = Math.min(2, Math.floor(first / 40));
  return [top, first - top * 40, ...arcs.slice(1)].join(".");
}

/** Decodes a UTCTime or GeneralizedTime in the `Z` form that DER requires. */
export function decodeTime(node: DerNode): Date {
  const text = String.fromCharCode(...node.value);
  let match: RegExpExecArray | null;
  let year: number;
  if (node.tag === Tag.utcTime) {
    match = /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text);
    if (!match) throw new DerError("Bad UTCTime");
    const short = Number(match[1]);
    year = short >= 50 ? 1900 + short : 2000 + short;
  } else if (node.tag === Tag.generalizedTime) {
    match = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text);
    if (!match) throw new DerError("Bad GeneralizedTime");
    year = Number(match[1]);
  } else {
    throw new DerError("Expected a time element");
  }
  const [, , month, day, hour, minute, second] = match.map(Number) as number[];
  return new Date(Date.UTC(year, (month as number) - 1, day, hour, minute, second));
}

/** Returns BIT STRING contents, requiring zero unused bits. */
export function decodeBitString(node: DerNode): Uint8Array {
  const value = expectTag(node, Tag.bitString).value;
  if (value[0] !== 0) throw new DerError("Unsupported unused bits in BIT STRING");
  return value.subarray(1);
}
