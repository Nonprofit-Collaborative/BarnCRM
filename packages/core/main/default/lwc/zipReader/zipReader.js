/**
 * Reads a zip file in the browser: its central directory, then any entry, inflated with the
 * browser's own DecompressionStream. Framework-free, so the import wizard's workbook reader
 * (an .xlsx file is a zip) and Import Files share one copy (ADR-0049; ADR-0214
 * `0214-files-import.md`). Reads the classic zip format, not ZIP64: an entry or a zip past
 * 4 GB is far past what either reader takes.
 */

const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_SIGNATURE = 0x02014b50;
const LOCAL_SIGNATURE = 0x04034b50;
const STORED = 0;
const DEFLATED = 8;

/** The reasons a zip cannot be read, as keys a caller turns into sentences. */
export const ZIP_ERRORS = {
  notAZip: 'notAZip',
  unsupportedBrowser: 'unsupportedBrowser',
  tooLarge: 'tooLarge'
};

export class ZipError extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

/** True when this browser can inflate a zip's entries: it needs DecompressionStream. */
export function canUnzip() {
  return typeof DecompressionStream === 'function';
}

/**
 * Opens a zip.
 *
 * @param {ArrayBuffer} buffer the file's bytes
 * @param {object} [options] `inflate(bytes)` returning a promise of the raw-inflated bytes,
 *   for a test to supply where the browser's DecompressionStream is not available
 * @returns {{names: string[], sizeOf: function(string): number,
 *   read: function(string, number): Promise<Uint8Array>}} the file names (folders left out),
 *   each one's size once inflated, and a reader that gives an entry's bytes, or null for a
 *   name the zip does not hold, refusing one larger than `maxBytes`
 */
export function openZip(buffer, options = {}) {
  const inflate = options.inflate || inflateInBrowser;
  const bytes = new Uint8Array(buffer);
  const entries = readCentralDirectory(bytes);
  return {
    names: [...entries.keys()].filter((name) => !name.endsWith('/')),
    sizeOf: (name) => (entries.has(name) ? entries.get(name).uncompressedSize : 0),
    read: async (name, maxBytes) => {
      const entry = entries.get(name);
      if (!entry) {
        return null;
      }
      if (entry.uncompressedSize > maxBytes) {
        throw new ZipError(ZIP_ERRORS.tooLarge);
      }
      const data = await extract(bytes, entry, inflate);
      if (data.length > maxBytes) {
        throw new ZipError(ZIP_ERRORS.tooLarge);
      }
      return data;
    }
  };
}

/** UTF-8 bytes as text. */
export function decodeUtf8(bytes) {
  return new TextDecoder('utf-8').decode(bytes);
}

function readCentralDirectory(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 65535); i--) {
    if (view.getUint32(i, true) === EOCD_SIGNATURE) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) {
    throw new ZipError(ZIP_ERRORS.notAZip);
  }
  const count = view.getUint16(eocd + 10, true);
  let offset = view.getUint32(eocd + 16, true);
  const entries = new Map();
  for (let i = 0; i < count; i++) {
    if (offset + 46 > bytes.length || view.getUint32(offset, true) !== CENTRAL_SIGNATURE) {
      throw new ZipError(ZIP_ERRORS.notAZip);
    }
    const nameLength = view.getUint16(offset + 28, true);
    const extraLength = view.getUint16(offset + 30, true);
    const commentLength = view.getUint16(offset + 32, true);
    const name = decodeUtf8(bytes.subarray(offset + 46, offset + 46 + nameLength));
    entries.set(name, {
      method: view.getUint16(offset + 10, true),
      compressedSize: view.getUint32(offset + 20, true),
      uncompressedSize: view.getUint32(offset + 24, true),
      localOffset: view.getUint32(offset + 42, true)
    });
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

async function extract(bytes, entry, inflate) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const local = entry.localOffset;
  if (local + 30 > bytes.length || view.getUint32(local, true) !== LOCAL_SIGNATURE) {
    throw new ZipError(ZIP_ERRORS.notAZip);
  }
  const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
  const data = bytes.subarray(start, start + entry.compressedSize);
  if (entry.method === STORED) {
    return data;
  }
  if (entry.method === DEFLATED) {
    return inflate(data);
  }
  throw new ZipError(ZIP_ERRORS.notAZip);
}

async function inflateInBrowser(data) {
  if (!canUnzip()) {
    throw new ZipError(ZIP_ERRORS.unsupportedBrowser);
  }
  const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}
