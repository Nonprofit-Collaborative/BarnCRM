/**
 * Ticket and promo code rules for Event Management (EV-03, canonical model 29EV2 and 29EV3),
 * framework free so the staff pages now and registration (EV-02) later share them, and so they
 * port to BarnCRM for WordPress (plan 9.9). No Salesforce imports.
 *
 * A ticket is `{ id, price, quantity, active }`; a code is `{ discountType, discountValue,
 * ticketTypeId, validFrom, validUntil, active }`. Dates are ISO strings or Date objects.
 */

export const DISCOUNT_PERCENT = 'Percent';
export const DISCOUNT_AMOUNT = 'Amount';

/** A code's state at a moment: 'active', 'inactive', 'scheduled' (not yet valid) or 'expired'. */
export function codeState(code, now = new Date()) {
  if (!code || !code.active) {
    return 'inactive';
  }
  const at = toTime(now);
  if (code.validFrom && toTime(code.validFrom) > at) {
    return 'scheduled';
  }
  if (code.validUntil && toTime(code.validUntil) <= at) {
    return 'expired';
  }
  return 'active';
}

/** Whether the code takes money off this ticket type at this moment (R-PC5). */
export function codeApplies(code, ticketTypeId, now = new Date()) {
  if (codeState(code, now) !== 'active') {
    return false;
  }
  return !code.ticketTypeId || code.ticketTypeId === ticketTypeId;
}

/**
 * The price with the code applied (R-PC5): a percent off rounded to the cent, an amount off
 * capped at the price, never below zero. A code that does not apply leaves the price as it is.
 */
export function priceWithCode(price, code, ticketTypeId, now = new Date()) {
  const base = toCents(price);
  if (!codeApplies(code, ticketTypeId, now)) {
    return base / 100;
  }
  const value = Number(code.discountValue) || 0;
  const off =
    code.discountType === DISCOUNT_AMOUNT
      ? toCents(value)
      : Math.round((base * Math.min(Math.max(value, 0), 100)) / 100);
  return Math.max(base - Math.max(off, 0), 0) / 100;
}

/**
 * The quantities of the active tickets beside the event's capacity (R-TT4): `total` is the sum
 * of the limited quantities, `unlimited` says whether any active ticket has no limit, and
 * `overCapacity` whether the total is larger than the capacity. Nothing is refused.
 */
export function quantitySummary(tickets, capacity) {
  let total = 0;
  let unlimited = false;
  (tickets || [])
    .filter((ticket) => ticket && ticket.active)
    .forEach((ticket) => {
      if (ticket.quantity === null || ticket.quantity === undefined || ticket.quantity === '') {
        unlimited = true;
      } else {
        total += Number(ticket.quantity) || 0;
      }
    });
  const hasCapacity = capacity !== null && capacity !== undefined && capacity !== '';
  return {
    total,
    unlimited,
    overCapacity: hasCapacity && total > Number(capacity)
  };
}

function toTime(value) {
  return value instanceof Date ? value.getTime() : new Date(value).getTime();
}

function toCents(value) {
  return Math.round((Number(value) || 0) * 100);
}
