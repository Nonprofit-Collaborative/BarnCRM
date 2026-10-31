import { TextDecoder as NodeTextDecoder, TextEncoder as NodeTextEncoder } from 'util';
import { deflateRawSync, inflateRawSync } from 'zlib';
import {
  CELL_TYPES,
  columnName,
  crc32,
  MAX_CELL_TEXT,
  sheetChunks,
  sheetXml,
  toSerial,
  writeXlsx,
  writeZip
} from 'c/xlsxWriter';
// The import wizard's reader reads back what the writer wrote.
import { readXlsx } from '../../importWizard/xlsx';

global.TextEncoder = global.TextEncoder || NodeTextEncoder;
global.TextDecoder = global.TextDecoder || NodeTextDecoder;

const deflate = async (bytes) => new Uint8Array(deflateRawSync(bytes));
const inflate = async (bytes) => new Uint8Array(inflateRawSync(bytes));

const COLUMNS = [
  { label: 'Name', type: CELL_TYPES.TEXT },
  { label: 'Amount', type: CELL_TYPES.NUMBER },
  { label: 'Gift Date', type: CELL_TYPES.DATE },
  { label: 'Paid', type: CELL_TYPES.BOOLEAN }
];

describe('c/xlsxWriter', () => {
  it('names columns as Excel does', () => {
    expect(columnName(0)).toBe('A');
    expect(columnName(25)).toBe('Z');
    expect(columnName(26)).toBe('AA');
    expect(columnName(701)).toBe('ZZ');
    expect(columnName(702)).toBe('AAA');
  });

  it('computes the zip checksum', () => {
    expect(crc32(new NodeTextEncoder().encode('123456789'))).toBe(0xcbf43926);
    const encoder = new NodeTextEncoder();
    expect(crc32(encoder.encode('6789'), crc32(encoder.encode('12345')))).toBe(0xcbf43926);
  });

  it('turns dates into Excel serials, and date-times as the clock reads in a time zone', () => {
    expect(toSerial('1900-03-01', CELL_TYPES.DATE)).toBe(61);
    expect(toSerial('2026-10-12', CELL_TYPES.DATE)).toBe(46307);
    expect(toSerial('not a date', CELL_TYPES.DATE)).toBeNull();
    const noonUtc = '2026-01-05T12:00:00.000Z';
    expect(toSerial(noonUtc, CELL_TYPES.DATETIME, 'UTC')).toBe(46027.5);
    // Los Angeles is eight hours behind UTC in January: 4 in the morning.
    expect(toSerial(noonUtc, CELL_TYPES.DATETIME, 'America/Los_Angeles')).toBeCloseTo(
      46027 + 4 / 24,
      9
    );
    expect(toSerial('not a time', CELL_TYPES.DATETIME, 'UTC')).toBeNull();
  });

  it('encodes the sheet a piece at a time, the same bytes as one string', () => {
    const rows = [];
    for (let index = 0; index < 200; index++) {
      rows.push([`Person ${index}`, index, '2026-01-31', true]);
    }
    const chunks = sheetChunks(COLUMNS, rows, 'UTC', 500);
    expect(chunks.length).toBeGreaterThan(10);
    const decoder = new NodeTextDecoder();
    expect(chunks.map((chunk) => decoder.decode(chunk)).join('')).toBe(
      sheetXml(COLUMNS, rows, 'UTC')
    );
  });

  it('writes numbers, booleans and dates as values and escapes text', () => {
    const xml = sheetXml(COLUMNS, [['Ruiz & <Sons>', 12.5, '2026-10-12', true]]);
    expect(xml).toContain('<c r="A1" t="inlineStr" s="3"><is><t xml:space="preserve">Name</t>');
    expect(xml).toContain('Ruiz &amp; &lt;Sons&gt;');
    expect(xml).toContain('<c r="B2"><v>12.5</v></c>');
    expect(xml).toContain('<c r="C2" s="1"><v>46307</v></c>');
    expect(xml).toContain('<c r="D2" t="b"><v>1</v></c>');
    expect(sheetXml(COLUMNS, [['a\u0001b', null, '', undefined]])).toContain('>ab<');
  });

  it('writes text that looks like a formula as an inline string, never a formula', () => {
    const risky = ['=1+1', '+1', '-1', '@SUM(A1)', '\tx', '\rx'];
    const xml = sheetXml(
      COLUMNS,
      risky.map((text) => [text, null, null, null])
    );
    expect(xml).not.toContain('<f>');
    expect(xml).toContain('<c r="A2" t="inlineStr"><is><t xml:space="preserve">=1+1</t>');
    expect(xml).toContain('<c r="A5" t="inlineStr"><is><t xml:space="preserve">@SUM(A1)</t>');
    expect(xml).toContain('<c r="A3" t="inlineStr"><is><t xml:space="preserve">+1</t>');
  });

  it('cuts text to what one Excel cell holds, never splitting a character', () => {
    const cellText = (xml, reference) =>
      xml
        .split(`<c r="${reference}" t="inlineStr"><is><t xml:space="preserve">`)[1]
        .split('</t>')[0];
    const long = 'x'.repeat(MAX_CELL_TEXT + 100);
    // An emoji (two code units) straddling the limit is dropped whole.
    const straddling = `${'y'.repeat(MAX_CELL_TEXT - 1)}\u{1F600}z`;
    const xml = sheetXml(COLUMNS, [
      [long, null, null, null],
      [straddling, null, null, null],
      ['short', null, null, null]
    ]);
    expect(MAX_CELL_TEXT).toBe(32767);
    expect(cellText(xml, 'A2')).toHaveLength(MAX_CELL_TEXT);
    expect(cellText(xml, 'A3')).toBe('y'.repeat(MAX_CELL_TEXT - 1));
    expect(cellText(xml, 'A4')).toBe('short');
  });

  it('writes a workbook the import reader reads back, deflated and stored', async () => {
    const rows = [];
    for (let index = 0; index < 200; index++) {
      rows.push([`Person ${index}`, index * 10, '2026-01-31', index % 2 === 0]);
    }
    for (const options of [{ deflate }, { deflate: null }]) {
      // eslint-disable-next-line no-await-in-loop
      const bytes = await writeXlsx(COLUMNS, rows, options);
      // eslint-disable-next-line no-await-in-loop
      const read = await readXlsx(bytes.buffer, { inflate });
      expect(read).toHaveLength(201);
      expect(read[0]).toEqual(['Name', 'Amount', 'Gift Date', 'Paid']);
      expect(read[1]).toEqual(['Person 0', '0', '2026-01-31', 'TRUE']);
      expect(read[200]).toEqual(['Person 199', '1990', '2026-01-31', 'FALSE']);
    }
  });

  it('writes a zip of text files, each entry named, checksummed and readable', async () => {
    const files = [
      ['README.md', '# Pack\n\nAccents: é ü'],
      ['data/Contact.csv', 'Id,Email\r\n003A,a@example.org\r\n']
    ];
    for (const options of [{ deflate }, { deflate: null }]) {
      // eslint-disable-next-line no-await-in-loop
      const bytes = await writeZip(files, options);
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      const read = [];
      let at = 0;
      while (view.getUint32(at, true) === 0x04034b50) {
        const method = view.getUint16(at + 8, true);
        const crc = view.getUint32(at + 14, true);
        const size = view.getUint32(at + 18, true);
        const nameLength = view.getUint16(at + 26, true);
        const name = new NodeTextDecoder().decode(bytes.slice(at + 30, at + 30 + nameLength));
        const data = bytes.slice(at + 30 + nameLength, at + 30 + nameLength + size);
        // eslint-disable-next-line no-await-in-loop
        const raw = method === 8 ? await inflate(data) : data;
        expect(crc32(raw)).toBe(crc);
        read.push([name, new NodeTextDecoder().decode(raw)]);
        at += 30 + nameLength + size;
      }
      expect(read).toEqual(files);
    }
  });
});
