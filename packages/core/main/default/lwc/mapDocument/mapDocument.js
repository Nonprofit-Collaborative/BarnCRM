/**
 * The map document of the Mapper (canonical model R-MAP1 to R-MAP4; integration hub design
 * Section 2.2; ADR-NEXT `NEXT-reusable-mapper.md`), without a framework (plan 9.9): no
 * lightning/* or @salesforce/* imports, so it ports to BarnCRM for WordPress as it is.
 *
 * A map document is the import mapping document of R-IT1 at version 4: `from` (columns of a
 * file, the fields of a record, or a JSON payload), `to` (a record or a JSON body), `columns`
 * (source or fixed value, target, steps, required, lookup), `defaults` and `match`. A version 1
 * to 3 template mapping reads as a version 4 map from columns to a record, so nothing migrates.
 *
 * What lives here: reading a document forgivingly, the save checks (the twin of
 * SavedTransformService.checkMap, both tested against MapDocumentFixture.json), JSON paths,
 * sources and samples, auto-match (exact names, then best guesses with the D-150 badge), the
 * value checks of the preview, the summary of Check Before Running, and copying a map into and
 * out of a Super Importer mapping. Running the steps of R-IT15 and finding lookups happens on
 * the server (MapController.previewMap), so the browser and an import never disagree.
 */

export const VERSION = 4;
export const MAX_COLUMNS = 200;
export const MAX_DEFAULTS = 50;
export const MAX_SAMPLE = 20000;
export const MAX_SAMPLES = 200;
export const MAX_TEXT = 255;
export const MAX_PATH_PARTS = 10;
export const RECORD = 'Record';
export const FROM_KINDS = ['columns', 'record', 'json'];
export const TO_KINDS = ['record', 'json'];
export const MATCH_BY = ['id', 'field', 'externalId', 'duplicateRules'];
export const MATCH_SEVERAL = ['reject', 'newest'];
export const MATCH_NONE = ['create', 'skip', 'reject'];
export const NOT_FOUND = ['reject', 'leaveEmpty'];
/** The fewest likeness points (fieldSuggest.score) a best guess needs. */
export const MIN_GUESS = 2;
/** The most source paths read from one JSON sample. */
export const MAX_PATHS = 300;

