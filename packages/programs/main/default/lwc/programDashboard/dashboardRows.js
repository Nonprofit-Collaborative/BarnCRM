/**
 * The Programs Dashboard's logic, framework free (plan Section 9.9): the periods, the attendance
 * rate, and the tiles and rows the page shows, from the plain figures the server returns. No
 * Lightning or Salesforce import.
 */

/** The periods offered, in the order the picker lists them; the first is the default. */
export const PERIODS = ['thisMonth', 'lastMonth', 'thisYear', 'lastYear', 'last12Months'];
export const DEFAULT_PERIOD = PERIODS[0];

/** A local date as YYYY-MM-DD, the form Apex takes for a Date. */
export function isoDate(date) {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

/** The first and last day of a period, both included, as of `today`. */
export function periodRange(period, today) {
  const year = today.getFullYear();
  const month = today.getMonth();
  let from;
  let to;
  switch (period) {
    case 'lastMonth':
      from = new Date(year, month - 1, 1);
      to = new Date(year, month, 0);
      break;
    case 'thisYear':
      from = new Date(year, 0, 1);
      to = new Date(year, 11, 31);
      break;
    case 'lastYear':
      from = new Date(year - 1, 0, 1);
      to = new Date(year - 1, 11, 31);
      break;
    case 'last12Months':
      from = new Date(year, month - 11, 1);
      to = new Date(year, month + 1, 0);
      break;
    default:
      from = new Date(year, month, 1);
      to = new Date(year, month + 1, 0);
  }
  return { fromDate: isoDate(from), toDate: isoDate(to) };
}

/** Present deliveries as a whole percent of all deliveries, or the label given when none. */
export function attendanceRate(figures, noneLabel) {
  const total = figures && figures.deliveries ? figures.deliveries : 0;
  if (total === 0) {
    return noneLabel;
  }
  return `${Math.round(((figures.delivered || 0) * 100) / total)}%`;
}

/** The tiles across the top, in order. */
export function tiles(dashboard, labels) {
  if (!dashboard || !dashboard.canSee) {
    return [];
  }
  const totals = dashboard.totals || {};
  return [
    { key: 'active', label: labels.activePrograms, value: dashboard.activePrograms || 0 },
    { key: 'open', label: labels.openEnrollments, value: totals.openEnrollments || 0 },
    { key: 'new', label: labels.newEnrollments, value: totals.newEnrollments || 0 },
    { key: 'people', label: labels.peopleServed, value: totals.peopleServed || 0 },
    { key: 'delivered', label: labels.delivered, value: totals.delivered || 0 },
    { key: 'rate', label: labels.attendanceRate, value: attendanceRate(totals, labels.noRate) }
  ].map((tile) => ({ ...tile, value: String(tile.value) }));
}

/** One row per program, in the server's order (by name), with a link and its rate. */
export function programRows(dashboard, noRateLabel) {
  const programs = dashboard && dashboard.programs ? dashboard.programs : [];
  return programs.map((program) => ({
    key: program.programId,
    name: program.name || '',
    href: `/lightning/r/Program__c/${program.programId}/view`,
    openEnrollments: program.openEnrollments || 0,
    newEnrollments: program.newEnrollments || 0,
    completedEnrollments: program.completedEnrollments || 0,
    peopleServed: program.peopleServed || 0,
    delivered: program.delivered || 0,
    rate: attendanceRate(program, noRateLabel)
  }));
}
