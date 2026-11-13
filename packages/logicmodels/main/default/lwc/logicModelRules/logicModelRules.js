/**
 * The Logic Model Builder's rules, framework-free (plan 9.9): no lightning or @salesforce imports,
 * so a WordPress block or Node can reuse them. The platform enforces the same chain with validation
 * rules on the stage rank (canonical model R-LL2, R-IN1); this module only decides what the builder
 * offers and shows.
 *
 * A model is plain JSON, as LogicModelBuilderController returns it:
 * { elements: [{ id, name, type, term, sortOrder }], links: [{ id, fromId, toId, assumption }],
 *   indicators: [{ id, elementId, betterWhen, baselineValue, periods: [{ startDate, endDate,
 *   targetValue, resultValue }] }] }
 */
import { escapeHtml } from 'c/barnFormat';

/**
 * The seven columns, in order, as configuration. `rank` matches the Stage_Rank__c formula on
 * Logic_Model_Element__c; `measured` says whether the column takes indicators.
 */
export const STAGES = Object.freeze([
  { key: 'Input', type: 'Input', term: null, rank: 1, measured: false },
  { key: 'Activity', type: 'Activity', term: null, rank: 2, measured: false },
  { key: 'Output', type: 'Output', term: null, rank: 3, measured: true },
  { key: 'Outcome_Short', type: 'Outcome', term: 'Short Term', rank: 4, measured: true },
  {
    key: 'Outcome_Intermediate',
    type: 'Outcome',
    term: 'Intermediate Term',
    rank: 5,
    measured: true
  },
  { key: 'Outcome_Long', type: 'Outcome', term: 'Long Term', rank: 6, measured: true },
  { key: 'Impact', type: 'Impact', term: null, rank: 7, measured: false }
]);

/** The column an element sits in, or undefined for an unknown type. */
export function stageOf(element) {
  if (!element) {
    return undefined;
  }
  if (element.type === 'Outcome') {
    return STAGES.find((stage) => stage.term === element.term) || STAGES[3];
  }
  return STAGES.find((stage) => stage.type === element.type);
}

/** The column with this key. */
export function stageByKey(key) {
  return STAGES.find((stage) => stage.key === key);
}

/** The element's rank, from 1 (input) to 7 (impact); 0 when unknown. */
export function rankOf(element) {
  const stage = stageOf(element);
  return stage ? stage.rank : 0;
}

/** True when an arrow may go from one element to the other: forward only (R-LL2). */
export function canLink(from, to) {
  return Boolean(from && to) && from.id !== to.id && rankOf(to) > rankOf(from);
}

/**
 * The arrows that would point backward if this element moved to the column `stageKey` (R-LL2):
 * each { id, fromName, toName }, in the model's order. Empty when the move keeps every arrow
 * forward. LogicModelService.saveElement refuses the same move.
 */
export function backwardLinks(model, elementId, stageKey) {
  const stage = stageByKey(stageKey);
  const elements = (model && model.elements) || [];
  const byId = new Map(elements.map((element) => [element.id, element]));
  if (!stage || !byId.has(elementId)) {
    return [];
  }
  return liveLinks(model)
    .filter((link) => {
      if (link.fromId === elementId) {
        return stage.rank >= rankOf(byId.get(link.toId));
      }
      return link.toId === elementId && rankOf(byId.get(link.fromId)) >= stage.rank;
    })
    .map((link) => ({
      id: link.id,
      fromName: byId.get(link.fromId).name,
      toName: byId.get(link.toId).name
    }));
}

/** True when the element takes indicators: outputs and outcomes (R-IN1). */
export function takesIndicators(element) {
  const stage = stageOf(element);
  return Boolean(stage && stage.measured);
}

function byOrder(a, b) {
  const left = a.sortOrder == null ? Number.MAX_SAFE_INTEGER : a.sortOrder;
  const right = b.sortOrder == null ? Number.MAX_SAFE_INTEGER : b.sortOrder;
  if (left !== right) {
    return left - right;
  }
  return String(a.name || '').localeCompare(String(b.name || ''));
}

