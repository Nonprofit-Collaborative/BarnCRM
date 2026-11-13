/**
 * The Timesheet and Approvals pages' logic in plain JavaScript (plan Section 9.9; canonical model
 * R-PM10, R-PM11): Monday-to-Sunday week math on ISO dates (YYYY-MM-DD, worked in UTC so no time
 * zone or locale moves a day), the grid of a person's entries, the week's status counts, the
 * changes a grid edit sends, and the approval queue grouped by person and week. No Salesforce
 * imports, so it ports as it is.
 */

const DAY = 24 * 60 * 60 * 1000;
const LOCKED = new Set(['Submitted', 'Approved']);

function toUtc(iso) {
  const [year, month, day] = String(iso).slice(0, 10).split('-').map(Number);
  return Date.UTC(year, month - 1, day);
}

function toIso(utc) {
  return new Date(utc).toISOString().slice(0, 10);
}

/** Two decimals at most, without a trailing zero tail: 3.5 stays 3.5, 0.1 + 0.2 is 0.3. */
export function round2(value) {
  return Math.round((Number(value) || 0) * 100) / 100;
}

/** An ISO date `count` days from another. */
export function addDays(iso, count) {
  return toIso(toUtc(iso) + count * DAY);
}

/** The Monday on or before a day (Sunday belongs to the week that began the Monday before). */
export function mondayOf(iso) {
  const utc = toUtc(iso);
  const sinceMonday = (new Date(utc).getUTCDay() + 6) % 7;
  return toIso(utc - sinceMonday * DAY);
}

/** The seven days of the week that starts on `monday`, with a short name for the column. */
export function weekDays(monday) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names.map((name, index) => {
    const iso = addDays(monday, index);
    return { iso, name, day: Number(iso.slice(8)), weekend: index > 4 };
  });
}

/** True when the person can still change an entry: not Submitted or Approved (R-PM11). */
export function isEditable(status) {
  return !LOCKED.has(status);
}

/**
 * The person's entries as grid rows: one row for each project, task and billable flag, one cell
 * for each day of the week. A cell with one entry is editable while that entry is Open or
 * Rejected (or has no status); a cell with two or more shows their sum and is read only (change
 * them where they were logged). Totals are by row, by day and for the week.
 */
export function buildGrid(entries, days) {
  const rows = new Map();
  (entries || []).forEach((entry) => {
    const key = `${entry.projectId}|${entry.taskId || ''}|${entry.billable ? 1 : 0}`;
    if (!rows.has(key)) {
      rows.set(
        key,
        newRow(
          { id: entry.projectId, name: entry.projectName },
          entry.taskId ? { id: entry.taskId, name: entry.taskName } : null,
          entry.billable === true,
          days
        )
      );
    }
    const cell = rows.get(key).cells.find((candidate) => candidate.iso === entry.entryDate);
    if (cell) {
      cell.entries.push(entry);
    }
  });
  const list = [...rows.values()];
  list.forEach(finishRow);
  return withTotals(list, days);
}

/** An empty row for a project, an optional task and a billable flag. */
export function newRow(project, task, billable, days) {
  return {
    key: `${project.id}|${task ? task.id : ''}|${billable ? 1 : 0}`,
    projectId: project.id,
    projectName: project.name,
    taskId: task ? task.id : null,
    taskName: task ? task.name : null,
    billable: billable === true,
    cells: days.map((day) => ({ iso: day.iso, weekend: day.weekend, entries: [] })),
    total: 0
  };
}

function finishRow(row) {
  row.cells.forEach((cell) => {
    cell.hours = round2(cell.entries.reduce((sum, entry) => sum + (entry.hours || 0), 0));
    cell.entryId = cell.entries.length === 1 ? cell.entries[0].id : null;
    cell.status = cell.entries.length === 1 ? cell.entries[0].status || null : null;
    cell.reason = cell.entries.length === 1 ? cell.entries[0].rejectionReason : null;
    cell.editable =
      cell.entries.length === 0 ||
      (cell.entries.length === 1 && isEditable(cell.entries[0].status));
    cell.value = cell.hours || '';
  });
  row.total = round2(row.cells.reduce((sum, cell) => sum + cell.hours, 0));
}

