/**
 * The LWC Builder's definition document (LB-01 to LB-06; ADR-NEXT `NEXT-lwc-builder-module.md`,
 * decision 3; canonical model R-LB1), with no Salesforce dependency so the same logic can serve
 * another platform (plan 9.9).
 *
 * A definition is `{schemaVersion, sections: [{id, title, rows: [{id, columns: [{id, width,
 * blocks: [block]}]}]}]}`. Every change returns a new definition; nothing is changed in place.
 */

export const SCHEMA_VERSION = 1;
export const MAX_FIELDS = 6;
export const BLOCK_TYPES = [
  'fields',
  'relatedList',
  'recordList',
  'chart',
  'text',
  'image',
  'action'
];
export const LAYOUTS = {
  12: [12],
  '6-6': [6, 6],
  '4-4-4': [4, 4, 4],
  '3-3-3-3': [3, 3, 3, 3],
  '8-4': [8, 4],
  '4-8': [4, 8]
};
const FIELD_OPERATORS = ['equals', 'notEquals', 'contains', 'isBlank', 'isNotBlank'];
const API_NAME = /^[A-Za-z][A-Za-z0-9_]{0,79}$/;
const ACTION_NAME = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)?$/;

const clone = (value) => JSON.parse(JSON.stringify(value));

export function emptyDefinition() {
  return { schemaVersion: SCHEMA_VERSION, sections: [] };
}

/** A definition from stored JSON text or an object, with every list present. Never throws. */
export function normalize(raw) {
  let value = raw;
  if (typeof raw === 'string') {
    try {
      value = JSON.parse(raw);
    } catch {
      value = null;
    }
  }
  const sections = value && Array.isArray(value.sections) ? value.sections : [];
  return {
    schemaVersion: SCHEMA_VERSION,
    sections: sections.map((section) => ({
      ...section,
      title: section.title || '',
      rows: (Array.isArray(section.rows) ? section.rows : []).map((row) => ({
        ...row,
        columns: (Array.isArray(row.columns) ? row.columns : []).map((column) => ({
          ...column,
          width: Number(column.width) || 12,
          blocks: Array.isArray(column.blocks) ? column.blocks : []
        }))
      }))
    }))
  };
}

function walk(definition, visit) {
  for (const section of definition.sections) {
    visit(section, 'section', null);
    for (const row of section.rows) {
      visit(row, 'row', section);
      for (const column of row.columns) {
        visit(column, 'column', row);
        for (const block of column.blocks) {
          visit(block, 'block', column);
        }
      }
    }
  }
}

/** The first id with this prefix that the definition does not use yet: s1, r2, c3, b4. */
export function nextId(definition, prefix) {
  const used = new Set();
  walk(definition, (item) => used.add(item.id));
  let n = 1;
  while (used.has(prefix + n)) {
    n += 1;
  }
  return prefix + n;
}

/** Where an item sits: `{item, kind, parent, list}`, or null. */
export function locate(definition, id) {
  let found = null;
  for (const section of definition.sections) {
    if (section.id === id) found = { item: section, kind: 'section', list: definition.sections };
    for (const row of section.rows) {
      if (row.id === id) found = { item: row, kind: 'row', parent: section, list: section.rows };
      for (const column of row.columns) {
        if (column.id === id)
          found = { item: column, kind: 'column', parent: row, list: row.columns };
        for (const block of column.blocks) {
          if (block.id === id)
            found = { item: block, kind: 'block', parent: column, row, list: column.blocks };
        }
      }
    }
  }
  return found;
}

export function addSection(definition, title = '') {
  const next = clone(definition);
  const id = nextId(next, 's');
  next.sections.push({ id, title, rows: [] });
  return { definition: next, id };
}

function columnsFor(definition, layout) {
  const widths = LAYOUTS[layout] || LAYOUTS[12];
  const columns = [];
  for (const width of widths) {
    const probe = { sections: [...definition.sections, { id: '', rows: [{ id: '', columns }] }] };
    columns.push({ id: nextId(probe, 'c'), width, blocks: [] });
  }
  return columns;
}

export function addRow(definition, sectionId, layout = '12') {
  const next = clone(definition);
  const place = locate(next, sectionId);
  if (!place || place.kind !== 'section') return { definition, id: null };
  const id = nextId(next, 'r');
  place.item.rows.push({ id, columns: columnsFor(next, layout) });
  return { definition: next, id };
}

/** The layout key a row's widths match, or '' for a custom one. */
export function layoutOf(row) {
  const widths = row.columns.map((column) => column.width).join('-');
  return Object.keys(LAYOUTS).find((key) => LAYOUTS[key].join('-') === widths) || '';
}

