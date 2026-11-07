/**
 * Event Calendar rules for Event Management (EV-19), framework free so they port to BarnCRM for
 * WordPress (plan 9.9). No Salesforce imports.
 *
 * Dates here are ISO date strings ("2026-11-02"); months run 1 to 12; `firstDay` is the first
 * day of the week, 0 for Sunday to 6 for Saturday. A moment is an ISO date and time as the
 * server reports it, and the day it falls on is worked out in the person's time zone.
 *
 * An entry is what the calendar draws: `{ key, kind: 'event' | 'session', recordId, objectApiName,
 * name, eventId, eventName, status, filterStatus, filterFormat, startsAt, endsAt, startDay,
 * endDay, place, typeLabel, onlineLink, description }`.
 */

export const VIEWS = Object.freeze(['month', 'week', 'list']);
export const EVENT_STATUSES = Object.freeze(['Draft', 'Open', 'Closed', 'Completed', 'Cancelled']);
export const EVENT_FORMATS = Object.freeze(['In Person', 'Virtual', 'Hybrid']);
export const ALL = 'all';

const pad = (value) => String(value).padStart(2, '0');

/** A UTC date as an ISO date string. */
function iso(date) {
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

function parseDay(day) {
  return new Date(`${day}T00:00:00Z`);
}

function addDays(day, count) {
  const date = parseDay(day);
  date.setUTCDate(date.getUTCDate() + count);
  return iso(date);
}

/** The calendar day a moment falls on in the time zone, or '' when it cannot be read. */
export function dayKey(moment, timeZone) {
  const date = new Date(moment);
  if (!moment || Number.isNaN(date.getTime())) {
    return '';
  }
  return new Intl.DateTimeFormat('en-CA', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    ...(timeZone ? { timeZone } : {})
  }).format(date);
}

/**
 * The first and last day a month view shows: whole weeks from the week holding the 1st to the
 * week holding the last day.
 */
export function monthRange(year, month, firstDay = 0) {
  const first = new Date(Date.UTC(year, month - 1, 1));
  const last = new Date(Date.UTC(year, month, 0));
  const start = new Date(first);
  start.setUTCDate(first.getUTCDate() - ((first.getUTCDay() - firstDay + 7) % 7));
  const end = new Date(last);
  end.setUTCDate(last.getUTCDate() + ((firstDay + 6 - last.getUTCDay() + 7) % 7));
  return { from: iso(start), to: iso(end) };
}

/** The seven days of the week that holds the day. */
export function weekRange(day, firstDay = 0) {
  const date = parseDay(day);
  const from = addDays(day, -((date.getUTCDay() - firstDay + 7) % 7));
  return { from, to: addDays(from, 6) };
}

/**
 * The days a view reads: a month view the whole weeks around the month, a list view the month's
 * own days, a week view the week.
 */
export function viewRange(view, anchor, firstDay = 0) {
  const date = parseDay(anchor);
  const year = date.getUTCFullYear();
  const month = date.getUTCMonth() + 1;
  if (view === 'week') {
    return weekRange(anchor, firstDay);
  }
  if (view === 'list') {
    return {
      from: iso(new Date(Date.UTC(year, month - 1, 1))),
      to: iso(new Date(Date.UTC(year, month, 0)))
    };
  }
  return monthRange(year, month, firstDay);
}

/** The anchor day after moving one step back (-1) or forward (1) in the view. */
export function shiftAnchor(view, anchor, delta) {
  if (view === 'week') {
    return addDays(anchor, 7 * delta);
  }
  const date = parseDay(anchor);
  return iso(new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + delta, 1)));
}

/** The view a person's day-of-week setting uses: Salesforce counts from 1 for Sunday. */
export function firstDayFrom(salesforceFirstDay) {
  const day = Number(salesforceFirstDay);
  return day >= 1 && day <= 7 ? day - 1 : 0;
}

function placeOf(venueName, venueAddress, onlineLink) {
  const parts = [venueName, venueAddress].filter((part) => part && String(part).trim());
  if (parts.length) {
    return parts.join(', ');
  }
  return onlineLink || '';
}

