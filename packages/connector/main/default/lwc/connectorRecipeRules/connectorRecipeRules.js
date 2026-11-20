/**
 * BarnCRM Connector's recipe rules for the browser (CN-02; canonical model R-CR1 to R-CR5,
 * R-RUN4; security review F1 and F4). Framework free, so it runs in Jest and ports to BarnCRM for
 * WordPress (plan 9.9). It edits a recipe document as plain JSON and returns help keys, never
 * text. The server checks every rule again (ConnectorRecipeDocument); these spare a round trip.
 */

export const MAX_STEPS = 25;
export const MAX_DEPTH = 2;
export const MAX_CONDITIONS = 10;

/** Each step kind the editor offers, in menu order, with its help key. */
export const STEP_KINDS = [
  { value: 'find', key: 'Connector_Step_Find' },
  { value: 'create', key: 'Connector_Step_Create' },
  { value: 'update', key: 'Connector_Step_Update' },
  { value: 'upsert', key: 'Connector_Step_Upsert' },
  { value: 'callApp', key: 'Connector_Step_CallApp' },
  { value: 'sendWebhook', key: 'Connector_Step_SendWebhook' },
  { value: 'importRows', key: 'Connector_Step_ImportRows' },
  { value: 'if', key: 'Connector_Step_If' },
  { value: 'stop', key: 'Connector_Step_Stop' }
];

/**
 * Load Rows limits (CN-09, R-CR9) in the order the editor shows them, each with its default and
 * help key; Most Rows is 1 to 4,000, the others 0 to 4,000.
 */
export const MOST_IMPORT_ROWS = 4000;
export const IMPORT_LIMITS = [
  { key: 'rows', fallback: 1000, label: 'Connector_Editor_MostRows', min: 1 },
  { key: 'rejected', fallback: 0, label: 'Connector_Editor_MostRejected', min: 0 },
  { key: 'created', fallback: 1000, label: 'Connector_Editor_MostCreated', min: 0 },
  { key: 'updated', fallback: 1000, label: 'Connector_Editor_MostUpdated', min: 0 }
];

/** A Load Rows step's limits, each its own value or its default. */
export function importLimits(step) {
  const given = (step && step.limits) || {};
  return IMPORT_LIMITS.map((entry) => ({
    ...entry,
    value: Number.isInteger(given[entry.key]) ? given[entry.key] : entry.fallback
  }));
}

export const RECORD_KINDS = ['create', 'update', 'upsert'];
export const METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
export const OPERATORS = [
  'equals',
  'not equals',
  'contains',
  'does not contain',
  'starts with',
  'greater than',
  'less than',
  'is null',
  'is not null'
];
export const OUTCOMES = ['Succeeded', 'Skipped', 'Failed'];
export const RUN_AS_AUTOMATION = 'Automation';
export const RUN_AS_SYSTEM = 'System';
export const RUN_AS_USER = 'IntegrationUser';

/** The triggers a recipe may start on (R-CR1), with the help key of each. */
export const TRIGGERS = [
  { value: 'manual', key: 'Connector_Trigger_Manual' },
  { value: 'schedule', key: 'Connector_Trigger_Schedule' },
  { value: 'record', key: 'Connector_Trigger_Record' },
  { value: 'webhook', key: 'Connector_Trigger_Webhook' },
  { value: 'appPoll', key: 'Connector_Trigger_AppPoll' }
];
/** The one value path an App Poll request may read (R-CR20). */
export const WATERMARK_PATH = 'trigger.watermark';
const ITEM_PATH =
  /^[A-Za-z0-9_-]{1,80}(\[[0-9]{1,3}\])?(\.[A-Za-z0-9_-]{1,80}(\[[0-9]{1,3}\])?){0,9}$/;
