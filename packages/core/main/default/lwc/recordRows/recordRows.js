/**
 * Small helpers for the record list item the people panels share (Household Members,
 * Relationships, Affiliations, Addresses; the Visual Standard's record list item). Framework
 * free (no lightning or @salesforce imports), so the same logic serves BarnCRM for WordPress
 * (plan 9.9).
 */

/** "MG" for "Maria Garcia": the first letters of the first and last words of the name. */
export function initialsOf(name) {
  const words = String(name || '')
    .trim()
    .split(/\s+/)
    .filter((word) => word);
  if (!words.length) {
    return '';
  }
  const first = Array.from(words[0])[0];
  const last = words.length > 1 ? Array.from(words[words.length - 1])[0] : '';
  return `${first}${last}`.toUpperCase();
}

/** The plain record path, which works as a link's address everywhere until a click is handled. */
export function recordHref(recordId) {
  return recordId ? `/${recordId}` : undefined;
}

/** True when the click asks for a new tab or window (a modifier key or a middle click). */
export function opensElsewhere(event) {
  return Boolean(event && (event.button > 0 || event.ctrlKey || event.metaKey || event.shiftKey));
}
