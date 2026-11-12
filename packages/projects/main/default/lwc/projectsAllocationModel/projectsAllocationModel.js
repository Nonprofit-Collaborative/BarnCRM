/**
 * Resource allocation in plain JavaScript (R-PM14, R-PM15; plan Section 9.9): each person's
 * weekly planned hours against capacity, unfilled requests as demand, and the ranking of people
 * for a request by skills, role and free capacity. No Salesforce imports, so it ports as it is.
 * Dates are YYYY-MM-DD strings; weeks run Monday to Sunday.
 */

const DAY = 24 * 60 * 60 * 1000;
const WORK_WEEK = 5;

function toTime(value) {
  if (!value) {
    return null;
  }
  const time = Date.parse(`${String(value).slice(0, 10)}T00:00:00Z`);
  return Number.isNaN(time) ? null : time;
}

function toIso(time) {
  return new Date(time).toISOString().slice(0, 10);
}

function round(value) {
  return Math.round(value * 100) / 100;
}

/** Monday to Friday days from the first time to the last, both included; 0 when reversed. */
function workdays(first, last) {
  let count = 0;
  for (let time = first; time <= last; time += DAY) {
    const day = new Date(time).getUTCDay();
    if (day !== 0 && day !== 6) {
      count += 1;
    }
  }
  return count;
}

/** Monday of the week holding a date, as YYYY-MM-DD; empty for no date. */
export function mondayOf(value) {
  const time = toTime(value);
  return time === null ? '' : toIso(time - ((new Date(time).getUTCDay() + 6) % 7) * DAY);
}

/** The first Monday and last Sunday of `count` weeks starting with the week of `start`. */
export function weekRange(start, count) {
  const first = toTime(mondayOf(start));
  return first === null
    ? null
    : { from: toIso(first), to: toIso(first + (Math.max(count, 1) * 7 - 1) * DAY) };
}

/** Mondays of every week from the week of `from` through `to`. */
export function weekStarts(from, to) {
  const first = toTime(mondayOf(from));
  const last = toTime(to);
  const weeks = [];
  if (first !== null && last !== null) {
    for (let time = first; time <= last; time += 7 * DAY) {
      weeks.push(toIso(time));
    }
  }
  return weeks;
}

/** The skills in a multi-select value (`A;B`), trimmed. */
export function skillList(value) {
  return String(value || '')
    .split(';')
    .map((skill) => skill.trim())
    .filter((skill) => skill);
}

/**
 * Hours of an item ({ hours, start, end }) that fall in a range: its hours spread evenly over
 * its working days, the range's own days when it has no dates (R-PM14).
 */
export function hoursInRange(item, from, to, span) {
  const total = Number(item.hours) || 0;
  const start = toTime(item.start) === null ? toTime(span.from) : toTime(item.start);
  const end = toTime(item.end) === null ? toTime(span.to) : toTime(item.end);
  const days = workdays(start, end);
  if (total <= 0 || days === 0) {
    return 0;
  }
  const overlap = workdays(Math.max(start, toTime(from)), Math.min(end, toTime(to)));
  return (total * overlap) / days;
}

function capacityOf(resource, fallback) {
  const own = Number(resource.Weekly_Capacity_Hours__c);
  return own > 0 ? own : fallback;
}

function plans(assignments, userId) {
  return (assignments || [])
    .filter((row) => row.Resource__c === userId)
    .map((row) => ({
      hours: row.Planned_Hours__c,
      start: row.Start_Date__c,
      end: row.End_Date__c
    }));
}

/**
 * The allocation view for the range: `weeks`, one row per active person with a cell per week
 * (allocated, capacity, logged counted hours, percent, over), and unfilled demand per week.
 */
export function allocation(data, fromDate, toDate) {
  const weeks = weekStarts(fromDate, toDate);
  const span = weeks.length
    ? { from: weeks[0], to: toIso(toTime(weeks[weeks.length - 1]) + 6 * DAY) }
    : { from: fromDate, to: toDate };
  const fallback = Number(data.defaultCapacity) || 40;
  const logged = new Map();
  (data.logged || []).forEach((row) => {
    const key = `${row.userId}|${mondayOf(row.date)}`;
    logged.set(key, (logged.get(key) || 0) + (Number(row.hours) || 0));
  });
  const weekEnd = (week) => toIso(toTime(week) + 6 * DAY);
  const people = (data.resources || [])
    .filter((row) => row.Active__c !== false)
    .map((row) => {
      const capacity = capacityOf(row, fallback);
      const mine = plans(data.assignments, row.User__c);
      const cells = weeks.map((week) => {
        const allocated = round(
          mine.reduce((sum, item) => sum + hoursInRange(item, week, weekEnd(week), span), 0)
        );
        return {
          week,
          allocated,
          capacity,
          logged: round(logged.get(`${row.User__c}|${week}`) || 0),
          percent: Math.round((allocated * 100) / capacity),
          over: allocated > capacity
        };
      });
      return { id: row.Id, userId: row.User__c, name: row.User__r && row.User__r.Name, cells };
    })
    .sort((a, b) => String(a.name).localeCompare(String(b.name)));
  const demand = weeks.map((week) => ({
    week,
    hours: round(
      (data.requests || []).reduce(
        (sum, row) =>
          sum +
          hoursInRange(
            { hours: row.Hours__c, start: row.Start_Date__c, end: row.End_Date__c },
            week,
            weekEnd(week),
            span
          ),
        0
      )
    )
  }));
  return { weeks, people, demand };
}

/**
 * Active people for a request, best first (R-PM15): those with every requested skill, then those
 * whose Default Role is the request's role, then the most free capacity in the request's dates
 * (capacity for its working days less the planned hours already there), then by name.
 */
export function rankCandidates(request, data) {
  const need = skillList(request.Skills__c);
  const span = { from: request.Start_Date__c, to: request.End_Date__c };
  const days = workdays(toTime(span.from), toTime(span.to));
  const fallback = Number(data.defaultCapacity) || 40;
  const role = String(request.Role__c || '')
    .trim()
    .toLowerCase();
  return (data.resources || [])
    .filter((row) => row.Active__c !== false)
    .map((row) => {
      const have = new Set(skillList(row.Skills__c));
      const matched = need.filter((skill) => have.has(skill)).length;
      const capacity = round((capacityOf(row, fallback) * days) / WORK_WEEK);
      const allocated = round(
        plans(data.assignments, row.User__c).reduce(
          (sum, item) => sum + hoursInRange(item, span.from, span.to, span),
          0
        )
      );
      return {
        id: row.Id,
        userId: row.User__c,
        name: row.User__r && row.User__r.Name,
        matched,
        needed: need.length,
        allSkills: matched === need.length,
        roleMatch:
          role !== '' &&
          String(row.Default_Role__c || '')
            .trim()
            .toLowerCase() === role,
        capacity,
        allocated,
        free: round(capacity - allocated)
      };
    })
    .sort(
      (a, b) =>
        Number(b.allSkills) - Number(a.allSkills) ||
        Number(b.roleMatch) - Number(a.roleMatch) ||
        b.free - a.free ||
        String(a.name).localeCompare(String(b.name))
    );
}
