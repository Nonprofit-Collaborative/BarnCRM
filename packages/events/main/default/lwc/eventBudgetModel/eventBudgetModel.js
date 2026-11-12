/**
 * An event budget's arithmetic, with no framework in it (EV-23, canonical model 29EV33, 29EV34
 * and R-EXP1, plan Section 9.9): totals by category, funding expected against received, and the
 * net cost. Computed on read, never stored.
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module.
 */

function amount(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

/**
 * Budgeted and actual added up by category, in the order categories first appear, with a total.
 *
 * @param {Array<{category: string, budgeted: number, actual: number}>} expenses the lines
 * @returns {{categories: Array<{category: string, budgeted: number, actual: number}>,
 *   budgeted: number, actual: number}}
 */
export function expenseTotals(expenses) {
  const byCategory = new Map();
  let budgeted = 0;
  let actual = 0;
  (expenses || []).forEach((line) => {
    const key = line.category || '';
    const row = byCategory.get(key) || { category: key, budgeted: 0, actual: 0 };
    row.budgeted += amount(line.budgeted);
    row.actual += amount(line.actual);
    byCategory.set(key, row);
    budgeted += amount(line.budgeted);
    actual += amount(line.actual);
  });
  return { categories: [...byCategory.values()], budgeted, actual };
}

/**
 * Funding expected and received, added up.
 *
 * @param {Array<{expected: number, received: number}>} funding the funding lines
 * @returns {{expected: number, received: number}}
 */
export function fundingTotals(funding) {
  return (funding || []).reduce(
    (sum, line) => ({
      expected: sum.expected + amount(line.expected),
      received: sum.received + amount(line.received)
    }),
    { expected: 0, received: 0 }
  );
}

/**
 * R-EXP1: Net Cost is actual spend less funding received and registrations paid; Budgeted Net
 * Cost is budgeted spend less funding expected and registrations paid.
 *
 * @param {{expenses: Array, funding: Array, registrationsPaid: number}} budget the panel's data
 * @returns {{netCost: number, budgetedNetCost: number}}
 */
export function netCosts(budget) {
  const data = budget || {};
  const spend = expenseTotals(data.expenses);
  const money = fundingTotals(data.funding);
  const paid = amount(data.registrationsPaid);
  return {
    netCost: spend.actual - money.received - paid,
    budgetedNetCost: spend.budgeted - money.expected - paid
  };
}