/**
 * Gives a row another layout. Columns keep their blocks in order; when there are fewer columns,
 * the blocks of the columns that go move to the last one kept, so nothing is lost.
 */
export function setRowLayout(definition, rowId, layout) {
  const widths = LAYOUTS[layout];
  const next = clone(definition);
  const place = locate(next, rowId);
  if (!widths || !place || place.kind !== 'row') return definition;
  const row = place.item;
  const kept = row.columns.slice(0, widths.length);
  const dropped = row.columns.slice(widths.length);
  while (kept.length < widths.length) {
    const probe = { sections: [...next.sections, { id: '', rows: [{ id: '', columns: kept }] }] };
    kept.push({ id: nextId(probe, 'c'), width: 0, blocks: [] });
  }
  kept.forEach((column, index) => {
    column.width = widths[index];
  });
  for (const column of dropped) {
    kept[kept.length - 1].blocks.push(...column.blocks);
  }
  row.columns = kept;
  return next;
}

/** A new block of a type, with the properties its form edits. */
export function newBlock(id, type) {
  const block = { id, type, title: '', visibility: { type: 'always' } };
  switch (type) {
    case 'fields':
      return { ...block, fields: [], columns: 1 };
    case 'relatedList':
      return { ...block, object: '', parentField: '', fields: [], orderBy: '', direction: 'asc' };
    case 'recordList':
      return {
        ...block,
        object: '',
        fields: [],
        filterField: '',
        filterOperator: 'equals',
        filterValue: '',
        orderBy: '',
        direction: 'asc'
      };
    case 'chart':
      return { ...block, report: '' };
    case 'text':
      return { ...block, body: '' };
    case 'image':
      return { ...block, url: '', altText: '' };
    case 'action':
      return {
        ...block,
        label: '',
        kind: 'flow',
        actionName: '',
        flowName: '',
        passRecordId: true
      };
    default:
      return block;
  }
}

/** Adds a block of a type to a column, before another block or at the end. */
export function addBlock(definition, columnId, type, beforeId) {
  if (!BLOCK_TYPES.includes(type)) return { definition, id: null };
  const next = clone(definition);
  const place = locate(next, columnId);
  if (!place || place.kind !== 'column') return { definition, id: null };
  const id = nextId(next, 'b');
  insertAt(place.item.blocks, newBlock(id, type), beforeId);
  return { definition: next, id };
}

function insertAt(blocks, block, beforeId) {
  const index = beforeId ? blocks.findIndex((item) => item.id === beforeId) : -1;
  if (index < 0) blocks.push(block);
  else blocks.splice(index, 0, block);
}

/** Moves a block to a column, before another block or at the end. */
export function moveBlock(definition, blockId, columnId, beforeId) {
  if (blockId === beforeId) return definition;
  const next = clone(definition);
  const from = locate(next, blockId);
  const to = locate(next, columnId);
  if (!from || from.kind !== 'block' || !to || to.kind !== 'column') return definition;
  from.list.splice(from.list.indexOf(from.item), 1);
  insertAt(to.item.blocks, from.item, beforeId);
  return next;
}

/**
 * Moves a block one step without dragging: up or down within its column, or to the end of the
 * previous or next column in its row. A move past an edge changes nothing.
 */
export function nudgeBlock(definition, blockId, direction) {
  const place = locate(definition, blockId);
  if (!place || place.kind !== 'block') return definition;
  const columns = place.row.columns;
  const columnIndex = columns.indexOf(place.parent);
  const index = place.list.indexOf(place.item);
  if (direction === 'up' || direction === 'down') {
    const target = direction === 'up' ? index - 1 : index + 1;
    if (target < 0 || target >= place.list.length) return definition;
    const next = clone(definition);
    const list = locate(next, place.parent.id).item.blocks;
    const [moved] = list.splice(index, 1);
    list.splice(target, 0, moved);
    return next;
  }
  const targetColumn = columns[direction === 'left' ? columnIndex - 1 : columnIndex + 1];
  return targetColumn ? moveBlock(definition, blockId, targetColumn.id) : definition;
}

/** Moves a section or a row one place up (-1) or down (1) among its siblings. */
export function moveItem(definition, id, delta) {
  const place = locate(definition, id);
  if (!place || (place.kind !== 'section' && place.kind !== 'row')) return definition;
  const index = place.list.indexOf(place.item);
  const target = index + delta;
  if (target < 0 || target >= place.list.length) return definition;
  const next = clone(definition);
  const list = locate(next, id).list;
  const [moved] = list.splice(index, 1);
  list.splice(target, 0, moved);
  return next;
}