/** The seven columns, each with its elements in order. */
export function columns(model) {
  const elements = (model && model.elements) || [];
  return STAGES.map((stage) => ({
    ...stage,
    elements: elements.filter((element) => stageOf(element) === stage).sort(byOrder)
  }));
}

/** Arrows with both ends in the model; a link with an end deleted elsewhere is left out. */
export function liveLinks(model) {
  const ids = new Set(((model && model.elements) || []).map((element) => element.id));
  return ((model && model.links) || []).filter(
    (link) => ids.has(link.fromId) && ids.has(link.toId)
  );
}

/** The elements an arrow from this one may reach and does not reach yet (R-LL2, R-LL3). */
export function linkTargets(model, fromId) {
  const elements = (model && model.elements) || [];
  const from = elements.find((element) => element.id === fromId);
  const taken = new Set(
    liveLinks(model)
      .filter((link) => link.fromId === fromId)
      .map((link) => link.toId)
  );
  return elements
    .filter((element) => canLink(from, element) && !taken.has(element.id))
    .sort((a, b) => rankOf(a) - rankOf(b) || byOrder(a, b));
}

/**
 * What usually needs attention, as codes the builder turns into words:
 * `emptyStage` (a column other than inputs with nothing in it), `noArrowIn` and `noArrowOut` (a
 * part not linked; an input needs no arrow in, an impact no arrow out) and `noIndicator` (an
 * outcome no indicator measures). Empty outcome terms are one finding: no outcome at all.
 */
export function findings(model) {
  const result = [];
  const cols = columns(model);
  const outcomes = cols.filter((col) => col.type === 'Outcome');
  for (const col of cols) {
    if (col.type === 'Outcome' || col.type === 'Input' || col.elements.length) {
      continue;
    }
    result.push({ code: 'emptyStage', stage: col.key });
  }
  if (outcomes.every((col) => col.elements.length === 0)) {
    result.push({ code: 'emptyStage', stage: 'Outcome' });
  }
  const links = liveLinks(model);
  const measured = new Set(((model && model.indicators) || []).map((item) => item.elementId));
  for (const col of cols) {
    for (const element of col.elements) {
      if (col.type !== 'Input' && !links.some((link) => link.toId === element.id)) {
        result.push({ code: 'noArrowIn', elementId: element.id, name: element.name });
      }
      if (col.type !== 'Impact' && !links.some((link) => link.fromId === element.id)) {
        result.push({ code: 'noArrowOut', elementId: element.id, name: element.name });
      }
      if (col.type === 'Outcome' && !measured.has(element.id)) {
        result.push({ code: 'noIndicator', elementId: element.id, name: element.name });
      }
    }
  }
  return result;
}

