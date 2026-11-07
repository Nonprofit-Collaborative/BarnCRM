/**
 * The Agenda Builder's rules (EV-04, canonical model 29EV5), framework free so they port to
 * BarnCRM for WordPress (plan 9.9) and a published agenda can reuse them. No Salesforce imports.
 *
 * A track is `{ id, name }`; a session is `{ id, name, trackId, startsAt, endsAt, room, status,
 * speakerIds }`, dates as ISO strings or Date objects.
 */

/** The column of sessions without a track, and the day of sessions without a time. */
export const NO_TRACK = 'none';
export const UNSCHEDULED = 'unscheduled';
const CANCELLED = 'Cancelled';

/** A session's day as YYYY-MM-DD in the time zone, or UNSCHEDULED. */
export function dayOf(session, timeZone) {
  if (!session || !session.startsAt) {
    return UNSCHEDULED;
  }
  const start = new Date(session.startsAt);
  if (Number.isNaN(start.getTime())) {
    return UNSCHEDULED;
  }
  return new Intl.DateTimeFormat('en-CA', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    ...(timeZone ? { timeZone } : {})
  }).format(start);
}

/** The days that have sessions, in order, with UNSCHEDULED last when any session has no time. */
export function daysOf(sessions, timeZone) {
  const days = new Set((sessions || []).map((session) => dayOf(session, timeZone)));
  const dated = [...days].filter((day) => day !== UNSCHEDULED).sort();
  return days.has(UNSCHEDULED) ? [...dated, UNSCHEDULED] : dated;
}

/**
 * The board for one day: a column per track in the order given, then the No Track column, each
 * with that day's sessions by start time then title. `day` empty means every day.
 */
export function columnsFor(tracks, sessions, day, timeZone) {
  const columns = (tracks || []).map((track) => ({ id: track.id, name: track.name, sessions: [] }));
  const none = { id: NO_TRACK, name: null, sessions: [] };
  const byId = new Map(columns.map((column) => [column.id, column]));
  (sessions || [])
    .filter((session) => !day || dayOf(session, timeZone) === day)
    .forEach((session) => {
      (byId.get(session.trackId) || none).sessions.push(session);
    });
  return [...columns, none].map((column) => ({
    ...column,
    sessions: column.sessions.slice().sort(bySchedule)
  }));
}

/** True when the two sessions' times overlap; touching end to start is not an overlap. */
export function overlaps(a, b) {
  if (!timed(a) || !timed(b)) {
    return false;
  }
  return time(a.startsAt) < time(b.endsAt) && time(b.startsAt) < time(a.endsAt);
}

/**
 * The clashes (R-ESN4): for each session id that clashes, `{ room: [ids], speaker: [ids] }`,
 * the other sessions in the same room, or with a speaker in common, at an overlapping time.
 * Cancelled and unscheduled sessions are ignored. Room names compare without case or spaces
 * around them. Nothing is refused.
 */
export function clashesOf(sessions) {
  const live = (sessions || []).filter(
    (session) => session && session.status !== CANCELLED && timed(session)
  );
  const result = new Map();
  const note = (session, kind, otherId) => {
    if (!result.has(session.id)) {
      result.set(session.id, { room: [], speaker: [] });
    }
    result.get(session.id)[kind].push(otherId);
  };
  for (let i = 0; i < live.length; i++) {
    for (let j = i + 1; j < live.length; j++) {
      const a = live[i];
      const b = live[j];
      if (!overlaps(a, b)) {
        continue;
      }
      if (roomKey(a) && roomKey(a) === roomKey(b)) {
        note(a, 'room', b.id);
        note(b, 'room', a.id);
      }
      if (sharesSpeaker(a, b)) {
        note(a, 'speaker', b.id);
        note(b, 'speaker', a.id);
      }
    }
  }
  return result;
}

function sharesSpeaker(a, b) {
  const theirs = new Set(b.speakerIds || []);
  return (a.speakerIds || []).some((id) => theirs.has(id));
}

function roomKey(session) {
  return String(session.room || '')
    .trim()
    .toLowerCase();
}

function timed(session) {
  return Boolean(session && session.startsAt && session.endsAt);
}

function time(value) {
  return new Date(value).getTime();
}

function bySchedule(a, b) {
  const left = a.startsAt ? time(a.startsAt) : Number.MAX_SAFE_INTEGER;
  const right = b.startsAt ? time(b.startsAt) : Number.MAX_SAFE_INTEGER;
  if (left !== right) {
    return left - right;
  }
  return String(a.name || '').localeCompare(String(b.name || ''));
}