/**
 * The entries to draw from the controller's calendar. Sessions need a start; one with no end
 * lasts its start's day. Entries are sorted by start, then name.
 */
export function entriesFrom(calendar, timeZone) {
  const entries = [];
  ((calendar && calendar.events) || []).forEach((row) => {
    const startDay = dayKey(row.startsAt, timeZone);
    if (!startDay) {
      return;
    }
    entries.push({
      key: `event-${row.id}`,
      kind: 'event',
      recordId: row.id,
      objectApiName: 'Event__c',
      name: row.name || '',
      eventId: row.id,
      eventName: row.name || '',
      status: row.status,
      filterStatus: row.status,
      filterFormat: row.format,
      format: row.format,
      startsAt: row.startsAt,
      endsAt: row.endsAt || row.startsAt,
      startDay,
      endDay: dayKey(row.endsAt, timeZone) || startDay,
      place: placeOf(row.venueName, row.venueAddress, row.onlineLink),
      venueName: row.venueName,
      venueAddress: row.venueAddress,
      onlineLink: row.onlineLink,
      typeLabel: row.format || '',
      description: row.description
    });
  });
  ((calendar && calendar.sessions) || []).forEach((row) => {
    const startDay = dayKey(row.startsAt, timeZone);
    if (!startDay) {
      return;
    }
    entries.push({
      key: `session-${row.id}`,
      kind: 'session',
      recordId: row.id,
      objectApiName: 'Event_Session__c',
      name: row.name || '',
      eventId: row.eventId,
      eventName: row.eventName || '',
      status: row.status,
      filterStatus: row.eventStatus,
      filterFormat: row.eventFormat,
      format: row.eventFormat,
      startsAt: row.startsAt,
      endsAt: row.endsAt || row.startsAt,
      startDay,
      endDay: dayKey(row.endsAt, timeZone) || startDay,
      place: row.room || '',
      typeLabel: row.sessionType || '',
      description: ''
    });
  });
  return entries.sort(
    (a, b) => String(a.startsAt).localeCompare(String(b.startsAt)) || a.name.localeCompare(b.name)
  );
}

/**
 * The entries that pass the filters: `status` and `format` are a value or 'all' and apply to an
 * event and to a session through its event; `sessions` false leaves sessions out.
 */
export function filterEntries(entries, { status = ALL, format = ALL, sessions = true } = {}) {
  return (entries || []).filter(
    (entry) =>
      (sessions || entry.kind === 'event') &&
      (status === ALL || entry.filterStatus === status) &&
      (format === ALL || entry.filterFormat === format)
  );
}

/** The entries on each day from `from` to `to`; a multi-day entry is on every day it spans. */
export function entriesByDay(entries, from, to) {
  const byDay = new Map();
  (entries || []).forEach((entry) => {
    const last = entry.endDay < entry.startDay ? entry.startDay : entry.endDay;
    let day = entry.startDay < from ? from : entry.startDay;
    const stop = last > to ? to : last;
    while (day <= stop) {
      if (!byDay.has(day)) {
        byDay.set(day, []);
      }
      byDay.get(day).push({
        ...entry,
        dayKey: `${entry.key}-${day}`,
        continues: day > entry.startDay,
        continuesAfter: day < last
      });
      day = addDays(day, 1);
    }
  });
  return byDay;
}

function daysOf(from, to, byDay, today, inMonth) {
  const days = [];
  for (let day = from; day <= to; day = addDays(day, 1)) {
    days.push({
      key: day,
      date: day,
      day: parseDay(day).getUTCDate(),
      inMonth: inMonth ? inMonth(day) : true,
      isToday: day === today,
      items: byDay.get(day) || []
    });
  }
  return days;
}

/** A month view: its weeks, each of seven days, each with its entries. */
export function monthWeeks(year, month, entries, today, firstDay = 0) {
  const { from, to } = monthRange(year, month, firstDay);
  const days = daysOf(from, to, entriesByDay(entries, from, to), today, (day) => {
    const date = parseDay(day);
    return date.getUTCMonth() + 1 === month;
  });
  const weeks = [];
  for (let i = 0; i < days.length; i += 7) {
    weeks.push({ key: days[i].date, days: days.slice(i, i + 7) });
  }
  return weeks;
}

