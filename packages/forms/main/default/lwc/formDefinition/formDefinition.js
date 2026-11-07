/**
 * The form definition: its shape, defaults and checks (canonical model 29ZW, R-FM1; ADR-0175
 * `0175-forms-module.md`, decision 3). Framework-free (plan 9.9): no lightning or @salesforce
 * imports, so a WordPress block or Node can read and check the same JSON.
 *
 * A problem is `{ code, args }`: the code says what is wrong and the args name the parts, so the
 * page words it from its help catalog and the module stays free of display text.
 *
 * Definition, schemaVersion 1:
 * { schemaVersion: 1,
 *   steps: [{ key, title, showWhen?, fields: [{ key, label, type, required?, help?, options?,
 *     maxLength?, min?, max?, showWhen?, target?: { record, field } }] }],
 *   records: [{ key, kind: 'person' | 'organization' | 'related', object?, matching?: { rule,
 *     onMatch }, links?: { field: recordKey | 'context' }, values?: { field: constant } }],
 *   public?: { enabled, minSeconds?, hourlyLimit?, confirmation?, saveForLater?, resumeDays? } }
 * `public` (C-42b, ADR-NEXT public forms on a Salesforce Site) lets the published version be
 * filled in on a Salesforce Site or by an API caller; `saveForLater` (C-42c) lets a person save
 * their answers and finish from an emailed link that works for `resumeDays`. A `file` question
 * (C-42c) has no target: its file is kept with the submission.
 */

export const SCHEMA_VERSION = 1;

export const FIELD_TYPES = Object.freeze([
  'text',
  'textarea',
  'email',
  'phone',
  'number',
  'date',
  'checkbox',
  'picklist',
  'file'
]);

/** Tests a condition can make; the first five compare with `value`. */
export const OPERATORS = Object.freeze([
  'equals',
  'notEquals',
  'contains',
  'greaterThan',
  'lessThan',
  'isBlank',
  'isNotBlank'
]);
const NEEDS_VALUE = new Set(['equals', 'notEquals', 'contains', 'greaterThan', 'lessThan']);

export const RECORD_KINDS = Object.freeze(['person', 'organization', 'related']);

/** What each kind is stored on; a related record names its own object. */
export const KIND_OBJECTS = Object.freeze({ person: 'Contact', organization: 'Account' });

export const MATCH_RULES = Object.freeze({
  person: ['emailThenNamePostal', 'email'],
  organization: ['name']
});
export const ON_MATCH = Object.freeze(['fillBlanks', 'overwrite']);

/** The record a link may name besides another record: the one the form was filled from. */
export const CONTEXT_LINK = 'context';

export const LIMITS = Object.freeze({
  steps: 20,
  fields: 100,
  records: 10,
  options: 200,
  conditionDepth: 3,
  keyLength: 40
});

/** A public form's spam settings: their ranges and the values used when one is not set. */
export const PUBLIC_LIMITS = Object.freeze({
  minSeconds: [0, 600],
  hourlyLimit: [1, 1000],
  resumeDays: [1, 30],
  confirmation: 1000
});
export const PUBLIC_DEFAULTS = Object.freeze({ minSeconds: 3, hourlyLimit: 50, resumeDays: 7 });

const KEY = /^[A-Za-z][A-Za-z0-9_]*$/;
const FIELD_NAME = /^[A-Za-z][A-Za-z0-9_]*$/;
const CUSTOM_OBJECT = /^[A-Za-z][A-Za-z0-9_]*__c$/;

/** A definition with one empty step and a person to write, the builder's starting point. */
export function emptyDefinition() {
  return {
    schemaVersion: SCHEMA_VERSION,
    steps: [{ key: 'step1', title: '', fields: [] }],
    records: [
      {
        key: 'person',
        kind: 'person',
        matching: { rule: MATCH_RULES.person[0], onMatch: ON_MATCH[0] }
      }
    ]
  };
}

/**
 * Reads a definition from JSON text. A blank text gives the empty definition, so a new form opens
 * in the builder. Never throws: text that is not a definition gives `{ definition: null,
 * problems: [{ code: 'notJson' }] }`.
 */
