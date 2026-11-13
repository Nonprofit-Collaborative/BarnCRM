/**
 * What a gift mirror's page shows, worked out from the controller's plain status and
 * comparison values. Framework-free and browser-safe (plan 9.9), so the same logic serves a page
 * built on another platform.
 */

export const OFF = 'Off';

/** Puts values into a label's {0}, {1} and so on. */
export function fill(template, ...values) {
  return values.reduce(
    (text, value, index) => text.split(`{${index}}`).join(String(value)),
    template || ''
  );
}

/** A local date as yyyy-mm-dd. */
export function isoDate(date) {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

/** Which parts of the page show, and which buttons are enabled, for a status and a busy flag. */
export function viewOf(status, working) {
  const loaded = Boolean(status);
  const available = loaded && status.available === true;
  const on = available && status.direction !== OFF;
  const canManage = loaded && status.canManage === true;
  const ready = on && !status.notReadyReason;
  const canRun = loaded && status.canRun === true;
  const manageDisabled = working || !canManage;
  const scheduleDisabled = manageDisabled || !canRun || !ready;
  return {
    loaded,
    available,
    unavailableShown: loaded && !available,
    offShown: available && status.direction === OFF,
    onShown: on,
    notReadyShown: on && Boolean(status.notReadyReason),
    noManageShown: on && !canManage,
    noAccessShown: ready && canManage && !canRun,
    runningShown: on && status.running === true,
    scheduled: loaded && Boolean(status.nextRunAt),
    manageDisabled,
    scheduleDisabled,
    runDisabled: scheduleDisabled || status.running === true
  };
}

/** The difference count line: none, all of them listed, or the first ones listed. */
export function differenceTextOf(comparison, labels) {
  const count = comparison ? comparison.differenceCount : 0;
  if (!count) {
    return labels.noDifferences;
  }
  const listed = comparison.differences.length;
  return count > listed
    ? fill(labels.differenceCount, count, listed)
    : fill(labels.differenceCountAll, count);
}

/**
 * The datatable rows: links to the gift and its mirrored record, named when they have names.
 * `linked` is the mirrored record's field prefix: `opportunity` or `giftTransaction`.
 */
export function rowsOf(comparison, linked) {
  if (!comparison) {
    return [];
  }
  return comparison.differences.map((row) => {
    const id = row[`${linked}Id`];
    return {
      ...row,
      giftUrl: row.giftId ? `/${row.giftId}` : undefined,
      [`${linked}Url`]: id ? `/${id}` : undefined,
      [`${linked}Label`]: row[`${linked}Name`] || id
    };
  });
}
