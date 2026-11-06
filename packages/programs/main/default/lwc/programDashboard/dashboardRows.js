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

/** Present deliveries as a fraction of all deliveries (0.75), or null when there were none. */
export function rateFraction(figures) {
  const total = figures && figures.deliveries ? figures.deliveries : 0;
  return total === 0 ? null : (figures.delivered || 0) / total;
}

/**
 * The tiles across the top, in order. Counts are numbers (the stat tile formats them for the
 * person's locale); the rate is a fraction shown as a percent, or the none label as text.
 */
export function tiles(dashboard, labels) {
  if (!dashboard || !dashboard.canSee) {
    return [];
  }
  const totals = dashboard.totals || {};
  const rate = rateFraction(totals);
  return [
    { key: 'active', label: labels.activePrograms, value: dashboard.activePrograms || 0 },
    { key: 'open', label: labels.openEnrollments, value: totals.openEnrollments || 0 },
    { key: 'new', label: labels.newEnrollments, value: totals.newEnrollments || 0 },
    { key: 'people', label: labels.peopleServed, value: totals.peopleServed || 0 },
    { key: 'counted', label: labels.peopleCounted, value: totals.peopleCounted || 0 },
    { key: 'delivered', label: labels.delivered, value: totals.delivered || 0 },
    {
      key: 'rate',
      label: labels.attendanceRate,
      value: rate === null ? labels.noRate : rate,
      formatStyle: 'percent'
    }
  ].map((tile) => ({ formatStyle: 'decimal', ...tile }));
}

/**
 * One row per program, in the server's order (by name), with a link and its rate: the text
 * ("75%" or the none label) and the percent the rate's meter draws (0 when none).
 */
export function programRows(dashboard, noRateLabel) {
  const programs = dashboard && dashboard.programs ? dashboard.programs : [];
  return programs.map((program) => {
    const rate = rateFraction(program);
    return {
      key: program.programId,
      name: program.name || '',
      href: `/lightning/r/Program__c/${program.programId}/view`,
      openEnrollments: program.openEnrollments || 0,
      newEnrollments: program.newEnrollments || 0,
      completedEnrollments: program.completedEnrollments || 0,
      peopleServed: program.peopleServed || 0,
      peopleCounted: program.peopleCounted || 0,
      delivered: program.delivered || 0,
      rate: attendanceRate(program, noRateLabel),
      ratePercent: rate === null ? 0 : Math.round(rate * 100)
    };
  });
}

/**
 * The module home's tool tiles (vis-modules-19): one per Programs tab the person can open, in
 * the app's tab order, from the object descriptions the platform returned (results the person
 * cannot read are left out). `describe(apiName)` gives the tile's line; `iconOf(apiName)` its icon.
 */
export function toolTiles(objectInfos, apiNames, describe, iconOf) {
  const byName = {};
  ((objectInfos && objectInfos.results) || []).forEach((item) => {
    if (item && item.statusCode === 200 && item.result) {
      byName[item.result.apiName] = item.result;
    }
  });
  return apiNames
    .filter((apiName) => byName[apiName])
    .map((apiName) => ({
      key: apiName,
      name: apiName,
      label: byName[apiName].labelPlural || byName[apiName].label || apiName,
      description: describe(apiName),
      iconName: iconOf(apiName),
      href: `/lightning/o/${apiName}/home`
    }));
}
