/**
 * Writes one sheet of values as an Excel workbook (.xlsx), in the browser, with no third-party
 * code (C-36, canonical model R-SQ11; the reasoning of ADR-0049, which keeps the import's
 * reader to reading). A pure module: it takes rows and returns bytes, and touches nothing else.
 *
 * The workbook holds a header row of labels in bold, then one row per record: numbers as
 * numbers, booleans as TRUE and FALSE, dates and date-times as Excel dates (date-times in the
 * browser's own time zone, as the person saw them), and everything else as text. The zip is
 * deflated with the browser's CompressionStream where it has one, and stored otherwise.
 */

const DAY_MS = 86400000;
const EXCEL_EPOCH = Date.UTC(1899, 11, 30);
// Characters XML 1.0 cannot hold at all; a value that has them loses only them.
// eslint-disable-next-line no-control-regex
const NOT_XML = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g;

export const CELL_TYPES = Object.freeze({
  TEXT: 'text',
  NUMBER: 'number',
  BOOLEAN: 'boolean',
  DATE: 'date',
  DATETIME: 'datetime'
});

/** True when this browser can deflate the workbook; it is stored, larger, when not. */
export function canCompress() {
  return typeof CompressionStream === 'function';
}

/** A file name such as `Gift__c-2026-10-12.xlsx`. */
export function xlsxFileName(objectApiName, today = new Date()) {
  const day = today.toISOString().slice(0, 10);
  return `${String(objectApiName || 'export').replace(/[^A-Za-z0-9_]/g, '_')}-${day}.xlsx`;
}

/** The letters of a zero-based column: 0 is A, 26 is AA. */
export function columnName(index) {
  let name = '';
  for (let rest = index + 1; rest > 0; rest = Math.floor((rest - 1) / 26)) {
    name = String.fromCharCode(65 + ((rest - 1) % 26)) + name;
  }
  return name;
}

/** An Excel date serial for `YYYY-MM-DD`, or for a date-time in the browser's time zone. */
export function toSerial(value, type) {
  if (type === CELL_TYPES.DATE) {
    const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value));
    return parts ? (Date.UTC(+parts[1], parts[2] - 1, +parts[3]) - EXCEL_EPOCH) / DAY_MS : null;
  }
  const moment = new Date(value);
  if (Number.isNaN(moment.getTime())) {
    return null;
  }
  const local = Date.UTC(
    moment.getFullYear(),
    moment.getMonth(),
    moment.getDate(),
    moment.getHours(),
    moment.getMinutes(),
    moment.getSeconds()
  );
  return (local - EXCEL_EPOCH) / DAY_MS;
}

