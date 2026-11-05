/**
 * Suggested fields for the columns a spreadsheet has not matched yet (admin-1 drag and drop item
 * 3). Framework free (plan 9.9). A column heading and a field are split into lower-case words;
 * a field scores 2 for each heading word it holds exactly and 1 for each word either one starts
 * with (three letters or more). Nothing scoring is never suggested, so a column with no likeness
 * to any field adds nothing to the list.
 */

const MIN_PREFIX = 3;

/** Lower-case words of a heading or a field label ("firstName" and "First Name" alike). */
export function words(text) {
  return String(text || '')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

/** How alike a heading and a field label are: 0 for not at all. */
export function score(heading, label) {
  const fieldWords = words(label);
  return words(heading).reduce((total, word) => {
    if (fieldWords.includes(word)) {
      return total + 2;
    }
    const near = fieldWords.some(
      (other) =>
        Math.min(word.length, other.length) >= MIN_PREFIX &&
        (other.startsWith(word) || word.startsWith(other))
    );
    return near ? total + 1 : total;
  }, 0);
}

/**
 * The fields worth offering for the unmatched headings: for each heading its best `perHeading`
 * (default 3) fields that no other column loads into, in heading order, each field once, and at
 * most `max` (default 12). `skip` lists values never offered ("Do not load", Create New Field).
 */
export function suggestFields(headings, options, usedValues, settings = {}) {
  const perHeading = settings.perHeading || 3;
  const max = settings.max || 12;
  const skip = new Set((settings.skip || []).map((value) => String(value).toLowerCase()));
  const used = new Set((usedValues || []).map((value) => String(value).toLowerCase()));
  const open = (options || []).filter((option) => {
    const key = String(option.value).toLowerCase();
    return !skip.has(key) && !used.has(key);
  });
  const chosen = [];
  const seen = new Set();
  (headings || []).forEach((heading) => {
    open
      .map((option) => ({ option, points: score(heading, option.label) }))
      .filter((entry) => entry.points > 0)
      .sort((a, b) => b.points - a.points)
      .slice(0, perHeading)
      .forEach(({ option }) => {
        if (!seen.has(option.value) && chosen.length < max) {
          seen.add(option.value);
          chosen.push(option);
        }
      });
  });
  return chosen;
}
