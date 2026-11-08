import { codeApplies, codeState, priceWithCode, quantitySummary } from 'c/eventTicketsModel';

const NOW = new Date('2027-03-10T12:00:00Z');
const percent = (value, extra = {}) => ({
  discountType: 'Percent',
  discountValue: value,
  active: true,
  ...extra
});

describe('eventTicketsModel', () => {
  it('works out a code state from active and its window', () => {
    expect(codeState(percent(10), NOW)).toBe('active');
    expect(codeState(percent(10, { active: false }), NOW)).toBe('inactive');
    expect(codeState(percent(10, { validFrom: '2027-04-01T00:00:00Z' }), NOW)).toBe('scheduled');
    expect(codeState(percent(10, { validUntil: '2027-03-01T00:00:00Z' }), NOW)).toBe('expired');
    expect(codeState(null, NOW)).toBe('inactive');
  });

  it('applies a code to every ticket or to its one ticket type', () => {
    expect(codeApplies(percent(10), 'T1', NOW)).toBe(true);
    expect(codeApplies(percent(10, { ticketTypeId: 'T2' }), 'T1', NOW)).toBe(false);
    expect(codeApplies(percent(10, { ticketTypeId: 'T1' }), 'T1', NOW)).toBe(true);
  });

  it('takes a percent off rounded to the cent', () => {
    expect(priceWithCode(25, percent(15), 'T1', NOW)).toBe(21.25);
    expect(priceWithCode(9.99, percent(33), 'T1', NOW)).toBe(6.69);
    expect(priceWithCode(40, percent(100), 'T1', NOW)).toBe(0);
  });

  it('takes an amount off and never goes below zero', () => {
    const amount = { discountType: 'Amount', discountValue: 15, active: true };
    expect(priceWithCode(40, amount, 'T1', NOW)).toBe(25);
    expect(priceWithCode(10, amount, 'T1', NOW)).toBe(0);
  });

  it('leaves the price when the code does not apply', () => {
    expect(priceWithCode(40, percent(50, { active: false }), 'T1', NOW)).toBe(40);
    expect(priceWithCode(40, undefined, 'T1', NOW)).toBe(40);
  });

  it('adds the active tickets quantities beside the capacity', () => {
    const tickets = [
      { quantity: 60, active: true },
      { quantity: 50, active: true },
      { quantity: 500, active: false }
    ];
    expect(quantitySummary(tickets, 100)).toEqual({
      total: 110,
      unlimited: false,
      overCapacity: true
    });
    expect(quantitySummary([{ quantity: null, active: true }], 100)).toEqual({
      total: 0,
      unlimited: true,
      overCapacity: false
    });
    expect(quantitySummary(tickets, null).overCapacity).toBe(false);
  });
});
