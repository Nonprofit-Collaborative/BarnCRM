/**
 * The form's rules while it is filled in: conditions, which steps and questions show, answer
 * checks, and the answers that count (canonical model R-FM1, R-FS1; ADR-0175
 * `0175-forms-module.md`, decisions 4 and 5). Framework-free (plan 9.9). `FormRules` in Apex
 * applies the same rules on the server, which decides; the vectors in
 * `__tests__/data/formVectors.json` are the cases both are held to.
 *
 * Answers are a plain object by field key. A problem with an answer is `{ code, args }`.
 */

import { allFields } from 'c/formDefinition';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE = /^[+()0-9\s.\-x]+$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const MIN_PHONE_DIGITS = 7;

/** The longest text answer when the form sets none: a text field, then a long text field. */
export const DEFAULT_MAX_LENGTH = Object.freeze({ text: 255, textarea: 32768 });

/** Whether an answer counts as not given: missing, null, or only spaces. False is an answer. */
export function isBlank(value) {
  return value === undefined || value === null || String(value).trim() === '';
}

function comparable(value) {
  if (value === true || value === false) {
    return String(value);
  }
  return isBlank(value) ? '' : String(value).trim().toLowerCase();
}

function asNumber(value) {
  if (isBlank(value) || typeof value === 'boolean') {
    return null;
  }
  const number = Number(String(value).trim());
  return Number.isFinite(number) ? number : null;
}

/** Orders two answers: as numbers when both are, as dates when both are, else not at all. */
function compare(left, right) {
  const a = asNumber(left);
  const b = asNumber(right);
  if (a !== null && b !== null) {
    return a === b ? 0 : a < b ? -1 : 1;
  }
  const x = isBlank(left) ? '' : String(left).trim();
  const y = isBlank(right) ? '' : String(right).trim();
  if (DATE.test(x) && DATE.test(y)) {
    return x === y ? 0 : x < y ? -1 : 1;
  }
  return null;
}

/**
 * Whether a condition holds for these answers. No condition always holds. Text compares
 * without regard to case or surrounding spaces; greater and less than compare numbers or dates
 * and are false for anything else.
 */
export function evaluate(condition, answers) {
  if (!condition) {
    return true;
  }
  if (Array.isArray(condition.all)) {
    return condition.all.every((part) => evaluate(part, answers));
  }
  if (Array.isArray(condition.any)) {
    return condition.any.some((part) => evaluate(part, answers));
  }
  const value = (answers || {})[condition.field];
  switch (condition.op) {
    case 'isBlank':
      return isBlank(value);
    case 'isNotBlank':
      return !isBlank(value);
    case 'equals':
      return comparable(value) === comparable(condition.value);
    case 'notEquals':
      return comparable(value) !== comparable(condition.value);
    case 'contains':
      return comparable(value).includes(comparable(condition.value));
    case 'greaterThan':
      return compare(value, condition.value) === 1;
    case 'lessThan':
      return compare(value, condition.value) === -1;
    default:
      return false;
  }
}

/**
 * Which questions show, by key. A question shows when its step shows and its own condition
 * holds; a question whose condition names a hidden question reads that answer as not given,
 * so hiding one question hides those that depend on it.
 */
export function visibility(definition, answers) {
  const shown = {};
  const counted = {};
  ((definition && definition.steps) || []).forEach((step) => {
    const stepShows = evaluate(step.showWhen, counted);
    (step.fields || []).forEach((field) => {
      const fieldShows = stepShows && evaluate(field.showWhen, counted);
      shown[field.key] = fieldShows;
      if (fieldShows) {
        counted[field.key] = (answers || {})[field.key];
      }
    });
  });
  return shown;
}

/** The indexes of the steps that show: a step with no question showing is skipped. */
export function visibleSteps(definition, answers) {
  const shown = visibility(definition, answers);
  const indexes = [];
  ((definition && definition.steps) || []).forEach((step, index) => {
    if ((step.fields || []).some((field) => shown[field.key])) {
      indexes.push(index);
    }
  });
  return indexes;
}

/** The step after this one that shows, or -1 when this is the last. */
export function nextStep(definition, current, answers) {
  return visibleSteps(definition, answers).find((index) => index > current) ?? -1;
}

/** The step before this one that shows, or -1 when this is the first. */
export function previousStep(definition, current, answers) {
  const before = visibleSteps(definition, answers).filter((index) => index < current);
  return before.length ? before[before.length - 1] : -1;
}