/** The steps that make a request through a connection. */
export const CALL_KINDS = ['callApp', 'sendWebhook'];
/** A webhook trigger's reply when the recipe sets none (R-CR10). */
export const DEFAULT_REPLY = '{"received": true, "reference": "{reference}"}';
export const MAX_REPLY = 4000;
const FIELD_NAME = /^[A-Za-z0-9_.-]{1,100}$/;
export const EVERY = ['15m', 'hour', 'day', 'week'];
export const DAYS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
export const STAMPS = ['created', 'changed'];
export const MODES = ['each', 'batch'];
export const MAX_POLLED = 200;
const AT = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
const STEP_ID = /^[A-Za-z0-9_]{1,20}$/;
const PILL = /^(trigger|steps)(\.[A-Za-z0-9_-]+(\[[0-9]{1,3}\])?){0,10}$/;
const SLOT = /\{([A-Za-z0-9_]{1,40})\}/g;
const QUERY_NAME = /^[A-Za-z0-9_.[\]-]{1,100}$/;
const HEADER_NAME = /^[A-Za-z0-9-]{1,64}$/;
const RESERVED_HEADERS = ['authorization', 'host', 'cookie', 'content-length', 'transfer-encoding'];

/** A new, empty recipe document under the manual trigger. */
export function newDocument() {
  return { version: 1, trigger: { kind: 'manual', sample: {} }, steps: [] };
}

/** A document read from text, or a new one when the text is blank or unreadable. */
export function readDocument(text) {
  if (!text) {
    return newDocument();
  }
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      parsed.trigger = parsed.trigger || { kind: 'manual', sample: {} };
      parsed.steps = Array.isArray(parsed.steps) ? parsed.steps : [];
      return parsed;
    }
  } catch {
    // A new document below.
  }
  return newDocument();
}

/**
 * A copy with the trigger changed to a kind, with that kind's starting values (R-CR1). The
 * sample data stays, since Test reads it whatever starts the recipe.
 */
export function setTrigger(document, kind) {
  const next = copy(document);
  const sample = (next.trigger && next.trigger.sample) || {};
  if (kind === 'schedule') {
    next.trigger = { kind, every: 'day', at: '08:00', sample };
  } else if (kind === 'record') {
    next.trigger = { kind, query: null, savedQuery: '', on: 'changed', mode: 'each', sample };
  } else if (kind === 'webhook') {
    next.trigger = {
      kind,
      eventId: '',
      reply: { status: 202, body: DEFAULT_REPLY, challenge: '' },
      sample
    };
  } else if (kind === 'appPoll') {
    next.trigger = {
      kind,
      connection: '',
      path: '',
      pathValues: [],
      query: [],
      items: '',
      id: 'id',
      stamp: '',
      mode: 'each',
      sample
    };
  } else {
    next.trigger = { kind: 'manual', sample };
  }
  return next;
}

/** A copy with fields of the trigger changed. */
export function updateTrigger(document, changes) {
  const next = copy(document);
  next.trigger = { ...next.trigger, ...changes };
  if (next.trigger.every !== 'week') {
    delete next.trigger.day;
  } else if (!next.trigger.day) {
    next.trigger.day = 'MON';
  }
  if (next.trigger.kind !== 'schedule') {
    delete next.trigger.day;
  }
  return next;
}

/** What is wrong with a document's trigger, as a help key, or null (the server's twin). */
export function triggerProblem(trigger) {
  const starter = trigger || {};
  if (!TRIGGERS.some((entry) => entry.value === starter.kind)) {
    return 'Connector_Recipe_ErrorTrigger';
  }
  if (starter.kind === 'schedule') {
    const timed = starter.every === 'day' || starter.every === 'week';
    const bad =
      !EVERY.includes(starter.every) ||
      (timed && !AT.test(starter.at || '')) ||
      (starter.every === 'week' && !DAYS.includes(starter.day));
    return bad ? 'Connector_Recipe_ErrorSchedule' : null;
  }
  if (starter.kind === 'record') {
    const most = starter.limit;
    const bad =
      !starter.query ||
      !starter.query.object ||
      !STAMPS.includes(starter.on) ||
      (starter.mode !== undefined && !MODES.includes(starter.mode)) ||
      (most !== undefined &&
        most !== null &&
        !(Number.isInteger(most) && most >= 1 && most <= MAX_POLLED));
    return bad ? 'Connector_Recipe_ErrorRecordTrigger' : null;
  }
  if (starter.kind === 'webhook') {
    return webhookProblem(starter) ? 'Connector_Recipe_ErrorWebhook' : null;
  }
  if (starter.kind === 'appPoll') {
    return appPollProblem(starter) ? 'Connector_Recipe_ErrorAppPoll' : null;
  }
  return null;
}

