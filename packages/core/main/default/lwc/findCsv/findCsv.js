/**
 * Writes Find results as CSV the way canonical model R-SQ3 says: UTF-8 with a byte-order mark,
 * so Excel opens names with accents correctly, one header row of column labels, and every value
 * quoted when it holds a comma, a quote or a line break. A text value that starts with = + - @ or
 * a tab or carriage return gets a leading single quote, so a spreadsheet shows it as text and
 * never runs it as a formula. Real numbers are left alone, so a negative amount stays a number.
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
  let text = typeof value === 'object' ? JSON.stringify(value) : String(value);
  if (typeof value !== 'number' && /^[=+\-@\t\r]/.test(text)) {
    text = `'${text}`;
  }
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

/** A file name such as `Gift__c-2026-10-12.csv`, or `.xlsx` with that extension. */
export function fileName(objectApiName, today = new Date(), extension = 'csv') {
  const day = today.toISOString().slice(0, 10);
  return `${String(objectApiName || 'export').replace(/[^A-Za-z0-9_]/g, '_')}-${day}.${extension}`;
}

// -----------------------------------------------------------------------------------------
// What the Find components share
// -----------------------------------------------------------------------------------------

/** A label with `{0}`, `{1}` and so on replaced by the values, in order. */
export function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

/** The message to show for a failed server call or a thrown error. */
export function messageFrom(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return error && error.message ? error.message : String(error);
}

const zonedFormats = new Map();

/**
 * A date-time's calendar parts in a time zone (the person's Salesforce one), or null when the
 * value is not a date-time: `{ year, month, day, hour, minute, second }`, all numbers.
 */
export function zonedParts(value, timeZone) {
  const moment = new Date(value);
  if (value === null || value === undefined || value === '' || Number.isNaN(moment.getTime())) {
    return null;
  }
  const zone = timeZone || 'UTC';
  let formatter = zonedFormats.get(zone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: zone,
      hourCycle: 'h23',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric'
    });
    zonedFormats.set(zone, formatter);
  }
  const parts = {};
  for (const part of formatter.formatToParts(moment)) {
    if (part.type !== 'literal') {
      parts[part.type] = Number(part.value);
    }
  }
  return parts;
}

/**
 * A date-time as `2026-01-05 09:30:00` in a time zone (the person's Salesforce one), the way a
 * CSV export writes it, or the value as it came when it is not a date-time.
 */
export function zonedDateTime(value, timeZone) {
  const parts = zonedParts(value, timeZone);
  if (!parts) {
    return value;
  }
  const two = (number) => String(number).padStart(2, '0');
  return (
    `${parts.year}-${two(parts.month)}-${two(parts.day)} ` +
    `${two(parts.hour)}:${two(parts.minute)}:${two(parts.second)}`
  );
}