export function parseDefinition(text) {
  if (text === null || text === undefined || String(text).trim() === '') {
    return { definition: emptyDefinition(), problems: [] };
  }
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return { definition: null, problems: [{ code: 'notJson', args: [] }] };
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { definition: null, problems: [{ code: 'notJson', args: [] }] };
  }
  const definition = withDefaults(parsed);
  return { definition, problems: checkDefinition(definition) };
}

/** The definition as stored: compact JSON, keys in the order the builder writes them. */
export function serializeDefinition(definition) {
  return JSON.stringify(definition);
}

/**
 * A copy with the defaults filled in: lists where they are missing, `required` false, and the
 * default matching for a person or organization. Unknown properties are kept, so a later schema
 * version read by this one loses nothing it does not understand.
 */
export function withDefaults(definition) {
  const copy = JSON.parse(JSON.stringify(definition || {}));
  if (copy.schemaVersion === undefined) {
    copy.schemaVersion = SCHEMA_VERSION;
  }
  copy.steps = Array.isArray(copy.steps) ? copy.steps : [];
  copy.steps.forEach((step) => {
    step.fields = Array.isArray(step.fields) ? step.fields : [];
    step.fields.forEach((field) => {
      field.required = field.required === true;
    });
  });
  copy.records = Array.isArray(copy.records) ? copy.records : [];
  copy.records.forEach((record) => {
    if (MATCH_RULES[record.kind]) {
      const matching = record.matching || {};
      record.matching = {
        rule: matching.rule || MATCH_RULES[record.kind][0],
        onMatch: matching.onMatch || ON_MATCH[0]
      };
    }
  });
  return copy;
}

/** Every field in order, each with the index of its step. */
export function allFields(definition) {
  const fields = [];
  ((definition && definition.steps) || []).forEach((step, stepIndex) => {
    (step.fields || []).forEach((field) => fields.push({ ...field, stepIndex }));
  });
  return fields;
}

/** The object a record entry writes to. */
export function objectOf(record) {
  if (!record) {
    return null;
  }
  return KIND_OBJECTS[record.kind] || record.object || null;
}

function problem(code, ...args) {
  return { code, args };
}

/** The field keys a condition names, at any depth. */
export function conditionFields(condition) {
  if (!condition || typeof condition !== 'object') {
    return [];
  }
  const group = condition.all || condition.any;
  if (Array.isArray(group)) {
    return group.flatMap((part) => conditionFields(part));
  }
  return condition.field ? [condition.field] : [];
}

/**
 * Problems with one condition. `earlier` is the set of field keys it may name (those before its
 * owner), `owner` names the field or step it belongs to, for the message.
 */
function checkCondition(condition, earlier, owner, depth = 1) {
  if (!condition || typeof condition !== 'object' || Array.isArray(condition)) {
    return [problem('badCondition', owner)];
  }
  const group = condition.all || condition.any;
  if (condition.all !== undefined || condition.any !== undefined) {
    if (!Array.isArray(group) || group.length === 0) {
      return [problem('badCondition', owner)];
    }
    if (depth > LIMITS.conditionDepth) {
      return [problem('conditionTooDeep', owner)];
    }
    return group.flatMap((part) => checkCondition(part, earlier, owner, depth + 1));
  }
  if (!OPERATORS.includes(condition.op) || typeof condition.field !== 'string') {
    return [problem('badCondition', owner)];
  }
  if (!earlier.has(condition.field)) {
    return [problem('conditionNotEarlier', owner, condition.field)];
  }
  const hasValue =
    condition.value !== undefined && condition.value !== null && condition.value !== '';
  if (NEEDS_VALUE.has(condition.op) && !hasValue) {
    return [problem('conditionNeedsValue', owner, condition.field)];
  }
  return [];
}

