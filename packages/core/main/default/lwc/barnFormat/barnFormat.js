/**
 * The small text and date helpers every package's framework-free modules share (UTIL-01, plan
 * 9.9): no Lightning or Salesforce import, so the same file runs in a browser, a test or another
 * interface. Modules re-export these rather than keep their own copies.
 */

/**
 * A label with every `{0}`, `{1}` and so on replaced by the values, in order. A placeholder with
 * no value given stays as it is; a value given as null or undefined reads as empty text; a
 * missing label reads as empty text. A value is never read again for placeholders.
 */
export function format(template, ...values) {
  return String(template ?? '').replace(/\{(\d+)\}/g, (match, index) => {
    const position = Number(index);
    if (position >= values.length) {
      return match;
    }
    const value = values[position];
    return value === undefined || value === null ? '' : String(value);
  });
}

/** A date as YYYY-MM-DD in the browser's local time; today when none is given. */
export function isoDate(date = new Date()) {
  const two = (number) => String(number).padStart(2, '0');
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
}

/**
 * A YYYY-MM-DD date as the locale writes it (medium style), read as a calendar day; null for
 * none, and the text as given when it is not a date or the locale cannot format it.
 */
export function formatDate(iso, locale) {
  if (!iso) {
    return null;
  }
  const [year, month, day] = String(iso).split('-').map(Number);
  if (!year || !month || !day) {
    return String(iso);
  }
  try {
    return new Intl.DateTimeFormat(locale || undefined, {
      dateStyle: 'medium',
      timeZone: 'UTC'
    }).format(new Date(Date.UTC(year, month - 1, day)));
  } catch {
    return String(iso);
  }
}

const HTML_ESCAPES = Object.freeze({
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;'
});

/** A value made safe to place in HTML text or an attribute; empty text for null or undefined. */
export function escapeHtml(value) {
  return value === undefined || value === null
    ? ''
    : String(value).replace(/[&<>"']/g, (character) => HTML_ESCAPES[character]);
}
