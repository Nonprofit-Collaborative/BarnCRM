/**
 * What the Setup Changes section works out without the server or the framework (plan 9.9): the
 * table and CSV columns, the summary line and the filter values sent to the server. Labels,
 * the locale and the time zone are passed in, so this module imports nothing.
 */

/** The table's columns: When, who, logged in as, where, and Salesforce's own sentence. */
export function tableColumns(labels) {
  return [
    {
      label: labels.changedAt,
      fieldName: 'changedAt',
      type: 'date',
      initialWidth: 170,
      typeAttributes: {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      }
    },
    { label: labels.changedBy, fieldName: 'changedBy', type: 'text', initialWidth: 160 },
    { label: labels.loggedInAs, fieldName: 'delegateUser', type: 'text', initialWidth: 160 },
    { label: labels.section, fieldName: 'section', type: 'text', initialWidth: 180 },
    { label: labels.whatChanged, fieldName: 'display', type: 'text', wrapText: true }
  ];
}

/** The CSV's columns: the table's, with Changed At as zoned text, plus Action. */
export function csvColumns(labels) {
  return [
    { label: labels.changedAt, path: 'changedAtText' },
    { label: labels.changedBy, path: 'changedBy' },
    { label: labels.loggedInAs, path: 'delegateUser' },
    { label: labels.section, path: 'section' },
    { label: labels.action, path: 'action' },
    { label: labels.whatChanged, path: 'display' }
  ];
}

/** The rows as the CSV writes them, Changed At turned into text by `dateTimeText`. */
export function csvRows(rows, dateTimeText) {
  return (rows || []).map((row) => ({ ...row, changedAtText: dateTimeText(row.changedAt) }));
}

/** A day in the person's locale and time zone, such as 3 May 2026, or '' when there is none. */
export function dayText(value, locale, timeZone) {
  if (!value) {
    return '';
  }
  const when = new Date(value);
  if (Number.isNaN(when.getTime())) {
    return '';
  }
  try {
    return new Intl.DateTimeFormat(locale, { dateStyle: 'medium', timeZone }).format(when);
  } catch {
    return when.toISOString().slice(0, 10);
  }
}

/** A whole number with the locale's grouping, such as 1,240. */
export function countText(value, locale) {
  const number = Number(value) || 0;
  try {
    return new Intl.NumberFormat(locale).format(number);
  } catch {
    return String(number);
  }
}

/** A label with `{0}`, `{1}` and so on replaced by the values, in order. */
export function fill(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

/**
 * The line above the table: how many changes are kept and from when to when, or that nothing
 * is kept yet.
 */
export function keptText(summary, labels, locale, timeZone) {
  if (!summary || !summary.keptCount) {
    return labels.nothingKept;
  }
  return fill(
    labels.kept,
    countText(summary.keptCount, locale),
    dayText(summary.oldest, locale, timeZone),
    dayText(summary.newest, locale, timeZone)
  );
}

/** The line about the nightly copy: running, scheduled with its retention, or not scheduled. */
export function copyText(summary, labels) {
  if (!summary) {
    return '';
  }
  if (summary.running) {
    return labels.copyRunning;
  }
  return summary.scheduled
    ? fill(labels.scheduled, String(summary.retentionDays))
    : labels.notScheduled;
}

/** The Section filter's options: every section first, then each kept one. */
export function sectionOptions(sections, allLabel) {
  return [
    { label: allLabel, value: '' },
    ...(sections || []).map((section) => ({ label: section, value: section }))
  ];
}

/** The filter values as the server takes them: blanks for anything not set. */
export function filterArgs(filters, maxRows) {
  const text = (value) => (value === undefined || value === null ? '' : String(value).trim());
  return {
    fromDate: text(filters.fromDate),
    toDate: text(filters.toDate),
    section: text(filters.section),
    search: text(filters.search),
    maxRows
  };
}

/** True when From is after To, so the search would find nothing. */
export function datesReversed(filters) {
  return Boolean(filters.fromDate && filters.toDate && filters.fromDate > filters.toDate);
}
