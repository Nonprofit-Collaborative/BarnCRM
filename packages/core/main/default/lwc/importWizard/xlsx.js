/**
 * Reads one sheet of an Excel workbook (.xlsx), the first unless another is named, into rows
 * of text, the same shape `parseCsv` returns, so the rest of the wizard does not know which
 * kind of file it was given.
 *
 * An .xlsx file is a zip of XML documents. This reads the zip's central directory, inflates
 * the few parts it needs with the browser's own DecompressionStream, and reads the XML with
 * DOMParser. It reads values, not formatting: a formula gives the value Excel last saved for
 * it, a date gives YYYY-MM-DD (with the time when there is one), and a number gives the digits
 * Excel stored. See ADR-0049 (the workbook is read in the browser without SheetJS).
 */

const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_SIGNATURE = 0x02014b50;
const LOCAL_SIGNATURE = 0x04034b50;
const STORED = 0;
const DEFLATED = 8;

/** Excel's built-in number formats that show a date or a time. */
const BUILT_IN_DATE_FORMATS = new Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47]);
const DAY_MS = 86400000;

/**
 * The most any one part of the workbook may hold once inflated. A sheet this size is far past
 * what the wizard can stage, and a zip can claim to hold far more than it is sent as.
 */
export const MAX_PART_BYTES = 100 * 1024 * 1024;

/** The last row and column the reader will place a value in; a file past them is refused. */
export const MAX_ROWS = 500000;
export const MAX_COLUMNS = 1000;

/** The reasons a file cannot be read, as keys the wizard turns into sentences. */
export const XLSX_ERRORS = {
  notAWorkbook: 'notAWorkbook',
  unsupportedBrowser: 'unsupportedBrowser',
  tooLarge: 'tooLarge'
};

class XlsxError extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

/** True when this browser can read a workbook: it needs DecompressionStream. */
export function canReadXlsx() {
  return typeof DecompressionStream === 'function';
}

/** True for a file the wizard should read as a workbook rather than as CSV text. */
export function isXlsx(fileName) {
  return /\.xlsx$/i.test(fileName || '');
}

/**
 * The names of the workbook's sheets, in the order Excel shows their tabs. Reads only the
 * workbook part, so it is cheap to call before choosing which sheet to read.
 *
 * @param {ArrayBuffer} buffer the file's bytes
 * @param {object} [options] as for readXlsx
 * @returns {Promise<string[]>} the sheet names
 */
export async function readSheetNames(buffer, options = {}) {
  const { workbook } = await openWorkbook(buffer, options);
  return byLocalName(workbook, 'sheet').map((sheet) => sheet.getAttribute('name') || '');
}

/**
 * One sheet's rows, each an array of text: the sheet named in `options.sheet`, or the first.
 *
 * @param {ArrayBuffer} buffer the file's bytes
 * @param {object} [options] `inflate(bytes)` returning a promise of the raw-inflated bytes,
 *   for a test to supply where the browser's DecompressionStream is not available; `sheet`,
 *   the name of the sheet to read
 * @returns {Promise<string[][]>} the rows
 */
export async function readXlsx(buffer, options = {}) {
  const { workbook, read } = await openWorkbook(buffer, options);
  const relationships = parseRelationships(await read('xl/_rels/workbook.xml.rels'));
  const sheets = byLocalName(workbook, 'sheet');
  const chosen = options.sheet
    ? sheets.find((sheet) => sheet.getAttribute('name') === options.sheet)
    : sheets[0];
  if (!chosen) {
    throw new XlsxError(XLSX_ERRORS.notAWorkbook);
  }
  const sheetTarget = relationships.byId.get(relationshipId(chosen));
  const sheetXml = sheetTarget ? await read(sheetTarget) : null;
  if (!sheetXml) {
    throw new XlsxError(XLSX_ERRORS.notAWorkbook);
  }
  const sharedStrings = readSharedStrings(
    await read(relationships.byType.get('sharedStrings') || 'xl/sharedStrings.xml')
  );
  const dateStyles = readDateStyles(
    await read(relationships.byType.get('styles') || 'xl/styles.xml')
  );
  const workbookPr = byLocalName(workbook, 'workbookPr')[0];
  const date1904 = Boolean(
    workbookPr && ['1', 'true'].includes(workbookPr.getAttribute('date1904'))
  );
  return readSheet(parseXml(sheetXml), { sharedStrings, dateStyles, date1904 });
}