/** True when an App Poll trigger breaks R-CR20 (the server's twin, `ConnectorAppPoll.problem`). */
function appPollProblem(starter) {
  const request = {
    kind: 'callApp',
    method: 'GET',
    connection: starter.connection,
    path: starter.path,
    pathValues: starter.pathValues,
    query: starter.query,
    headers: starter.headers
  };
  const most = starter.limit;
  const itemPath = (path, blankOk) => (path ? ITEM_PATH.test(path) : blankOk);
  const fixedOrWatermark = [
    ...(starter.pathValues || []),
    ...(starter.query || []),
    ...(starter.headers || [])
  ].every((entry) => !entry.path || entry.path === WATERMARK_PATH);
  return (
    !String(starter.connection || '').startsWith('BarnConn_') ||
    Boolean(callProblem(request, ['trigger'])) ||
    !itemPath(starter.items, true) ||
    !itemPath(starter.id, false) ||
    !itemPath(starter.stamp, false) ||
    (starter.mode !== undefined && !MODES.includes(starter.mode)) ||
    (most !== undefined &&
      most !== null &&
      !(Number.isInteger(most) && most >= 1 && most <= MAX_POLLED)) ||
    !fixedOrWatermark
  );
}

/** True when a webhook trigger's event id path or reply breaks R-CR10 (the server's twin). */
function webhookProblem(starter) {
  const reply = starter.reply || {};
  const body = typeof reply.body === 'string' ? reply.body : '';
  const challenge = reply.challenge || '';
  let jsonBody = true;
  if (body) {
    try {
      JSON.parse(body);
    } catch {
      jsonBody = false;
    }
  }
  return (
    Boolean(starter.eventId && !isPill(starter.eventId)) ||
    (reply.status !== undefined && reply.status !== null && ![200, 202].includes(reply.status)) ||
    body.length > MAX_REPLY ||
    !jsonBody ||
    Boolean(challenge && (!FIELD_NAME.test(challenge) || challenge.toLowerCase() === 'token'))
  );
}

/** The help key naming a Run As value. */
export function runAsKey(runAs) {
  if (runAs === RUN_AS_SYSTEM) {
    return 'Connector_RunAs_System';
  }
  return runAs === RUN_AS_USER ? 'Connector_RunAs_IntegrationUser' : 'Connector_RunAs_Automation';
}

/** The help key naming a recipe's Trigger Kind (Manual, Schedule, RecordChange). */
export function triggerKindKey(kind) {
  if (kind === 'Schedule') {
    return 'Connector_Trigger_Schedule';
  }
  if (kind === 'Webhook') {
    return 'Connector_Trigger_Webhook';
  }
  if (kind === 'AppPoll') {
    return 'Connector_Trigger_AppPoll';
  }
  return kind === 'RecordChange' ? 'Connector_Trigger_Record' : 'Connector_Trigger_Manual';
}

/** Every step, nested ones included, in document order. */
export function allSteps(document) {
  const found = [];
  const collect = (steps) => {
    (steps || []).forEach((step) => {
      found.push(step);
      collect(step.then);
      collect(step.otherwise);
    });
  };
  collect(document && document.steps);
  return found;
}