/** Removes a section, a row or a block, with everything inside it. */
export function removeItem(definition, id) {
  const next = clone(definition);
  const place = locate(next, id);
  if (!place || place.kind === 'column') return definition;
  place.list.splice(place.list.indexOf(place.item), 1);
  return next;
}

/** Changes properties of a section or a block. Its id and type never change. */
export function updateItem(definition, id, changes) {
  const next = clone(definition);
  const place = locate(next, id);
  if (!place) return definition;
  const rest = { ...(changes || {}) };
  delete rest.id;
  delete rest.type;
  Object.assign(place.item, rest);
  return next;
}

/** A field list typed as text: names split on commas and spaces, at most six, no repeats. */
export function parseFieldList(text) {
  const names = String(text || '')
    .split(/[\s,]+/)
    .map((name) => name.trim())
    .filter(Boolean);
  return [...new Set(names)].slice(0, MAX_FIELDS);
}

/** A Salesforce-relative address, or https. Never javascript:, data: or protocol-relative. */
export function isSafeImageUrl(url) {
  const value = String(url || '').trim();
  return /^\/(?!\/)/.test(value) || /^https:\/\/[^\s]+$/i.test(value);
}

const blank = (value) => value === undefined || value === null || String(value).trim() === '';

/**
 * Whether a block shows (LB-05; R-LB3). `record` holds the page record's field values by API
 * name (a field the viewer cannot read is simply missing, so it counts as blank);
 * `permissions` the custom permissions the viewer holds, by name.
 */
export function isVisible(rule, record, permissions) {
  if (!rule || !rule.type || rule.type === 'always') return true;
  if (rule.type === 'permission') {
    const held = Boolean(permissions && permissions[rule.permission]);
    return rule.has === false ? !held : held;
  }
  if (rule.type === 'field') {
    const value = record ? record[rule.field] : undefined;
    const expected = blank(rule.value) ? '' : String(rule.value).trim();
    switch (rule.operator) {
      case 'isBlank':
        return blank(value);
      case 'isNotBlank':
        return !blank(value);
      case 'notEquals':
        return (blank(value) ? '' : String(value)) !== expected;
      case 'contains':
        return !blank(value) && String(value).toLowerCase().includes(expected.toLowerCase());
      default:
        return (blank(value) ? '' : String(value)) === expected;
    }
  }
  return true;
}

function blocksOf(definition) {
  const blocks = [];
  walk(definition, (item, kind) => {
    if (kind === 'block') blocks.push(item);
  });
  return blocks;
}

/** The page record fields the visibility rules read, so the renderer loads them. */
export function ruleFields(definition) {
  const names = blocksOf(definition)
    .map((block) => block.visibility)
    .filter((rule) => rule && rule.type === 'field' && API_NAME.test(rule.field || ''))
    .map((rule) => rule.field);
  return [...new Set(names)];
}

/** The custom permissions the visibility rules name, so the renderer checks them once. */
export function rulePermissions(definition) {
  const names = blocksOf(definition)
    .map((block) => block.visibility)
    .filter((rule) => rule && rule.type === 'permission' && API_NAME.test(rule.permission || ''))
    .map((rule) => rule.permission);
  return [...new Set(names)];
}

/**
 * What is wrong with a definition, as `{id, code}` problems the builder shows by its help text:
 * a row whose widths are not 12, and each block missing what it needs. Empty when it can be
 * saved.
 */
export function validate(definition) {
  const problems = [];
  const seen = new Set();
  const need = (condition, id, code) => {
    if (!condition) problems.push({ id, code });
  };
  walk(definition, (item, kind) => {
    need(item.id && !seen.has(item.id), item.id, 'duplicateId');
    seen.add(item.id);
    if (kind === 'row') {
      need(item.columns.reduce((sum, column) => sum + column.width, 0) === 12, item.id, 'rowWidth');
    }
    if (kind !== 'block') return;
    const block = item;
    const hasFields = Array.isArray(block.fields) && block.fields.length > 0;
    switch (block.type) {
      case 'fields':
        need(hasFields, block.id, 'fieldsNeeded');
        break;
      case 'relatedList':
        need(API_NAME.test(block.object || ''), block.id, 'objectNeeded');
        need(API_NAME.test(block.parentField || ''), block.id, 'parentFieldNeeded');
        need(hasFields, block.id, 'fieldsNeeded');
        break;
      case 'recordList':
        need(API_NAME.test(block.object || ''), block.id, 'objectNeeded');
        need(hasFields, block.id, 'fieldsNeeded');
        break;
      case 'chart':
        need(API_NAME.test(block.report || ''), block.id, 'reportNeeded');
        break;
      case 'image':
        need(isSafeImageUrl(block.url), block.id, 'imageUrl');
        need(!blank(block.altText), block.id, 'imageAlt');
        break;
      case 'action':
        need(!blank(block.label), block.id, 'labelNeeded');
        need(
          block.kind === 'quickAction'
            ? ACTION_NAME.test(block.actionName || '')
            : API_NAME.test(block.flowName || ''),
          block.id,
          'actionNeeded'
        );
        break;
      case 'text':
        break;
      default:
        need(false, block.id, 'blockType');
    }
    const rule = block.visibility;
    if (rule && rule.type === 'field') {
      need(
        API_NAME.test(rule.field || '') && FIELD_OPERATORS.includes(rule.operator),
        block.id,
        'ruleField'
      );
    }
    if (rule && rule.type === 'permission') {
      need(API_NAME.test(rule.permission || ''), block.id, 'rulePermission');
    }
  });
  return problems;
}

