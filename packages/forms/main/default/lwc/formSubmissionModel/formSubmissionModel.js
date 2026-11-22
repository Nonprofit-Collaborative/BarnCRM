/**
 * The Submission panel's shaping, with no framework in it (C-42a, canonical model 29ZY, plan
 * Section 9.9): one submission's answers by question, as the version it answered asked them, and
 * the records it wrote, from the submission's stored fields (ADR-0093: the panel reads them as
 * the person through GraphQL).
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module. A
 * submission is { id, formName, formVersionId, status, message, answersJson, outcomeJson,
 * definitionJson }; the view is { id, formName, status, message, canProcess, answers, records },
 * an answer { key, label, type, value } and a record { key, kind, objectName, recordId, action }.
 */

/** The status of a submission that has nothing left to process. */
export const PROCESSED = 'Processed';

/** A JSON value as text, as the server writes it: null stays null. */
function textOf(value) {
  if (value === null || value === undefined) {
    return null;
  }
  return typeof value === 'object' ? JSON.stringify(value) : String(value);
}

/** JSON text parsed, or undefined when it is blank or not JSON. */
function parsed(text) {
  if (text === null || text === undefined || String(text).trim() === '') {
    return undefined;
  }
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

const isObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

/** A list of JSON objects, skipping anything else in it. */
const objectsIn = (value) => (Array.isArray(value) ? value.filter(isObject) : []);

/** Every question of a definition, in the order its steps ask them. */
function questionsOf(definition) {
  const questions = [];
  objectsIn(isObject(definition) ? definition.steps : null).forEach((step) => {
    questions.push(...objectsIn(step.fields));
  });
  return questions;
}

/** An answer as text: a picklist option's label when it matches one. */
function shownAnswer(question, value) {
  const text = textOf(value);
  const option = objectsIn(question.options).find((candidate) => textOf(candidate.value) === text);
  return option ? textOf(option.label) : text;
}

/**
 * The answers in the order the version asks them; answers to questions the version no longer
 * has are kept last, under their key.
 */
export function answerRows(answersJson, definitionJson) {
  const answers = parsed(answersJson);
  if (!isObject(answers)) {
    return [];
  }
  const rows = [];
  const shown = new Set();
  questionsOf(parsed(definitionJson)).forEach((question) => {
    const key = textOf(question.key);
    if (!Object.prototype.hasOwnProperty.call(answers, key)) {
      return;
    }
    rows.push({
      key,
      label: textOf(question.label),
      type: textOf(question.type),
      value: shownAnswer(question, answers[key])
    });
    shown.add(key);
  });
  Object.keys(answers)
    .filter((key) => !shown.has(key))
    .forEach((key) => rows.push({ key, label: key, type: 'text', value: textOf(answers[key]) }));
  return rows;
}

/** The records a processed submission wrote or found, from its stored outcome. */
export function writtenRecords(outcomeJson) {
  return objectsIn(parsed(outcomeJson)).map((record) => ({
    key: textOf(record.key),
    kind: textOf(record.kind),
    objectName: textOf(record.objectName),
    recordId: textOf(record.recordId),
    action: textOf(record.action)
  }));
}

/**
 * What the panel draws for a submission, or null when there is none. Process Again is offered
 * when it is not yet processed, it names the version it answered, and the person may edit it.
 */
export function submissionView(submission, canEdit) {
  if (!submission) {
    return null;
  }
  return {
    id: submission.id,
    // A deleted form leaves the name stored with the submission (R-FS8).
    formName: submission.formName || null,
    status: submission.status || null,
    message: submission.message || null,
    canProcess: Boolean(
      submission.status !== PROCESSED && submission.formVersionId && canEdit === true
    ),
    answers: answerRows(submission.answersJson, submission.definitionJson),
    records: writtenRecords(submission.outcomeJson)
  };
}
