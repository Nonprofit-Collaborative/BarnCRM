/**
 * Appointment slot rules for Event Management (EV-15, canonical model 29EV8), framework free so
 * they port to BarnCRM for WordPress (plan 9.9). No Salesforce imports.
 *
 * A slot is `{ id, hostId, start, end, status }` with ISO dates. Statuses are Open, Booked,
 * Completed, No-Show and Cancelled; a cancelled slot takes no time.
 */

export const MAX_SLOTS = 100;
export const CANCELLED = 'Cancelled';

const STATUS_WORDS = {
  Open: 'pending',
  Booked: 'active',
  Completed: 'closed',
  'No-Show': 'warning',
  Cancelled: 'inactive'
};

/** The status badge word for a status. */
export function statusWord(status) {
  return STATUS_WORDS[status] || 'neutral';
}

function localTime(date, hhmm) {
  const day = String(date || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const time = String(hhmm || '').match(/^(\d{1,2}):(\d{2})$/);
  if (!day || !time) {
    return null;
  }
  return new Date(+day[1], +day[2] - 1, +day[3], +time[1], +time[2], 0, 0);
}

function overlaps(aStart, aEnd, bStart, bEnd) {
  return aStart < bEnd && bStart < aEnd;
}

/**
 * The back-to-back slots of one day for a host: from `from` to `to`, `minutes` long each, the
 * last slot dropped when it would run past `to`. A slot that overlaps one the host already has
 * (not cancelled) is left out and counted in `skipped`. At most MAX_SLOTS slots, `capped` when
 * there would be more. `invalid` names what is wrong ('date', 'times' or 'length'), if anything.
 */
export function generateSlots({ date, from, to, minutes, existing = [], hostId }) {
  const result = { slots: [], skipped: 0, capped: false, invalid: null };
  const start = localTime(date, from);
  const end = localTime(date, to);
  const length = Math.floor(Number(minutes));
  if (!start || !end) {
    result.invalid = !date ? 'date' : 'times';
    return result;
  }
  if (end <= start) {
    result.invalid = 'times';
    return result;
  }
  if (!(length >= 5 && length <= 480)) {
    result.invalid = 'length';
    return result;
  }
  const taken = existing
    .filter((slot) => slot.hostId === hostId && slot.status !== CANCELLED)
    .map((slot) => [new Date(slot.start), new Date(slot.end)]);
  for (let at = new Date(start); ; at = new Date(at.getTime() + length * 60000)) {
    const slotEnd = new Date(at.getTime() + length * 60000);
    if (slotEnd > end) {
      break;
    }
    if (result.slots.length >= MAX_SLOTS) {
      result.capped = true;
      break;
    }
    if (taken.some(([s, e]) => overlaps(at, slotEnd, s, e))) {
      result.skipped += 1;
    } else {
      result.slots.push({ start: at.toISOString(), end: slotEnd.toISOString() });
    }
  }
  return result;
}

/** The ids of slots that overlap another not-cancelled slot of the same host. */
export function hostClashes(slots) {
  const live = (slots || []).filter((slot) => slot.status !== CANCELLED && slot.start && slot.end);
  const clashing = new Set();
  for (let i = 0; i < live.length; i += 1) {
    for (let j = i + 1; j < live.length; j += 1) {
      const a = live[i];
      const b = live[j];
      if (
        a.hostId &&
        a.hostId === b.hostId &&
        overlaps(new Date(a.start), new Date(a.end), new Date(b.start), new Date(b.end))
      ) {
        clashing.add(a.id);
        clashing.add(b.id);
      }
    }
  }
  return clashing;
}

/** Slots grouped by host in name order, each group's slots in time order, with the counts. */
export function groupByHost(slots) {
  const groups = new Map();
  for (const slot of slots || []) {
    const key = slot.hostId || '';
    if (!groups.has(key)) {
      groups.set(key, { hostId: slot.hostId || null, hostName: slot.hostName || '', slots: [] });
    }
    groups.get(key).slots.push(slot);
  }
  return [...groups.values()]
    .map((group) => ({
      ...group,
      slots: group.slots.sort((a, b) => new Date(a.start) - new Date(b.start)),
      open: group.slots.filter((s) => s.status === 'Open').length,
      booked: group.slots.filter((s) => s.status === 'Booked').length
    }))
    .sort((a, b) => a.hostName.localeCompare(b.hostName));
}

/** The next states a staff member can move a slot to, by its current status. */
export function nextActions(status) {
  switch (status) {
    case 'Open':
      return ['book', 'cancel'];
    case 'Booked':
      return ['complete', 'noShow', 'release', 'cancel'];
    case 'Completed':
    case 'No-Show':
      return ['release'];
    case CANCELLED:
      return ['reopen'];
    default:
      return [];
  }
}