/** A step name not yet used: the kind and the next free number. */
export function freeId(document, kind) {
  const used = new Set(allSteps(document).map((step) => String(step.id).toLowerCase()));
  for (let n = 1; ; n++) {
    const id = `${kind}${n}`;
    if (!used.has(id.toLowerCase())) {
      return id;
    }
  }
}

/** A new step of a kind with the fields its editor shows. */
export function newStep(document, kind) {
  const step = { id: freeId(document, kind), kind };
  if (kind === 'find') {
    Object.assign(step, { query: null, values: [], stopIfNone: false });
  } else if (RECORD_KINDS.includes(kind)) {
    Object.assign(step, { map: '', input: 'trigger' });
    if (kind === 'update') {
      step.recordId = '';
    }
  } else if (kind === 'callApp') {
    Object.assign(step, {
      connection: '',
      method: 'GET',
      path: '/',
      pathValues: [],
      query: [],
      headers: [],
      bodyMap: '',
      bodyInput: 'trigger',
      success: [],
      notFoundOk: false
    });
  } else if (kind === 'importRows') {
    const limits = {};
    IMPORT_LIMITS.forEach((entry) => {
      limits[entry.key] = entry.fallback;
    });
    Object.assign(step, { template: '', rows: 'trigger.rows', limits });
  } else if (kind === 'sendWebhook') {
    Object.assign(step, {
      connection: '',
      path: '',
      urlFrom: '',
      pathValues: [],
      query: [],
      headers: [],
      bodyMap: '',
      bodyInput: 'trigger',
      success: []
    });
  } else if (kind === 'if') {
    Object.assign(step, {
      match: 'all',
      conditions: [{ path: 'trigger', operator: 'is not null', value: '' }],
      then: [],
      otherwise: []
    });
  } else {
    Object.assign(step, { outcome: 'Succeeded', message: '' });
  }
  return step;
}

/**
 * The steps as one list to show: each with its address (a list of `[index, branch]` pairs from
 * the top), depth and branch, so nested If steps render without a recursive component.
 */
export function flatten(document) {
  const rows = [];
  const walk = (steps, address, depth, branch) => {
    (steps || []).forEach((step, index) => {
      const here = [...address, [index, branch]];
      rows.push({
        key: here.map((pair) => pair.join(':')).join('/'),
        address: here,
        depth,
        branch,
        step
      });
      if (step.kind === 'if') {
        walk(step.then, here, depth + 1, 'then');
        walk(step.otherwise, here, depth + 1, 'otherwise');
      }
    });
  };
  walk(document.steps, [], 0, 'steps');
  return rows;
}

/** The list a step's address points into, and its index there. */
function locate(document, address) {
  let list = document.steps;
  for (let i = 0; i < address.length - 1; i++) {
    const [index] = address[i];
    const branch = address[i + 1][1];
    list = list[index][branch];
  }
  return { list, index: address[address.length - 1][0] };
}

function copy(document) {
  return JSON.parse(JSON.stringify(document));
}

/** A copy with a new step at the end of the top list, or of an If's branch. */
export function addStep(document, kind, parentAddress, branch) {
  const next = copy(document);
  const step = newStep(next, kind);
  if (parentAddress) {
    const { list, index } = locate(next, parentAddress);
    list[index][branch] = list[index][branch] || [];
    list[index][branch].push(step);
  } else {
    next.steps.push(step);
  }
  return next;
}

/** A copy without the step at the address. */
export function removeStep(document, address) {
  const next = copy(document);
  const { list, index } = locate(next, address);
  list.splice(index, 1);
  return next;
}

/** A copy with the step moved one place up (-1) or down (1) within its list. */
export function moveStep(document, address, delta) {
  const next = copy(document);
  const { list, index } = locate(next, address);
  const target = index + delta;
  if (target >= 0 && target < list.length) {
    const [step] = list.splice(index, 1);
    list.splice(target, 0, step);
  }
  return next;
}

