// A deliberately small CBOR (RFC 8949) reader covering only what App Attest objects need:
// definite-length unsigned integers, byte strings, text strings, arrays and maps with text keys.

/** Raised for any structural problem in CBOR input, including features this reader does not support. */
export class CborError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CborError";
  }
}

export type CborValue = number | Uint8Array | string | CborValue[] | Map<string, CborValue>;

const MAX_DEPTH = 8;
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

/** Decodes a single CBOR item that must span the whole input. */
export function decodeCbor(input: Uint8Array): CborValue {
  const reader = { input, offset: 0 };
  const value = readItem(reader, 0);
  if (reader.offset !== input.length) throw new CborError("Trailing bytes after item");
  return value;
}

/** Reads `key` from a decoded map, asserting it holds a byte string. */
export function cborBytes(map: Map<string, CborValue>, key: string): Uint8Array {
  const value = map.get(key);
  if (!(value instanceof Uint8Array)) throw new CborError(`Expected bytes at ${key}`);
  return value;
}

/** Asserts a decoded value is a map. */
export function cborMap(value: CborValue | undefined, where: string): Map<string, CborValue> {
  if (!(value instanceof Map)) throw new CborError(`Expected a map at ${where}`);
  return value;
}

interface Reader {
  input: Uint8Array;
  offset: number;
}

function readItem(reader: Reader, depth: number): CborValue {
  if (depth > MAX_DEPTH) throw new CborError("Nesting too deep");
  const initial = reader.input[reader.offset];
  if (initial === undefined) throw new CborError("Truncated item");
  reader.offset += 1;
  const major = initial >> 5;
  const argument = readArgument(reader, initial & 0x1f);
  switch (major) {
    case 0:
      return argument;
    case 2:
      return take(reader, argument);
    case 3:
      try {
        return decoder.decode(take(reader, argument));
      } catch (error) {
        if (error instanceof CborError) throw error;
        throw new CborError("Invalid UTF-8 in text string");
      }
    case 4: {
      const items: CborValue[] = [];
      for (let i = 0; i < argument; i++) items.push(readItem(reader, depth + 1));
      return items;
    }
    case 5: {
      const map = new Map<string, CborValue>();
      for (let i = 0; i < argument; i++) {
        const key = readItem(reader, depth + 1);
        if (typeof key !== "string") throw new CborError("Map keys must be text");
        if (map.has(key)) throw new CborError("Duplicate map key");
        map.set(key, readItem(reader, depth + 1));
      }
      return map;
    }
    default:
      throw new CborError(`Unsupported major type ${major}`);
  }
}

function readArgument(reader: Reader, info: number): number {
  if (info < 24) return info;
  const width = { 24: 1, 25: 2, 26: 4, 27: 8 }[info];
  if (width === undefined) throw new CborError("Indefinite or reserved length");
  let value = 0;
  for (const byte of take(reader, width)) value = value * 256 + byte;
  if (!Number.isSafeInteger(value)) throw new CborError("Integer too large");
  return value;
}

function take(reader: Reader, length: number): Uint8Array {
  const end = reader.offset + length;
  if (end > reader.input.length) throw new CborError("Length exceeds input");
  const bytes = reader.input.subarray(reader.offset, end);
  reader.offset = end;
  return bytes;
}
