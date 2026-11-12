import { TextDecoder as NodeTextDecoder, TextEncoder as NodeTextEncoder } from 'util';
import { deflateRawSync, inflateRawSync } from 'zlib';
import { Buffer } from 'buffer';
import { openZip, decodeUtf8, ZIP_ERRORS } from 'c/zipReader';

global.TextDecoder = global.TextDecoder || NodeTextDecoder;
const encoder = new NodeTextEncoder();
const inflate = async (bytes) => new Uint8Array(inflateRawSync(bytes));

/** A zip of the given entries, deflated unless `store`; a name ending in / is a folder. */
function zip(parts, { store = false } = {}) {
  const chunks = [];
  const central = [];
  let offset = 0;
  for (const [name, text] of Object.entries(parts)) {
    const nameBytes = encoder.encode(name);
    const raw = encoder.encode(text);
    const data = store ? raw : new Uint8Array(deflateRawSync(raw));
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(store ? 0 : 8, 8);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(raw.length, 22);
    local.writeUInt16LE(nameBytes.length, 26);
    chunks.push(local, nameBytes, data);
    const entry = Buffer.alloc(46);
    entry.writeUInt32LE(0x02014b50, 0);
    entry.writeUInt16LE(store ? 0 : 8, 10);
    entry.writeUInt32LE(data.length, 20);
    entry.writeUInt32LE(raw.length, 24);
    entry.writeUInt16LE(nameBytes.length, 28);
    entry.writeUInt32LE(offset, 42);
    central.push(entry, nameBytes);
    offset += 30 + nameBytes.length + data.length;
  }
  const centralBytes = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(Object.keys(parts).length, 8);
  end.writeUInt16LE(Object.keys(parts).length, 10);
  end.writeUInt32LE(centralBytes.length, 12);
  end.writeUInt32LE(offset, 16);
  const all = Buffer.concat([...chunks, centralBytes, end]);
  return all.buffer.slice(all.byteOffset, all.byteOffset + all.length);
}

describe('c/zipReader', () => {
  it('lists the files, leaving folders out, with their sizes', () => {
    const opened = openZip(zip({ 'letters/': '', 'letters/a.txt': 'hello', 'manifest.csv': 'x' }), {
      inflate
    });
    expect(opened.names).toEqual(['letters/a.txt', 'manifest.csv']);
    expect(opened.sizeOf('letters/a.txt')).toBe(5);
    expect(opened.sizeOf('missing.txt')).toBe(0);
  });

  it('reads a deflated and a stored entry, and null for a name it does not hold', async () => {
    const deflated = openZip(zip({ 'a.txt': 'deflated text' }), { inflate });
    expect(decodeUtf8(await deflated.read('a.txt', 100))).toBe('deflated text');
    expect(await deflated.read('b.txt', 100)).toBeNull();
    const stored = openZip(zip({ 'a.txt': 'stored text' }, { store: true }));
    expect(decodeUtf8(await stored.read('a.txt', 100))).toBe('stored text');
  });

  it('refuses an entry larger than asked for', async () => {
    const opened = openZip(zip({ 'a.txt': 'twelve bytes' }), { inflate });
    await expect(opened.read('a.txt', 5)).rejects.toMatchObject({
      reason: ZIP_ERRORS.tooLarge
    });
  });

  it('refuses bytes that are not a zip', () => {
    expect(() => openZip(encoder.encode('not a zip at all, just text').buffer)).toThrow(
      expect.objectContaining({ reason: ZIP_ERRORS.notAZip })
    );
  });

  it('says the browser cannot unzip when it has no DecompressionStream', async () => {
    const opened = openZip(zip({ 'a.txt': 'text' }));
    await expect(opened.read('a.txt', 100)).rejects.toMatchObject({
      reason: ZIP_ERRORS.unsupportedBrowser
    });
  });
});
