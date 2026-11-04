/**
 * The model behind the type-to-search field picker on Check Columns (admin-13). Framework free
 * (plan 9.9): no lightning/* or @salesforce/* imports, so it ports as it is.
 *
 * Options arrive as `{ label, value }`. A field of a people file carries its group in its label
 * ("Person: First Name", "Second person: Email", "Organization: Name"): the part before the first
 * ": " becomes the group heading and the rest the option's own label, when the value is a dotted
 * name (`Contact1.FirstName`). A one-object file's fields have no dots and stay in one flat list.
 */

const SEPARATOR = ': ';

/** Splits one option into its group heading (or '') and its own label. */
export function splitOption(option) {
  const label = String(option.label || '');
  const dotted = String(option.value || '').includes('.');
  const at = label.indexOf(SEPARATOR);
  if (dotted && at > 0) {
    return { group: label.slice(0, at), name: label.slice(at + SEPARATOR.length) };
  }
  return { group: '', name: label };
}

/** True when every word typed appears in the text, in any order, ignoring case. */
export function matches(text, query) {
  const words = String(query || '')
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean);
  const haystack = String(text || '').toLowerCase();
  return words.every((word) => haystack.includes(word));
}

/**
 * What the open list shows: the pinned choice (Do not load) first and always, then the options
 * that match the typed text under their group headings, in the order given. Every item has
 * `value`, `label`, `text` (the group and label, for a search and for a screen reader),
 * `used` (another column already loads into it) and `selected`.
 *
 * Returns `{ pinned, groups: [{ key, label, items }], items, count }` where `items` is the flat
 * list in display order (the pinned item first), which the keyboard walks.
 */
export function buildModel({ options, query, usedValues, selected, pinnedValue }) {
  const used = new Set((usedValues || []).map((value) => String(value).toLowerCase()));
  const groups = [];
  const byKey = new Map();
  let pinned = null;
  const flat = [];
  (options || []).forEach((option) => {
    const { group, name } = splitOption(option);
    const text = group ? `${group}${SEPARATOR}${name}` : name;
    const item = {
      value: option.value,
      label: name,
      text,
      used:
        option.value !== pinnedValue &&
        option.value !== selected &&
        used.has(String(option.value).toLowerCase()),
      selected: option.value === selected
    };
    if (option.value === pinnedValue) {
      pinned = { ...item, label: option.label, text: option.label };
      return;
    }
    if (!matches(text, query)) {
      return;
    }
    if (!byKey.has(group)) {
      const entry = { key: group || '-', label: group, items: [] };
      byKey.set(group, entry);
      groups.push(entry);
    }
    byKey.get(group).items.push(item);
  });
  if (pinned) {
    flat.push(pinned);
  }
  groups.forEach((group) => group.items.forEach((item) => flat.push(item)));
  return { pinned, groups, items: flat, count: flat.length - (pinned ? 1 : 0) };
}

/** The text the closed picker shows for the chosen value. */
export function selectedText(options, value) {
  const found = (options || []).find((option) => option.value === value);
  return found ? String(found.label || '') : '';
}

/** The next index walking the list by `delta`, stopping at the ends. */
export function stepIndex(current, delta, length) {
  if (length <= 0) {
    return -1;
  }
  if (current < 0) {
    return delta > 0 ? 0 : length - 1;
  }
  return Math.min(Math.max(current + delta, 0), length - 1);
}
