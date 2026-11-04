/**
 * Eligibility screening rules, framework free (plan Section 9.9, P-14): reads and writes the rules
 * JSON stored on a program, and evaluates it against an enrollment's intake values for the
 * preview. No Lightning or Salesforce import. Apex (`EligibilityRules`) evaluates the same rules
 * when saving; both carry the same test cases and must give the same answers.
 *
 * Format (version 1): { version, defaultResult, defaultReason, rules: [ { id, all: [ { field,
 * operator, value } ], result, reason, basis } ] }. Rules are checked in order; the first whose
 * conditions all hold decides; when none does the default result decides.
 */

export const ELIGIBLE = 'Eligible';
export const NOT_ELIGIBLE = 'Not Eligible';
export const REVIEW = 'Review';
export const RESULTS = [ELIGIBLE, NOT_ELIGIBLE, REVIEW];
export const OPERATORS = [
  'equals',
  'notEquals',
  'in',
  'notIn',
  'greaterThan',
  'greaterOrEqual',
  'lessThan',
  'lessOrEqual',
  'isBlank',
  'isNotBlank'
];

const LIST_OPERATORS = ['in', 'notIn'];
const NO_VALUE_OPERATORS = ['isBlank', 'isNotBlank'];
const NUMBER = /^-?\d+(\.\d+)?$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

export function needsValue(operator) {
  return !NO_VALUE_OPERATORS.includes(operator);
}

export function isListOperator(operator) {
  return LIST_OPERATORS.includes(operator);
}

/** Rules with nothing in them. */
export function emptyConfig() {
  return { version: 1, defaultResult: REVIEW, defaultReason: '', rules: [] };
}

/** The next unused rule id: r1, r2, and so on. */
export function nextRuleId(config) {
  const used = new Set(config.rules.map((rule) => rule.id));
  let number = config.rules.length + 1;
  while (used.has(`r${number}`)) {
    number += 1;
  }
  return `r${number}`;
}

export function newCondition(field) {
  return { field: field || '', operator: 'equals', value: '' };
}

export function newRule(config, field) {
  return {
    id: nextRuleId(config),
    all: [newCondition(field)],
    result: NOT_ELIGIBLE,
    reason: '',
    basis: ''
  };
}

/**
 * The rules JSON as an editable configuration. Blank or unreadable text gives an empty one, so
 * the panel always has something to show; list values become comma separated text for editing.
 */
export function parseRules(json) {
  if (!json || !String(json).trim()) {
    return emptyConfig();
  }
  let root;
  try {
    root = JSON.parse(json);
  } catch {
    return emptyConfig();
  }
  const config = emptyConfig();
  if (RESULTS.includes(root.defaultResult)) {
    config.defaultResult = root.defaultResult;
  }
  config.defaultReason = root.defaultReason || '';
  config.rules = (Array.isArray(root.rules) ? root.rules : []).map((rule, index) => ({
    id: rule.id || `r${index + 1}`,
    all: (Array.isArray(rule.all) ? rule.all : []).map((condition) => ({
      field: condition.field || '',
      operator: condition.operator || 'equals',
      value: Array.isArray(condition.value)
        ? condition.value.join(', ')
        : condition.value === undefined || condition.value === null
          ? ''
          : String(condition.value)
    })),
    result: rule.result || NOT_ELIGIBLE,
    reason: rule.reason || '',
    basis: rule.basis || ''
  }));
  return config;
}

/** The configuration as the JSON to store, or an empty string when it has no rules. */
export function serializeRules(config) {
  if (!config || !config.rules || config.rules.length === 0) {
    return '';
  }
  const rules = config.rules.map((rule) => {
    const out = {
      id: rule.id,
      all: rule.all.map((condition) => {
        const item = { field: condition.field, operator: condition.operator };
        if (isListOperator(condition.operator)) {
          item.value = String(condition.value || '')
            .split(',')
            .map((part) => part.trim())
            .filter((part) => part !== '');
        } else if (needsValue(condition.operator)) {
          item.value = String(condition.value === undefined ? '' : condition.value).trim();
        }
        return item;
      }),
      result: rule.result,
      reason: String(rule.reason || '').trim()
    };
    if (rule.basis) {
      out.basis = rule.basis;
    }
    return out;
  });
  const root = { version: 1, defaultResult: config.defaultResult || REVIEW, rules };
  if (config.defaultReason && config.defaultReason.trim()) {
    root.defaultReason = config.defaultReason.trim();
  }
  return JSON.stringify(root, null, 2);
}

