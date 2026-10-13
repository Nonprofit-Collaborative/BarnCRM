/**
 * The filter document of canonical model R-R2, without any markup: which operators suit which
 * field type, what kind of value each needs, how a value is written into the document and read
 * back, and whether a condition logic string is well formed.
 *
 * The server checks everything again (RollupFilterParser and the query compiler); this module
 * exists so the builder can say what is wrong next to the condition, before anything is saved.
 */

export const DOCUMENT_VERSION = 1;
export const MAX_DAYS = 3650;

export const OPERATORS = Object.freeze({
  EQUALS: 'equals',
  NOT_EQUALS: 'not equals',
  LESS_THAN: 'less than',
  LESS_OR_EQUAL: 'less or equal',
  GREATER_THAN: 'greater than',
  GREATER_OR_EQUAL: 'greater or equal',
  CONTAINS: 'contains',
  NOT_CONTAINS: 'does not contain',
  STARTS_WITH: 'starts with',
  IS_NULL: 'is null',
  IS_NOT_NULL: 'is not null',
  IN: 'in',
  NOT_IN: 'not in',
  THIS_YEAR: 'this year',
  LAST_YEAR: 'last year',
  LAST_N_DAYS: 'last n days'
});

const O = OPERATORS;
const NULL_TESTS = [O.IS_NULL, O.IS_NOT_NULL];
const COMPARISONS = [
  O.EQUALS,
  O.NOT_EQUALS,
  O.LESS_THAN,
  O.LESS_OR_EQUAL,
  O.GREATER_THAN,
  O.GREATER_OR_EQUAL
];
const TEXT = [
  O.EQUALS,
  O.NOT_EQUALS,
  O.CONTAINS,
  O.NOT_CONTAINS,
  O.STARTS_WITH,
  O.IN,
  O.NOT_IN,
  ...NULL_TESTS
];
const PICKLIST = [O.EQUALS, O.NOT_EQUALS, O.IN, O.NOT_IN, ...NULL_TESTS];
const MULTI_PICKLIST = [O.EQUALS, O.NOT_EQUALS, ...NULL_TESTS];
const NUMBER = [...COMPARISONS, ...NULL_TESTS];
const RELATIVE_DATES = [O.THIS_YEAR, O.LAST_YEAR, O.LAST_N_DAYS];
const DATE = [...NUMBER, ...RELATIVE_DATES];
const ID = [O.EQUALS, O.NOT_EQUALS, O.IN, O.NOT_IN, ...NULL_TESTS];

/** Operators each describe type is offered (canonical model R-R2, operators by field type). */
const OPERATORS_BY_TYPE = {
  string: TEXT,
  textarea: TEXT,
  email: TEXT,
  phone: TEXT,
  url: TEXT,
  combobox: TEXT,
  picklist: PICKLIST,
  multipicklist: MULTI_PICKLIST,
  double: NUMBER,
  currency: NUMBER,
  percent: NUMBER,
  integer: NUMBER,
  long: NUMBER,
  date: DATE,
  datetime: DATE,
  boolean: [O.EQUALS],
  id: ID,
  reference: ID
};

/** What the value input of a condition looks like. */
export const VALUE_KINDS = Object.freeze({
  NONE: 'none',
  DAYS: 'days',
  PICK_LIST: 'pickList',
  LINES: 'lines',
  PICK: 'pick',
  BOOLEAN: 'boolean',
  NUMBER: 'number',
  DATE: 'date',
  DATETIME: 'datetime',
  TEXT: 'text'
});

const NUMBER_TYPES = new Set(['double', 'currency', 'percent', 'integer', 'long']);
const PICKLIST_TYPES = new Set(['picklist', 'multipicklist']);

/** True when the builder can offer a field as the end of a condition. */
export function isFilterableField(field) {
  return !!field && field.filterable === true && !!OPERATORS_BY_TYPE[field.dataType];
}

/** The operators a field is offered, optionally without the relative date ones. */
export function operatorsFor(field, allowRelativeDates = true) {
  const operators = (field && OPERATORS_BY_TYPE[field.dataType]) || [];
  return allowRelativeDates
    ? operators
    : operators.filter((operator) => !RELATIVE_DATES.includes(operator));
}

/** The kind of value input a field and operator need. */
export function valueKindFor(field, operator) {
  if (!field || !operator) {
    return VALUE_KINDS.NONE;
  }
  if ([O.IS_NULL, O.IS_NOT_NULL, O.THIS_YEAR, O.LAST_YEAR].includes(operator)) {
    return VALUE_KINDS.NONE;
  }
  if (operator === O.LAST_N_DAYS) {
    return VALUE_KINDS.DAYS;
  }
  const type = field.dataType;
  if (operator === O.IN || operator === O.NOT_IN) {
    return PICKLIST_TYPES.has(type) ? VALUE_KINDS.PICK_LIST : VALUE_KINDS.LINES;
  }
  if (PICKLIST_TYPES.has(type)) {
    return VALUE_KINDS.PICK;
  }
  if (type === 'boolean') {
    return VALUE_KINDS.BOOLEAN;
  }
  if (NUMBER_TYPES.has(type)) {
    return VALUE_KINDS.NUMBER;
  }
  if (type === 'date') {
    return VALUE_KINDS.DATE;
  }
  if (type === 'datetime') {
    return VALUE_KINDS.DATETIME;
  }
  return VALUE_KINDS.TEXT;
}

/**
 * The value as the input holds it, from the value the document holds: a list stays a list for
 * a picklist and becomes one value per line otherwise; everything else becomes text.
 */
