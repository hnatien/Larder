// Minimal DER encoder used only to build throwaway test certificates.

function encodeLength(length: number): number[] {
  if (length < 0x80) return [length];
  const bytes: number[] = [];
  for (let value = length; value > 0; value = Math.floor(value / 256)) bytes.unshift(value & 0xff);
  return [0x80 | bytes.length, ...bytes];
}

export function tlv(tag: number, ...contents: Uint8Array[]): Uint8Array {
  const body = concat(...contents);
  return concat(new Uint8Array([tag, ...encodeLength(body.length)]), body);
}

export function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

export const sequence = (...items: Uint8Array[]) => tlv(0x30, ...items);
export const set = (...items: Uint8Array[]) => tlv(0x31, ...items);
export const octetString = (bytes: Uint8Array) => tlv(0x04, bytes);
export const bitString = (bytes: Uint8Array) => tlv(0x03, new Uint8Array([0]), bytes);
export const utf8String = (text: string) => tlv(0x0c, new TextEncoder().encode(text));
export const nullValue = () => tlv(0x05);

export function integer(bytes: Uint8Array): Uint8Array {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  const trimmed = bytes.subarray(start);
  const needsPad = ((trimmed[0] ?? 0) & 0x80) !== 0;
  return tlv(0x02, needsPad ? concat(new Uint8Array([0]), trimmed) : trimmed);
}

export function oid(dotted: string): Uint8Array {
  const [first = 0, second = 0, ...rest] = dotted.split(".").map(Number);
  const bytes = [first * 40 + second];
  for (const arc of rest) {
    const chunk: number[] = [arc & 0x7f];
    for (let value = Math.floor(arc / 128); value > 0; value = Math.floor(value / 128)) chunk.unshift((value & 0x7f) | 0x80);
    bytes.push(...chunk);
  }
  return tlv(0x06, new Uint8Array(bytes));
}

export function generalizedTime(date: Date): Uint8Array {
  const text = date.toISOString().replace(/[-:T]/g, "").slice(0, 14) + "Z";
  return tlv(0x18, new TextEncoder().encode(text));
}

export function utcTime(date: Date): Uint8Array {
  const text = date.toISOString().replace(/[-:T]/g, "").slice(2, 14) + "Z";
  return tlv(0x17, new TextEncoder().encode(text));
}
