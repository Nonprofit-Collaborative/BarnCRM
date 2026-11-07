/**
 * What the Form Builder does to a definition (C-42a; ADR-NEXT `NEXT-forms-module.md`, decision
 * 12): add, change, move and remove steps, questions and records, and set a condition.
 * Framework-free (plan 9.9): every function takes a definition and returns a changed copy, so a
 * WordPress block can build forms with the same code.
 */
import { KIND_OBJECTS, MATCH_RULES, ON_MATCH, withDefaults } from 'c/formDefinition';

function copy(definition) {
  return withDefaults(definition);
}

/** A key not yet used: the base followed by the first free number. */
export function uniqueKey(taken, base) {
  const used = new Set(taken);
  let number = 1;
  while (used.has(base + number)) {
    number += 1;
  }
  return base + number;
}

function fieldKeys(definition) {
  return definition.steps.flatMap((step) => step.fields.map((field) => field.key));
}

function moved(list, index, delta) {
  const to = index + delta;
  if (index < 0 || index >= list.length || to < 0 || to >= list.length) {
    return list;
  }
  const result = list.slice();
  const [item] = result.splice(index, 1);
  result.splice(to, 0, item);
  return result;
}

/** Changes that are undefined are dropped; null removes the property. */
function merged(item, changes) {
  const result = { ...item };
  Object.keys(changes || {}).forEach((name) => {
    if (changes[name] === null) {
      delete result[name];
    } else if (changes[name] !== undefined) {
      result[name] = changes[name];
    }
  });
  return result;
}

export function addStep(definition) {
  const next = copy(definition);
  const key = uniqueKey(
    next.steps.map((step) => step.key),
    'step'
  );
  next.steps.push({ key, title: '', fields: [] });
  return next;
}

export function updateStep(definition, stepIndex, changes) {
  const next = copy(definition);
  next.steps[stepIndex] = merged(next.steps[stepIndex], changes);
  return next;
}

export function moveStep(definition, stepIndex, delta) {
  const next = copy(definition);
  next.steps = moved(next.steps, stepIndex, delta);
  return next;
}

/** Removes a step and its questions, with any condition or target that named them. */
export function removeStep(definition, stepIndex) {
  const next = copy(definition);
  const gone = new Set(next.steps[stepIndex].fields.map((field) => field.key));
  next.steps.splice(stepIndex, 1);
  return withoutConditionsOn(next, gone);
}

export function addField(definition, stepIndex, type = 'text') {
  const next = copy(definition);
  const key = uniqueKey(fieldKeys(next), 'question');
  next.steps[stepIndex].fields.push({ key, label: '', type, required: false });
  return next;
}

/**
 * Changes a question. A changed key is followed everywhere the old one was named, so a
 * condition on the question keeps working. Options are kept only for a picklist.
 */
export function updateField(definition, stepIndex, fieldIndex, changes) {
  let next = copy(definition);
  const before = next.steps[stepIndex].fields[fieldIndex];
  const after = merged(before, changes);
  if (after.type !== 'picklist') {
    delete after.options;
  }
  next.steps[stepIndex].fields[fieldIndex] = after;
  if (changes && changes.key && changes.key !== before.key) {
    next = renameInConditions(next, before.key, changes.key);
  }
  return next;
}

export function moveField(definition, stepIndex, fieldIndex, delta) {
  const next = copy(definition);
  next.steps[stepIndex].fields = moved(next.steps[stepIndex].fields, fieldIndex, delta);
  return next;
}

export function removeField(definition, stepIndex, fieldIndex) {
  const next = copy(definition);
  const [gone] = next.steps[stepIndex].fields.splice(fieldIndex, 1);
  return withoutConditionsOn(next, new Set([gone.key]));
}

/** Adds a record to write: a person, an organization or a related record of its own object. */
export function addRecord(definition, kind) {
  const next = copy(definition);
  const key = uniqueKey(
    next.records.map((record) => record.key),
    kind
  );
  const record = { key, kind };
  if (MATCH_RULES[kind]) {
    record.matching = { rule: MATCH_RULES[kind][0], onMatch: ON_MATCH[0] };
  } else {
    record.object = '';
    record.links = {};
  }
  next.records.push(record);
  return next;
}

export function updateRecord(definition, recordIndex, changes) {
  const next = copy(definition);
  next.records[recordIndex] = merged(next.records[recordIndex], changes);
  return next;
}

