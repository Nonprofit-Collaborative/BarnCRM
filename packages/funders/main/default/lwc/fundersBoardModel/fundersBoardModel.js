/**
 * Board dashboard logic, with no framework in it (F-07, canonical model 29ZH R-GN9, ADR-NEXT
 * `NEXT-funders-reporting-links.md` decision 5, plan Section 9.9). Plain JavaScript in and out, so
 * a WordPress block or Node can use the same module.
 */

/** One source above this share of the year's revenue is a risk to discuss. */
export const SINGLE_SOURCE_LIMIT = 0.25;
/** The five largest sources together above this share are a risk to discuss. */
export const TOP_FIVE_LIMIT = 0.5;
const TOP = 5;

const amountOf = (value) => {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
};

/** The amount's share of the total, from 0 to 1; 0 when there is no total. */
export function shareOf(amount, total) {
  return total > 0 ? amountOf(amount) / total : 0;
}

/**
 * The revenue mix: awarded grants by funding source and, with Giving, one line for gifts.
 *
 * @param {object} board the server's dashboard
 * @param {{notSet: string, gifts: string}} words the names for a blank source and for gifts
 * @returns {{rows: Array<{key: string, name: string, amount: number, share: number}>, total: number}}
 */
export function revenueMix(board, words) {
  const rows = ((board && board.grantsBySource) || []).map((slice) => ({
    key: slice.key || 'not-set',
    name: slice.name || words.notSet,
    amount: amountOf(slice.amount)
  }));
  if (board && board.givingAvailable && amountOf(board.giftsThisYear) > 0) {
    rows.push({ key: 'gifts', name: words.gifts, amount: amountOf(board.giftsThisYear) });
  }
  rows.sort((a, b) => b.amount - a.amount);
  const total = rows.reduce((sum, row) => sum + row.amount, 0);
  return { rows: rows.map((row) => ({ ...row, share: shareOf(row.amount, total) })), total };
}

/**
 * Each organization's part of the year's revenue: its awarded grants plus its Giving This Year,
 * joined by record identifier, largest first.
 */
export function sources(board) {
  const byKey = new Map();
  const add = (slice) => {
    const key = slice.key || slice.name;
    const known = byKey.get(key);
    if (known) {
      known.amount += amountOf(slice.amount);
    } else {
      byKey.set(key, { key, name: slice.name, amount: amountOf(slice.amount) });
    }
  };
  ((board && board.grantsByFunder) || []).forEach(add);
  if (board && board.givingAvailable) {
    (board.givingByAccount || []).forEach(add);
  }
  return [...byKey.values()].sort(
    (a, b) => b.amount - a.amount || String(a.name).localeCompare(b.name)
  );
}

/**
 * The concentration: the five largest sources with their shares, and the two flags.
 *
 * @param {object} board the server's dashboard
 * @param {number} total the year's revenue, from `revenueMix`
 */
export function concentration(board, total) {
  const top = sources(board)
    .slice(0, TOP)
    .map((source) => ({ ...source, share: shareOf(source.amount, total) }));
  const largest = top.length > 0 ? top[0] : null;
  const topFiveShare = top.reduce((sum, source) => sum + source.share, 0);
  return {
    top,
    largest,
    topFiveShare,
    singleRisk: Boolean(largest) && largest.share > SINGLE_SOURCE_LIMIT,
    topFiveRisk: topFiveShare > TOP_FIVE_LIMIT
  };
}

/** A share as a whole percent in the locale, for example "42%". */
export function showShare(share, locale) {
  return amountOf(share).toLocaleString(locale, { style: 'percent', maximumFractionDigits: 0 });
}

/** "{0} gives {1}" style text with each `{n}` filled in. */
export function fill(text, values) {
  return String(text || '').replace(/\{(\d+)\}/g, (whole, index) => {
    const value = values[Number(index)];
    return value === undefined ? whole : String(value);
  });
}
