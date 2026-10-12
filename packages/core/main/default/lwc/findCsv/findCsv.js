/**
 * Writes Find results as CSV the way canonical model R-SQ3 says: UTF-8 with a byte-order mark,
 * so Excel opens names with accents correctly, one header row of column labels, and every value
 * quoted when it holds a comma, a quote or a line break.
 */

// Written as a code point so the source holds no invisible character.
export const BYTE_ORDER_MARK = String.fromCharCode(0xfeff);

/** The value at a field path such as `Donor_Contact__r.LastName`, or undefined. */
export function valueAt(row, path) {
  return String(path)
    .split('.')
    .reduce(
      (current, name) => (current === undefined || current === null ? undefined : current[name]),
      row
    );
}

/** One CSV cell. */
export function cell(value) {
  if (value === undefined || value === null) {
    return '';
  }
  const text = typeof value === 'object' ? JSON.stringify(value) : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/** The CSV text: header row of labels, then one line per row, lines ending CRLF. */
export function toCsv(columns, rows) {
  const lines = [columns.map((column) => cell(column.label)).join(',')];
  for (const row of rows) {
    lines.push(columns.map((column) => cell(valueAt(row, column.path))).join(','));
  }
  return BYTE_ORDER_MARK + lines.join('\r\n') + '\r\n';
}

/** A file name such as `Gift__c-2026-10-12.csv`. */
export function fileName(objectApiName, today = new Date()) {
  const day = today.toISOString().slice(0, 10);
  return `${String(objectApiName || 'export').replace(/[^A-Za-z0-9_]/g, '_')}-${day}.csv`;
}
