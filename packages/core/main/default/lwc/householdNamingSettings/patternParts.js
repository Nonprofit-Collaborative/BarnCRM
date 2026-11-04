/**
 * The parts a household name or greeting pattern is built from, and where one goes when it is
 * added (drag and drop item 4). Framework free, so it ports to BarnCRM for WordPress (plan 9.9).
 *
 * The three tokens are the ones HouseholdNamingService fills in; "and" and "Family" are the
 * words the shipped patterns use. A part is pattern text, not a UI string, so it is not a label.
 */
export const PARTS = ['{FirstName}', '{LastName}', '{Salutation}', 'and', 'Family'];

/**
 * The pattern with the part put in place of the text from `start` to `end`, with a space on
 * each side where the neighbouring text has none: `{ value, caret }`, the caret just after the
 * part. A missing or out-of-range position means the end of the pattern.
 */
export function insertPart(pattern, part, start, end) {
  const text = pattern || '';
  const from = Number.isInteger(start) && start >= 0 && start <= text.length ? start : text.length;
  const to = Number.isInteger(end) && end >= from && end <= text.length ? end : from;
  const before = text.slice(0, from);
  const after = text.slice(to);
  const lead = before === '' || /\s$/.test(before) ? '' : ' ';
  const trail = after === '' || /^\s/.test(after) ? '' : ' ';
  const inserted = `${lead}${part}${trail}`;
  return { value: `${before}${inserted}${after}`, caret: before.length + lead.length + part.length };
}

/**
 * The character position nearest to `offset` pixels into the text, given a function that
 * measures the width of a piece of text. Without a measure, the end of the text.
 */
export function positionAtOffset(text, offset, measure) {
  const value = text || '';
  if (typeof measure !== 'function' || !(offset >= 0)) {
    return value.length;
  }
  let previous = 0;
  for (let index = 1; index <= value.length; index++) {
    const width = measure(value.slice(0, index));
    if (width >= offset) {
      return offset - previous < width - offset ? index - 1 : index;
    }
    previous = width;
  }
  return value.length;
}
