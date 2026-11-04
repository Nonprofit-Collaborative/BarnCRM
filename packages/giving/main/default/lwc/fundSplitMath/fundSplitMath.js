/**
 * The arithmetic of splitting one gift across funds, with no framework in it (people-giving-16,
 * plan Section 9.9): rows of a fund and an amount, what is left to assign, whether the split
 * can be saved, and the drag divider on the stacked bar that moves money between two
 * neighbouring rows.
 *
 * Money is worked in whole cents so a split always adds up to the gift exactly, the way the
 * allocation rule checks it (R-GA1). Plain JavaScript in and out, so a WordPress block or Node
 * can use the same module.
 */

/** A number of currency units as whole cents; anything unreadable is 0. */
export function toCents(value) {
  if (value === null || value === undefined || value === '') {
    return 0;
  }
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number * 100) : 0;
}

/** Whole cents back to currency units. */
export function fromCents(cents) {
  return cents / 100;
}

/** Whether a row has an amount typed (0 counts as typed, an empty box does not). */
function hasAmount(row) {
  return row.amount !== null && row.amount !== undefined && row.amount !== '';
}

/** The share of the total an amount is, as a percent with two decimals; 0 when there is no total. */
export function percentOf(amount, total) {
  const totalCents = toCents(total);
  if (totalCents === 0) {
    return 0;
  }
  return Math.round((toCents(amount) / totalCents) * 10000) / 100;
}

/** The amount a percent of the total comes to, rounded to the cent. */
export function amountForPercent(percent, total) {
  const share = Number(percent);
  if (!Number.isFinite(share)) {
    return 0;
  }
  return fromCents(Math.round((toCents(total) * share) / 100));
}

/** What is still to assign: the total less every row's amount. */
export function leftToAssign(total, rows) {
  const assigned = (rows || []).reduce((sum, row) => sum + toCents(row.amount), 0);
  return fromCents(toCents(total) - assigned);
}

/**
 * Everything that stops the split being saved, as flags a screen turns into words:
 * a row with no fund, the same fund on two rows, a row with no amount or with an amount of the
 * wrong sign (a refund's split is negative throughout), no rows at all, and money left over.
 */
export function problemsOf(total, rows) {
  const list = rows || [];
  const totalCents = toCents(total);
  const sign = Math.sign(totalCents);
  const seen = new Set();
  let duplicateFund = false;
  let missingFund = false;
  let badAmount = false;
  list.forEach((row) => {
    if (!row.fundId) {
      missingFund = true;
    } else if (seen.has(row.fundId)) {
      duplicateFund = true;
    } else {
      seen.add(row.fundId);
    }
    const cents = toCents(row.amount);
    if (!hasAmount(row) || cents === 0 || (sign !== 0 && Math.sign(cents) !== sign)) {
      badAmount = true;
    }
  });
  return {
    noRows: list.length === 0,
    missingFund,
    duplicateFund,
    badAmount,
    unbalanced: toCents(leftToAssign(total, list)) !== 0
  };
}

/** Whether the split can be saved: no problem of any kind. */
export function isValid(total, rows) {
  if (toCents(total) === 0) {
    return false;
  }
  return !Object.values(problemsOf(total, rows)).some(Boolean);
}

/** The rows as the allocations a save takes: a fund and an amount each. */
export function toAllocations(rows) {
  return (rows || []).map((row) => ({
    fundId: row.fundId || null,
    amount: hasAmount(row) ? fromCents(toCents(row.amount)) : null
  }));
}

/** Whether two lists of allocations are the same funds and amounts in the same order. */
export function sameAllocations(first, second) {
  const a = toAllocations(first);
  const b = toAllocations(second);
  if (a.length !== b.length) {
    return false;
  }
  return a.every(
    (entry, index) =>
      (entry.fundId || null) === (b[index].fundId || null) &&
      toCents(entry.amount) === toCents(b[index].amount) &&
      (entry.amount === null) === (b[index].amount === null)
  );
}

/**
 * Where each divider of the stacked bar sits, as the running percent of the total after each
 * row but the last. Rows are measured by size, so a refund's negative split draws the same way.
 */
export function dividerPercents(total, rows) {
  const totalCents = Math.abs(toCents(total));
  const list = rows || [];
  if (totalCents === 0 || list.length < 2) {
    return [];
  }
  const positions = [];
  let running = 0;
  for (let index = 0; index < list.length - 1; index++) {
    running += Math.abs(toCents(list[index].amount));
    positions.push(Math.min(100, Math.round((running / totalCents) * 10000) / 100));
  }
  return positions;
}

/**
 * Moves the divider after row `index` to `percent` of the total, taking money from one
 * neighbour and giving it to the other, so the pair keeps its sum and the rest of the split is
 * untouched. Each neighbour keeps at least one cent, so neither becomes an empty row. Returns
 * new rows; the ones given are not changed.
 */
export function moveDivider(total, rows, index, percent) {
  const list = (rows || []).map((row) => ({ ...row }));
  if (index < 0 || index >= list.length - 1) {
    return list;
  }
  const totalCents = toCents(total);
  const sign = totalCents < 0 ? -1 : 1;
  const absTotal = Math.abs(totalCents);
  let before = 0;
  for (let position = 0; position < index; position++) {
    before += Math.abs(toCents(list[position].amount));
  }
  const pair = Math.abs(toCents(list[index].amount)) + Math.abs(toCents(list[index + 1].amount));
  if (pair < 2) {
    return list;
  }
  const wanted = Math.round((absTotal * Number(percent)) / 100) - before;
  const first = Math.min(pair - 1, Math.max(1, wanted));
  list[index].amount = fromCents(sign * first);
  list[index + 1].amount = fromCents(sign * (pair - first));
  return list;
}
