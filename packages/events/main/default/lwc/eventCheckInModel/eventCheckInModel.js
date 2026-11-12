/**
 * Framework-free rules for the event Check-In tab (EV-12; plan Section 9.9): finding an attendee
 * by typed text or by a scanned QR code, counting who is in, and shaping a walk-in's request.
 * A QR code holds the attendee's record identifier, so a scan is matched to the loaded list.
 */

export const REGISTERED = 'Registered';
export const ATTENDED = 'Attended';

const ID_PATTERN = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/;

/** The record identifier a scan or typed code holds, or null when it is not one. */
export function codeFrom(text) {
  const value = text === null || text === undefined ? '' : String(text).trim();
  return ID_PATTERN.test(value) ? value : null;
}

/** The attendee a scanned or typed identifier belongs to (15 or 18 characters), or null. */
export function findByCode(attendees, text) {
  const code = codeFrom(text);
  if (!code) {
    return null;
  }
  const head = code.slice(0, 15);
  return (attendees || []).find((attendee) => String(attendee.id).slice(0, 15) === head) || null;
}

/**
 * The attendees matching the typed text in name, badge name, email or ticket (every word must
 * match), by name. Empty text matches everyone. Each row carries `checkedIn` and `shownName` (the
 * badge name when set, EV-26) for the screen.
 */
export function visibleAttendees(attendees, term) {
  const words = String(term || '')
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean);
  return (attendees || [])
    .filter((attendee) => {
      const haystack = [attendee.name, attendee.badgeName, attendee.email, attendee.ticketName]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      return words.every((word) => haystack.includes(word));
    })
    .map((attendee) => ({
      ...attendee,
      checkedIn: attendee.status === ATTENDED,
      shownName: attendee.badgeName || attendee.name,
      alsoName: attendee.badgeName && attendee.badgeName !== attendee.name ? attendee.name : ''
    }));
}

/** How many are expected, in and still to come. */
export function counts(attendees) {
  const total = (attendees || []).length;
  const checkedIn = (attendees || []).filter((attendee) => attendee.status === ATTENDED).length;
  return { total, checkedIn, remaining: total - checkedIn };
}

/** Whether the walk-in form names someone: a last name. */
export function canAddWalkIn(form) {
  return Boolean(trim((form || {}).lastName));
}

/** The request the walk-in action takes: the typed person and the chosen ticket. */
export function walkInRequest(eventId, form) {
  const values = form || {};
  return {
    eventId,
    registrant: {
      firstName: trim(values.firstName),
      lastName: trim(values.lastName),
      email: trim(values.email)
    },
    ticketType: values.ticketTypeId || null
  };
}

function trim(value) {
  const text = value === null || value === undefined ? '' : String(value).trim();
  return text || null;
}
