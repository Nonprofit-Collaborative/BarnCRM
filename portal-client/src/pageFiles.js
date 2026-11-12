/**
 * Files a portal page hands the person, built in the browser from the records already sent
 * (ADR-0215 `0215-events-attendee-app-operations-portal-templates.md`, decision 2): an iCalendar
 * file for Add to Calendar and a CSV for Download CSV. Framework-free and free of the DOM, so the
 * same code serves any portal client.
 */

/** Text for an iCalendar value: backslash, semicolon, comma and line breaks escaped. */
function icsText(value) {
  return String(value ?? '')
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');
}

/** Lines longer than 75 octets are folded, as RFC 5545 asks (characters stand in for octets). */
function fold(line) {
  const parts = [];
  for (let at = 0; at < line.length; at += 74) {
    parts.push((at === 0 ? '' : ' ') + line.slice(at, at + 74));
  }
  return parts.join('\r\n');
}

function pad(number) {
  return String(number).padStart(2, '0');
}

/** A date (`yyyy-MM-dd`) as an all-day value, or a date and time as UTC. */
function icsWhen(name, value) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(value))) {
    return name + ';VALUE=DATE:' + String(value).replace(/-/g, '');
  }
  const at = new Date(value);
  if (Number.isNaN(at.getTime())) {
    return null;
  }
  const stamp =
    at.getUTCFullYear() +
    pad(at.getUTCMonth() + 1) +
    pad(at.getUTCDate()) +
    'T' +
    pad(at.getUTCHours()) +
    pad(at.getUTCMinutes()) +
    pad(at.getUTCSeconds()) +
    'Z';
  return name + ':' + stamp;
}

/**
 * An iCalendar file of a page's records.
 * @param {object} page the page as read: `calendar` maps title, start, end and location to fields
 * @param {object[]} records `{ id, values }` rows
 * @param {Date} [now] the stamp time
 * @returns {string} the file's text, or '' when no record has a title and start
 */
export function toIcs(page, records, now = new Date()) {
  const calendar = page.calendar || {};
  const stamp = icsWhen('DTSTAMP', now.toISOString());
  const events = [];
  records.forEach((record) => {
    const values = record.values || {};
    const start = icsWhen('DTSTART', values[calendar.start]);
    if (!start || !values[calendar.title]) {
      return;
    }
    const lines = [
      'BEGIN:VEVENT',
      'UID:' + record.id + '@barncrm-portal',
      stamp,
      start,
      'SUMMARY:' + icsText(values[calendar.title])
    ];
    const end =
      calendar.end && values[calendar.end] ? icsWhen('DTEND', values[calendar.end]) : null;
    if (end) {
      lines.push(end);
    }
    if (calendar.location && values[calendar.location]) {
      lines.push('LOCATION:' + icsText(values[calendar.location]));
    }
    lines.push('END:VEVENT');
    events.push(...lines);
  });
  if (events.length === 0) {
    return '';
  }
  return (
    ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//BarnCRM//Portal//EN', ...events, 'END:VCALENDAR']
      .map(fold)
      .join('\r\n') + '\r\n'
  );
}

/** One CSV cell: quoted when needed, and a leading formula sign made inert. */
function csvCell(value) {
  let text = String(value ?? '');
  if (/^[=+\-@\t\r]/.test(text)) {
    text = "'" + text;
  }
  return /[",\r\n]/.test(text) ? '"' + text.replace(/"/g, '""') + '"' : text;
}

/**
 * A CSV of a page's records as shown: one column per field, labelled.
 * @param {object} page the page as read, with `fields`
 * @param {object[]} records `{ id, values }` rows
 * @param {function} show turns a field and its value into the text shown
 * @returns {string} the file's text
 */
export function toCsv(page, records, show) {
  const header = page.fields.map((field) => csvCell(field.label));
  const rows = records.map((record) =>
    page.fields.map((field) => csvCell(show(field, (record.values || {})[field.field]))).join(',')
  );
  return [header.join(','), ...rows].join('\r\n') + '\r\n';
}
