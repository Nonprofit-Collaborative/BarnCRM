import { expenseTotals, fundingTotals, netCosts } from 'c/eventBudgetModel';

const EXPENSES = [
  { category: 'Venue', budgeted: 1000, actual: 1200 },
  { category: 'Food and Beverage', budgeted: 500, actual: null },
  { category: 'Venue', budgeted: '250', actual: 50 }
];

describe('eventBudgetModel', () => {
  it('adds budgeted and actual by category, in first-seen order', () => {
    const totals = expenseTotals(EXPENSES);
    expect(totals.categories).toEqual([
      { category: 'Venue', budgeted: 1250, actual: 1250 },
      { category: 'Food and Beverage', budgeted: 500, actual: 0 }
    ]);
    expect(totals.budgeted).toBe(1750);
    expect(totals.actual).toBe(1250);
  });

  it('treats no lines as zero', () => {
    expect(expenseTotals(undefined)).toEqual({ categories: [], budgeted: 0, actual: 0 });
    expect(fundingTotals(null)).toEqual({ expected: 0, received: 0 });
  });

  it('adds funding expected and received', () => {
    expect(
      fundingTotals([
        { expected: 800, received: 300 },
        { expected: 'x', received: 50 }
      ])
    ).toEqual({ expected: 800, received: 350 });
  });

  it('works out net cost the way the testing guide does (R-EXP1)', () => {
    const result = netCosts({
      expenses: [
        { category: 'Venue', budgeted: 1000, actual: 1200 },
        { category: 'Food and Beverage', budgeted: 500 }
      ],
      funding: [{ expected: 800, received: 300 }],
      registrationsPaid: 100
    });
    expect(result).toEqual({ netCost: 800, budgetedNetCost: 600 });
  });

  it('goes below zero when the event brings in more than it spends', () => {
    expect(netCosts({ expenses: [], funding: [{ received: 50 }], registrationsPaid: 0 })).toEqual({
      netCost: -50,
      budgetedNetCost: 0
    });
  });
});