function problem(code, ...args) {
  return { code, args };
}

/** What is wrong with one answer to one question, or null when nothing is. */
export function checkAnswer(field, value) {
  if (field.type === 'checkbox') {
    return field.required && value !== true && value !== 'true' ? problem('mustTick') : null;
  }
  if (isBlank(value)) {
    return field.required ? problem('required') : null;
  }
  const text = String(value).trim();
  switch (field.type) {
    case 'email':
      return EMAIL.test(text) ? null : problem('badEmail');
    case 'phone':
      return PHONE.test(text) && text.replace(/\D/g, '').length >= MIN_PHONE_DIGITS
        ? null
        : problem('badPhone');
    case 'number': {
      const number = asNumber(text);
      if (number === null) {
        return problem('badNumber');
      }
      if (asNumber(field.min) !== null && number < asNumber(field.min)) {
        return problem('belowMin', field.min);
      }
      if (asNumber(field.max) !== null && number > asNumber(field.max)) {
        return problem('aboveMax', field.max);
      }
      return null;
    }
    case 'date':
      return DATE.test(text) && !Number.isNaN(Date.parse(text + 'T00:00:00Z'))
        ? null
        : problem('badDate');
    case 'picklist':
      return (field.options || []).some((option) => String(option.value) === text)
        ? null
        : problem('notAnOption');
    default: {
      const limit = asNumber(field.maxLength) || DEFAULT_MAX_LENGTH[field.type] || 255;
      return text.length > limit ? problem('tooLong', limit) : null;
    }
  }
}

/** The problems with one step's showing questions, by field key. Empty when it can go on. */
export function checkStep(definition, stepIndex, answers) {
  const step = ((definition && definition.steps) || [])[stepIndex];
  const shown = visibility(definition, answers);
  const problems = {};
  ((step && step.fields) || []).forEach((field) => {
    if (shown[field.key]) {
      const found = checkAnswer(field, (answers || {})[field.key]);
      if (found) {
        problems[field.key] = found;
      }
    }
  });
  return problems;
}

/** The problems with every showing question, by field key. */
export function checkAll(definition, answers) {
  const problems = {};
  ((definition && definition.steps) || []).forEach((step, index) => {
    Object.assign(problems, checkStep(definition, index, answers));
  });
  return problems;
}

/**
 * The answers that count, as they are sent and stored: showing questions only, keys the form
 * has only, text trimmed, numbers as numbers, a checkbox always true or false, blanks left out.
 */
export function countedAnswers(definition, answers) {
  const shown = visibility(definition, answers);
  const counted = {};
  allFields(definition).forEach((field) => {
    if (!shown[field.key]) {
      return;
    }
    const value = (answers || {})[field.key];
    if (field.type === 'checkbox') {
      counted[field.key] = value === true || value === 'true';
    } else if (!isBlank(value)) {
      const text = String(value).trim();
      counted[field.key] =
        field.type === 'number' && asNumber(text) !== null ? asNumber(text) : text;
    }
  });
  return counted;
}

const INPUT_TYPES = Object.freeze({
  text: 'text',
  email: 'email',
  phone: 'tel',
  number: 'number',
  date: 'date'
});

/**
 * The questions of one step as a page draws them: the shown fields with their answer, input
 * type, options and problem (`{ code, args }` or null). The staff runner and the public page
 * (C-42b) both draw from this, so they show the same questions the same way.
 */
export function questionViews(definition, stepIndex, answers, problems) {
  const shown = visibility(definition, answers);
  const step = definition.steps[stepIndex];
  const given = answers || {};
  return step.fields
    .filter((field) => shown[field.key])
    .map((field) => ({
      key: field.key,
      label: field.label,
      help: field.help,
      required: field.required,
      value: given[field.key] === undefined ? '' : given[field.key],
      checked: given[field.key] === true,
      isCheckbox: field.type === 'checkbox',
      isLong: field.type === 'textarea',
      isPicklist: field.type === 'picklist',
      isInput: Boolean(INPUT_TYPES[field.type]),
      inputType: INPUT_TYPES[field.type],
      options: (field.options || []).map((option) => ({
        value: String(option.value),
        label: option.label || String(option.value)
      })),
      problem: (problems || {})[field.key] || null
    }));
}
