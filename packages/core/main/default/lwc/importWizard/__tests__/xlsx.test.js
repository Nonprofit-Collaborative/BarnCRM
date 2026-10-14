import { TextDecoder as NodeTextDecoder, TextEncoder as NodeTextEncoder } from 'util';
import { deflateRawSync, inflateRawSync } from 'zlib';
import { Buffer } from 'buffer';
import { readXlsx, readSheetNames, isXlsx, serialToDate, MAX_PART_BYTES } from '../xlsx';

global.TextDecoder = global.TextDecoder || NodeTextDecoder;
const encoder = new NodeTextEncoder();

const inflate = async (bytes) => new Uint8Array(inflateRawSync(bytes));

/**
 * Builds a zip the way a spreadsheet program writes one: each part deflated, then the central
 * directory, then its end record. The checksum is left at zero because the reader does not
 * use it.
 */
function zip(parts, { store = false, declaredSize } = {}) {
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
    entry.writeUInt32LE(declaredSize === undefined ? raw.length : declaredSize, 24);
    entry.writeUInt16LE(nameBytes.length, 28);
    entry.writeUInt32LE(offset, 42);
    central.push(entry, nameBytes);
    offset += 30 + nameBytes.length + data.length;
  }
  const centralSize = central.reduce((sum, part) => sum + part.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(Object.keys(parts).length, 8);
  end.writeUInt16LE(Object.keys(parts).length, 10);
  end.writeUInt32LE(centralSize, 12);
  end.writeUInt32LE(offset, 16);
  const all = Buffer.concat([...chunks, ...central, end]);
  return all.buffer.slice(all.byteOffset, all.byteOffset + all.length);
}

const MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

function workbook({ date1904 = false, sheet } = {}) {
  return {
    'xl/workbook.xml': `<?xml version="1.0"?><workbook xmlns="${MAIN}" xmlns:r="${REL}">${
      date1904 ? '<workbookPr date1904="1"/>' : ''
    }<sheets><sheet name="Donors" sheetId="1" r:id="rId1"/></sheets></workbook>`,
    'xl/_rels/workbook.xml.rels': `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${REL}/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="${REL}/sharedStrings" Target="sharedStrings.xml"/><Relationship Id="rId3" Type="${REL}/styles" Target="styles.xml"/></Relationships>`,
    'xl/sharedStrings.xml': `<?xml version="1.0"?><sst xmlns="${MAIN}"><si><t>Last Name</t></si><si><t>Email</t></si><si><t>Gift Date</t></si><si><r><t>Ram</t></r><r><t>irez</t></r></si><si><t>ana@example.org</t></si></sst>`,
    'xl/styles.xml': `<?xml version="1.0"?><styleSheet xmlns="${MAIN}"><numFmts><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="&quot;Total &quot;0.00"/></numFmts><cellXfs><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/><xf numFmtId="165"/></cellXfs></styleSheet>`,
    'xl/worksheets/sheet1.xml':
      sheet ||
      `<?xml version="1.0"?><worksheet xmlns="${MAIN}"><sheetData>` +
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c><c r="D1" t="inlineStr"><is><t>Amount</t></is></c></row>' +
        '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="s"><v>4</v></c><c r="C2" s="1"><v>46288</v></c><c r="D2" s="3"><v>25.5</v></c></row>' +
        '<row r="4"><c r="A4" t="str"><v>Okafor</v></c><c r="C4" s="2"><v>46288.5</v></c><c r="D4" t="b"><v>1</v></c></row>' +
        '</sheetData></worksheet>'
  };
}