function checkField(field, keys, earlier, recordKeys) {
  const found = [];
  const name = field.key || field.label || '';
  if (
    typeof field.key !== 'string' ||
    !KEY.test(field.key) ||
    field.key.length > LIMITS.keyLength
  ) {
    found.push(problem('badKey', name));
  } else if (keys.has(field.key)) {
    found.push(problem('duplicateKey', field.key));
  }
  if (typeof field.label !== 'string' || field.label.trim() === '') {
    found.push(problem('noLabel', name));
  }
  if (!FIELD_TYPES.includes(field.type)) {
    found.push(problem('badType', name, String(field.type)));
  }
  if (field.type === 'picklist') {
    const options = Array.isArray(field.options) ? field.options : [];
    const usable = options.filter(
      (option) => option && String(option.value === undefined ? '' : option.value).trim() !== ''
    );
    if (usable.length === 0 || usable.length !== options.length) {
      found.push(problem('noOptions', name));
    } else if (options.length > LIMITS.options) {
      found.push(problem('tooManyOptions', name, LIMITS.options));
    }
  }
  if (field.showWhen !== undefined && field.showWhen !== null) {
    found.push(...checkCondition(field.showWhen, earlier, name));
  }
  if (field.target !== undefined && field.target !== null) {
    const target = field.target;
    if (field.type === 'file') {
      // A file is kept with the submission and shared with the person, not written to a field.
      found.push(problem('fileTarget', name));
    } else if (!recordKeys.has(target.record)) {
      found.push(problem('unknownRecord', name, String(target.record)));
    } else if (typeof target.field !== 'string' || !FIELD_NAME.test(target.field)) {
      found.push(problem('noTargetField', name));
    }
  }
  return found;
}

function checkRecord(record, recordKeys, seenKinds) {
  const found = [];
  const name = (record && record.key) || '';
  if (!record || typeof record.key !== 'string' || !KEY.test(record.key)) {
    return [problem('badRecord', name)];
  }
  if (recordKeys.has(record.key) || record.key === CONTEXT_LINK) {
    found.push(problem('duplicateRecord', record.key));
  }
  if (!RECORD_KINDS.includes(record.kind)) {
    found.push(problem('badRecord', name));
    return found;
  }
  if (record.kind !== 'related' && seenKinds.has(record.kind)) {
    found.push(problem(record.kind === 'person' ? 'twoPeople' : 'twoOrganizations'));
  }
  seenKinds.add(record.kind);
  if (record.kind === 'related' && !CUSTOM_OBJECT.test(record.object || '')) {
    found.push(problem('relatedNeedsObject', name));
  }
  if (MATCH_RULES[record.kind]) {
    // Missing settings read as the defaults (withDefaults); only a setting given and wrong fails.
    const matching = {
      rule: MATCH_RULES[record.kind][0],
      onMatch: ON_MATCH[0],
      ...(record.matching || {})
    };
    if (!MATCH_RULES[record.kind].includes(matching.rule) || !ON_MATCH.includes(matching.onMatch)) {
      found.push(problem('badMatching', name));
    }
  }
  return found;
}

function checkLinks(records) {
  const keys = new Set(records.map((record) => record.key));
  const found = [];
  records.forEach((record) => {
    Object.entries(record.links || {}).forEach(([field, to]) => {
      const known = to === CONTEXT_LINK || (keys.has(to) && to !== record.key);
      if (!FIELD_NAME.test(field) || !known) {
        found.push(problem('badLink', record.key, field));
      }
    });
    Object.keys(record.values || {}).forEach((field) => {
      if (!FIELD_NAME.test(field)) {
        found.push(problem('badValue', record.key, field));
      }
    });
  });
  return found;
}

/** The fields mapped to a record entry, by target field name (lower case) to field key. */
export function targetsOf(definition, recordKey) {
  const targets = {};
  allFields(definition).forEach((field) => {
    if (field.target && field.target.record === recordKey && field.target.field) {
      targets[field.target.field.toLowerCase()] = field.key;
    }
  });
  return targets;
}

/** What a person or organization must have mapped for a record to be written and found. */
function checkRequiredTargets(definition) {
  const found = [];
  (definition.records || []).forEach((record) => {
    const targets = targetsOf(definition, record.key);
    if (record.kind === 'person' && !targets.lastname) {
      found.push(problem('personNeedsLastName', record.key));
    }
    if (record.kind === 'person' && !targets.email && record.matching?.rule === 'email') {
      found.push(problem('personNeedsEmail', record.key));
    }
    if (record.kind === 'organization' && !targets.name) {
      found.push(problem('organizationNeedsName', record.key));
    }
  });
  return found;
}