function escapeXml(text) {
  return String(text)
    .replace(NOT_XML, '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function textCell(reference, text, style) {
  return `<c r="${reference}" t="inlineStr"${style ? ` s="${style}"` : ''}><is><t xml:space="preserve">${escapeXml(text)}</t></is></c>`;
}

function cell(reference, value, type) {
  if (value === undefined || value === null || value === '') {
    return '';
  }
  if (type === CELL_TYPES.NUMBER && Number.isFinite(Number(value))) {
    return `<c r="${reference}"><v>${Number(value)}</v></c>`;
  }
  if (type === CELL_TYPES.BOOLEAN && typeof value === 'boolean') {
    return `<c r="${reference}" t="b"><v>${value ? 1 : 0}</v></c>`;
  }
  if (type === CELL_TYPES.DATE || type === CELL_TYPES.DATETIME) {
    const serial = toSerial(value, type);
    if (serial !== null) {
      return `<c r="${reference}" s="${type === CELL_TYPES.DATE ? 1 : 2}"><v>${serial}</v></c>`;
    }
  }
  return textCell(reference, typeof value === 'object' ? JSON.stringify(value) : value);
}

/** The sheet's XML: a bold header row of labels, then the rows. */
export function sheetXml(columns, rows) {
  const lines = [
    `<row r="1">${columns.map((column, index) => textCell(`${columnName(index)}1`, column.label, 3)).join('')}</row>`
  ];
  rows.forEach((values, rowIndex) => {
    const number = rowIndex + 2;
    const cells = columns
      .map((column, index) => cell(`${columnName(index)}${number}`, values[index], column.type))
      .join('');
    lines.push(`<row r="${number}">${cells}</row>`);
  });
  return (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    `<sheetData>${lines.join('')}</sheetData></worksheet>`
  );
}

const STATIC_PARTS = {
  '[Content_Types].xml':
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/>' +
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
    '</Types>',
  '_rels/.rels':
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
    '</Relationships>',
  'xl/_rels/workbook.xml.rels':
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
    '</Relationships>',
  'xl/styles.xml':
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm:ss"/></numFmts>' +
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
    '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>' +
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
    '<cellXfs count="4">' +
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
    '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' +
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' +
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +
    '</cellXfs></styleSheet>'
};

function workbookXml(sheetName) {
  return (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' +
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
    `<sheets><sheet name="${escapeXml(sheetName)}" sheetId="1" r:id="rId1"/></sheets></workbook>`
  );
}

// -----------------------------------------------------------------------------------------
// The zip
// -----------------------------------------------------------------------------------------

let crcTable;

/** The CRC-32 a zip entry carries. */
export function crc32(bytes) {
  if (!crcTable) {
    crcTable = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) {
        c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      }
      crcTable[n] = c >>> 0;
    }
  }
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    crc = crcTable[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

async function deflateInBrowser(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream('deflate-raw'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function header(size) {
  const bytes = new Uint8Array(size);
  return { bytes, view: new DataView(bytes.buffer) };
}

/** A zip of the given parts: entries deflated by `deflate`, or stored when it is null. */
async function zip(parts, deflate) {
  const encoder = new TextEncoder();
  const chunks = [];
  const central = [];
  let offset = 0;
  for (const [name, text] of parts) {
    const nameBytes = encoder.encode(name);
    const raw = encoder.encode(text);
    // eslint-disable-next-line no-await-in-loop
    const data = deflate ? await deflate(raw) : raw;
    const crc = crc32(raw);
    const method = deflate ? 8 : 0;
    const local = header(30);
    local.view.setUint32(0, 0x04034b50, true);
    local.view.setUint16(4, 20, true);
    local.view.setUint16(6, 0x0800, true);
    local.view.setUint16(8, method, true);
    local.view.setUint32(14, crc, true);
    local.view.setUint32(18, data.length, true);
    local.view.setUint32(22, raw.length, true);
    local.view.setUint16(26, nameBytes.length, true);
    chunks.push(local.bytes, nameBytes, data);

    const entry = header(46);
    entry.view.setUint32(0, 0x02014b50, true);
    entry.view.setUint16(4, 20, true);
    entry.view.setUint16(6, 20, true);
    entry.view.setUint16(8, 0x0800, true);
    entry.view.setUint16(10, method, true);
    entry.view.setUint32(16, crc, true);
    entry.view.setUint32(20, data.length, true);
    entry.view.setUint32(24, raw.length, true);
    entry.view.setUint16(28, nameBytes.length, true);
    entry.view.setUint32(42, offset, true);
    central.push(entry.bytes, nameBytes);
    offset += 30 + nameBytes.length + data.length;
  }
  const centralSize = central.reduce((total, part) => total + part.length, 0);
  const end = header(22);
  end.view.setUint32(0, 0x06054b50, true);
  end.view.setUint16(8, parts.length, true);
  end.view.setUint16(10, parts.length, true);
  end.view.setUint32(12, centralSize, true);
  end.view.setUint32(16, offset, true);
  const all = [...chunks, ...central, end.bytes];
  const result = new Uint8Array(all.reduce((total, part) => total + part.length, 0));
  let at = 0;
  for (const part of all) {
    result.set(part, at);
    at += part.length;
  }
  return result;
}

/**
 * The workbook's bytes.
 *
 * @param {Array<{label: string, type: string}>} columns header labels and CELL_TYPES
 * @param {Array<Array<*>>} rows values in column order
 * @param {object} [options] `sheetName`; `deflate(bytes)` returning a promise of raw-deflated
 *   bytes, or `deflate: null` to store, for a test where CompressionStream is missing
 * @returns {Promise<Uint8Array>}
 */
export function writeXlsx(columns, rows, options = {}) {
  let deflate = canCompress() ? deflateInBrowser : null;
  if (Object.prototype.hasOwnProperty.call(options, 'deflate')) {
    deflate = options.deflate;
  }
  const sheetName = String(options.sheetName || 'Find')
    .slice(0, 31)
    .replace(/[\\/?*[\]:]/g, ' ');
  return zip(
    [
      ['[Content_Types].xml', STATIC_PARTS['[Content_Types].xml']],
      ['_rels/.rels', STATIC_PARTS['_rels/.rels']],
      ['xl/workbook.xml', workbookXml(sheetName)],
      ['xl/_rels/workbook.xml.rels', STATIC_PARTS['xl/_rels/workbook.xml.rels']],
      ['xl/styles.xml', STATIC_PARTS['xl/styles.xml']],
      ['xl/worksheets/sheet1.xml', sheetXml(columns, rows)]
    ],
    deflate
  );
}