/** A value as trimmed text; empty for null. */
function normalized(value) {
  return value === undefined || value === null ? '' : String(value).trim();
}

/** Numbers compare as numbers, anything else as text without regard to case. */
function same(a, b) {
  if (NUMBER.test(a) && NUMBER.test(b)) {
    return Number(a) === Number(b);
  }
  return a.toLowerCase() === b.toLowerCase();
}

/** Orders two numbers or two dates; null for anything else, which never satisfies an order. */
function compare(a, b) {
  if (NUMBER.test(a) && NUMBER.test(b)) {
    return Math.sign(Number(a) - Number(b));
  }
  if (DATE.test(a) && DATE.test(b)) {
    return a === b ? 0 : a > b ? 1 : -1;
  }
  return null;
}

function holds(condition, values) {
  const actual = normalized(values[String(condition.field).toLowerCase()]);
  const operator = condition.operator;
  // An operator the rules cannot hold (the server refuses it on save) never matches.
  if (!OPERATORS.includes(operator)) {
    return false;
  }
  if (operator === 'isBlank') {
    return actual === '';
  }
  if (operator === 'isNotBlank') {
    return actual !== '';
  }
  if (isListOperator(operator)) {
    const options = Array.isArray(condition.value)
      ? condition.value
      : String(condition.value || '').split(',');
    const found = options.some((option) => same(actual, normalized(option)));
    return operator === 'in' ? found : !found;
  }
  const target = normalized(condition.value);
  if (operator === 'equals') {
    return same(actual, target);
  }
  if (operator === 'notEquals') {
    return !same(actual, target);
  }
  const order = compare(actual, target);
  if (order === null) {
    return false;
  }
  switch (operator) {
    case 'greaterThan':
      return order > 0;
    case 'greaterOrEqual':
      return order >= 0;
    case 'lessThan':
      return order < 0;
    default:
      return order <= 0;
  }
}

/**
 * What screening decides for these values: { status, reason, basis, ruleId }, or null when the
 * rules have no rule at all. `values` maps a field's API name to its plain value; names are
 * matched without regard to case. `noRuleMatchedReason` is the reason when the default decides
 * and the rules give none.
 */
export function evaluateRules(config, values, noRuleMatchedReason) {
  if (!config || !config.rules || config.rules.length === 0) {
    return null;
  }
  const byName = {};
  Object.keys(values || {}).forEach((key) => {
    byName[key.toLowerCase()] = values[key];
  });
  for (const rule of config.rules) {
    if (rule.all.every((condition) => holds(condition, byName))) {
      return {
        status: rule.result,
        reason: rule.reason || '',
        basis: rule.basis || '',
        ruleId: rule.id || ''
      };
    }
  }
  return {
    status: RESULTS.includes(config.defaultResult) ? config.defaultResult : REVIEW,
    reason: config.defaultReason || noRuleMatchedReason || '',
    basis: '',
    ruleId: ''
  };
}

/** Replaces {0}, {1} and so on in a label with the values given. */
export function format(template, ...values) {
  return values.reduce(
    (text, value, index) => text.split(`{${index}}`).join(String(value)),
    template || ''
  );
}

/** Moves a rule one place up (-1) or down (1); returns a new list. */
export function moveRule(rules, index, step) {
  const target = index + step;
  if (target < 0 || target >= rules.length) {
    return rules;
  }
  const copy = rules.slice();
  [copy[index], copy[target]] = [copy[target], copy[index]];
  return copy;
}
