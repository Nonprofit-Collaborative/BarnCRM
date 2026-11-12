/**
 * Checks a portal template's shape before it is pasted into a Portal record, with the same rules
 * the Salesforce side applies (PortalTemplate.cls). Salesforce also checks every object and field
 * against the org's schema, which this file cannot see; a template that passes here can still be
 * refused there, never the other way round.
 */

export const SCHEMA_VERSION = 1;
const KINDS = ['person', 'related', 'catalog'];
const OPS = ['equals', 'notEquals', 'greaterOrEqual', 'lessOrEqual', 'isBlank', 'isNotBlank'];
const MAX_PAGES = 20;
const MAX_FIELDS = 40;
const KEY = /^[A-Za-z0-9]+$/;
const ORDER = /^[A-Za-z0-9_]+( (ASC|DESC))?$/i;

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/** Each calendar entry names a field on the page; a title and a start are needed. */
function checkCalendar(page, fields, at, problems) {
  if (page.calendar === undefined) {
    return;
  }
  if (!isObject(page.calendar)) {
    problems.push(at + 'calendar needs a title and a start');
    return;
  }
  const onPage = new Set(fields.filter(isObject).map((field) => field.field));
  ['title', 'start', 'end', 'location'].forEach((part) => {
    const path = page.calendar[part];
    if (path !== undefined && !onPage.has(path)) {
      problems.push(at + 'calendar ' + part + ' must be a field on the page');
    }
  });
  if (!page.calendar.title || !page.calendar.start) {
    problems.push(at + 'calendar needs a title and a start');
  }
}

/** A field name, or one parent hop (`Parent__r.Field__c`). */
function isPath(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)?$/.test(value);
}

/** `personScope` narrows a catalog page to records tied to the person (Salesforce checks types). */
function checkScope(page, at, problems) {
  const scope = page.personScope;
  if (scope === undefined) {
    return;
  }
  if (page.kind !== 'catalog') {
    problems.push(at + 'personScope is for catalog pages');
    return;
  }
  if (!isObject(scope)) {
    problems.push(at + 'personScope must be a JSON object');
    return;
  }
  const scopeAt = at + 'personScope ';
  if (!isPath(scope.field)) {
    problems.push(scopeAt + 'field must be a lookup or Id');
  }
  if (typeof scope.object !== 'string' || scope.object === '') {
    problems.push(scopeAt + 'object must be a custom object of this org');
  }
  if (!isPath(scope.personField)) {
    problems.push(scopeAt + 'personField must be a lookup to Contact');
  }
  if (!isPath(scope.valueField)) {
    problems.push(scopeAt + 'valueField must be a lookup to what field names');
  }
  (Array.isArray(scope.where) ? scope.where : []).forEach((test) => {
    if (!isObject(test) || typeof test.field !== 'string' || !OPS.includes(test.op)) {
      problems.push(scopeAt + 'a where test names no field of the object');
    }
  });
}

function checkPage(page, problems) {
  if (!isObject(page)) {
    problems.push('Each page must be a JSON object');
    return;
  }
  if (typeof page.key !== 'string' || !KEY.test(page.key)) {
    problems.push('Each page needs a key of letters and numbers');
    return;
  }
  const at = 'Page ' + page.key + ': ';
  if (!KINDS.includes(page.kind)) {
    problems.push(at + 'kind must be person, related or catalog');
    return;
  }
  if (page.kind !== 'person' && typeof page.object !== 'string') {
    problems.push(at + 'object must be a custom object of this org');
  }
  if (page.kind === 'related' && typeof page.personField !== 'string') {
    problems.push(at + 'personField must be a lookup to Contact');
  }
  // `Parent__r.Contact__c`: the person reached through one parent, read only.
  const viaParent = page.kind === 'related' && String(page.personField).includes('.');
  const fields = Array.isArray(page.fields) ? page.fields : [];
  if (fields.length === 0 || fields.length > MAX_FIELDS) {
    problems.push(at + 'list 1 to ' + MAX_FIELDS + ' fields');
  }
  fields.forEach((field) => {
    if (!isObject(field) || typeof field.field !== 'string' || field.field === '') {
      problems.push(at + 'each field needs a field name');
    } else if (field.edit === true && field.field.includes('.')) {
      problems.push(at + field.field + ' cannot be edited in a portal');
    } else if (field.edit === true && (viaParent || field.field === page.personField)) {
      problems.push(at + field.field + ' cannot be edited in a portal');
    } else if (field.scan === true && field.edit !== true) {
      problems.push(at + field.field + ' can be scanned only as an edited text field');
    }
  });
  checkCalendar(page, fields, at, problems);
  checkScope(page, at, problems);
  if (page.download !== undefined && typeof page.download !== 'boolean') {
    problems.push(at + 'download must be true or false');
  }
  const where = Array.isArray(page.where) ? page.where : [];
  where.forEach((test) => {
    if (!isObject(test) || typeof test.field !== 'string') {
      problems.push(at + 'a where test names no field of the object');
    } else if (!OPS.includes(test.op)) {
      problems.push(at + 'where op ' + test.op + ' is not known');
    } else if (isObject(test.value) || Array.isArray(test.value)) {
      problems.push(at + 'a where value must be text, a number or true or false');
    }
  });
  if (page.kind === 'catalog' && where.length === 0) {
    problems.push(at + 'a catalog page needs at least one where test');
  }
  if (page.search !== undefined && typeof page.search !== 'boolean') {
    problems.push(at + 'search must be true or false');
  }
  if (page.orderBy !== undefined && !ORDER.test(String(page.orderBy).trim())) {
    problems.push(at + 'orderBy must be a field, then ASC or DESC');
  }
  (Array.isArray(page.actions) ? page.actions : []).forEach((action) => {
    const update = action === 'update' && page.kind !== 'catalog' && !viaParent;
    const create = action === 'create' && page.kind === 'related' && !viaParent;
    if (update || create) {
      return;
    }
    if (isObject(action)) {
      if (typeof action.extension !== 'string' || !action.extension.includes('.')) {
        problems.push(at + 'an extension action is named Module.Action');
      }
      return;
    }
    problems.push(at + 'action ' + action + ' is not allowed here');
  });
}

/**
 * @param {string|object} source the template, as JSON text or already parsed
 * @returns {string[]} the problems found; empty when the template's shape is right
 */
export function checkTemplate(source) {
  let template = source;
  if (typeof source === 'string') {
    try {
      template = JSON.parse(source);
    } catch (notJson) {
      return ['The template is not valid JSON'];
    }
  }
  if (!isObject(template)) {
    return ['The template is not valid JSON'];
  }
  const problems = [];
  if (template.schemaVersion !== SCHEMA_VERSION) {
    problems.push('schemaVersion must be ' + SCHEMA_VERSION);
  }
  const pages = Array.isArray(template.pages) ? template.pages : [];
  if (pages.length === 0 || pages.length > MAX_PAGES) {
    problems.push('A template has 1 to ' + MAX_PAGES + ' pages');
  }
  const seen = new Set();
  pages.forEach((page) => {
    if (isObject(page) && seen.has(page.key)) {
      problems.push('Two pages have the key ' + page.key);
    }
    seen.add(isObject(page) ? page.key : undefined);
    checkPage(page, problems);
  });
  return problems;
}