describe('the workbook reader', () => {
  it('reads the first sheet into rows of text, as the CSV reader does', async () => {
    const rows = await readXlsx(zip(workbook()), { inflate });
    expect(rows[0]).toEqual(['Last Name', 'Email', 'Gift Date', 'Amount']);
    expect(rows[1]).toEqual(['Ramirez', 'ana@example.org', '2026-09-23', '25.5']);
  });

  it('keeps a skipped row and a skipped column in their places', async () => {
    const rows = await readXlsx(zip(workbook()), { inflate });
    expect(rows[2]).toEqual([]);
    expect(rows[3][0]).toBe('Okafor');
    expect(rows[3][1]).toBe('');
  });

  it('reads a date in a custom format with its time, and a checkbox as TRUE', async () => {
    const rows = await readXlsx(zip(workbook()), { inflate });
    expect(rows[3][2]).toBe('2026-09-23 12:00:00');
    expect(rows[3][3]).toBe('TRUE');
  });

  it('reads a file whose parts are stored rather than compressed', async () => {
    const rows = await readXlsx(zip(workbook(), { store: true }), { inflate });
    expect(rows[1][0]).toBe('Ramirez');
  });

  it('counts dates from 1904 when the workbook says so', async () => {
    const rows = await readXlsx(zip(workbook({ date1904: true })), { inflate });
    expect(rows[1][2]).toBe('2030-09-24');
  });

  it('refuses a file that is not a workbook', async () => {
    await expect(readXlsx(zip({ 'readme.txt': 'hello' }), { inflate })).rejects.toMatchObject({
      reason: 'notAWorkbook'
    });
    await expect(readXlsx(new ArrayBuffer(10), { inflate })).rejects.toMatchObject({
      reason: 'notAWorkbook'
    });
  });

  it('says the browser cannot read it when it has no decompression', async () => {
    await expect(readXlsx(zip(workbook()))).rejects.toMatchObject({
      reason: 'unsupportedBrowser'
    });
  });

  it('refuses a sheet past the last row or column it will fill, rather than padding to it', async () => {
    const farRow =
      `<?xml version="1.0"?><worksheet xmlns="${MAIN}"><sheetData>` +
      '<row r="1"><c r="A1" t="inlineStr"><is><t>Name</t></is></c></row>' +
      '<row r="1048576"><c r="A1048576" t="inlineStr"><is><t>Last</t></is></c></row>' +
      '</sheetData></worksheet>';
    await expect(readXlsx(zip(workbook({ sheet: farRow })), { inflate })).rejects.toMatchObject({
      reason: 'tooLarge'
    });
    const farColumn =
      `<?xml version="1.0"?><worksheet xmlns="${MAIN}"><sheetData>` +
      '<row r="1"><c r="XFD1" t="inlineStr"><is><t>Far</t></is></c></row>' +
      '</sheetData></worksheet>';
    await expect(readXlsx(zip(workbook({ sheet: farColumn })), { inflate })).rejects.toMatchObject({
      reason: 'tooLarge'
    });
  });

  it('refuses a part that says it unpacks to more than the ceiling, before unpacking it', async () => {
    let inflated = false;
    const counting = async (bytes) => {
      inflated = true;
      return inflate(bytes);
    };
    await expect(
      readXlsx(zip(workbook(), { declaredSize: MAX_PART_BYTES + 1 }), { inflate: counting })
    ).rejects.toMatchObject({ reason: 'tooLarge' });
    expect(inflated).toBe(false);
  });

  describe('a workbook with several sheets', () => {
    function twoSheets() {
      return {
        ...workbook(),
        'xl/workbook.xml': `<?xml version="1.0"?><workbook xmlns="${MAIN}" xmlns:r="${REL}"><sheets><sheet name="Read me" sheetId="1" r:id="rId4"/><sheet name="Donors" sheetId="2" r:id="rId1"/></sheets></workbook>`,
        'xl/_rels/workbook.xml.rels': `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${REL}/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId4" Type="${REL}/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId2" Type="${REL}/sharedStrings" Target="sharedStrings.xml"/><Relationship Id="rId3" Type="${REL}/styles" Target="styles.xml"/></Relationships>`,
        'xl/worksheets/sheet2.xml': `<?xml version="1.0"?><worksheet xmlns="${MAIN}"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>About this export</t></is></c></row></sheetData></worksheet>`
      };
    }

    it('lists the sheets in tab order', async () => {
      expect(await readSheetNames(zip(twoSheets()), { inflate })).toEqual(['Read me', 'Donors']);
    });

    it('reads the first sheet unless another is named', async () => {
      const first = await readXlsx(zip(twoSheets()), { inflate });
      expect(first).toEqual([['About this export']]);
      const chosen = await readXlsx(zip(twoSheets()), { inflate, sheet: 'Donors' });
      expect(chosen[0]).toEqual(['Last Name', 'Email', 'Gift Date', 'Amount']);
    });

    it('refuses a sheet name the workbook does not have', async () => {
      await expect(readXlsx(zip(twoSheets()), { inflate, sheet: 'Gone' })).rejects.toMatchObject({
        reason: 'notAWorkbook'
      });
    });
  });

  it('knows a workbook by its name', () => {
    expect(isXlsx('Donors.XLSX')).toBe(true);
    expect(isXlsx('donors.csv')).toBe(false);
    expect(isXlsx(undefined)).toBe(false);
  });

  it('turns Excel date serials into dates, allowing for the leap day 1900 never had', () => {
    expect(serialToDate(1)).toBe('1900-01-01');
    expect(serialToDate(61)).toBe('1900-03-01');
    expect(serialToDate(45000)).toBe('2023-03-15');
    expect(serialToDate(0, true)).toBe('1904-01-01');
    expect(serialToDate(Number.NaN)).toBe('');
  });
});
