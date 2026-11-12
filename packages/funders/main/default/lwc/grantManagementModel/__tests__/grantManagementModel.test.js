import { budgetView, checklistProgress } from 'c/grantManagementModel';

describe('c-grant-management-model', () => {
  it('works out what is left of each line and how the totals differ from the grant', () => {
    const view = budgetView({
      amountRequested: 50000,
      amountAwarded: 35000,
      unassignedSpent: 500,
      lines: [
        { id: 'l1', name: 'Tutor stipends', requested: 30000, awarded: 28000, spent: 29000 },
        { id: 'l2', name: 'Books and supplies', requested: 10000, awarded: 7000, spent: null }
      ]
    });
    expect(view.lines[0]).toMatchObject({ remaining: -1000, overspent: true });
    expect(view.lines[1]).toMatchObject({ spent: 0, remaining: 7000, overspent: false });
    expect(view.totals).toEqual({ requested: 40000, awarded: 35000, spent: 29000 });
    expect(view.requestedGap).toBe(10000);
    expect(view.awardedGap).toBeNull();
    expect(view.unassigned).toBe(500);
  });

  it('compares nothing when there are no lines or the grant has no amount', () => {
    expect(budgetView({ amountRequested: 1000, lines: [] }).requestedGap).toBeNull();
    const view = budgetView({ lines: [{ id: 'l1', name: 'Rent', requested: 100, awarded: null }] });
    expect(view.requestedGap).toBeNull();
    expect(view.lines[0].remaining).toBeNull();
    expect(budgetView(undefined)).toMatchObject({ lines: [], unassigned: 0 });
  });

  it('counts the tasks done', () => {
    expect(checklistProgress([{ done: true }, { done: false }, { done: true }])).toEqual({
      done: 2,
      total: 3
    });
    expect(checklistProgress(null)).toEqual({ done: 0, total: 0 });
  });
});
