/**
 * The letter periods (modules-4): This Year, Last Year and Custom, as yyyy-mm-dd dates in the
 * user's own day. Shared by the Volunteer Letter action and Volunteer Letters on Approve Hours.
 * Framework free (no lightning or @salesforce imports), so it ports to BarnCRM for WordPress
 * (plan 9.9).
 */
export const THIS_YEAR = 'thisYear';
export const LAST_YEAR = 'lastYear';
export const CUSTOM = 'custom';

function isoDate(date) {
  const two = (number) => String(number).padStart(2, '0');
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
}

/**
 * The From and To dates of a period: This Year runs from 1 January to today, Last Year is the
 * whole of the year before. Custom, or anything else, returns undefined: the person types them.
 */
export function periodDates(period, today = new Date()) {
  const year = today.getFullYear();
  if (period === THIS_YEAR) {
    return { fromDate: isoDate(new Date(year, 0, 1)), toDate: isoDate(today) };
  }
  if (period === LAST_YEAR) {
    return {
      fromDate: isoDate(new Date(year - 1, 0, 1)),
      toDate: isoDate(new Date(year - 1, 11, 31))
    };
  }
  return undefined;
}

/** The period choices for a combobox, with the caller's labels. */
export function periodOptions(labels) {
  return [
    { label: labels.thisYear, value: THIS_YEAR },
    { label: labels.lastYear, value: LAST_YEAR },
    { label: labels.custom, value: CUSTOM }
  ];
}
