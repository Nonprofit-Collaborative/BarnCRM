/**
 * Project Management's page logic in plain JavaScript (plan Section 9.9): phases with their tasks
 * and progress, each phase's bar on the project timeline, utilization percentages and the
 * billable export's columns. No Salesforce imports, so it ports as it is.
 */

const CLOSED = new Set(['Done', 'Cancelled']);

/** Whole percent of done over total, 0 when there is nothing to count. */
export function percent(done, total) {
  const whole = Number(total) || 0;
  return whole > 0 ? Math.round(((Number(done) || 0) * 100) / whole) : 0;
}

/** A task is open while it is not Done or Cancelled. */
export function isOpen(task) {
  return !CLOSED.has(task && task.Status__c);
}

/**
 * Phases in order, each with its tasks, done and counted tasks (Cancelled left out) and percent;
 * tasks with no phase (or a phase not on this project) come last, in a group with no id.
 */
export function groupTasks(phases, tasks) {
  const groups = (phases || []).map((phase) => ({ ...phase, tasks: [] }));
  const byId = new Map(groups.map((group) => [group.Id, group]));
  const loose = { Id: null, Name: null, tasks: [] };
  (tasks || []).forEach((task) => {
    (byId.get(task.Phase__c) || loose).tasks.push(task);
  });
  const all = loose.tasks.length ? [...groups, loose] : groups;
  return all.map((group) => {
    const counted = group.tasks.filter((task) => task.Status__c !== 'Cancelled');
    const done = counted.filter((task) => task.Status__c === 'Done').length;
    return { ...group, done, total: counted.length, percent: percent(done, counted.length) };
  });
}

const DAY = 24 * 60 * 60 * 1000;

function toTime(value) {
  if (!value) {
    return null;
  }
  const time = Date.parse(`${String(value).slice(0, 10)}T00:00:00Z`);
  return Number.isNaN(time) ? null : time;
}

/**
 * The span the timeline covers: the project's start and target dates, widened to every phase
 * date. Null when there are no dates at all.
 */
export function timelineSpan(project, phases) {
  const times = [project && project.Start_Date__c, project && project.Target_Date__c];
  (phases || []).forEach((phase) => times.push(phase.Start_Date__c, phase.End_Date__c));
  const known = times.map(toTime).filter((time) => time !== null);
  if (!known.length) {
    return null;
  }
  return { start: Math.min(...known), end: Math.max(...known) + DAY };
}

/**
 * A phase's bar as CSS percentages of the span: `left` and `width`, at least 1% wide so a
 * one-day phase still shows. Null when the phase or the span has no dates.
 */
export function bar(phase, span) {
  const start = toTime(phase && (phase.Start_Date__c || phase.End_Date__c));
  const end = toTime(phase && (phase.End_Date__c || phase.Start_Date__c));
  if (!span || start === null || end === null) {
    return null;
  }
  const length = span.end - span.start;
  const left = ((start - span.start) * 100) / length;
  const width = Math.max(((end + DAY - start) * 100) / length, 1);
  return {
    left: Math.round(left * 10) / 10,
    width: Math.round(Math.min(width, 100 - left) * 10) / 10
  };
}

/** Where today falls on the span, as a CSS percentage, or null when outside it. */
export function todayMark(span, today = new Date()) {
  if (!span) {
    return null;
  }
  const time = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
  if (time < span.start || time >= span.end) {
    return null;
  }
  return Math.round(((time - span.start) * 1000) / (span.end - span.start)) / 10;
}

/** Utilization rows sorted by name, each with its percent of capacity used (R-PM5). */
export function utilizationRows(rows) {
  return [...(rows || [])]
    .map((row) => ({ ...row, used: percent(row.logged, row.capacity) }))
    .sort((a, b) => String(a.name || '').localeCompare(String(b.name || '')));
}

/** The billable export's columns (R-PM7), for `toCsv` in `c/findCsv`. */
export const BILLABLE_COLUMNS = [
  { label: 'Entry', path: 'entry' },
  { label: 'Project', path: 'project' },
  { label: 'Client', path: 'client' },
  { label: 'Task', path: 'task' },
  { label: 'Person', path: 'person' },
  { label: 'Date', path: 'date' },
  { label: 'Hours', path: 'hours' },
  { label: 'Rate', path: 'rate' },
  { label: 'Amount', path: 'amount' },
  { label: 'Notes', path: 'notes' }
];
