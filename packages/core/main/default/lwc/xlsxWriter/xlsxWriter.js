/**
 * Writes one sheet of values as an Excel workbook (.xlsx), in the browser, with no third-party
 * code (C-36, canonical model R-SQ11; the reasoning of ADR-0049, which keeps the import's
 * reader to reading). A pure module: it takes rows and returns bytes, and touches nothing else.
 *
 * The workbook holds a header row of labels in bold, then one row per record: numbers as
 * numbers, booleans as TRUE and FALSE, dates and date-times as Excel dates (date-times as the
 * clock reads in the time zone it is given, the person's Salesforce one), and everything else
 * as text. The sheet is encoded a piece at a time, and the zip is deflated with the browser's
 * CompressionStream where it has one, and stored otherwise.
 */

import { zonedParts } from 'c/findCsv';

const DAY_MS = 86400000;
/** About how many characters of sheet XML are encoded at a time, so no one string holds it all. */
const PIECE_SIZE = 1 << 20;
const EXCEL_EPOCH = Date.UTC(1899, 11, 30);
/** The most characters one Excel cell holds. */
export const MAX_CELL_TEXT = 32767;
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

/** The letters of a zero-based column: 0 is A, 26 is AA. */
export function columnName(index) {
  let name = '';
  for (let rest = index + 1; rest > 0; rest = Math.floor((rest - 1) / 26)) {
    name = String.fromCharCode(65 + ((rest - 1) % 26)) + name;
  }
  return name;
}

/**
 * An Excel date serial for `YYYY-MM-DD`, or for a date-time as the clock reads in `timeZone`
 * (the person's Salesforce time zone, so the workbook agrees with the grid and the CSV).
 */
export function toSerial(value, type, timeZone) {
  if (type === CELL_TYPES.DATE) {
    const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value));
    return parts ? (Date.UTC(+parts[1], parts[2] - 1, +parts[3]) - EXCEL_EPOCH) / DAY_MS : null;
  }
  const clock = zonedParts(value, timeZone);
  if (!clock) {
    return null;
  }
  const local = Date.UTC(
    clock.year,
    clock.month - 1,
    clock.day,
    clock.hour,
    clock.minute,
    clock.second
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

/**
 * Text cut to what one Excel cell holds; a longer cell makes Excel report the workbook as
 * damaged. A character made of two code units is never split.
 */
function fitCell(text) {
  const value = String(text);
  if (value.length <= MAX_CELL_TEXT) {
    return value;
  }
  const cut = value.slice(0, MAX_CELL_TEXT);
  const last = cut.charCodeAt(cut.length - 1);
  return last >= 0xd800 && last <= 0xdbff ? cut.slice(0, -1) : cut;
}

function textCell(reference, text, style) {
  return `<c r="${reference}" t="inlineStr"${style ? ` s="${style}"` : ''}><is><t xml:space="preserve">${escapeXml(fitCell(text))}</t></is></c>`;
}

function cell(reference, value, type, timeZone) {
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
    const serial = toSerial(value, type, timeZone);
    if (serial !== null) {
      return `<c r="${reference}" s="${type === CELL_TYPES.DATE ? 1 : 2}"><v>${serial}</v></c>`;
    }
  }
  return textCell(reference, typeof value === 'object' ? JSON.stringify(value) : value);
}

/**
 * The sheet's XML, a bold header row of labels then the rows, handed to `emit` in pieces of
 * about `pieceSize` characters.
 */
function eachSheetPiece(columns, rows, emit, timeZone, pieceSize = PIECE_SIZE) {
  const letters = columns.map((column, index) => columnName(index));
  let piece =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' +
    `<row r="1">${columns.map((column, index) => textCell(`${letters[index]}1`, column.label, 3)).join('')}</row>`;
  rows.forEach((values, rowIndex) => {
    const number = rowIndex + 2;
    let cells = '';
    columns.forEach((column, index) => {
      cells += cell(`${letters[index]}${number}`, values[index], column.type, timeZone);
    });
    piece += `<row r="${number}">${cells}</row>`;
    if (piece.length >= pieceSize) {
      emit(piece);
      piece = '';
    }
  });
  emit(`${piece}</sheetData></worksheet>`);
}

/** The sheet's XML as one string, for a small sheet or a test. */
export function sheetXml(columns, rows, timeZone) {
  const pieces = [];
  eachSheetPiece(columns, rows, (piece) => pieces.push(piece), timeZone);
  return pieces.join('');
}