function toNumber(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

/**
 * A period's progress (R-IN2): `none` without a target and a result; `met` when the result is at
 * or beyond the target in the indicator's direction; otherwise `partial`, with the percent of the
 * way from the baseline (or zero) to the target, between 0 and 99.
 */
export function progress(indicator, period) {
  const target = toNumber(period && period.targetValue);
  const result = toNumber(period && period.resultValue);
  if (target === null || result === null) {
    return { state: 'none', percent: null };
  }
  const lower = indicator && indicator.betterWhen === 'Lower';
  if (lower ? result <= target : result >= target) {
    return { state: 'met', percent: 100 };
  }
  const baseline = toNumber(indicator && indicator.baselineValue);
  const start = baseline === null ? 0 : baseline;
  const span = target - start;
  if (span === 0 || (lower ? span > 0 : span < 0)) {
    return { state: 'partial', percent: 0 };
  }
  const percent = Math.floor(((result - start) / span) * 100);
  return { state: 'partial', percent: Math.max(0, Math.min(99, percent)) };
}

/** True when another period of the indicator has the same start and end dates (R-IP2). */
export function samePeriodExists(indicator, period) {
  return ((indicator && indicator.periods) || []).some(
    (other) =>
      other.id !== period.id &&
      other.startDate === period.startDate &&
      other.endDate === period.endDate
  );
}

/**
 * The new sort orders after moving one element up (-1) or down (+1) in its column: every
 * element of the column numbered 10, 20, 30 in its new order. Empty when it cannot move.
 */
export function moveOrders(model, elementId, direction) {
  const element = ((model && model.elements) || []).find((item) => item.id === elementId);
  if (!element) {
    return [];
  }
  const stage = stageOf(element);
  const column = columns(model).find((col) => col === stage || col.key === stage.key);
  const list = column ? column.elements.slice() : [];
  const index = list.findIndex((item) => item.id === elementId);
  const target = index + direction;
  if (target < 0 || target >= list.length) {
    return [];
  }
  [list[index], list[target]] = [list[target], list[index]];
  return list.map((item, position) => ({ id: item.id, sortOrder: (position + 1) * 10 }));
}

/** True when indicators measure the element, which keeps it in a measured column (R-IN1). */
export function hasIndicators(model, elementId) {
  return ((model && model.indicators) || []).some((indicator) => indicator.elementId === elementId);
}

/**
 * True when a drag may take the element into the column `stageKey` (DnD-2): any column, except
 * that an element with indicators stays in Outputs or an Outcomes column, as the Edit form's
 * Column list offers. Backward arrows are checked on the drop, so the refusal can name them.
 */
export function canMoveTo(model, elementId, stageKey) {
  const stage = stageByKey(stageKey);
  return Boolean(stage) && (stage.measured || !hasIndicators(model, elementId));
}

/**
 * The new sort orders of the column `stageKey` once the element is put at `toIndex` among the
 * column's other elements (a drag drop, DnD-2): every element numbered 10, 20, 30 in its new
 * order. The element is placed whichever column it is in now.
 */
export function dropOrders(model, elementId, stageKey, toIndex) {
  const column = columns(model).find((col) => col.key === stageKey);
  const rest = (column ? column.elements : []).filter((item) => item.id !== elementId);
  const at = Number.isInteger(toIndex) ? Math.max(0, Math.min(toIndex, rest.length)) : rest.length;
  const ids = rest.map((item) => item.id);
  ids.splice(at, 0, elementId);
  return ids.map((id, position) => ({ id, sortOrder: (position + 1) * 10 }));
}

/** The sort order for a new element added at the end of a column. */
export function nextOrder(model, stageKey) {
  const column = columns(model).find((col) => col.key === stageKey);
  const orders = (column ? column.elements : []).map((item) => item.sortOrder || 0);
  return (orders.length ? Math.max(...orders) : 0) + 10;
}

// ------------------------------------------------------------------- sources (L-03, R-IN3)

/** Where an indicator's results come from, as Indicator__c.Source__c holds it. */
export const SOURCES = Object.freeze({ MANUAL: 'Manual', IMPORT: 'Import', COMPUTED: 'Computed' });

/** What a computed source works out, as its definition holds it (R-IN4). */
export const FUNCTIONS = Object.freeze({ COUNT: 'count', SUM: 'sum', UNIQUE: 'unique' });

/** True when the indicator's results are worked out by the refresh, never typed. */
export function isComputed(indicator) {
  return Boolean(indicator) && indicator.source === SOURCES.COMPUTED;
}

/**
 * True when a source draft can be saved: any source but Computed as it is; Computed with a saved
 * query, a date field and what to work out, plus a field for a sum or a unique count.
 */
export function sourceReady(draft) {
  if (!draft || !Object.values(SOURCES).includes(draft.source)) {
    return false;
  }
  if (draft.source !== SOURCES.COMPUTED) {
    return true;
  }
  if (!draft.queryId || !draft.dateField || !Object.values(FUNCTIONS).includes(draft.function)) {
    return false;
  }
  return draft.function === FUNCTIONS.COUNT || Boolean(draft.field);
}

/**
 * The results sheet's columns, in order. Period Id, Target, Result and Notes are the columns the
 * shipped Import template Indicator Results reads (R-IN3), so their headers never change; the
 * others are there for the person filling it in and are ignored by the import.
 */
export const RESULTS_SHEET_COLUMNS = Object.freeze([
  { label: 'Period Id', path: 'periodId' },
  { label: 'Logic Model', path: 'model' },
  { label: 'Part', path: 'part' },
  { label: 'Indicator', path: 'indicator' },
  { label: 'Unit', path: 'unit' },
  { label: 'Period', path: 'period' },
  { label: 'Start Date', path: 'startDate' },
  { label: 'End Date', path: 'endDate' },
  { label: 'Target', path: 'target' },
  { label: 'Result', path: 'result' },
  { label: 'Notes', path: 'notes' }
]);

/**
 * The results sheet's rows: one per period of every indicator that is not computed, in column
 * order, then the parts' order, the indicators' order and the periods' order.
 */
export function resultsSheetRows(model) {
  const indicators = (model && model.indicators) || [];
  const rows = [];
  for (const column of columns(model)) {
    for (const element of column.elements) {
      for (const indicator of indicators) {
        if (indicator.elementId !== element.id || isComputed(indicator)) {
          continue;
        }
        for (const period of indicator.periods || []) {
          rows.push({
            periodId: period.id,
            model: model.name,
            part: element.name,
            indicator: indicator.name,
            unit: indicator.unit,
            period: period.name,
            startDate: period.startDate,
            endDate: period.endDate,
            target: period.targetValue,
            result: period.resultValue,
            notes: period.notes
          });
        }
      }
    }
  }
  return rows;
}

// ------------------------------------------------------------------- report (L-04, R-IN7)

/** A period's place across indicators: periods with the same start and end dates are one period. */
export function periodKey(period) {
  return `${(period && period.startDate) || ''}|${(period && period.endDate) || ''}`;
}

/**
 * Every period of the model's indicators, once per pair of dates, oldest first. Each takes the
 * name of the first period found with those dates.
 */
export function reportPeriods(model) {
  const byKey = new Map();
  for (const indicator of (model && model.indicators) || []) {
    for (const period of indicator.periods || []) {
      const key = periodKey(period);
      if (!byKey.has(key)) {
        byKey.set(key, {
          key,
          name: period.name,
          startDate: period.startDate,
          endDate: period.endDate
        });
      }
    }
  }
  return [...byKey.values()].sort((a, b) => a.key.localeCompare(b.key));
}

/** The periods a report opens with: the latest four, or fewer when there are fewer. */
export function defaultReportKeys(model, count = 4) {
  return reportPeriods(model)
    .slice(-count)
    .map((period) => period.key);
}

/**
 * The report (R-IN7): the chosen periods oldest first, and one row per indicator in column, then
 * part, then indicator order, with its baseline and, per chosen period, the target, result and
 * progress. An indicator without that period has an empty cell.
 */
export function report(model, keys) {
  const chosen = new Set(keys || []);
  const periods = reportPeriods(model).filter((period) => chosen.has(period.key));
  const indicators = (model && model.indicators) || [];
  const rows = [];
  for (const column of columns(model)) {
    for (const element of column.elements) {
      for (const indicator of indicators) {
        if (indicator.elementId !== element.id) {
          continue;
        }
        rows.push({
          id: indicator.id,
          stage: column.key,
          part: element.name,
          indicator: indicator.name,
          unit: indicator.unit,
          betterWhen: indicator.betterWhen,
          baseline: indicator.baselineValue,
          baselineDate: indicator.baselineDate,
          cells: periods.map((wanted) => {
            const period = (indicator.periods || []).find((item) => periodKey(item) === wanted.key);
            return {
              key: wanted.key,
              found: Boolean(period),
              target: period ? period.targetValue : null,
              result: period ? period.resultValue : null,
              progress: period ? progress(indicator, period) : { state: 'none', percent: null }
            };
          })
        });
      }
    }
  }
  return { periods, rows };
}

/** A progress as words: the Met word, the percent, or nothing. */
export function progressWords(value, words) {
  if (!value || value.state === 'none') {
    return '';
  }
  return value.state === 'met' ? words.met : `${value.percent}%`;
}

/**
 * The report as CSV columns and flat rows for c/findCsv: Column, Part, Indicator, Unit, Better
 * When, Baseline and Baseline Date, then a Target, Result and Progress column per period, each
 * headed with the period's name.
 */
export function reportCsv(built, words) {
  const csvColumns = [
    { label: words.column, path: 'column' },
    { label: words.part, path: 'part' },
    { label: words.indicator, path: 'indicator' },
    { label: words.unit, path: 'unit' },
    { label: words.betterWhen, path: 'betterWhen' },
    { label: words.baseline, path: 'baseline' },
    { label: words.baselineDate, path: 'baselineDate' }
  ];
  built.periods.forEach((period, index) => {
    csvColumns.push(
      { label: `${period.name} ${words.target}`, path: `target${index}` },
      { label: `${period.name} ${words.result}`, path: `result${index}` },
      { label: `${period.name} ${words.progress}`, path: `progress${index}` }
    );
  });
  const rows = built.rows.map((row) => {
    const flat = {
      column: words.stage(row.stage),
      part: row.part,
      indicator: row.indicator,
      unit: row.unit,
      betterWhen: row.betterWhen === 'Lower' ? words.lower : words.higher,
      baseline: row.baseline,
      baselineDate: row.baselineDate
    };
    row.cells.forEach((cell, index) => {
      flat[`target${index}`] = cell.target;
      flat[`result${index}`] = cell.result;
      flat[`progress${index}`] = progressWords(cell.progress, words);
    });
    return flat;
  });
  return { columns: csvColumns, rows };
}

/** Text made safe to place in HTML, from the shared kit. */
export { escapeHtml };

/**
 * The report as one printable HTML page, with its own styles and no scripts, to open in a
 * browser and print or save as PDF. Every value is escaped.
 */
export function reportHtml(built, words) {
  const e = escapeHtml;
  const periodHeads = built.periods
    .map(
      (period) =>
        `<th colspan="3" scope="colgroup">${e(period.name)}<br><span class="dates">${e(
          period.startDate
        )} to ${e(period.endDate)}</span></th>`
    )
    .join('');
  const subHeads = built.periods
    .map(
      () =>
        `<th scope="col">${e(words.target)}</th><th scope="col">${e(words.result)}</th><th scope="col">${e(
          words.progress
        )}</th>`
    )
    .join('');
  const body = built.rows
    .map((row) => {
      const cells = row.cells
        .map(
          (cell) =>
            `<td class="num">${e(cell.target)}</td><td class="num">${e(cell.result)}</td><td>${e(
              progressWords(cell.progress, words)
            )}</td>`
        )
        .join('');
      return `<tr><td>${e(words.stage(row.stage))}</td><td>${e(row.part)}</td><th scope="row">${e(
        row.indicator
      )}${row.unit ? ` <span class="unit">(${e(row.unit)})</span>` : ''}</th><td class="num">${e(
        row.baseline
      )}</td>${cells}</tr>`;
    })
    .join('\n');
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${e(words.title)}</title>
<style>
body { font-family: Arial, Helvetica, sans-serif; color: #181818; margin: 24px; }
h1 { font-size: 20px; margin: 0 0 4px; }
p.meta { color: #444; margin: 0 0 16px; font-size: 13px; }
table { border-collapse: collapse; width: 100%; font-size: 12px; }
th, td { border: 1px solid #999; padding: 4px 6px; text-align: left; vertical-align: top; }
thead th { background: #eee; }
td.num { text-align: right; }
.dates, .unit { font-weight: normal; color: #444; }
@page { size: landscape; margin: 12mm; }
@media print { body { margin: 0; } thead { display: table-header-group; } tr { page-break-inside: avoid; } }
</style>
</head>
<body>
<h1>${e(words.title)}</h1>
<p class="meta">${e(words.meta)}</p>
<table>
<thead>
<tr><th rowspan="2" scope="col">${e(words.column)}</th><th rowspan="2" scope="col">${e(
    words.part
  )}</th><th rowspan="2" scope="col">${e(words.indicator)}</th><th rowspan="2" scope="col">${e(
    words.baseline
  )}</th>${periodHeads}</tr>
<tr>${subHeads}</tr>
</thead>
<tbody>
${body}
</tbody>
</table>
</body>
</html>
`;
}