/** The parsed workbook part, and a reader for the zip's other parts. */
async function openWorkbook(buffer, options) {
  const inflate = options.inflate || inflateInBrowser;
  const bytes = new Uint8Array(buffer);
  const entries = readCentralDirectory(bytes);
  const read = async (path) => {
    const entry = entries.get(path.replace(/^\//, ''));
    if (!entry) {
      return null;
    }
    if (entry.uncompressedSize > MAX_PART_BYTES) {
      throw new XlsxError(XLSX_ERRORS.tooLarge);
    }
    const part = await extract(bytes, entry, inflate);
    if (part.length > MAX_PART_BYTES) {
      throw new XlsxError(XLSX_ERRORS.tooLarge);
    }
    return decodeUtf8(part);
  };

  const workbookXml = await read('xl/workbook.xml');
  if (!workbookXml) {
    throw new XlsxError(XLSX_ERRORS.notAWorkbook);
  }
  return { workbook: parseXml(workbookXml), read };
}

// -----------------------------------------------------------------------------------------
// The zip
// -----------------------------------------------------------------------------------------

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
    throw new XlsxError(XLSX_ERRORS.notAWorkbook);
  }
  const count = view.getUint16(eocd + 10, true);
  let offset = view.getUint32(eocd + 16, true);
  const entries = new Map();
  for (let i = 0; i < count; i++) {
    if (offset + 46 > bytes.length || view.getUint32(offset, true) !== CENTRAL_SIGNATURE) {
      throw new XlsxError(XLSX_ERRORS.notAWorkbook);
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
  if (view.getUint32(local, true) !== LOCAL_SIGNATURE) {
    throw new XlsxError(XLSX_ERRORS.notAWorkbook);
  }
  const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
  const data = bytes.subarray(start, start + entry.compressedSize);
  if (entry.method === STORED) {
    return data;
  }
  if (entry.method === DEFLATED) {
    return inflate(data);
  }
  throw new XlsxError(XLSX_ERRORS.notAWorkbook);
}

async function inflateInBrowser(data) {
  if (!canReadXlsx()) {
    throw new XlsxError(XLSX_ERRORS.unsupportedBrowser);
  }
  const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function decodeUtf8(bytes) {
  return new TextDecoder('utf-8').decode(bytes);
}

// -----------------------------------------------------------------------------------------
// The XML parts
// -----------------------------------------------------------------------------------------

function parseXml(text) {
  const doc = new DOMParser().parseFromString(text, 'application/xml');
  if (byLocalName(doc, 'parsererror').length > 0) {
    throw new XlsxError(XLSX_ERRORS.notAWorkbook);
  }
  return doc;
}

/** Elements by local name, whatever namespace prefix the writing program used. */
function byLocalName(node, name) {
  return Array.from(node.getElementsByTagNameNS('*', name));
}

function childrenNamed(node, name) {
  return Array.from(node.childNodes).filter((child) => child.localName === name);
}

function relationshipId(sheet) {
  for (const attribute of Array.from(sheet.attributes)) {
    if (attribute.localName === 'id') {
      return attribute.value;
    }
  }
  return null;
}

/** The workbook's parts by relationship id and by kind, as paths from the zip's root. */
function parseRelationships(text) {
  const byId = new Map();
  const byType = new Map();
  if (!text) {
    return { byId, byType };
  }
  for (const relationship of byLocalName(parseXml(text), 'Relationship')) {
    const target = relationship.getAttribute('Target') || '';
    const path = target.startsWith('/') ? target.slice(1) : `xl/${target}`;
    byId.set(relationship.getAttribute('Id'), path);
    const type = (relationship.getAttribute('Type') || '').split('/').pop();
    byType.set(type, path);
  }
  return { byId, byType };
}

/** Each shared string, its runs joined, leaving out the phonetic guides some locales add. */
function readSharedStrings(text) {
  if (!text) {
    return [];
  }
  return byLocalName(parseXml(text), 'si').map(richText);
}

/** The style indexes whose number format shows a date or a time. */
function readDateStyles(text) {
  const styles = new Set();
  if (!text) {
    return styles;
  }
  const doc = parseXml(text);
  const customDates = new Set();
  for (const format of byLocalName(doc, 'numFmt')) {
    const code = (format.getAttribute('formatCode') || '')
      .replace(/"[^"]*"/g, '')
      .replace(/\[[^\]]*\]/g, '')
      .replace(/\\./g, '');
    if (/[dmyhs]/i.test(code)) {
      customDates.add(Number(format.getAttribute('numFmtId')));
    }
  }
  const cellXfs = byLocalName(doc, 'cellXfs')[0];
  if (!cellXfs) {
    return styles;
  }
  childrenNamed(cellXfs, 'xf').forEach((xf, index) => {
    const id = Number(xf.getAttribute('numFmtId') || 0);
    if (BUILT_IN_DATE_FORMATS.has(id) || customDates.has(id)) {
      styles.add(index);
    }
  });
  return styles;
}

// -----------------------------------------------------------------------------------------
// The sheet
// -----------------------------------------------------------------------------------------

function readSheet(doc, context) {
  const rows = [];
  for (const row of byLocalName(doc, 'row')) {
    const rowNumber = Number(row.getAttribute('r')) || rows.length + 1;
    if (rowNumber > MAX_ROWS) {
      throw new XlsxError(XLSX_ERRORS.tooLarge);
    }
    while (rows.length < rowNumber - 1) {
      rows.push([]);
    }
    const values = [];
    for (const cell of childrenNamed(row, 'c')) {
      const column = columnIndex(cell.getAttribute('r'), values.length);
      if (column >= MAX_COLUMNS) {
        throw new XlsxError(XLSX_ERRORS.tooLarge);
      }
      while (values.length < column) {
        values.push('');
      }
      values[column] = cellText(cell, context);
    }
    rows.push(values);
  }
  return rows;
}

/** The zero-based column of a reference such as "AB12", or the next column when it has none. */
function columnIndex(reference, next) {
  const letters = /^([A-Z]+)/i.exec(reference || '');
  if (!letters) {
    return next;
  }
  let index = 0;
  for (const letter of letters[1].toUpperCase()) {
    index = index * 26 + (letter.charCodeAt(0) - 64);
  }
  return index - 1;
}

function cellText(cell, context) {
  const type = cell.getAttribute('t') || 'n';
  const valueNode = childrenNamed(cell, 'v')[0];
  const value = valueNode ? valueNode.textContent : '';
  if (type === 'inlineStr') {
    const inline = childrenNamed(cell, 'is')[0];
    return inline ? richText(inline) : '';
  }
  if (type === 's') {
    return context.sharedStrings[Number(value)] || '';
  }
  if (type === 'b') {
    return value === '1' ? 'TRUE' : 'FALSE';
  }
  if (type === 'n' && value !== '' && context.dateStyles.has(Number(cell.getAttribute('s')))) {
    return serialToDate(Number(value), context.date1904);
  }
  return value;
}

/** The text of a string item: its own text and its runs', joined, without phonetic guides. */
function richText(node) {
  const runs = [...childrenNamed(node, 't')];
  for (const run of childrenNamed(node, 'r')) {
    runs.push(...childrenNamed(run, 't'));
  }
  return runs.map((each) => each.textContent).join('');
}

/**
 * An Excel date serial as YYYY-MM-DD, with HH:MM:SS when it carries a time. The 1900 date
 * system counts a 29 February 1900 that never was, so serials before it start a day later.
 */
export function serialToDate(serial, date1904 = false) {
  if (!Number.isFinite(serial)) {
    return '';
  }
  let base;
  if (date1904) {
    base = Date.UTC(1904, 0, 1);
  } else {
    base = serial < 60 ? Date.UTC(1899, 11, 31) : Date.UTC(1899, 11, 30);
  }
  const iso = new Date(base + Math.round((serial * DAY_MS) / 1000) * 1000).toISOString();
  const date = iso.slice(0, 10);
  const time = iso.slice(11, 19);
  return time === '00:00:00' ? date : `${date} ${time}`;
}
