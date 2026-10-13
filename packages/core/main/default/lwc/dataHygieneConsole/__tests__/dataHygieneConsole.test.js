import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import DataHygieneConsole from 'c/dataHygieneConsole';
import getChecks from '@salesforce/apex/DataHygieneController.getChecks';
import openInFind from '@salesforce/apex/DataHygieneController.openInFind';

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
jest.mock('@salesforce/apex/DataHygieneController.getChecks', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/DataHygieneController.openInFind', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_DataHygiene_OpenedNotice',
  () => ({ default: 'In Find, choose "{0}" from Saved queries.' }),
  { virtual: true }
);

const CHECKS = [
  {
    key: 'people_without_household',
    title: 'People with no household',
    description: 'Contacts with no account.',
    count: 214,
    countLabel: '214',
    canOpenInFind: true
  },
  {
    key: 'households_without_members',
    title: 'Households with nobody in them',
    description: 'Member Count is zero or empty.',
    count: 2001,
    countLabel: 'More than 2,000',
    canOpenInFind: true
  },
  {
    key: 'addresses_without_owner',
    title: 'Addresses that belong to nobody',
    description: 'Owner deleted.',
    errorMessage: 'You cannot see the records this check reads.',
    canOpenInFind: false
  },
  {
    key: 'memberships_without_person',
    title: 'Memberships that name nobody',
    description: 'Person deleted.',
    count: 3,
    countLabel: '3',
    canOpenInFind: false,
    note: 'Find cannot list these yet.'
  }
];

// A macrotask, because the page awaits an Apex call and then renders.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  const element = createElement('c-data-hygiene-console', { is: DataHygieneConsole });
  document.body.appendChild(element);
  await flush();
  return element;
}

function row(element, key) {
  return element.shadowRoot.querySelector(`li[data-key="${key}"]`);
}

describe('c-data-hygiene-console', () => {
  beforeEach(() => {
    getChecks.mockResolvedValue(CHECKS);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    mockNavigate.mockClear();
  });

  it('lists every check with its count, labelled by its heading', async () => {
    const element = await render();

    const items = element.shadowRoot.querySelectorAll('li[data-key]');
    expect(items.length).toBe(4);
    const people = row(element, 'people_without_household');
    expect(people.querySelector('h3').textContent).toBe('People with no household');
    expect(people.querySelector('[data-id="count"]').textContent).toBe('214');
    expect(people.querySelector('section').getAttribute('aria-labelledby')).toBeTruthy();
    expect(
      row(element, 'households_without_members').querySelector('[data-id="count"]').textContent
    ).toBe('More than 2,000');
  });

  it('shows a refusal instead of a number, and no Find button', async () => {
    const element = await render();

    const ownerless = row(element, 'addresses_without_owner');
    expect(ownerless.querySelector('[data-id="count"]')).toBeNull();
    expect(ownerless.querySelector('[data-id="check-error"]').textContent).toContain(
      'You cannot see'
    );
    expect(ownerless.querySelector('[data-id="open"]')).toBeNull();
  });

  it('shows the note on a check Find cannot list, with its count and no button', async () => {
    const element = await render();

    const memberships = row(element, 'memberships_without_person');
    expect(memberships.querySelector('[data-id="note"]').textContent).toContain('Find cannot');
    expect(memberships.querySelector('[data-id="count"]').textContent).toBe('3');
    expect(memberships.querySelector('[data-id="open"]')).toBeNull();
  });

  it('opens a check in Find with the tab and state key Apex returns', async () => {
    openInFind.mockResolvedValue({
      savedQueryId: 'a0X000000000001AAA',
      savedQueryName: 'Data hygiene: People with no household',
      findTabApiName: 'Find',
      stateKey: 'c__savedQueryId'
    });
    const element = await render();
    const toasts = jest.spyOn(Toast, 'show');

    row(element, 'people_without_household').querySelector('[data-id="open"]').click();
    await flush();

    expect(openInFind).toHaveBeenCalledWith({ checkKey: 'people_without_household' });
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Find' },
      state: { c__savedQueryId: 'a0X000000000001AAA' }
    });
    expect(toasts).toHaveBeenCalledTimes(1);
    expect(toasts.mock.calls[0][0].label).toBe(
      'In Find, choose "Data hygiene: People with no household" from Saved queries.'
    );
  });

  it('says why when opening fails, and stays on the page', async () => {
    openInFind.mockRejectedValue({ body: { message: 'Find cannot list these yet.' } });
    const element = await render();

    row(element, 'people_without_household').querySelector('[data-id="open"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain(
      'Find cannot list these yet.'
    );
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('counts again on Recount', async () => {
    const element = await render();
    expect(getChecks).toHaveBeenCalledTimes(1);

    element.shadowRoot.querySelector('[data-id="recount"]').click();
    await flush();

    expect(getChecks).toHaveBeenCalledTimes(2);
  });

  it('shows the page error when the checks cannot be read', async () => {
    getChecks.mockRejectedValue({ body: { message: 'Data hygiene needs the permission.' } });
    const element = await render();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain(
      'needs the permission'
    );
    expect(element.shadowRoot.querySelectorAll('li[data-key]').length).toBe(0);
  });
});