/** Removes a record, every answer written to it and every link naming it. */
export function removeRecord(definition, recordIndex) {
  const next = copy(definition);
  const [gone] = next.records.splice(recordIndex, 1);
  next.steps.forEach((step) => {
    step.fields.forEach((field) => {
      if (field.target && field.target.record === gone.key) {
        delete field.target;
      }
    });
  });
  next.records.forEach((record) => {
    Object.keys(record.links || {}).forEach((field) => {
      if (record.links[field] === gone.key) {
        delete record.links[field];
      }
    });
  });
  return next;
}

/** Sets or clears a link: a field of a related record pointing at another record. */
export function setLink(definition, recordIndex, field, recordKey) {
  const next = copy(definition);
  const record = next.records[recordIndex];
  record.links = { ...(record.links || {}) };
  if (recordKey) {
    record.links[field] = recordKey;
  } else {
    delete record.links[field];
  }
  return next;
}

/** The object a record is stored on, as the builder offers its fields. */
export function recordObject(record) {
  return (record && (KIND_OBJECTS[record.kind] || record.object)) || '';
}

/**
 * A condition as the builder edits it: whether all or any clause must hold, and flat clauses.
 * A nested group from the JSON is kept as it was and counted, not edited.
 */
export function conditionParts(condition) {
  if (!condition) {
    return { mode: 'always', clauses: [], nested: [] };
  }
  const mode = Array.isArray(condition.any) ? 'any' : 'all';
  const parts = condition[mode] || [];
  return {
    mode,
    clauses: parts.filter((part) => part && part.field),
    nested: parts.filter((part) => !part || !part.field)
  };
}

/** The condition back from its parts; mode 'always', or no clause, clears it. */
export function conditionFrom(parts) {
  const all = [...(parts.clauses || []), ...(parts.nested || [])];
  if (parts.mode === 'always' || all.length === 0) {
    return null;
  }
  return { [parts.mode === 'any' ? 'any' : 'all']: all };
}

/** Sets a step's condition, or a question's when `fieldIndex` is given; null clears it. */
export function setCondition(definition, stepIndex, fieldIndex, condition) {
  const changes = { showWhen: condition || null };
  return fieldIndex === null || fieldIndex === undefined
    ? updateStep(definition, stepIndex, changes)
    : updateField(definition, stepIndex, fieldIndex, changes);
}

/** The questions asked before this place, the only ones a condition may test (R-FM1). */
export function earlierFields(definition, stepIndex, fieldIndex) {
  const found = [];
  definition.steps.forEach((step, s) => {
    step.fields.forEach((field, f) => {
      const before =
        fieldIndex === null || fieldIndex === undefined
          ? s < stepIndex
          : s < stepIndex || (s === stepIndex && f < fieldIndex);
      if (before) {
        found.push(field);
      }
    });
  });
  return found;
}

/** Choices typed one per line, as `{ label, value }` with the line as both. */
export function optionsFromText(text) {
  return String(text || '')
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line !== '')
    .map((line) => ({ label: line, value: line }));
}

export function optionsToText(options) {
  return (options || []).map((option) => option.label || option.value).join('\n');
}

function eachCondition(definition, change) {
  definition.steps.forEach((step) => {
    step.showWhen = change(step.showWhen);
    if (!step.showWhen) {
      delete step.showWhen;
    }
    step.fields.forEach((field) => {
      field.showWhen = change(field.showWhen);
      if (!field.showWhen) {
        delete field.showWhen;
      }
    });
  });
  return definition;
}

function mapClauses(condition, change) {
  if (!condition) {
    return condition;
  }
  if (condition.field) {
    return change(condition);
  }
  const mode = Array.isArray(condition.any) ? 'any' : 'all';
  const parts = (condition[mode] || [])
    .map((part) => mapClauses(part, change))
    .filter((part) => part);
  return parts.length ? { [mode]: parts } : null;
}

function renameInConditions(definition, from, to) {
  return eachCondition(definition, (condition) =>
    mapClauses(condition, (clause) => (clause.field === from ? { ...clause, field: to } : clause))
  );
}

function withoutConditionsOn(definition, keys) {
  return eachCondition(definition, (condition) =>
    mapClauses(condition, (clause) => (keys.has(clause.field) ? null : clause))
  );
}
