/**
 * The Ask Pipeline board's arithmetic, with no framework in it (G-26, canonical model Section 25O,
 * plan Section 9.9): the stages become columns in list order, each with the database's exact totals
 * (R-SO6) and the cards that belong in it, asks at a stage no longer in the list gather in one
 * extra column (R-SO2), and each card learns how many days it has sat in its stage (R-SO4).
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module. Dates arrive
 * as ISO date strings ("2026-10-31"), the shape the server sends.
 */

/** The key of the column that holds asks at a stage not in the list. */
export const OTHER_COLUMN = '__other__';

const DAY_MS = 24 * 60 * 60 * 1000;

/** Whole days from one ISO date to another; null when either is missing or unreadable. */
export function daysBetween(fromIso, toIso) {
  if (!fromIso || !toIso) {
    return null;
  }
  const from = Date.parse(`${fromIso}T00:00:00Z`);
  const to = Date.parse(`${toIso}T00:00:00Z`);
  if (Number.isNaN(from) || Number.isNaN(to)) {
    return null;
  }
  return Math.max(0, Math.round((to - from) / DAY_MS));
}

/**
 * The board's columns.
 *
 * @param {string[]} stages the org's stages, in order
 * @param {{stage: string, count: number, amount: number}[]} totals open asks by stage
 * @param {object[]} cards the open asks drawn as cards, each with a `stage`
 * @param {string} today today's ISO date
 * @returns {object[]} one column per stage, then the other-stages column when it has asks:
 *   `{key, stage, isOther, count, amount, cards}`, each card with `daysInStage` added
 */
export function buildColumns(stages, totals, cards, today) {
  const known = new Map();
  const columns = (stages || []).map((stage) => {
    const column = { key: stage, stage, isOther: false, count: 0, amount: 0, cards: [] };
    known.set(stage, column);
    return column;
  });
  const other = { key: OTHER_COLUMN, stage: null, isOther: true, count: 0, amount: 0, cards: [] };
  (totals || []).forEach((total) => {
    const column = known.get(total.stage) || other;
    column.count += total.count || 0;
    column.amount += total.amount || 0;
  });
  (cards || []).forEach((card) => {
    const column = known.get(card.stage) || other;
    column.cards.push({ ...card, daysInStage: daysBetween(card.stageChangedDate, today) });
  });
  if (other.count > 0 || other.cards.length > 0) {
    columns.push(other);
  }
  return columns;
}

/**
 * The same open asks as rows for the list view, in stage order (list order, then the stages not in
 * the list), soonest target date first within a stage, as the server sorted them.
 */
export function listRows(columns) {
  const rows = [];
  (columns || []).forEach((column) => {
    column.cards.forEach((card) => rows.push(card));
  });
  return rows;
}