export function toInputValue(kind, documentValue) {
  if (documentValue === undefined || documentValue === null) {
    return kind === VALUE_KINDS.PICK_LIST ? [] : '';
  }
  const list = Array.isArray(documentValue) ? documentValue : [documentValue];
  if (kind === VALUE_KINDS.PICK_LIST) {
    return list.map(String);
  }
  if (kind === VALUE_KINDS.LINES) {
    return list.map(String).join('\n');
  }
  return String(documentValue);
}

/** The value as the document holds it, typed as R-R2 says. Undefined means "no value". */
export function toDocumentValue(kind, inputValue) {
  switch (kind) {
    case VALUE_KINDS.NONE:
      return undefined;
    case VALUE_KINDS.DAYS:
      return Number.parseInt(inputValue, 10);
    case VALUE_KINDS.NUMBER:
      return Number(inputValue);
    case VALUE_KINDS.BOOLEAN:
      return inputValue === 'true';
    case VALUE_KINDS.PICK_LIST:
      return Array.isArray(inputValue) ? [...inputValue] : [];
    case VALUE_KINDS.LINES:
      return String(inputValue || '')
        .split('\n')
        .map((line) => line.trim())
        .filter((line) => line.length > 0);
    default:
      return inputValue;
  }
}

/** Why a value cannot be saved, as a key the component turns into a label; null when it can. */
export function valueProblem(kind, inputValue) {
  if (kind === VALUE_KINDS.NONE) {
    return null;
  }
  if (kind === VALUE_KINDS.PICK_LIST || kind === VALUE_KINDS.LINES) {
    return toDocumentValue(kind, inputValue).length === 0 ? 'valueRequired' : null;
  }
  if (inputValue === undefined || inputValue === null || String(inputValue).trim() === '') {
    return 'valueRequired';
  }
  if (kind === VALUE_KINDS.NUMBER && !Number.isFinite(Number(inputValue))) {
    return 'number';
  }
  if (kind === VALUE_KINDS.DAYS) {
    const text = String(inputValue).trim();
    const days = Number(text);
    if (!/^\d+$/.test(text) || days < 1 || days > MAX_DAYS) {
      return 'days';
    }
  }
  return null;
}

/**
 * Checks a condition logic string the way the server does, and a little more: only condition
 * numbers, AND, OR, NOT and brackets, in an order that reads, every bracket closed, every
 * number an existing condition, and every condition used.
 * Returns null, or { problem: 'syntax' | 'unknown' | 'missing', condition }.
 */
export function logicProblem(logic, conditionCount) {
  const tokens = String(logic || '')
    .replace(/\(/g, ' ( ')
    .replace(/\)/g, ' ) ')
    .trim()
    .split(/\s+/)
    .filter((token) => token.length > 0);
  if (tokens.length === 0) {
    return { problem: 'syntax' };
  }
  const used = new Set();
  let depth = 0;
  let expectOperand = true;
  for (const token of tokens) {
    const upper = token.toUpperCase();
    if (expectOperand) {
      if (upper === '(') {
        depth++;
      } else if (upper === 'NOT') {
        // NOT is followed by another operand.
      } else if (/^\d+$/.test(upper)) {
        const number = Number(upper);
        if (number < 1 || number > conditionCount) {
          return { problem: 'unknown', condition: upper };
        }
        used.add(number);
        expectOperand = false;
      } else {
        return { problem: 'syntax' };
      }
    } else if (upper === ')') {
      depth--;
      if (depth < 0) {
        return { problem: 'syntax' };
      }
    } else if (upper === 'AND' || upper === 'OR') {
      expectOperand = true;
    } else {
      return { problem: 'syntax' };
    }
  }
  if (expectOperand || depth !== 0) {
    return { problem: 'syntax' };
  }
  for (let number = 1; number <= conditionCount; number++) {
    if (!used.has(number)) {
      return { problem: 'missing', condition: String(number) };
    }
  }
  return null;
}

/**
 * Reads a filter document. Returns { logic, conditions } or throws when the text is not a
 * version 1 document; an empty or blank document reads as no conditions.
 */
export function parseDocument(text) {
  if (text === undefined || text === null || String(text).trim() === '') {
    return { logic: '', conditions: [] };
  }
  const parsed = typeof text === 'string' ? JSON.parse(text) : text;
  const version = parsed.version === undefined ? DOCUMENT_VERSION : Number(parsed.version);
  if (version !== DOCUMENT_VERSION || (parsed.conditions && !Array.isArray(parsed.conditions))) {
    throw new Error('Unsupported filter document');
  }
  // The builder numbers conditions in the order they appear. A document whose ids are not
  // already 1, 2, 3 has its logic renumbered to match, so the logic keeps its meaning.
  const positionById = new Map();
  (parsed.conditions || []).forEach((condition, index) => {
    const id = condition.id === undefined || condition.id === null ? index + 1 : condition.id;
    positionById.set(String(id), String(index + 1));
  });
  const logic = parsed.logic
    ? String(parsed.logic).replace(/\d+/g, (id) => positionById.get(id) || id)
    : '';
  return {
    logic,
    conditions: (parsed.conditions || []).map((condition) => ({
      field: condition.field ? String(condition.field) : '',
      operator: condition.operator ? String(condition.operator).toLowerCase().trim() : '',
      value: condition.value
    }))
  };
}

/** Writes a filter document; no conditions writes an empty string, which means every record. */
export function serializeDocument(conditions, logic) {
  if (!conditions || conditions.length === 0) {
    return '';
  }
  const document = { version: DOCUMENT_VERSION };
  if (logic && String(logic).trim() !== '') {
    document.logic = String(logic).trim();
  }
  document.conditions = conditions.map((condition, index) => {
    const written = { id: index + 1, field: condition.field, operator: condition.operator };
    if (condition.value !== undefined) {
      written.value = condition.value;
    }
    return written;
  });
  return JSON.stringify(document);
}
