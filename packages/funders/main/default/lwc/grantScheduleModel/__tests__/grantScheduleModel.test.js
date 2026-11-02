import { addMonths, buildPayments, MAX_PAYMENTS } from 'c/grantScheduleModel';

describe('grantScheduleModel', () => {
  it('adds months on the same day, or the last day of a shorter month', () => {
    expect(addMonths('2027-01-15', 1)).toBe('2027-02-15');
    expect(addMonths('2027-01-31', 1)).toBe('2027-02-28');
    expect(addMonths('2028-01-31', 1)).toBe('2028-02-29');
    expect(addMonths('2027-11-30', 3)).toBe('2028-02-29');
    expect(addMonths('2027-06-01', 12)).toBe('2028-06-01');
    expect(addMonths('not a date', 1)).toBeNull();
  });

  it('splits a two-year award into two annual payments', () => {
    expect(
      buildPayments({ amount: 25000, start: '2027-01-01', end: '2028-12-31', frequency: 'Annual' })
    ).toEqual([
      { key: '2027-01-01', dueDate: '2027-01-01', amount: 12500 },
      { key: '2028-01-01', dueDate: '2028-01-01', amount: 12500 }
    ]);
  });

  it('includes a payment that falls on the award end date', () => {
    const payments = buildPayments({
      amount: 300,
      start: '2027-01-01',
      end: '2027-07-01',
      frequency: 'Semiannual'
    });
    expect(payments.map((payment) => payment.dueDate)).toEqual(['2027-01-01', '2027-07-01']);
  });

  it('gives the cents left by rounding to the last payment', () => {
    const payments = buildPayments({
      amount: 100,
      start: '2027-01-01',
      end: '2027-12-31',
      frequency: 'Quarterly'
    });
    expect(payments.map((payment) => payment.amount)).toEqual([25, 25, 25, 25]);
    const thirds = buildPayments({
      amount: 1000,
      start: '2027-01-01',
      end: '2027-03-31',
      frequency: 'Monthly'
    });
    expect(thirds.map((payment) => payment.amount)).toEqual([333.33, 333.33, 333.34]);
    expect(thirds.reduce((sum, payment) => sum + payment.amount * 100, 0)).toBe(100000);
  });

  it('makes one payment for Once, on the award start date', () => {
    expect(
      buildPayments({ amount: 5000, start: '2027-03-01', end: '2029-02-28', frequency: 'Once' })
    ).toEqual([{ key: '2027-03-01', dueDate: '2027-03-01', amount: 5000 }]);
  });

  it('builds nothing it cannot split', () => {
    const award = { amount: 1000, start: '2027-01-01', end: '2027-12-31', frequency: 'Annual' };
    expect(buildPayments({ ...award, amount: 0 })).toEqual([]);
    expect(buildPayments({ ...award, start: null })).toEqual([]);
    expect(buildPayments({ ...award, end: '2026-12-31' })).toEqual([]);
    expect(buildPayments({ ...award, frequency: 'Weekly' })).toEqual([]);
    expect(buildPayments()).toEqual([]);
  });

  it('allows ten years of monthly payments and no more', () => {
    const tenYears = buildPayments({
      amount: 120000,
      start: '2027-01-01',
      end: '2036-12-31',
      frequency: 'Monthly'
    });
    expect(tenYears).toHaveLength(MAX_PAYMENTS);
    expect(
      buildPayments({ amount: 1, start: '2027-01-01', end: '2037-01-01', frequency: 'Monthly' })
    ).toEqual([]);
  });
});