/** True when the definition may be filled in on a Salesforce Site or by an API caller. */
export function isPublic(definition) {
  return Boolean(definition && definition.public && definition.public.enabled === true);
}

function inRange(value, [low, high]) {
  return value === undefined || (Number.isInteger(value) && value >= low && value <= high);
}

/** Problems with the `public` block: its settings, and no overwrite on a public form (R-FM3). */
function checkPublic(definition) {
  const settings = definition.public;
  if (settings === undefined || settings === null) {
    return [];
  }
  if (typeof settings !== 'object' || Array.isArray(settings)) {
    return [problem('badPublic')];
  }
  const found = [];
  if (!inRange(settings.minSeconds, PUBLIC_LIMITS.minSeconds)) {
    found.push(problem('badPublicSeconds', ...PUBLIC_LIMITS.minSeconds));
  }
  if (!inRange(settings.hourlyLimit, PUBLIC_LIMITS.hourlyLimit)) {
    found.push(problem('badPublicLimit', ...PUBLIC_LIMITS.hourlyLimit));
  }
  if (!inRange(settings.resumeDays, PUBLIC_LIMITS.resumeDays)) {
    found.push(problem('badPublicResumeDays', ...PUBLIC_LIMITS.resumeDays));
  }
  const confirmation = settings.confirmation;
  if (
    confirmation !== undefined &&
    confirmation !== null &&
    (typeof confirmation !== 'string' || confirmation.length > PUBLIC_LIMITS.confirmation)
  ) {
    found.push(problem('badPublicConfirmation', PUBLIC_LIMITS.confirmation));
  }
  if (settings.enabled === true) {
    (definition.records || []).forEach((record) => {
      if (record && record.matching && record.matching.onMatch === 'overwrite') {
        found.push(problem('publicOverwrite', record.key));
      }
    });
  }
  return found;
}

/**
 * Every problem with a definition, in reading order: steps and fields, then records. An empty
 * list means the definition can be saved and published.
 */
export function checkDefinition(definition) {
  if (!definition || typeof definition !== 'object') {
    return [problem('notJson')];
  }
  const found = [];
  if (definition.schemaVersion !== SCHEMA_VERSION) {
    found.push(problem('schemaVersion', String(definition.schemaVersion)));
  }
  const steps = Array.isArray(definition.steps) ? definition.steps : [];
  if (steps.length === 0) {
    found.push(problem('noSteps'));
  } else if (steps.length > LIMITS.steps) {
    found.push(problem('tooManySteps', LIMITS.steps));
  }
  const records = Array.isArray(definition.records) ? definition.records : [];
  if (records.length > LIMITS.records) {
    found.push(problem('tooManyRecords', LIMITS.records));
  }
  const recordKeys = new Set();
  const seenKinds = new Set();
  records.forEach((record) => {
    found.push(...checkRecord(record, recordKeys, seenKinds));
    if (record && record.key) {
      recordKeys.add(record.key);
    }
  });
  const keys = new Set();
  const stepKeys = new Set();
  let fieldCount = 0;
  steps.forEach((step, index) => {
    const stepName = (step && (step.title || step.key)) || String(index + 1);
    if (!step || typeof step.key !== 'string' || !KEY.test(step.key) || stepKeys.has(step.key)) {
      found.push(problem('badStepKey', stepName));
    } else {
      stepKeys.add(step.key);
    }
    // A step's condition may name only fields on earlier steps.
    const beforeStep = new Set(keys);
    if (step && step.showWhen !== undefined && step.showWhen !== null) {
      found.push(...checkCondition(step.showWhen, beforeStep, stepName));
    }
    const fields = (step && Array.isArray(step.fields) && step.fields) || [];
    if (fields.length === 0) {
      found.push(problem('emptyStep', stepName));
    }
    fields.forEach((field) => {
      fieldCount += 1;
      found.push(...checkField(field || {}, keys, keys, recordKeys));
      if (field && typeof field.key === 'string') {
        keys.add(field.key);
      }
    });
  });
  if (fieldCount > LIMITS.fields) {
    found.push(problem('tooManyFields', LIMITS.fields));
  }
  found.push(...checkLinks(records));
  found.push(...checkRequiredTargets({ ...definition, steps, records }));
  found.push(...checkPublic({ ...definition, records }));
  return found;
}
