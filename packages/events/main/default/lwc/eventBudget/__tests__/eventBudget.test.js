import { createElement } from 'lwc';
import EventBudget from 'c/eventBudget';
import getBudget from '@salesforce/apex/EventBudgetController.getBudget';
import { deleteRecord } from 'lightning/uiRecordApi';
import EventRecordModal from 'c/eventRecordModal';
import { setHelpTextForTest } from 'c/barnHelpText';

jest.mock('@salesforce/apex/EventBudgetController.getBudget', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('lightning/uiRecordApi', () => ({ deleteRecord: jest.fn() }), { virtual: true });

const EVENT_ID = 'a01000000000001AAA';
const HALL = 'a0C000000000001AAA';
const ACME = 'a0D000000000001AAA';
const DATA = {
  canAddExpense: true,
  canAddFunding: true,
  canEdit: true,
  registrationsPaid: 100,
  fieldLabels: { Expenses: 'Expenses', Funding: 'Funding', Expense_Name: 'Item' },
  expenses: [
    { id: HALL, name: 'Hall', category: 'Venue', budgeted: 1000, actual: 1200, status: 'Paid' },
    { id: 'a0C000000000002AAA', name: 'Lunch', category: 'Food and Beverage', budgeted: 500 }
  ],
  funding: [
    {
      id: ACME,
      name: 'Acme MDF',
      type: 'Partner Funds (MDF)',
      organizationName: 'Acme',
      expected: 800,
      received: 300
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getBudget.mockResolvedValue(data);
  const element = createElement('c-event-budget', { is: EventBudget });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);
const text = (element, id) => one(element, `[data-id="${id}"]`).textContent.trim();
const choose = (menu, value) =>
  menu.dispatchEvent(new CustomEvent('select', { detail: { value } }));

describe('c-event-budget', () => {
  beforeEach(() => {
    setHelpTextForTest({
      Events_Budget_NetCost: 'Net Cost: {0}',
      Events_Budget_BudgetedNetCost: 'Budgeted Net Cost: {0}',
      Events_Budget_Totals: 'Budgeted {0}, actual {1}',
      Events_Budget_FundingTotals: 'Expected {0}, received {1}',
      Events_Budget_CategoryLine: '{0}: budgeted {1}, actual {2}'
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the lines, totals by category and net cost (T-EV-28)', async () => {
    const element = await render();
    expect(getBudget).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, '[data-id="expense-row"]')).toHaveLength(2);
    expect(all(element, '[data-id="funding-row"]')).toHaveLength(1);
    expect(text(element, 'net-cost')).toBe('Net Cost: 800');
    expect(text(element, 'budgeted-net-cost')).toBe('Budgeted Net Cost: 600');
    expect(text(element, 'expense-totals')).toBe('Budgeted 1,500, actual 1,200');
    expect(text(element, 'funding-totals')).toBe('Expected 800, received 300');
    const categories = all(element, '[data-id="categories"] li').map((li) => li.textContent);
    expect(categories).toEqual([
      'Venue: budgeted 1,000, actual 1,200',
      'Food and Beverage: budgeted 500, actual 0'
    ]);
  });

  it('shows no buttons or menus to a read-only person, and empty lines', async () => {
    const element = await render({
      ...DATA,
      canAddExpense: false,
      canAddFunding: false,
      canEdit: false,
      expenses: [],
      funding: []
    });
    expect(one(element, '[data-id="add-expense"]')).toBeNull();
    expect(one(element, '[data-id="add-funding"]')).toBeNull();
    expect(one(element, 'lightning-button-menu')).toBeNull();
    expect(one(element, '[data-id="expenses-empty"]')).not.toBeNull();
    expect(one(element, '[data-id="funding-empty"]')).not.toBeNull();
  });

  it('adds and edits lines through the record form, defaulting the event', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValue(true);
    one(element, '[data-id="add-expense"]').click();
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        objectApiName: 'Event_Expense__c',
        defaults: { Event__c: EVENT_ID }
      })
    );
    one(element, '[data-id="add-funding"]').click();
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ objectApiName: 'Event_Funding__c' })
    );
    choose(all(element, '[data-kind="funding"]')[0], 'edit');
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ objectApiName: 'Event_Funding__c', recordId: ACME })
    );
    expect(getBudget.mock.calls.length).toBeGreaterThan(1);
  });

  it('removes a line after the person confirms, and shows a refusal', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValueOnce(true);
    deleteRecord.mockResolvedValue();
    choose(all(element, '[data-kind="expenses"]')[0], 'remove');
    await flush();
    await flush();
    expect(deleteRecord).toHaveBeenCalledWith(HALL);

    deleteRecord.mockRejectedValue({ body: { message: 'Not yours' } });
    const toasts = jest.fn();
    element.addEventListener('lightning__showtoast', toasts);
    EventRecordModal.open.mockResolvedValueOnce(true);
    choose(all(element, '[data-kind="expenses"]')[0], 'remove');
    await flush();
    await flush();
    expect(toasts).toHaveBeenCalled();
  });

  it('shows the load error', async () => {
    getBudget.mockRejectedValue({ body: { message: 'No access' } });
    const element = createElement('c-event-budget', { is: EventBudget });
    element.recordId = EVENT_ID;
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]')).not.toBeNull();
  });
});
