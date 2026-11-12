/**
 * The Grid tool's logic (C-41, C-41b), free of any framework so it can be reused off the
 * platform (plan Section 9.9): which saved queries are saved grids, the grid's document, the
 * columns and rows of the main table and of each related record table, and which drafts a
 * save refused. The page (c/gridTool) only draws what these functions return. Dotted paths and
 * {0} templates are read with Find's own helpers (c/findCsv), which are plain JavaScript too.
 */
import { format, valueAt } from 'c/findCsv';

/** The key a saved grid adds to its Find query document; Find ignores it (C-41b). */
export const GRID_KEY = 'grid';
export const GRID_VERSION = 1;

/** Field types a datatable can edit in place, as Find's results grid (C-36, R-SQ10). */
export const EDITABLE_TYPES = new Set([
  'string',
  'email',
  'phone',
  'url',
  'currency',
  'double',
  'integer',
  'percent',
  'date',
  'boolean'
]);

const TABLE_TYPES = {
  boolean: 'boolean',
  currency: 'currency',
  date: 'date-local',
  datetime: 'date',
  double: 'number',
  email: 'email',
  integer: 'number',
  long: 'number',
  percent: 'number',
  phone: 'phone',
  url: 'url'
};

/** The column that names a related record's parent row. */
export const PARENT_COLUMN = '_parentName';

/** Reads a query document, or null when it is not one. */
export function parseDocument(queryJson) {
  try {
    const document = JSON.parse(queryJson);
    return document && typeof document === 'object' && document.object ? document : null;
  } catch {
    return null;
  }
}

/** True when a saved query was saved from the Grid. */
export function isSavedGrid(queryJson) {
  const document = parseDocument(queryJson);
  return Boolean(document && document[GRID_KEY]);
}

/**
 * The saved queries as choices: saved grids first, then other Find queries, each group in the
 * order the server gave (the person's own first).
 */
export function sourceOptions(savedQueries, gridLabel) {
  const grids = [];
  const queries = [];
  for (const query of savedQueries || []) {
    if (isSavedGrid(query.queryJson)) {
      grids.push({ label: format(gridLabel, query.name), value: query.recordId });
    } else {
      queries.push({ label: query.name, value: query.recordId });
    }
  }
  return [...grids, ...queries];
}

/** The document a grid saves: the query, its related record columns, and the grid key. */
export function gridDocument(document, children) {
  const saved = { ...document, [GRID_KEY]: { version: GRID_VERSION } };
  if (children && children.length > 0) {
    saved.children = children;
  } else {
    delete saved.children;
  }
  return JSON.stringify(saved);
}

/**
 * Datatable columns for the given field paths. `fields` is the object's field list from
 * QueryFieldCatalog; `editable` the API names the person may change. A parent field
 * (`Account.Name`) is never editable here.
 */
export function columnsFor(paths, fields, editable) {
  const byName = new Map((fields || []).map((field) => [field.apiName, field]));
  return (paths || []).map((path) => {
    const field = byName.get(path);
    const dataType = field ? field.dataType : undefined;
    const column = {
      label: field ? field.label : path,
      fieldName: path,
      type: TABLE_TYPES[dataType] || 'text'
    };
    if (
      !String(path).includes('.') &&
      editable &&
      editable.has(path) &&
      EDITABLE_TYPES.has(dataType)
    ) {
      column.editable = true;
    }
    return column;
  });
}

/** One flat row a datatable can show: the Id and each path's value. */
export function flatRow(record, paths) {
  const flat = { Id: record.Id };
  for (const path of paths || []) {
    flat[path] = valueAt(record, path);
  }
  return flat;
}

/** The records of one related record column inside a parent row, as the server returns them. */
export function childRecords(row, relationship) {
  const records = row ? row[relationship] : undefined;
  if (Array.isArray(records)) {
    return records;
  }
  return (records && records.records) || [];
}

/**
 * The rows of one related record table: every child of the given parents (all parents when
 * none is selected), each with the name of its parent row.
 */
export function relatedRows(rows, child, selectedIds, parentLabelOf) {
  const selected = new Set(selectedIds || []);
  const result = [];
  for (const row of rows || []) {
    if (selected.size > 0 && !selected.has(row.Id)) {
      continue;
    }
    for (const record of childRecords(row, child.relationship)) {
      const flat = flatRow(record, child.fields);
      flat[PARENT_COLUMN] = parentLabelOf(row);
      result.push(flat);
    }
  }
  return result;
}

/** A parent row's name for the related tables: its Name, else the first chosen field, else its Id. */
export function parentLabel(row, paths) {
  const name = valueAt(row, 'Name');
  if (name !== undefined && name !== null && name !== '') {
    return String(name);
  }
  const first = (paths || [])
    .map((path) => valueAt(row, path))
    .find((value) => value !== undefined && value !== null && value !== '');
  return first === undefined ? row.Id : String(first);
}

/** Drafts merged by record: a later edit of a cell replaces the earlier one. */
export function mergeDrafts(current, incoming) {
  const byId = new Map((current || []).map((draft) => [draft.Id, { ...draft }]));
  for (const draft of incoming || []) {
    byId.set(draft.Id, { ...(byId.get(draft.Id) || {}), ...draft });
  }
  return [...byId.values()];
}

/** The datatable errors for the rows a save refused, and the drafts kept for them. */
export function refusedDrafts(drafts, errors, titleOf) {
  const failed = new Map((errors || []).map((error) => [error.recordId, error.message]));
  const kept = (drafts || []).filter((draft) => failed.has(draft.Id));
  const rows = {};
  for (const draft of kept) {
    rows[draft.Id] = {
      title: titleOf(1),
      messages: [failed.get(draft.Id)],
      fieldNames: Object.keys(draft).filter((name) => name !== 'Id')
    };
  }
  return {
    kept,
    errors:
      kept.length > 0 ? { rows, table: { title: titleOf(kept.length), messages: [] } } : undefined
  };
}
