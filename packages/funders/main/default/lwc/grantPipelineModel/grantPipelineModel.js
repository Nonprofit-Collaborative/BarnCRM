/**
 * The Grant Pipeline tab's arithmetic, with no framework in it (F-01, canonical model 29ZH, plan
 * Section 9.9): the open stages become columns in order, each with the database's exact totals and
 * the cards that belong in it, and the upcoming application deadlines become rows that know how
 * many days are left and whether they are overdue (R-GN7).
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module. Dates arrive
 * as ISO date strings ("2026-11-02"), the shape the server sends.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/** Whole days from one ISO date to another (negative when `toIso` is earlier); null when unreadable. */
export function daysBetween(fromIso, toIso) {
  if (!fromIso || !toIso) {
    return null;
  }
  const from = Date.parse(`${fromIso}T00:00:00Z`);
  const to = Date.parse(`${toIso}T00:00:00Z`);
  if (Number.isNaN(from) || Number.isNaN(to)) {
    return null;
  }
  return Math.round((to - from) / DAY_MS);
}

/**
 * The board's columns, one per open stage.
 *
 * @param {string[]} stages the open stages, in order
 * @param {{stage: string, count: number, amount: number}[]} totals open grants by stage
 * @param {object[]} cards the open grants drawn as cards, each with a `stage`
 * @returns {object[]} `{key, stage, count, amount, cards}`; a card at a stage not in the list is
 *   left out (the server sends only open stages)
 */
export function buildColumns(stages, totals, cards) {
  const byStage = new Map();
  const columns = (stages || []).map((stage) => {
    const column = { key: stage, stage, count: 0, amount: 0, cards: [] };
    byStage.set(stage, column);
    return column;
  });
  (totals || []).forEach((total) => {
    const column = byStage.get(total.stage);
    if (column) {
      column.count += total.count || 0;
      column.amount += total.amount || 0;
    }
  });
  (cards || []).forEach((card) => {
    const column = byStage.get(card.stage);
    if (column) {
      column.cards.push({ ...card });
    }
  });
  return columns;
}

/**
 * The upcoming application deadlines, soonest first, each with `daysLeft` (negative when past)
 * and `overdue`.
 *
 * @param {object[]} grants grants with a `deadline`
 * @param {string} today today's ISO date
 * @returns {object[]} copies of the grants, sorted by deadline then name
 */
export function deadlineRows(grants, today) {
  return (grants || [])
    .filter((grant) => grant && grant.deadline)
    .map((grant) => {
      const daysLeft = daysBetween(today, grant.deadline);
      return { ...grant, daysLeft, overdue: daysLeft !== null && daysLeft < 0 };
    })
    .sort(
      (a, b) =>
        a.deadline.localeCompare(b.deadline) || String(a.name || '').localeCompare(b.name || '')
    );
}

/**
 * The stages a grant can move to from where it is: every stage but its own.
 *
 * @param {string[]} allStages every stage, in order
 * @param {string} current the grant's stage
 */
export function moveTargets(allStages, current) {
  return (allStages || []).filter((stage) => stage !== current);
}