/** The grid with its day totals and week total; rows already hold their own. */
export function withTotals(rows, days) {
  rows.forEach((row) => {
    if (row.cells.some((cell) => cell.hours === undefined)) {
      finishRow(row);
    }
  });
  const dayTotals = days.map((day, index) =>
    round2(rows.reduce((sum, row) => sum + row.cells[index].hours, 0))
  );
  return { rows, dayTotals, total: round2(dayTotals.reduce((sum, hours) => sum + hours, 0)) };
}

/**
 * What the week's Submit and Recall buttons can do: counts by status over the time entries and
 * expenses, Submit when anything is Open or Rejected, Recall when anything is Submitted.
 */
export function weekStatus(entries, expenses) {
  const counts = { Open: 0, Rejected: 0, Submitted: 0, Approved: 0, none: 0 };
  [...(entries || []), ...(expenses || [])].forEach((row) => {
    counts[row.status || 'none'] += 1;
  });
  return {
    ...counts,
    canSubmit: counts.Open + counts.Rejected > 0,
    canRecall: counts.Submitted > 0
  };
}

/**
 * The cells to save from a set of edits ({ "rowKey|iso": "hours text" }): a new entry for an
 * edited empty cell, the new hours for an edited existing one. Unchanged, read only and blank
 * cells send nothing; a cell emptied or set to 0 is reported in `cleared` (it cannot be removed
 * here) and one that is not a number in `invalid`.
 */
export function cellChanges(rows, edits) {
  const cells = [];
  const cleared = [];
  const invalid = [];
  rows.forEach((row) => {
    row.cells.forEach((cell) => {
      const text = edits[`${row.key}|${cell.iso}`];
      if (text === undefined || !cell.editable) {
        return;
      }
      const hours = text === '' || text === null ? 0 : Number(text);
      if (Number.isNaN(hours) || hours < 0 || hours > 24) {
        invalid.push({ row: row.key, iso: cell.iso });
      } else if (hours === 0) {
        if (cell.entryId) {
          cleared.push({ row: row.key, iso: cell.iso });
        }
      } else if (hours !== cell.hours) {
        cells.push({
          id: cell.entryId || null,
          projectId: row.projectId,
          taskId: row.taskId,
          workDate: cell.iso,
          hours,
          billable: row.billable
        });
      }
    });
  });
  return { cells, cleared, invalid };
}

/**
 * The approval queue as person-weeks, oldest week first: each has the person, the Monday, the
 * projects, hours, expense amount and the ids of every entry and expense in it, with the
 * individual lines for the detail.
 */
export function groupApprovals(time, expenses) {
  const groups = new Map();
  const group = (row, kind) => {
    const monday = mondayOf(row.Date__c);
    const key = `${row.User__c}|${monday}`;
    if (!groups.has(key)) {
      groups.set(key, {
        key,
        person: row.User__r && row.User__r.Name,
        weekStart: monday,
        hours: 0,
        amount: 0,
        ids: [],
        projects: new Set(),
        lines: []
      });
    }
    const target = groups.get(key);
    target.ids.push(row.Id);
    target.projects.add(row.Project__r && row.Project__r.Name);
    target.lines.push({ ...row, kind });
    return target;
  };
  (time || []).forEach((row) => {
    group(row, 'time').hours += row.Hours__c || 0;
  });
  (expenses || []).forEach((row) => {
    group(row, 'expense').amount += row.Amount__c || 0;
  });
  return [...groups.values()]
    .map((entry) => ({
      ...entry,
      hours: round2(entry.hours),
      amount: round2(entry.amount),
      projects: [...entry.projects].filter(Boolean).join(', ')
    }))
    .sort((a, b) => a.weekStart.localeCompare(b.weekStart) || a.person.localeCompare(b.person));
}
