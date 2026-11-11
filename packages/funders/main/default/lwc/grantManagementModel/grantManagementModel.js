/**
 * The arithmetic of the grant management cards (F-10, F-12; canonical model R-GQ7, R-BL2),
 * framework-free so it ports to BarnCRM for WordPress (plan Section 9.9).
 */

const amount = (value) => {
  return value === null || value === undefined || value === '' ? null : Number(value);
};
const sum = (values) => values.reduce((total, value) => total + (value === null ? 0 : value), 0);

/**
 * The Budget card: each line with what is left of its award, the totals, and how far the totals
 * are from the grant's own amounts (null when they match or there is nothing to compare).
 *
 * @param {object} budget what GrantManagementController.getBudget returns
 * @returns {{lines: object[], totals: object, requestedGap: number|null, awardedGap: number|null, unassigned: number}}
 */
export function budgetView(budget) {
  const source = budget || {};
  const lines = (source.lines || []).map((line) => {
    const awarded = amount(line.awarded);
    const spent = amount(line.spent) || 0;
    return {
      id: line.id,
      name: line.name,
      requested: amount(line.requested),
      awarded,
      spent,
      remaining: awarded === null ? null : awarded - spent,
      overspent: awarded !== null && spent > awarded
    };
  });
  const totals = {
    requested: sum(lines.map((line) => line.requested)),
    awarded: sum(lines.map((line) => line.awarded)),
    spent: sum(lines.map((line) => line.spent))
  };
  const gap = (grantAmount, total, hasAny) => {
    const value = amount(grantAmount);
    return value === null || !hasAny || value === total ? null : value - total;
  };
  return {
    lines,
    totals,
    requestedGap: gap(
      source.amountRequested,
      totals.requested,
      lines.some((line) => line.requested !== null)
    ),
    awardedGap: gap(
      source.amountAwarded,
      totals.awarded,
      lines.some((line) => line.awarded !== null)
    ),
    unassigned: amount(source.unassignedSpent) || 0
  };
}

/**
 * The Checklist card's count of tasks done.
 *
 * @param {object[]} tasks rows with a done flag
 * @returns {{done: number, total: number}}
 */
export function checklistProgress(tasks) {
  const rows = tasks || [];
  return { done: rows.filter((task) => task.done).length, total: rows.length };
}