/** A week view: the seven days with their entries. */
export function weekDays(anchor, entries, today, firstDay = 0) {
  const { from, to } = weekRange(anchor, firstDay);
  return daysOf(from, to, entriesByDay(entries, from, to), today);
}

/** A list view: only the days from `from` to `to` that have something on them, in order. */
export function listDays(from, to, entries, today) {
  return daysOf(from, to, entriesByDay(entries, from, to), today).filter((day) => day.items.length);
}

/** The days of the week in view order, by index (0 for Sunday), for the column headings. */
export function weekdayOrder(firstDay = 0) {
  return [0, 1, 2, 3, 4, 5, 6].map((offset) => (firstDay + offset) % 7);
}

const CRLF = '\r\n';

/** A text value for an iCalendar property: backslash, semicolon, comma and line breaks. */
export function icsText(value) {
  return String(value === null || value === undefined ? '' : value)
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r\n|\r|\n/g, '\\n');
}

/** A moment as an iCalendar UTC date-time, 20270604T080000Z; '' when it cannot be read. */
export function icsMoment(moment) {
  const date = new Date(moment);
  if (!moment || Number.isNaN(date.getTime())) {
    return '';
  }
  return date
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d{3}/, '');
}

/** Folds a line at 75 octets with a space continuation, never inside a character. */
export function icsFold(line) {
  const limit = 75;
  const lines = [];
  let current = '';
  let bytes = 0;
  for (const char of line) {
    const code = char.codePointAt(0);
    let size = 3;
    if (code < 0x80) {
      size = 1;
    } else if (code < 0x800) {
      size = 2;
    } else if (code > 0xffff) {
      size = 4;
    }
    // A continuation line starts with a space, which takes one octet.
    const room = lines.length ? limit - 1 : limit;
    if (bytes + size > room) {
      lines.push(current);
      current = '';
      bytes = 0;
    }
    current += char;
    bytes += size;
  }
  lines.push(current);
  return lines.join(`${CRLF} `);
}

function icsStatus(status) {
  if (status === 'Cancelled') {
    return 'CANCELLED';
  }
  return status === 'Draft' ? 'TENTATIVE' : 'CONFIRMED';
}

/**
 * The text of an .ics file with one VEVENT per entry (RFC 5545), times in UTC, lines folded and
 * ending CRLF. `now` stamps the file (DTSTAMP).
 */
export function icsFor(entries, now = new Date()) {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//BarnCRM//Event Management//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH'
  ];
  (entries || []).forEach((entry) => {
    const start = icsMoment(entry.startsAt);
    if (!start) {
      return;
    }
    const end = icsMoment(entry.endsAt) || start;
    lines.push('BEGIN:VEVENT');
    lines.push(`UID:${entry.recordId}@barncrm`);
    lines.push(`DTSTAMP:${icsMoment(now)}`);
    lines.push(`DTSTART:${start}`);
    lines.push(`DTEND:${end}`);
    lines.push(
      `SUMMARY:${icsText(entry.kind === 'session' && entry.eventName ? `${entry.name} (${entry.eventName})` : entry.name)}`
    );
    if (entry.place) {
      lines.push(`LOCATION:${icsText(entry.place)}`);
    }
    const description = [entry.description, entry.onlineLink ? `Online: ${entry.onlineLink}` : '']
      .filter(Boolean)
      .join('\n');
    if (description) {
      lines.push(`DESCRIPTION:${icsText(description)}`);
    }
    if (entry.onlineLink) {
      lines.push(`URL:${entry.onlineLink}`);
    }
    lines.push(`STATUS:${icsStatus(entry.status)}`);
    lines.push('END:VEVENT');
  });
  lines.push('END:VCALENDAR');
  return lines.map(icsFold).join(CRLF) + CRLF;
}

/** A safe file name for an entry's .ics download. */
export function icsFileName(entry) {
  const slug = String((entry && entry.name) || 'event')
    .normalize('NFKD')
    .replace(/[^\w\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .toLowerCase()
    .slice(0, 60);
  return `${slug || 'event'}.ics`;
}
