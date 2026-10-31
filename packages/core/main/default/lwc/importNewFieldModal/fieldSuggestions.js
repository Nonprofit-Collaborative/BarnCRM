/**
 * Suggestions for a new field from an import column (C-49d): an API name from the heading and
 * a type from the column's values. Pure functions, so they are tested without the modal.
 */
const NAME_LIMIT = 40;
const MAX_VALUES = 200;
const MAX_PICKLIST_SUGGESTED = 20;
const MAX_SCALE = 8;

const CHECKBOX = /^(true|false|yes|no|y|n)$/i;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const URL_PATTERN = /^(https?:\/\/|www\.)\S+$/i;
const CURRENCY = /^-?[$£€]\s?-?(\d{1,3}(,\d{3})+|\d+)(\.\d+)?$/;
const PERCENT = /^-?\d+(\.\d+)?\s?%$/;
const NUMBER = /^-?(\d{1,3}(,\d{3})+|\d+)(\.\d+)?$/;
const DATE = /^(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}\/\d{1,2}\/\d{2,4})$/;
const DATE_TIME =
  /^(\d{4}-\d{1,2}-\d{1,2}[T ]|\d{1,2}\/\d{1,2}\/\d{2,4} )\d{1,2}:\d{2}(:\d{2})?(\.\d+)?\s?(Z|[AP]M|[+-]\d{2}:?\d{2})?$/i;
const PHONE = /^\+?[\d\s().-]{7,20}$/;

/** A field API name (without __c) from a heading: letters, digits and single underscores. */
export function apiNameFrom(heading) {
  let name = String(heading || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!/^[A-Za-z]/.test(name)) {
    name = name ? `Field_${name}` : 'New_Field';
  }
  return name.slice(0, NAME_LIMIT).replace(/_+$/, '');
}

/** The column's distinct values, first spelling kept, in file order, at most 200. */
export function distinctValues(values) {
  const seen = new Map();
  (values || []).forEach((value) => {
    const text = value === undefined || value === null ? '' : String(value).trim();
    if (text && !seen.has(text.toLowerCase())) {
      seen.set(text.toLowerCase(), text.slice(0, 255));
    }
  });
  return [...seen.values()].slice(0, MAX_VALUES);
}

function decimals(values) {
  return Math.min(
    MAX_SCALE,
    Math.max(0, ...values.map((value) => (value.split('.')[1] || '').replace(/\D/g, '').length))
  );
}

/**
 * The suggested field for a column's values: { type, length, scale, values }. The first test
 * every non-blank value passes wins; a column of a few repeated words becomes a picklist.
 */
export function suggestField(rawValues) {
  const values = (rawValues || [])
    .map((value) => (value === undefined || value === null ? '' : String(value).trim()))
    .filter((value) => value.length > 0);
  const field = (type, scale = 0) => ({ type, length: 255, scale, values: [] });
  if (values.length === 0) {
    return field('Text');
  }
  const all = (pattern) => values.every((value) => pattern.test(value));
  if (all(CHECKBOX)) {
    return field('Checkbox');
  }
  if (all(EMAIL)) {
    return field('Email');
  }
  if (all(URL_PATTERN)) {
    return field('Url');
  }
  if (all(CURRENCY)) {
    return field('Currency', 2);
  }
  if (all(PERCENT)) {
    return field('Percent', decimals(values));
  }
  if (all(NUMBER)) {
    return field('Number', decimals(values));
  }
  if (all(DATE_TIME)) {
    return field('DateTime');
  }
  if (all(DATE)) {
    return field('Date');
  }
  if (all(PHONE) && values.some((value) => /[\s().+-]/.test(value))) {
    return field('Phone');
  }
  if (values.some((value) => value.length > 255)) {
    return field('LongTextArea');
  }
  const distinct = distinctValues(values);
  if (
    distinct.length > 1 &&
    distinct.length <= MAX_PICKLIST_SUGGESTED &&
    distinct.length * 2 <= values.length
  ) {
    return { ...field('Picklist'), values: distinct };
  }
  return field('Text');
}