/** A copy with fields of the step at the address changed. */
export function updateStep(document, address, changes) {
  const next = copy(document);
  const { list, index } = locate(next, address);
  list[index] = { ...list[index], ...changes };
  return next;
}

/** The `{slot}` names of a Call an App path, in order, once each. */
export function slotsOf(path) {
  const names = [];
  String(path || '').replace(SLOT, (whole, name) => {
    if (!names.includes(name)) {
      names.push(name);
    }
    return whole;
  });
  return names;
}

/** Path values kept for the slots a path still has, with a blank one for each new slot. */
export function syncSlots(path, pathValues) {
  const byName = new Map((pathValues || []).map((value) => [value.name, value]));
  return slotsOf(path).map((name) => byName.get(name) || { name, path: '' });
}

/** True for text that may not travel in a request (F1, F4): `{!`, CR or LF. */
export function unsafeValue(value) {
  return typeof value === 'string' && (value.includes('{!') || /[\r\n]/.test(value));
}

/** True for a path Call an App may not append to `callout:` (F4). */
export function pathProblem(path) {
  const text = typeof path === 'string' ? path : '';
  return (
    !text ||
    text.length > 1000 ||
    !text.startsWith('/') ||
    text.startsWith('//') ||
    /[@\\?#\s]/.test(text) ||
    text.includes('{!')
  );
}

export function isPill(path) {
  return typeof path === 'string' && PILL.test(path);
}

export function headerNameOk(name) {
  return (
    typeof name === 'string' &&
    HEADER_NAME.test(name) &&
    !RESERVED_HEADERS.includes(name.toLowerCase())
  );
}

function valueOk(entry) {
  if (entry && entry.path) {
    return isPill(entry.path);
  }
  return !unsafeValue(entry && entry.value);
}

/** What is wrong with one step, as `{ key, args }`, or null. */
function stepProblem(step, label) {
  const at = [label];
  switch (step.kind) {
    case 'find':
      if (!step.query || !step.query.object) {
        return { key: 'Connector_Recipe_ErrorFind', args: at };
      }
      return (step.values || []).every((value) => isPill(value.path))
        ? null
        : { key: 'Connector_Recipe_ErrorPath', args: at };
    case 'create':
    case 'update':
    case 'upsert':
      if (!step.map) {
        return { key: 'Connector_Recipe_ErrorMap', args: at };
      }
      if (step.input && !isPill(step.input)) {
        return { key: 'Connector_Recipe_ErrorPath', args: at };
      }
      return step.kind === 'update' && !isPill(step.recordId)
        ? { key: 'Connector_Recipe_ErrorRecordId', args: at }
        : null;
    case 'callApp':
    case 'sendWebhook':
      return callProblem(step, at);
    case 'importRows':
      return importProblem(step, at);
    case 'if': {
      const conditions = step.conditions || [];
      const bad =
        !conditions.length ||
        conditions.length > MAX_CONDITIONS ||
        conditions.some(
          (condition) => !isPill(condition.path) || !OPERATORS.includes(condition.operator)
        );
      return bad ? { key: 'Connector_Recipe_ErrorCondition', args: at } : null;
    }
    case 'stop':
      return OUTCOMES.includes(step.outcome) && String(step.message || '').length <= 255
        ? null
        : { key: 'Connector_Recipe_ErrorStop', args: at };
    default:
      return { key: 'Connector_Recipe_ErrorStepKind', args: at };
  }
}

function importProblem(step, at) {
  if (!step.template) {
    return { key: 'Connector_Recipe_ErrorTemplate', args: at };
  }
  if (!isPill(step.rows)) {
    return { key: 'Connector_Recipe_ErrorPath', args: at };
  }
  const given = step.limits || {};
  const bad = IMPORT_LIMITS.some((entry) => {
    const value = given[entry.key];
    return (
      value !== undefined &&
      value !== null &&
      !(Number.isInteger(value) && value >= entry.min && value <= MOST_IMPORT_ROWS)
    );
  });
  return bad ? { key: 'Connector_Recipe_ErrorLimits', args: at } : null;
}

function callProblem(step, at) {
  if (!step.connection) {
    return { key: 'Connector_Recipe_ErrorConnection', args: at };
  }
  if (step.kind === 'callApp' && !METHODS.includes(step.method)) {
    return { key: 'Connector_Recipe_ErrorMethod', args: at };
  }
  const fromData = Boolean(step.urlFrom);
  const badPath = fromData
    ? !isPill(step.urlFrom) ||
      Boolean(step.path) ||
      (step.pathValues || []).length > 0 ||
      (step.query || []).length > 0
    : !(step.kind === 'sendWebhook' && !step.path) && pathProblem(step.path);
  if (badPath) {
    return { key: 'Connector_Recipe_ErrorRequestPath', args: at };
  }
  const slots = slotsOf(step.path);
  const values = step.pathValues || [];
  const named = values.map((value) => value.name);
  if (
    slots.length !== values.length ||
    slots.some((name) => !named.includes(name)) ||
    values.some((value) => !value.path && !value.value) ||
    !values.every(valueOk)
  ) {
    return { key: 'Connector_Recipe_ErrorSlot', args: at };
  }
  if (!(step.query || []).every((pair) => QUERY_NAME.test(pair.name || '') && valueOk(pair))) {
    return { key: 'Connector_Recipe_ErrorQuery', args: at };
  }
  if (!(step.headers || []).every((header) => headerNameOk(header.name) && valueOk(header))) {
    return { key: 'Connector_Recipe_ErrorHeader', args: at };
  }
  if (!(step.success || []).every((code) => Number.isInteger(code) && code >= 100 && code <= 599)) {
    return { key: 'Connector_Recipe_ErrorCodes', args: at };
  }
  if (step.bodyInput && !isPill(step.bodyInput)) {
    return { key: 'Connector_Recipe_ErrorMap', args: at };
  }
  return null;
}

/**
 * Every problem of a document as `{ key, args }`, in the order the server reports them: a merge
 * field anywhere first (F1), then the steps, their count and nesting.
 */
export function problems(document) {
  if (JSON.stringify(document || {}).includes('{!')) {
    return [{ key: 'Connector_Recipe_ErrorMergeField', args: [] }];
  }
  const found = [];
  const starter = triggerProblem(document && document.trigger);
  if (starter) {
    found.push({ key: starter, args: [] });
  }
  const ids = new Set();
  let count = 0;
  const check = (steps, depth) => {
    (steps || []).forEach((step) => {
      count++;
      const label = step.id || String(count);
      const id = String(step.id || '');
      if (!STEP_ID.test(id) || ids.has(id.toLowerCase())) {
        found.push({ key: 'Connector_Recipe_ErrorStepId', args: [label] });
      }
      ids.add(id.toLowerCase());
      const problem = stepProblem(step, label);
      if (problem) {
        found.push(problem);
      }
      if (step.kind === 'if') {
        if (depth > MAX_DEPTH) {
          found.push({ key: 'Connector_Recipe_ErrorNesting', args: [label] });
        }
        check(step.then, depth + 1);
        check(step.otherwise, depth + 1);
      }
    });
  };
  check(document && document.steps, 1);
  if (!count) {
    found.push({ key: 'Connector_Recipe_ErrorNoSteps', args: [] });
  }
  if (count > MAX_STEPS) {
    found.push({ key: 'Connector_Recipe_ErrorTooManySteps', args: [] });
  }
  return found;
}

/** What a Schedule or Record Change trigger gives its run, as value paths (R-CR6). */
function triggerPaths(trigger) {
  if (trigger.kind === 'schedule') {
    return ['trigger.scheduledAt'];
  }
  if (trigger.kind === 'appPoll') {
    return trigger.mode === 'batch'
      ? ['trigger.itemIds', 'trigger.items']
      : ['trigger.itemId', 'trigger.item'];
  }
  if (trigger.kind !== 'record') {
    return [];
  }
  const fields = ['Id', ...((trigger.query && trigger.query.fields) || [])];
  return trigger.mode === 'batch'
    ? ['trigger.recordIds', ...fields.map((field) => `trigger.records[0].${field}`)]
    : ['trigger.recordId', ...fields.map((field) => `trigger.record.${field}`)];
}

/**
 * The value paths a step may read, for the editor's hints: what a Schedule or Record Change
 * trigger gives, the sample's keys under `trigger` (one level down), then each earlier step's
 * usual results.
 */
export function pathSuggestions(document, beforeStep) {
  const found = ['trigger', ...triggerPaths((document && document.trigger) || {})];
  const sample = document && document.trigger && document.trigger.sample;
  if (sample && typeof sample === 'object' && !Array.isArray(sample)) {
    Object.keys(sample).forEach((key) => {
      found.push(`trigger.${key}`);
      const value = sample[key];
      if (value && typeof value === 'object' && !Array.isArray(value)) {
        Object.keys(value).forEach((inner) => found.push(`trigger.${key}.${inner}`));
      }
    });
  }
  for (const step of allSteps(document)) {
    if (step === beforeStep) {
      break;
    }
    const base = `steps.${step.id}`;
    if (step.kind === 'find') {
      found.push(`${base}.count`, `${base}.records[0].Id`);
      ((step.query && step.query.fields) || []).forEach((field) =>
        found.push(`${base}.records[0].${field}`)
      );
    } else if (RECORD_KINDS.includes(step.kind)) {
      found.push(`${base}.id`, `${base}.action`);
    } else if (CALL_KINDS.includes(step.kind)) {
      found.push(`${base}.status`, `${base}.body`);
    } else if (step.kind === 'importRows') {
      found.push(`${base}.batch`, `${base}.created`, `${base}.updated`, `${base}.rejected`);
    }
  }
  return found;
}

/** Sample data from text: an object or list, or undefined when it is not JSON. */
export function readSample(text) {
  if (!text || !String(text).trim()) {
    return {};
  }
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' ? parsed : undefined;
  } catch {
    return undefined;
  }
}

