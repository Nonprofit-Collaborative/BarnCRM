/**
 * Post-event survey rules for Event Management (EV-18), framework free so they port to BarnCRM
 * for WordPress (plan 9.9). No Salesforce imports.
 *
 * A question is `{ key, label, kind }` as the form catalog reports it. A response is
 * `{ id, name, submittedOn, answers }` where `answers` is JSON text keyed by question key.
 */

const MAX_TEXTS = 20;
const NUMBER_KINDS = new Set(['number']);
const CHOICE_KINDS = new Set(['picklist', 'checkbox', 'radio']);

/** The answers of one response as an object; text that is not JSON gives no answers. */
export function parseAnswers(text) {
  if (!text) {
    return {};
  }
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function isAnswered(value) {
  return value !== null && value !== undefined && String(value).trim() !== '';
}

function answerWord(value) {
  if (value === true) {
    return 'Yes';
  }
  if (value === false) {
    return 'No';
  }
  return String(value).trim();
}

/** A rounded average, or null with no numbers. */
export function average(numbers) {
  if (!numbers.length) {
    return null;
  }
  const sum = numbers.reduce((total, value) => total + value, 0);
  return Math.round((sum / numbers.length) * 10) / 10;
}

function numberSummary(base, values) {
  const numbers = values.map(Number).filter((value) => Number.isFinite(value));
  return {
    ...base,
    type: 'number',
    average: average(numbers),
    lowest: numbers.length ? Math.min(...numbers) : null,
    highest: numbers.length ? Math.max(...numbers) : null
  };
}

function choiceSummary(base, values) {
  const counts = new Map();
  values.forEach((value) => {
    const word = answerWord(value);
    counts.set(word, (counts.get(word) || 0) + 1);
  });
  const options = [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([value, count]) => ({
      value,
      count,
      percent: Math.round((count / values.length) * 100)
    }));
  return { ...base, type: 'choice', options };
}

function textSummary(base, entries) {
  return {
    ...base,
    type: 'text',
    texts: entries.slice(0, MAX_TEXTS).map(({ name, value }) => ({
      who: name || '',
      text: String(value).trim()
    })),
    more: Math.max(0, entries.length - MAX_TEXTS)
  };
}

/**
 * The summary of a survey, one entry per question in the form's order: numbers get an average
 * with the lowest and highest, picklists and checkboxes get counts and percentages, everything
 * else lists the newest answers. Responses come newest first. A question nobody answered shows
 * with `answered` 0.
 */
export function summarize(questions, responses) {
  const parsed = (responses || []).map((response) => ({
    name: response.name,
    answers: parseAnswers(response.answers)
  }));
  return (questions || []).map((question) => {
    const entries = parsed
      .filter((response) => isAnswered(response.answers[question.key]))
      .map((response) => ({ name: response.name, value: response.answers[question.key] }));
    const base = {
      key: question.key,
      label: question.label || question.key,
      answered: entries.length
    };
    const values = entries.map((entry) => entry.value);
    if (NUMBER_KINDS.has(question.kind)) {
      return numberSummary(base, values);
    }
    if (CHOICE_KINDS.has(question.kind) && entries.length) {
      return choiceSummary(base, values);
    }
    return textSummary(base, entries);
  });
}

/**
 * The share of the people sent the survey who answered, as a whole percent. With no survey sent
 * (a link handed out by hand) the share is of those who attended; null when there is nothing to
 * compare with.
 */
export function responseRate(responseCount, sent, attended) {
  const base = sent > 0 ? sent : attended;
  if (!base || base <= 0) {
    return null;
  }
  return Math.min(100, Math.round((responseCount / base) * 100));
}