/** A component key from its name: Donor Snapshot becomes Donor_Snapshot. */
export function keyFromName(name) {
  const key = String(name || '')
    .normalize('NFKD')
    .replace(/[^A-Za-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80);
  if (!key) return '';
  return /^[A-Za-z]/.test(key) ? key : `C_${key}`.slice(0, 80);
}

/** The LWC bundle name for a key: Donor_Snapshot becomes donorSnapshot. */
export function bundleName(key) {
  const words = String(key || 'builtComponent')
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean);
  const camel = words
    .map((word, index) => {
      const first = index === 0 ? word.charAt(0).toLowerCase() : word.charAt(0).toUpperCase();
      return first + word.slice(1);
    })
    .join('');
  return /^[a-z]/.test(camel) ? camel : `c${camel}`;
}

const escapeHtml = (value) =>
  String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
// A comment may not hold "--", which would end it early.
const comment = (value) => `<!-- ${String(value).replace(/-{2,}/g, '-')} -->`;

function ruleNote(rule) {
  if (!rule || rule.type === 'field') {
    return rule ? `Shown when ${rule.field} ${rule.operator} ${rule.value || ''}`.trim() : '';
  }
  if (rule.type === 'permission') {
    return `Shown when the user ${rule.has === false ? 'lacks' : 'holds'} ${rule.permission}`;
  }
  return '';
}

function blockMarkup(block, pad, js) {
  const lines = [];
  const note = ruleNote(block.visibility);
  if (note) lines.push(`${pad}${comment(`${note}: add your own condition`)}`);
  if (block.title)
    lines.push(
      `${pad}<h3 class="slds-text-title_bold slds-var-m-bottom_x-small">${escapeHtml(block.title)}</h3>`
    );
  switch (block.type) {
    case 'fields':
      lines.push(
        `${pad}<lightning-record-view-form record-id={recordId} object-api-name={objectApiName}>`
      );
      for (const field of block.fields || []) {
        lines.push(
          `${pad}    <lightning-output-field field-name="${escapeHtml(field)}"></lightning-output-field>`
        );
      }
      lines.push(`${pad}</lightning-record-view-form>`);
      break;
    case 'text':
      js.text[block.id] = block.body || '';
      lines.push(
        `${pad}<lightning-formatted-rich-text value={richText.${block.id}}></lightning-formatted-rich-text>`
      );
      break;
    case 'image':
      lines.push(
        `${pad}<img src="${escapeHtml(block.url)}" alt="${escapeHtml(block.altText)}" class="slds-max-full-width" />`
      );
      break;
    case 'action':
      if (block.kind === 'quickAction') {
        js.quickAction = true;
        lines.push(
          `${pad}<lightning-button label="${escapeHtml(block.label)}" data-action="${escapeHtml(block.actionName)}" onclick={handleQuickAction}></lightning-button>`
        );
      } else {
        js.flow = true;
        js.flowInputs[block.id] = Boolean(block.passRecordId);
        lines.push(
          `${pad}<lightning-button label="${escapeHtml(block.label)}" data-block="${block.id}" onclick={toggleFlow}></lightning-button>`
        );
        lines.push(`${pad}<template lwc:if={openFlows.${block.id}}>`);
        lines.push(
          `${pad}    <lightning-flow flow-api-name="${escapeHtml(block.flowName)}" flow-input-variables={${block.passRecordId ? 'recordInput' : 'noInput'}}></lightning-flow>`
        );
        lines.push(`${pad}</template>`);
      }
      break;
    default: {
      const what =
        block.type === 'chart'
          ? `Report Chart block: report ${block.report}. Run the report through your own Apex (Reports.ReportManager) and draw it here.`
          : `${block.type === 'relatedList' ? 'Related List' : 'Record List'} block: ${block.object}${
              block.parentField ? ` by ${block.parentField}` : ''
            }, fields ${(block.fields || []).join(', ')}. Wire getRelatedListRecords or your own Apex here.`;
      lines.push(`${pad}${comment(what)}`);
      lines.push(`${pad}<div class="slds-box slds-box_x-small"></div>`);
    }
  }
  return lines;
}

