import { createElement } from 'lwc';
import GrantBudget from 'c/grantBudget';
import getBudget from '@salesforce/apex/GrantManagementController.getBudget';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);
jest.mock('lightning/pageReferenceUtils', () => ({ encodeDefaultFieldValues: (v) => v }), {
  virtual: true
});
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/currency', () => ({ default: 'USD' }), { virtual: true });
jest.mock('@salesforce/apex/GrantManagementController.getBudget', () => ({ default: jest.fn() }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(budget) {
  getBudget.mockResolvedValue(budget);
  const element = createElement('c-grant-budget', { is: GrantBudget });
  element.recordId = 'a01000000000001';
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-grant-budget', () => {
  beforeEach(() => {
    setHelpTextForTest({
      Funders_Budget_RequestedGap: 'The lines ask for {0}.',
      Funders_Budget_Unassigned: '{0} spent is on no line.'
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    clearHelpTextForTest();
    jest.clearAllMocks();
  });

  it('shows the lines, marks an overspent one, and notes the gaps', async () => {
    const element = await render({
      canCreate: true,
      amountRequested: 50000,
      amountAwarded: 35000,
      unassignedSpent: 250,
      lines: [
        { id: 'l1', name: 'Tutor stipends', requested: 30000, awarded: 28000, spent: 29000 },
        { id: 'l2', name: 'Books and supplies', requested: 10000, awarded: 7000, spent: 0 }
      ]
    });
    expect(element.shadowRoot.querySelectorAll('[data-id="line"]')).toHaveLength(2);
    const remaining = element.shadowRoot.querySelectorAll('[data-id="remaining"]');
    expect(remaining[0].classList.contains('slds-text-color_error')).toBe(true);
    expect(remaining[1].classList.contains('slds-text-color_error')).toBe(false);
    const notes = [...element.shadowRoot.querySelectorAll('[data-id="note"]')].map((note) =>
      note.textContent.trim()
    );
    expect(notes).toEqual(['The lines ask for $40,000.00.', '$250.00 spent is on no line.']);
  });

  it('adds a line to this grant', async () => {
    const element = await render({ canCreate: true, lines: [], unassignedSpent: 0 });
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    element.shadowRoot.querySelector('[data-id="new"]').click();
    expect(mockNavigate.mock.calls[0][0].state.defaultFieldValues).toEqual({
      Grant__c: 'a01000000000001'
    });
  });

  it('offers no new line to a reader', async () => {
    const element = await render({ canCreate: false, lines: [], unassignedSpent: 0 });
    expect(element.shadowRoot.querySelector('[data-id="new"]')).toBeNull();
  });
});
