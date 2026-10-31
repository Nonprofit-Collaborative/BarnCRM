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

/** The sort order for a new element added at the end of a column. */
export function nextOrder(model, stageKey) {
  const column = columns(model).find((col) => col.key === stageKey);
  const orders = (column ? column.elements : []).map((item) => item.sortOrder || 0);
  return (orders.length ? Math.max(...orders) : 0) + 10;
}
