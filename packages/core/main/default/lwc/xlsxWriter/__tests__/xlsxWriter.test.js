import { TextDecoder as NodeTextDecoder, TextEncoder as NodeTextEncoder } from 'util';
import { deflateRawSync, inflateRawSync } from 'zlib';
import {
  CELL_TYPES,
  columnName,
  crc32,
  sheetXml,
  toSerial,
  writeXlsx,
  xlsxFileName
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
  });

  it('turns dates into Excel serials', () => {
    expect(toSerial('1900-03-01', CELL_TYPES.DATE)).toBe(61);
    expect(toSerial('2026-10-12', CELL_TYPES.DATE)).toBe(46307);
    expect(toSerial('not a date', CELL_TYPES.DATE)).toBeNull();
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

  it('names the file after the object and the day', () => {
    expect(xlsxFileName('Gift__c', new Date('2026-10-12T10:00:00Z'))).toBe(
      'Gift__c-2026-10-12.xlsx'
    );
  });
});
