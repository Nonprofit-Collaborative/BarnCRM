/**
 * A CSV reader, small on purpose.
 *
 * The file is read in the browser and sent to the server as rows, so the server never holds
 * a whole spreadsheet in memory. That is why the parsing lives here rather than in Apex.
 *
 * It handles what an organization's export actually contains: quoted fields, commas and line
 * breaks inside quotes, doubled quotes as an escape, both line ending conventions, a byte
 * order mark from Excel, and a trailing blank line. Anything more exotic is a reason to open
 * the file in a spreadsheet and save it again, which the admin guide says.
 */

const BOM = '﻿';

/**
 * Splits CSV text into an array of rows, each an array of cell strings.
 *
 * @param {string} text the whole file
 * @returns {string[][]} the rows in file order, blank trailing rows removed
 */
export function parseCsv(text) {
  if (typeof text !== 'string' || text.length === 0) {
    return [];
  }
  const source = text.startsWith(BOM) ? text.slice(BOM.length) : text;
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;

  for (let i = 0; i < source.length; i++) {
    const char = source[i];
    if (quoted) {
      if (char === '"') {
        if (source[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += char;
      }
      continue;
    }
    if (char === '"') {
      quoted = true;
    } else if (char === ',') {
      row.push(field);
      field = '';
    } else if (char === '\n' || char === '\r') {
      // A carriage return and line feed pair ends one row, not two.
      if (char === '\r' && source[i + 1] === '\n') {
        i++;
      }
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
    } else {
      field += char;
    }
  }
  row.push(field);
  rows.push(row);

  while (rows.length > 0 && isBlankRow(rows[rows.length - 1])) {
    rows.pop();
  }
  return rows;
}

/**
 * Turns parsed rows into a header list and a list of objects keyed by header.
 *
 * A column with no heading is named by its position, so a file with a stray empty column
 * still reads and the administrator can see it in the picker and leave it unloaded.
 *
 * @param {string[][]} rows the output of parseCsv
 * @returns {{headers: string[], records: object[]}} the header row and the rows under it
 */
export function toRecords(rows) {
  if (!Array.isArray(rows) || rows.length === 0) {
    return { headers: [], records: [] };
  }
  const headers = rows[0].map((heading, index) => {
    const trimmed = (heading || '').trim();
    return trimmed.length > 0 ? trimmed : `Column ${index + 1}`;
  });
  const records = [];
  for (let i = 1; i < rows.length; i++) {
    if (isBlankRow(rows[i])) {
      continue;
    }
    const record = {};
    headers.forEach((heading, index) => {
      const value = rows[i][index];
      record[heading] = withoutFormulaGuard(
        value === undefined || value === null ? '' : String(value).trim()
      );
    });
    records.push(record);
  }
  return { headers, records };
}

/** Turns rows back into CSV text, which is how the exceptions file is built. */
export function toCsv(headers, records) {
  const lines = [headers.map(quote).join(',')];
  records.forEach((record) => {
    lines.push(headers.map((heading) => quote(record[heading])).join(','));
  });
  return lines.join('\r\n');
}

function quote(value) {
  const text = value === undefined || value === null ? '' : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/**
 * A value without the single quote a Find export puts before = + - or @ so a spreadsheet never
 * runs it as a formula (c/findCsv). Only that one quote is taken, so `'+44 20 7946 0000` loads
 * as `+44 20 7946 0000` and any other value loads as it is.
 */
export function withoutFormulaGuard(text) {
  return /^'[=+\-@]/.test(text) ? text.slice(1) : text;
}

function isBlankRow(row) {
  return row.every((cell) => (cell || '').trim().length === 0);
}