/**
 * The sheet's XML as UTF-8 byte chunks, each piece encoded as soon as it is written: a large
 * export never builds the whole sheet as one string, which a browser cannot hold past about
 * 500 million characters.
 */
export function sheetChunks(columns, rows, timeZone, pieceSize = PIECE_SIZE) {
  const encoder = new TextEncoder();
  const chunks = [];
  eachSheetPiece(columns, rows, (piece) => chunks.push(encoder.encode(piece)), timeZone, pieceSize);
  return chunks;
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

/**
 * The CRC-32 a zip entry carries. Pass the CRC of the bytes before as `previous` to carry it
 * across chunks: `crc32(b, crc32(a))` is the CRC of `a` then `b`.
 */
export function crc32(bytes, previous = 0) {
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
  let crc = (previous ^ 0xffffffff) >>> 0;
  for (let i = 0; i < bytes.length; i++) {
    crc = crcTable[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

/** Raw-deflates byte chunks as one stream, without joining them first. */
async function deflateInBrowser(chunks) {
  const stream = new Blob(chunks).stream().pipeThrough(new CompressionStream('deflate-raw'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function joined(chunks) {
  const result = new Uint8Array(chunks.reduce((total, part) => total + part.length, 0));
  let at = 0;
  for (const part of chunks) {
    result.set(part, at);
    at += part.length;
  }
  return result;
}

function header(size) {
  const bytes = new Uint8Array(size);
  return { bytes, view: new DataView(bytes.buffer) };
}

/**
 * A zip of the given parts, each text or a list of byte chunks: entries deflated by `deflate`
 * (which takes a list of chunks), or stored when it is null.
 */
async function zip(parts, deflate) {
  const encoder = new TextEncoder();
  const chunks = [];
  const central = [];
  let offset = 0;
  for (const [name, content] of parts) {
    const nameBytes = encoder.encode(name);
    const rawChunks = typeof content === 'string' ? [encoder.encode(content)] : content;
    let crc = 0;
    let rawLength = 0;
    for (const part of rawChunks) {
      crc = crc32(part, crc);
      rawLength += part.length;
    }
    // eslint-disable-next-line no-await-in-loop
    const data = deflate ? await deflate(rawChunks) : joined(rawChunks);
    const method = deflate ? 8 : 0;
    const local = header(30);
    local.view.setUint32(0, 0x04034b50, true);
    local.view.setUint16(4, 20, true);
    local.view.setUint16(6, 0x0800, true);
    local.view.setUint16(8, method, true);
    local.view.setUint32(14, crc, true);
    local.view.setUint32(18, data.length, true);
    local.view.setUint32(22, rawLength, true);
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
    entry.view.setUint32(24, rawLength, true);
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
  return joined([...chunks, ...central, end.bytes]);
}

/**
 * The workbook's bytes.
 *
 * @param {Array<{label: string, type: string}>} columns header labels and CELL_TYPES
 * @param {Array<Array<*>>} rows values in column order
 * @param {object} [options] `sheetName`; `timeZone`, the zone date-times are written in (the
 *   person's Salesforce one; UTC when absent); `deflate(bytes)` returning a promise of
 *   raw-deflated bytes, or `deflate: null` to store, for a test where CompressionStream is missing
 * @returns {Promise<Uint8Array>}
 */
export function writeXlsx(columns, rows, options = {}) {
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
      ['xl/worksheets/sheet1.xml', sheetChunks(columns, rows, options.timeZone)]
    ],
    deflaterFrom(options)
  );
}

/** The browser's deflater, or the one `options.deflate` gives, or null (store) when none. */
function deflaterFrom(options) {
  if (Object.prototype.hasOwnProperty.call(options, 'deflate')) {
    return options.deflate ? (chunks) => options.deflate(joined(chunks)) : null;
  }
  return canCompress() ? deflateInBrowser : null;
}

/**
 * A zip archive's bytes (the AI-Readiness Export's pack, AIR-01), from the same zip writer the
 * workbook uses.
 *
 * @param {Array<[string, string]>} files each a path inside the zip and its text (UTF-8)
 * @param {object} [options] `deflate`, as for writeXlsx
 * @returns {Promise<Uint8Array>}
 */
export function writeZip(files, options = {}) {
  return zip(files, deflaterFrom(options));
}
