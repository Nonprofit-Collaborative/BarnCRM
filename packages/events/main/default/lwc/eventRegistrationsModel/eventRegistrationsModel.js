/**
 * Registration rules the Registrations tab draws from (EV-02, canonical model 29EV8 and 29EV9),
 * framework free so they port to BarnCRM for WordPress (plan 9.9). No Salesforce imports.
 *
 * An attendee is `{ id, status, registrationId, registrationStatus, amountOwed, paymentStatus }`.
 */
import { badgeWord } from 'c/barnFormat';

export const REGISTERED = 'Registered';
export const WAITLISTED = 'Waitlisted';
export const CANCELLED = 'Cancelled';
export const ATTENDED = 'Attended';
export const NO_SHOW = 'No-Show';
/** A registration's status while an online payment is awaited (EV-20, R-ERG5). */
export const PENDING_PAYMENT = 'Pending Payment';
export const PAID = 'Paid';

const PAYMENT_WORDS = {
  Unpaid: 'pending',
  'Link Sent': 'pending',
  [PAID]: 'complete',
  Failed: 'not-met',
  'Partly Refunded': 'pending',
  Refunded: 'inactive',
  Cancelled: 'inactive'
};

/** The status badge word for a registration's Payment Status (EV-20). */
export function paymentWord(paymentStatus) {
  return PAYMENT_WORDS[paymentStatus] || 'neutral';
}

/** Statuses that hold a seat (R-EAT1). */
export const SEATED = [REGISTERED, ATTENDED, NO_SHOW];

const STATUS_WORDS = {
  [REGISTERED]: 'new',
  [WAITLISTED]: 'pending',
  [CANCELLED]: 'inactive',
  [ATTENDED]: 'complete',
  [NO_SHOW]: 'not-met'
};

/** The status badge word for a status. */
export function statusWord(status) {
  return badgeWord(STATUS_WORDS, status);
}

/**
 * Counts by status, seats taken and seats left (`null` with no capacity, never below zero).
 */
export function summarize(attendees, capacity) {
  const counts = { registered: 0, waitlisted: 0, cancelled: 0, attended: 0, noShow: 0 };
  (attendees || []).forEach((attendee) => {
    switch (attendee && attendee.status) {
      case REGISTERED:
        counts.registered++;
        break;
      case WAITLISTED:
        counts.waitlisted++;
        break;
      case CANCELLED:
        counts.cancelled++;
        break;
      case ATTENDED:
        counts.attended++;
        break;
      case NO_SHOW:
        counts.noShow++;
        break;
      default:
        break;
    }
  });
  const seated = counts.registered + counts.attended + counts.noShow;
  const hasCapacity = capacity !== null && capacity !== undefined && capacity !== '';
  return {
    ...counts,
    seated,
    seatsLeft: hasCapacity ? Math.max(Number(capacity) - seated, 0) : null
  };
}

/**
 * The status changes offered for an attendee, as `{ value, target }`: the value names the
 * action, the target the status it sets. `cancelRegistration` is offered while the
 * registration is not cancelled. `editBadge` is always offered (EV-26); `sendPaymentLink` when
 * `options.canSendPaymentLink` and the registration owes money, is not paid and is not cancelled
 * (EV-20, R-ERG7).
 */
export function actionsFor(attendee, options) {
  const actions = [];
  const add = (value, target) => actions.push({ value, target });
  switch (attendee && attendee.status) {
    case REGISTERED:
      add('markAttended', ATTENDED);
      add('markNoShow', NO_SHOW);
      add('cancelAttendee', CANCELLED);
      break;
    case WAITLISTED:
      add('moveOffWaitlist', REGISTERED);
      add('cancelAttendee', CANCELLED);
      break;
    case ATTENDED:
      add('markRegistered', REGISTERED);
      add('markNoShow', NO_SHOW);
      break;
    case NO_SHOW:
      add('markAttended', ATTENDED);
      add('markRegistered', REGISTERED);
      break;
    case CANCELLED:
      add('markRegistered', REGISTERED);
      break;
    default:
      break;
  }
  if (!attendee) {
    return actions;
  }
  add('editBadge', null);
  const open = Boolean(attendee.registrationStatus) && attendee.registrationStatus !== CANCELLED;
  if (
    open &&
    options &&
    options.canSendPaymentLink &&
    Number(attendee.amountOwed) > 0 &&
    attendee.paymentStatus !== PAID
  ) {
    add('sendPaymentLink', null);
  }
  if (open) {
    add('cancelRegistration', null);
  }
  return actions;
}

/**
 * The request the service takes, from the form's values: a chosen person or the typed one, the
 * registrant's ticket, the code and the guests with a last name (blank rows are left out).
 */
export function buildRequest(eventId, form) {
  const values = form || {};
  const registrant = values.contactId
    ? { contactId: values.contactId }
    : {
        firstName: trim(values.firstName),
        lastName: trim(values.lastName),
        email: trim(values.email),
        postalCode: trim(values.postalCode)
      };
  return {
    eventId,
    registrant,
    ticketType: values.ticketTypeId || null,
    promoCode: trim(values.promoCode),
    guests: (values.guests || [])
      .filter((guest) => guest && trim(guest.lastName))
      .map((guest) => ({
        person: {
          firstName: trim(guest.firstName),
          lastName: trim(guest.lastName),
          email: trim(guest.email)
        },
        ticketTypeId: guest.ticketTypeId || null
      }))
  };
}

/** Whether the form names someone to register: a chosen person or a last name. */
export function canSubmit(form) {
  const values = form || {};
  return Boolean(values.contactId || trim(values.lastName));
}

function trim(value) {
  const text = value === null || value === undefined ? '' : String(value).trim();
  return text || null;
}