/**
 * The definition as an LWC bundle for a developer (LB-06; ADR-NEXT decision 8):
 * `{bundle, files: [{name, content}]}`. Record Fields, Text, Image and Button blocks become
 * working markup; list and chart blocks a placeholder with a comment, since their data comes
 * from this module's Apex; visibility rules become comments. Nothing is deployed.
 */
export function exportSource(definition, { name, key, objectName } = {}) {
  const bundle = bundleName(key || keyFromName(name));
  const className = bundle.charAt(0).toUpperCase() + bundle.slice(1);
  const js = { text: {}, flowInputs: {}, quickAction: false, flow: false };
  const html = ['<template>'];
  for (const section of normalize(definition).sections) {
    html.push(`    <lightning-card title="${escapeHtml(section.title)}">`);
    html.push('        <div class="slds-var-p-horizontal_small">');
    for (const row of section.rows) {
      html.push('            <div class="slds-grid slds-wrap slds-gutters">');
      for (const column of row.columns) {
        html.push(
          `                <div class="slds-col slds-size_1-of-1 slds-medium-size_${column.width}-of-12">`
        );
        for (const block of column.blocks) {
          html.push('                    <div class="slds-var-m-bottom_small">');
          html.push(...blockMarkup(block, '                        ', js));
          html.push('                    </div>');
        }
        html.push('                </div>');
      }
      html.push('            </div>');
    }
    html.push('        </div>');
    html.push('    </lightning-card>');
  }
  html.push('</template>', '');

  const usesNavigation = js.quickAction;
  const source = [
    "import { LightningElement, api } from 'lwc';",
    ...(usesNavigation ? ["import { NavigationMixin } from 'lightning/navigation';"] : []),
    '',
    `// Exported from the BarnCRM LWC Builder (${escapeHtml(name || bundle)}). This bundle is yours to change,`,
    '// deploy and maintain; it does not depend on BarnCRM.',
    `export default class ${className} extends ${usesNavigation ? 'NavigationMixin(LightningElement)' : 'LightningElement'} {`,
    '    @api recordId;',
    '    @api objectApiName;',
    `    richText = ${JSON.stringify(js.text, null, 4).replace(/\n/g, '\n    ')};`,
    '    openFlows = {};',
    '    noInput = [];'
  ];
  if (js.flow) {
    source.push(
      '',
      '    get recordInput() {',
      "        return this.recordId ? [{ name: 'recordId', type: 'String', value: this.recordId }] : [];",
      '    }',
      '',
      '    toggleFlow(event) {',
      '        const id = event.target.dataset.block;',
      '        this.openFlows = { ...this.openFlows, [id]: !this.openFlows[id] };',
      '    }'
    );
  }
  if (js.quickAction) {
    source.push(
      '',
      '    handleQuickAction(event) {',
      '        this[NavigationMixin.Navigate]({',
      "            type: 'standard__quickAction',",
      '            attributes: { apiName: event.target.dataset.action },',
      '            state: { recordId: this.recordId, objectApiName: this.objectApiName }',
      '        });',
      '    }'
    );
  }
  source.push('}', '');

  const targets = objectName
    ? ['lightning__RecordPage']
    : ['lightning__AppPage', 'lightning__HomePage', 'lightning__RecordPage'];
  const meta = [
    '<?xml version="1.0" encoding="UTF-8" ?>',
    '<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">',
    '    <apiVersion>67.0</apiVersion>',
    '    <isExposed>true</isExposed>',
    `    <masterLabel>${escapeHtml(name || bundle)}</masterLabel>`,
    '    <targets>',
    ...targets.map((target) => `        <target>${target}</target>`),
    '    </targets>',
    '</LightningComponentBundle>',
    ''
  ];
  return {
    bundle,
    files: [
      { name: `${bundle}.html`, content: html.join('\n') },
      { name: `${bundle}.js`, content: source.join('\n') },
      { name: `${bundle}.js-meta.xml`, content: meta.join('\n') }
    ]
  };
}