/** Success codes from "200, 201": whole numbers, or undefined when any part is not one. */
export function readCodes(text) {
  const parts = String(text || '')
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
  const codes = parts.map(Number);
  return codes.every((code) => Number.isInteger(code)) ? codes : undefined;
}

/** A status badge variant for a run or recipe status. */
export function statusVariant(status) {
  return (
    {
      Succeeded: 'success',
      Active: 'success',
      Skipped: 'neutral',
      Draft: 'neutral',
      Queued: 'info',
      Received: 'info',
      Running: 'info',
      Waiting: 'warning',
      Failed: 'error',
      Paused: 'warning',
      PausedByFailures: 'warning'
    }[status] || 'neutral'
  );
}

/** A run's step log as rows to show, oldest first; blank or unreadable is none. */
export function stepRows(stepLogJson, resultsJson) {
  let log = [];
  let results = {};
  try {
    log = stepLogJson ? JSON.parse(stepLogJson) : [];
  } catch {
    log = [];
  }
  try {
    results = resultsJson ? JSON.parse(resultsJson) || {} : {};
  } catch {
    results = {};
  }
  return (Array.isArray(log) ? log : []).map((entry, index) => {
    const result = results[entry.step];
    const preview = result && (result.wouldWrite || result.request);
    return {
      key: `${entry.step}-${index}`,
      step: entry.step,
      kind: entry.kind,
      outcome: entry.outcome,
      ms: entry.ms,
      message: entry.message,
      status: entry.status,
      ids: (entry.ids || []).join(', '),
      response: entry.response,
      preview: preview ? JSON.stringify(preview, null, 2) : ''
    };
  });
}
