import {
  amountForPercent,
  dividerPercents,
  isValid,
  leftToAssign,
  moveDivider,
  percentOf,
  problemsOf,
  sameAllocations,
  toAllocations,
  toCents
} from 'c/fundSplitMath';

const BUILDING = 'a01000000000001AAA';
const GENERAL = 'a01000000000002AAA';
const SCHOLAR = 'a01000000000003AAA';

describe('fundSplitMath', () => {
  it('works in whole cents and reads blanks as nothing', () => {
    expect(toCents('12.345')).toBe(1235);
    expect(toCents('')).toBe(0);
    expect(toCents(undefined)).toBe(0);
    expect(toCents('abc')).toBe(0);
  });

  it('turns amounts into percents and back, to the cent', () => {
    expect(percentOf(25, 100)).toBe(25);
    expect(percentOf(1, 3)).toBe(33.33);
    expect(percentOf(5, 0)).toBe(0);
    expect(amountForPercent(33.33, 100)).toBe(33.33);
    expect(amountForPercent(50, 75.01)).toBe(37.51);
    expect(amountForPercent('x', 100)).toBe(0);
  });

  it('says what is left to assign', () => {
    expect(leftToAssign(100, [{ amount: 60 }, { amount: 30.5 }])).toBe(9.5);
    expect(leftToAssign(100, [])).toBe(100);
    expect(leftToAssign(0.3, [{ amount: 0.1 }, { amount: 0.2 }])).toBe(0);
  });

  it('accepts a balanced split with a fund on every row', () => {
    const rows = [
      { fundId: BUILDING, amount: 70 },
      { fundId: GENERAL, amount: 30 }
    ];
    expect(isValid(100, rows)).toBe(true);
    expect(Object.values(problemsOf(100, rows)).some(Boolean)).toBe(false);
  });

  it('names each problem that stops a save', () => {
    expect(problemsOf(100, []).noRows).toBe(true);
    expect(problemsOf(100, [{ fundId: null, amount: 100 }]).missingFund).toBe(true);
    expect(
      problemsOf(100, [
        { fundId: BUILDING, amount: 50 },
        { fundId: BUILDING, amount: 50 }
      ]).duplicateFund
    ).toBe(true);
    expect(
      problemsOf(100, [
        { fundId: BUILDING, amount: 100 },
        { fundId: GENERAL, amount: '' }
      ]).badAmount
    ).toBe(true);
    expect(problemsOf(100, [{ fundId: BUILDING, amount: 90 }]).unbalanced).toBe(true);
    expect(isValid(0, [{ fundId: BUILDING, amount: 0 }])).toBe(false);
  });

  it('keeps a refund split negative throughout', () => {
    expect(
      isValid(-100, [
        { fundId: BUILDING, amount: -60 },
        { fundId: GENERAL, amount: -40 }
      ])
    ).toBe(true);
    expect(
      problemsOf(-100, [
        { fundId: BUILDING, amount: -110 },
        { fundId: GENERAL, amount: 10 }
      ]).badAmount
    ).toBe(true);
  });

  it('gives back fund and amount pairs and compares them', () => {
    const rows = [
      { key: 'r1', fundId: BUILDING, amount: '70.004' },
      { key: 'r2', fundId: '', amount: '' }
    ];
    expect(toAllocations(rows)).toEqual([
      { fundId: BUILDING, amount: 70 },
      { fundId: null, amount: null }
    ]);
    expect(sameAllocations(rows, [{ fundId: BUILDING, amount: 70 }, { fundId: null }])).toBe(true);
    expect(sameAllocations(rows, [{ fundId: BUILDING, amount: 70 }])).toBe(false);
    expect(sameAllocations(rows, [{ fundId: BUILDING, amount: 70 }, { amount: 0 }])).toBe(false);
  });

  it('places the dividers between rows', () => {
    const rows = [
      { fundId: BUILDING, amount: 50 },
      { fundId: GENERAL, amount: 25 },
      { fundId: SCHOLAR, amount: 25 }
    ];
    expect(dividerPercents(100, rows)).toEqual([50, 75]);
    expect(dividerPercents(100, rows.slice(0, 1))).toEqual([]);
    expect(dividerPercents(0, rows)).toEqual([]);
  });

  it('moves money between neighbours only, keeping a cent on each', () => {
    const rows = [
      { fundId: BUILDING, amount: 50 },
      { fundId: GENERAL, amount: 25 },
      { fundId: SCHOLAR, amount: 25 }
    ];
    const moved = moveDivider(100, rows, 0, 70);
    expect(moved.map((row) => row.amount)).toEqual([70, 5, 25]);
    expect(rows[0].amount).toBe(50);
    expect(moveDivider(100, rows, 0, 99).map((row) => row.amount)).toEqual([74.99, 0.01, 25]);
    expect(moveDivider(100, rows, 1, 0).map((row) => row.amount)).toEqual([50, 0.01, 49.99]);
    expect(moveDivider(100, rows, 2, 50)).toEqual(rows);
  });

  it('moves a negative split by size', () => {
    const rows = [
      { fundId: BUILDING, amount: -50 },
      { fundId: GENERAL, amount: -50 }
    ];
    expect(moveDivider(-100, rows, 0, 30).map((row) => row.amount)).toEqual([-30, -70]);
  });

  it('leaves a pair too small to split alone', () => {
    const rows = [
      { fundId: BUILDING, amount: 0.01 },
      { fundId: GENERAL, amount: 0 }
    ];
    expect(moveDivider(0.01, rows, 0, 50)).toEqual(rows);
  });
});
