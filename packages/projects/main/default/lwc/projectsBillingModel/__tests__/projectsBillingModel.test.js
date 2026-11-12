import {
  defaultPeriod,
  financials,
  invoiceRows,
  INVOICE_COLUMNS,
  lastClosedMonth
} from 'c/projectsBillingModel';

describe('c/projectsBillingModel', () => {
  it('defaults the invoice period to last calendar month', () => {
    expect(defaultPeriod(new Date(2026, 0, 15))).toEqual({
      start: '2025-12-01',
      end: '2025-12-31'
    });
    expect(defaultPeriod(new Date(2026, 2, 1))).toEqual({ start: '2026-02-01', end: '2026-02-28' });
    expect(lastClosedMonth(new Date(2026, 10, 12))).toBe('2026-10-01');
  });

  it('writes one CSV row per invoice line with the invoice columns', () => {
    const rows = invoiceRows([
      {
        Name: 'INV-000001',
        Status__c: 'Sent',
        Project__r: { Name: 'Rollout' },
        Account__r: { Name: 'Acme' },
        Invoice_Date__c: '2026-11-01',
        Total__c: 350,
        Lines__r: [
          {
            Line_Type__c: 'Time',
            Description__c: 'Ann',
            Quantity__c: 3,
            Unit_Price__c: 100,
            Amount__c: 300
          },
          {
            Line_Type__c: 'Expense',
            Description__c: 'Taxi',
            Quantity__c: 1,
            Unit_Price__c: 50,
            Amount__c: 50
          }
        ]
      },
      { Name: 'INV-000002', Status__c: 'Paid' }
    ]);
    expect(rows).toHaveLength(3);
    expect(rows[1]).toMatchObject({
      invoice: 'INV-000001',
      client: 'Acme',
      lineType: 'Expense',
      amount: 50
    });
    expect(rows[2]).toEqual(expect.objectContaining({ invoice: 'INV-000002', status: 'Paid' }));
    expect(INVOICE_COLUMNS.map((column) => column.path)).toContain('amountPaid');
  });

  it('works out margin, unbilled and the open month', () => {
    const view = financials(
      {
        withCost: true,
        budget: 6000,
        revenue: 3000,
        cost: 1200,
        invoiced: 1000,
        months: [{ month: '2026-10-01', recognized: 2000, cost: 1000 }]
      },
      new Date(2026, 10, 12)
    );
    expect(view.margin).toBe(1800);
    expect(view.marginPercent).toBe(60);
    expect(view.unbilled).toBe(2000);
    expect(view.months).toHaveLength(2);
    expect(view.months[1]).toEqual({
      key: 'open',
      month: '2026-11-01',
      recognized: 1000,
      cost: 200,
      open: true
    });
  });

  it('hides cost and margin without cost access', () => {
    const view = financials({ withCost: false, revenue: 500, months: [] }, new Date(2026, 10, 1));
    expect(view.cost).toBeNull();
    expect(view.margin).toBeNull();
    expect(view.marginPercent).toBeNull();
    expect(view.months[0].cost).toBeNull();
    expect(financials(null).revenue).toBe(0);
  });
});