const PATH = /^[A-Za-z0-9_-]+(\[[0-9]{1,3}\])?(\.[A-Za-z0-9_-]+(\[[0-9]{1,3}\])?){0,9}$/;
const KEY = /^[A-Za-z0-9_-]+$/;
const TEXT_TYPES = ['string', 'textarea', 'email', 'phone', 'url', 'combobox', 'encryptedstring'];
const NUMBER_TYPES = ['int', 'integer', 'double', 'currency', 'percent', 'long'];
const BOOLEAN_TEXT = ['true', 'false', 'yes', 'no', 'y', 'n', '1', '0'];
const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const DATETIME =
  /^(\d{4})-(\d{2})-(\d{2})([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$/;
const NUMBER = /^[-+]?(\d+(\.\d*)?|\.\d+)$/;

/** Fills {0}, {1} in a template. */
export function format(template, ...args) {
  return String(template || '').replace(/\{(\d+)\}/g, (match, n) => {
    const value = args[Number(n)];
    return value === undefined || value === null ? '' : String(value);
  });
}

function lower(value) {
  return String(value === undefined || value === null ? '' : value)
    .trim()
    .toLowerCase();
}

function text(value) {
  if (value === undefined || value === null) {
    return '';
  }
  return typeof value === 'object' ? JSON.stringify(value) : String(value);
}

function isObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function nonBlank(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

// ---- paths (R-MAP2) ------------------------------------------------------------------------

/** True for a path of at most 10 keys, each with an optional [n]. Nothing in it is evaluated. */
export function isPath(path) {
  return typeof path === 'string' && PATH.test(path);
}

/** The keys and list positions of a path: `lines[0].sku` gives ['lines', 0, 'sku']. */
export function pathParts(path) {
  const parts = [];
  String(path || '')
    .split('.')
    .forEach((part) => {
      const at = part.indexOf('[');
      if (at < 0) {
        parts.push(part);
      } else {
        parts.push(part.slice(0, at), Number(part.slice(at + 1, -1)));
      }
    });
  return parts;
}

/** The value a path finds in a payload, as text; blank when it finds nothing. */
export function readPath(data, path) {
  if (!isPath(path)) {
    return '';
  }
  let current = data;
  for (const part of pathParts(path)) {
    if (current === null || current === undefined || typeof current !== 'object') {
      return '';
    }
    current = current[part];
  }
  return text(current);
}

/** A path in plain words: `profile.email` reads "profile, email", `lines[0]` reads "lines 1". */
export function pathLabel(path) {
  return String(path || '')
    .split('.')
    .map((part) => part.replace(/\[(\d+)\]/, (match, n) => ` ${Number(n) + 1}`))
    .join(', ');
}

/**
 * Every value a JSON sample holds, as a path (a list is read through its first item), at most
 * MAX_PATHS. A key a path cannot name (a space, a dot) is left out.
 */
export function pathsFromSample(sample) {
  const found = [];
  const walk = (node, prefix, depth) => {
    if (found.length >= MAX_PATHS || depth > MAX_PATH_PARTS) {
      return;
    }
    if (Array.isArray(node)) {
      if (node.length === 0 || !prefix) {
        if (prefix) {
          found.push(prefix);
        }
        return;
      }
      walk(node[0], `${prefix}[0]`, depth);
      return;
    }
    if (isObject(node)) {
      const keys = Object.keys(node).filter((key) => KEY.test(key));
      if (keys.length === 0 && prefix) {
        found.push(prefix);
      }
      keys.forEach((key) => walk(node[key], prefix ? `${prefix}.${key}` : key, depth + 1));
      return;
    }
    if (prefix) {
      found.push(prefix);
    }
  };
  walk(Array.isArray(sample) ? sample[0] : sample, '', 0);
  return found.filter(isPath);
}

/**
 * Pasted JSON as samples: each item of a list (at most MAX_SAMPLES), or the one object.
 * Returns { samples, error } with error 'unreadable' or 'tooBig' when it cannot be used.
 */
export function samplesFromJson(json) {
  if (!nonBlank(json)) {
    return { samples: [], error: null };
  }
  if (json.length > MAX_SAMPLE * MAX_SAMPLES) {
    return { samples: [], error: 'tooBig' };
  }
  let parsed;
  try {
    parsed = JSON.parse(json);
  } catch (e) {
    return { samples: [], error: 'unreadable' };
  }
  const list = Array.isArray(parsed) ? parsed : [parsed];
  const samples = list.filter(isObject).slice(0, MAX_SAMPLES);
  return { samples, error: samples.length === 0 ? 'unreadable' : null };
}

/** The sample a map keeps for the screen (R-MAP1): the first one, when it fits. */
export function keptSample(samples) {
  const first = (samples || [])[0];
  return first && JSON.stringify(first).length <= MAX_SAMPLE ? first : undefined;
}

// ---- sources -------------------------------------------------------------------------------

function examplesOf(samples, read) {
  const examples = [];
  (samples || []).forEach((sample) => {
    const value = read(sample);
    if (examples.length < 3 && nonBlank(value)) {
      examples.push(value.length > 60 ? `${value.slice(0, 57)}...` : value);
    }
  });
  return examples;
}

/** A file's columns, each with up to three example values from its first rows. */
export function sourcesFromRows(headers, rows) {
  return (headers || []).map((name) => ({
    name,
    label: name,
    examples: examplesOf(rows, (row) => text(row && row[name]))
  }));
}

/** A JSON payload's values, as paths with plain labels and examples. */
export function sourcesFromJson(samples) {
  return pathsFromSample((samples || [])[0]).map((path) => ({
    name: path,
    label: pathLabel(path),
    examples: examplesOf(samples, (sample) => readPath(sample, path))
  }));
}

/** A record's fields ({ apiName, label }) with the chosen record's values. */
export function sourcesFromRecord(fields, record) {
  return (fields || []).map((field) => ({
    name: field.apiName,
    label: field.label,
    examples: examplesOf(record ? [record] : [], (row) => text(row[field.apiName]))
  }));
}

/**
 * A sample as the preview reads it: every source name and its raw value. A file row is read by
 * column name; a record or a payload by path.
 */
export function sampleValues(fromKind, sample, sourceNames) {
  const values = {};
  (sourceNames || []).forEach((name) => {
    values[name] =
      fromKind === 'columns' ? text(sample && sample[name]) : readPath(sample || {}, name);
  });
  return values;
}

// ---- auto-match (C-49a, C-49e, D-150) ------------------------------------------------------

/** A name as exact matching compares it: no namespace, no __c, no spaces or punctuation. */
export function normalize(name) {
  return String(name || '')
    .replace(/__c$/i, '')
    .replace(/^[A-Za-z0-9]+__(?=[A-Za-z])/, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

function lastKey(name) {
  const parts = pathParts(name).filter((part) => typeof part === 'string');
  return parts.length > 0 ? parts[parts.length - 1] : String(name || '');
}

/**
 * Matches sources to targets, keeping every column already set. Exact names first (the
 * source's name, its last path key or its label against the target's API name or label, after
 * `normalize`); then, when `score` (fieldSuggest.score) is given, the best-scoring free target
 * for each source still unmatched, marked `guessed` so the screen shows "Best guess, check it"
 * until it is accepted (D-150). A target gets at most one column.
 *
 * @param sources [{ name, label }]
 * @param targets [{ value, label, name }] (name: the API name, when value is `Record.<name>`)
 * @param columns the map's columns now
 * @param score optional (heading, label) => points
 */
export function autoMatch(sources, targets, columns, score) {
  const result = (columns || []).slice();
  const used = new Set(result.map((column) => lower(column.target)));
  const mapped = new Set(result.filter((column) => column.source).map((c) => lower(c.source)));
  const open = (sources || []).filter((source) => !mapped.has(lower(source.name)));
  const free = () => (targets || []).filter((target) => !used.has(lower(target.value)));
  const take = (source, target, guessed) => {
    used.add(lower(target.value));
    const column = { source: source.name, target: target.value };
    if (guessed) {
      column.guessed = true;
    }
    result.push(column);
  };
  const unmatched = [];
  open.forEach((source) => {
    const keys = new Set(
      [source.name, lastKey(source.name), source.label].map(normalize).filter(Boolean)
    );
    const exact = free().find(
      (target) =>
        keys.has(normalize(target.name || target.value)) || keys.has(normalize(target.label))
    );
    if (exact) {
      take(source, exact, false);
    } else {
      unmatched.push(source);
    }
  });
  if (typeof score === 'function') {
    unmatched.forEach((source) => {
      let best = null;
      let bestPoints = MIN_GUESS - 1;
      free().forEach((target) => {
        const points = score(source.label || lastKey(source.name), target.label);
        if (points > bestPoints) {
          best = target;
          bestPoints = points;
        }
      });
      if (best) {
        take(source, best, true);
      }
    });
  }
  return result;
}

// ---- reading and checking a document (R-MAP1, R-MAP3) ----------------------------------------

function cleanLookup(raw) {
  if (!isObject(raw) || !nonBlank(raw.object) || !nonBlank(raw.field)) {
    return undefined;
  }
  const lookup = { object: raw.object, field: raw.field };
  if (NOT_FOUND.includes(raw.notFound)) {
    lookup.notFound = raw.notFound;
  }
  return lookup;
}

/** One column as stored, or null when it is broken (it is then skipped and counted). */
function cleanColumn(raw, fromKind, toKind) {
  if (!isObject(raw) || !nonBlank(raw.target)) {
    return null;
  }
  const hasValue = typeof raw.value === 'string';
  if (!nonBlank(raw.source) && !hasValue) {
    return null;
  }
  if (toKind === 'json' && !isPath(raw.target)) {
    return null;
  }
  if (nonBlank(raw.source) && fromKind === 'json' && !isPath(raw.source)) {
    return null;
  }
  if (hasValue && raw.value.length > MAX_TEXT) {
    return null;
  }
  if (raw.lookup !== undefined && !cleanLookup(raw.lookup)) {
    return null;
  }
  const column = nonBlank(raw.source) ? { source: raw.source } : {};
  if (hasValue) {
    column.value = raw.value;
  }
  column.target = raw.target;
  if (Array.isArray(raw.transforms) && raw.transforms.length > 0) {
    column.transforms = raw.transforms;
  }
  if (raw.required === true) {
    column.required = true;
  }
  if (raw.lookup !== undefined) {
    column.lookup = cleanLookup(raw.lookup);
  }
  if (nonBlank(raw.lookupField)) {
    column.lookupField = raw.lookupField;
  }
  if (raw.blankClears === true) {
    column.blankClears = true;
  }
  return column;
}

function cleanMatch(raw) {
  if (!isObject(raw) || !MATCH_BY.includes(raw.by)) {
    return undefined;
  }
  const match = { by: raw.by };
  if (nonBlank(raw.field)) {
    match.field = raw.field;
  }
  if (MATCH_SEVERAL.includes(raw.several)) {
    match.several = raw.several;
  }
  if (MATCH_NONE.includes(raw.none)) {
    match.none = raw.none;
  }
  return match;
}

function parsedInput(input) {
  if (typeof input !== 'string') {
    return input;
  }
  try {
    return JSON.parse(input);
  } catch (e) {
    return null;
  }
}

/**
 * Reads a map forgivingly (R-MAP3): a version 1 to 3 template mapping reads as a map from
 * columns to a record; a broken column or default is skipped and counted, as is a second
 * column for a target already filled. Keys this module does not know (a template's row rules)
 * are kept. Returns { document, skipped }.
 */
export function parseMap(input) {
  const raw = isObject(parsedInput(input)) ? parsedInput(input) : {};
  const from = { kind: FROM_KINDS.includes(raw.from && raw.from.kind) ? raw.from.kind : 'columns' };
  if (from.kind === 'record' && nonBlank(raw.from.object)) {
    from.object = raw.from.object;
  }
  if (from.kind === 'json') {
    if (nonBlank(raw.from.label)) {
      from.label = raw.from.label;
    }
    if (isObject(raw.from.sample) && JSON.stringify(raw.from.sample).length <= MAX_SAMPLE) {
      from.sample = raw.from.sample;
    }
  }
  const to = { kind: TO_KINDS.includes(raw.to && raw.to.kind) ? raw.to.kind : 'record' };
  if (to.kind === 'record' && raw.to && nonBlank(raw.to.object)) {
    to.object = raw.to.object;
  }
  let skipped = 0;
  const seen = new Set();
  const columns = [];
  (Array.isArray(raw.columns) ? raw.columns : []).forEach((entry) => {
    const column = cleanColumn(entry, from.kind, to.kind);
    if (!column || seen.has(lower(column.target)) || columns.length >= MAX_COLUMNS) {
      skipped += 1;
      return;
    }
    seen.add(lower(column.target));
    columns.push(column);
  });
  const defaults = [];
  (Array.isArray(raw.defaults) ? raw.defaults : []).forEach((entry) => {
    if (!isObject(entry) || !nonBlank(entry.target) || defaults.length >= MAX_DEFAULTS) {
      skipped += 1;
      return;
    }
    defaults.push({ target: entry.target, value: text(entry.value) });
  });
  const document = { ...raw, version: VERSION, from, to, columns, defaults };
  const match = cleanMatch(raw.match);
  if (match) {
    document.match = match;
  } else {
    delete document.match;
  }
  return { document, skipped };
}

/**
 * What stops a map saving, as { code, args } (the server refuses the same, R-MAP3):
 * unreadable, tooManyColumns, tooManyDefaults, noTarget, noSource, badPath, valueTooLong,
 * targetTwice, badLookup, badMatch, sampleTooBig. Steps and the record target's object are
 * checked by the server (DataTransform.problems, describe).
 */
export function problems(document) {
  const found = [];
  const doc = isObject(document) ? document : {};
  const fromKind = (doc.from && doc.from.kind) || 'columns';
  const toKind = (doc.to && doc.to.kind) || 'record';
  const version = doc.version;
  if (
    !Number.isInteger(version) ||
    version < 1 ||
    version > VERSION ||
    (doc.from !== undefined && (!isObject(doc.from) || !FROM_KINDS.includes(fromKind))) ||
    (doc.to !== undefined && (!isObject(doc.to) || !TO_KINDS.includes(toKind))) ||
    (doc.columns !== undefined && !Array.isArray(doc.columns)) ||
    (doc.defaults !== undefined && !Array.isArray(doc.defaults))
  ) {
    return [{ code: 'unreadable', args: [] }];
  }
  const columns = doc.columns || [];
  const defaults = doc.defaults || [];
  if (columns.length > MAX_COLUMNS) {
    found.push({ code: 'tooManyColumns', args: [MAX_COLUMNS] });
  }
  if (defaults.length > MAX_DEFAULTS) {
    found.push({ code: 'tooManyDefaults', args: [MAX_DEFAULTS] });
  }
  if (doc.from && doc.from.sample && JSON.stringify(doc.from.sample).length > MAX_SAMPLE) {
    found.push({ code: 'sampleTooBig', args: [MAX_SAMPLE] });
  }
  if (defaults.some((entry) => !isObject(entry) || !nonBlank(entry.target))) {
    found.push({ code: 'unreadable', args: [] });
  }
  const seen = new Set();
  columns.forEach((entry, index) => {
    const number = index + 1;
    const column = isObject(entry) ? entry : {};
    if (!nonBlank(column.target)) {
      found.push({ code: 'noTarget', args: [number] });
      return;
    }
    if (column.required !== undefined && typeof column.required !== 'boolean') {
      found.push({ code: 'badColumn', args: [number, column.target] });
    }
    if (!nonBlank(column.source) && typeof column.value !== 'string') {
      found.push({ code: 'noSource', args: [number, column.target] });
    }
    if (
      (toKind === 'json' && !isPath(column.target)) ||
      (fromKind === 'json' && nonBlank(column.source) && !isPath(column.source))
    ) {
      found.push({ code: 'badPath', args: [number, column.target] });
    }
    if (typeof column.value === 'string' && column.value.length > MAX_TEXT) {
      found.push({ code: 'valueTooLong', args: [number, MAX_TEXT] });
    }
    const lookup = column.lookup;
    if (
      lookup !== undefined &&
      lookup !== null &&
      (!cleanLookup(lookup) ||
        (lookup.notFound !== undefined &&
          lookup.notFound !== null &&
          !NOT_FOUND.includes(lookup.notFound)))
    ) {
      found.push({ code: 'badLookup', args: [number, column.target] });
    }
    if (seen.has(lower(column.target))) {
      found.push({ code: 'targetTwice', args: [column.target] });
    }
    seen.add(lower(column.target));
  });
  if (doc.match !== undefined) {
    const match = cleanMatch(doc.match);
    const needsField = match && (match.by === 'field' || match.by === 'externalId');
    if (
      !match ||
      (needsField && !match.field) ||
      (doc.match.several !== undefined && !match.several) ||
      (doc.match.none !== undefined && !match.none)
    ) {
      found.push({ code: 'badMatch', args: [] });
    }
  }
  return found;
}

/** The document as stored: stable key order, `guessed` marks and empty parts left out. */
export function serialize(document) {
  const doc = document || {};
  const ordered = { version: VERSION, from: doc.from || { kind: 'columns' } };
  ordered.to = doc.to || { kind: 'record' };
  ordered.columns = (doc.columns || []).map((column) => {
    const stored = { ...column };
    delete stored.guessed;
    if (!stored.transforms || stored.transforms.length === 0) {
      delete stored.transforms;
    }
    return stored;
  });
  ordered.defaults = (doc.defaults || []).filter((entry) => nonBlank(entry.value));
  if (doc.match) {
    ordered.match = doc.match;
  }
  Object.keys(doc).forEach((key) => {
    if (!(key in ordered) && key !== 'match') {
      ordered[key] = doc[key];
    }
  });
  return JSON.stringify(ordered);
}

// ---- preview checks (R-MAP4) ----------------------------------------------------------------

function validDate(year, month, day) {
  const date = new Date(Date.UTC(Number(year), Number(month) - 1, Number(day)));
  return (
    date.getUTCFullYear() === Number(year) &&
    date.getUTCMonth() === Number(month) - 1 &&
    date.getUTCDate() === Number(day)
  );
}

/**
 * The problems one value would have in a field ({ dataType, length, required, picklistValues }),
 * as codes: required (blank and required), tooLong, notNumber, notDate, notBoolean, notInList.
 */
export function checkValue(value, field) {
  const info = field || {};
  const given = text(value);
  if (given.trim() === '') {
    return info.required ? ['required'] : [];
  }
  const type = lower(info.dataType);
  const flags = [];
  if ((TEXT_TYPES.includes(type) || !type) && info.length > 0 && given.length > info.length) {
    flags.push('tooLong');
  }
  if (NUMBER_TYPES.includes(type) && !NUMBER.test(given.trim().replace(/,/g, ''))) {
    flags.push('notNumber');
  }
  if (type === 'date' || type === 'datetime') {
    const found = (type === 'date' ? DATE : DATETIME).exec(given.trim());
    if (!found || !validDate(found[1], found[2], found[3])) {
      flags.push('notDate');
    }
  }
  if (type === 'boolean' && !BOOLEAN_TEXT.includes(lower(given))) {
    flags.push('notBoolean');
  }
  const options = info.picklistValues || [];
  if ((type === 'picklist' || type === 'multipicklist') && options.length > 0) {
    const known = new Set(options.flatMap((option) => [lower(option.value), lower(option.label)]));
    const chosen = type === 'multipicklist' ? given.split(';') : [given];
    if (chosen.some((each) => !known.has(lower(each)))) {
      flags.push('notInList');
    }
  }
  return flags;
}

/**
 * The record or body one sample produces, row by row, with each value's flags. `fields` maps a
 * target (`Record.Email`, or a JSON path) to its field information; `sample` is one sample of
 * MapController.previewMap ({ values: [{ target, value, lookup }] }). A required field of the
 * object that nothing fills is listed too, blank and flagged.
 */
export function previewRows(document, fields, sample) {
  const info = fields || {};
  const columns = (document && document.columns) || [];
  const byTarget = new Map(((sample && sample.values) || []).map((entry) => [entry.target, entry]));
  const rows = [];
  const listed = new Set();
  const add = (target, required) => {
    const field = info[target] || {};
    const entry = byTarget.get(target) || {};
    const flags = checkValue(entry.value, {
      ...field,
      required: Boolean(field.required || required)
    });
    if (entry.lookup === 'none' || entry.lookup === 'several') {
      flags.push(entry.lookup === 'none' ? 'lookupNone' : 'lookupSeveral');
    }
    listed.add(lower(target));
    rows.push({ target, label: field.label || target, value: text(entry.value), flags });
  };
  columns.forEach((column) => add(column.target, column.required));
  byTarget.forEach((entry, target) => {
    if (!listed.has(lower(target))) {
      add(target, false);
    }
  });
  Object.keys(info).forEach((target) => {
    if (info[target].required && !listed.has(lower(target))) {
      add(target, true);
    }
  });
  return rows;
}

/**
 * Check Before Running (R-MAP4): every flagged value of every sample, by field, as
 * [{ target, label, flags: { code: count }, samples: [numbers, 1 based, at most 5] }], fields
 * with problems only, in the map's order.
 */
export function summarize(document, fields, samples) {
  const byTarget = new Map();
  (samples || []).forEach((sample, index) => {
    previewRows(document, fields, sample).forEach((row) => {
      if (row.flags.length === 0) {
        return;
      }
      if (!byTarget.has(row.target)) {
        byTarget.set(row.target, { target: row.target, label: row.label, flags: {}, samples: [] });
      }
      const entry = byTarget.get(row.target);
      row.flags.forEach((flag) => {
        entry.flags[flag] = (entry.flags[flag] || 0) + 1;
      });
      if (entry.samples.length < 5) {
        entry.samples.push(index + 1);
      }
    });
  });
  const order = ((document && document.columns) || []).map((column) => lower(column.target));
  const rank = (entry) => {
    const at = order.indexOf(lower(entry.target));
    return at < 0 ? order.length : at;
  };
  return Array.from(byTarget.values())
    .map((entry, index) => ({ entry, index }))
    .sort((a, b) => rank(a.entry) - rank(b.entry) || a.index - b.index)
    .map(({ entry }) => entry);
}

// ---- sentences --------------------------------------------------------------------------------

/**
 * A column in one sentence (design Section 2.4): "Email gets profile, email, then trimmed, then
 * lower case." `words` holds the screen's text: gets ("{0} gets {1}"), fixed ("{0} is always
 * {1}"), then (", then {0}"), end ("."), and steps, one phrase per step `op`.
 */
export function columnSentence(targetLabel, sourceLabel, column, words) {
  const w = words || {};
  const start =
    typeof (column && column.value) === 'string' && !nonBlank(column.source)
      ? format(w.fixed, targetLabel, column.value)
      : format(w.gets, targetLabel, sourceLabel);
  const steps = ((column && column.transforms) || [])
    .map((step) => (w.steps && w.steps[step.op]) || step.op)
    .map((phrase) => format(w.then, phrase))
    .join('');
  return `${start}${steps}${w.end || ''}`;
}

// ---- Super Importer (MAP-04) ------------------------------------------------------------------

/**
 * Save as Map: a Super Importer mapping as a map from file columns to the template's record
 * (`objectName`, empty for a people template). Columns set to Do Not Load (`ignored` values) are
 * left out; steps, lookups and empty-cell clearing are kept. Row rules stay with the template.
 */
export function fromImportMapping(mappingJson, objectName, ignored) {
  const skip = new Set((ignored || []).map(lower));
  const { document } = parseMap(mappingJson);
  const to = { kind: 'record' };
  if (nonBlank(objectName)) {
    to.object = objectName;
  }
  return {
    version: VERSION,
    from: { kind: 'columns' },
    to,
    columns: document.columns.filter((column) => !skip.has(lower(column.target))),
    defaults: document.defaults
  };
}

/**
 * Use a Saved Map: copies a map's columns onto a file's columns by source name (capitals and
 * surrounding spaces ignored). A file column the map does not name keeps its choice. A map
 * column is not used when the file has no such column (`missing`), or when this template cannot
 * load its target or it has no source (`unusable`). A lookup's field is kept only when
 * `lookupChoices[target]` (when given) offers it. Returns { columns, applied, missing, unusable }.
 */
export function applyToColumns(fileColumns, document, allowedTargets, lookupChoices) {
  const allowed = new Set((allowedTargets || []).map(lower));
  const choices = lookupChoices || {};
  const bySource = new Map();
  let unusable = 0;
  ((document && document.columns) || []).forEach((column) => {
    if (!nonBlank(column.source) || !allowed.has(lower(column.target))) {
      unusable += 1;
      return;
    }
    bySource.set(lower(column.source), column);
  });
  const usedSources = new Set();
  let applied = 0;
  const columns = (fileColumns || []).map((fileColumn) => {
    const mapped = bySource.get(lower(fileColumn.source));
    if (!mapped) {
      return fileColumn;
    }
    usedSources.add(lower(fileColumn.source));
    applied += 1;
    const lookupField = mapped.lookupField || (mapped.lookup && mapped.lookup.field);
    const offered = choices[mapped.target];
    const keepLookup = lookupField && (!offered || offered.map(lower).includes(lower(lookupField)));
    const next = {
      ...fileColumn,
      target: mapped.target,
      transforms: mapped.transforms || [],
      guessed: false,
      blankClears: Boolean(mapped.blankClears)
    };
    next.lookupField = keepLookup ? lookupField : undefined;
    return next;
  });
  const missing = Array.from(bySource.keys()).filter((key) => !usedSources.has(key)).length;
  return { columns, applied, missing, unusable };
}
