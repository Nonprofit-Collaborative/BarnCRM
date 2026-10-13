import { createElement } from 'lwc';
import HouseholdOfPerson from 'c/householdOfPerson';
import getHouseholdsForPerson from '@salesforce/apex/HouseholdOfPersonController.getHouseholdsForPerson';
import { EnclosingTabId, getTabInfo, openSubtab } from 'lightning/platformWorkspaceApi';

jest.mock(
  '@salesforce/apex/HouseholdOfPersonController.getHouseholdsForPerson',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const GenerateUrl = Symbol('GenerateUrl');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
        [GenerateUrl](pageReference) {
          return Promise.resolve(`/lightning/r/${pageReference.attributes.recordId}/view`);
        }
      };
    NavigationMixin.Navigate = Navigate;
    NavigationMixin.GenerateUrl = GenerateUrl;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);

const PERSON_ID = '003000000000001AAA';
const HOUSEHOLD_ID = '001000000000001AAA';

const GARCIA = {
  householdId: HOUSEHOLD_ID,
  name: 'The Garcia Family',
  memberCount: 3,
  formalGreeting: 'Mr. and Mrs. Luis Garcia'
};

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function build() {
  const element = createElement('c-household-of-person', { is: HouseholdOfPerson });
  element.recordId = PERSON_ID;
  document.body.appendChild(element);
  return element;
}

describe('c-household-of-person', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('links to the household and shows its count and greeting', async () => {
    const element = build();
    getHouseholdsForPerson.emit([GARCIA]);
    await flush();

    const link = element.shadowRoot.querySelector('.household-link');
    expect(link.textContent).toBe('The Garcia Family');
    expect(link.getAttribute('href')).toBe(`/lightning/r/${HOUSEHOLD_ID}/view`);
    // Labels resolve to their names under Jest, so the plural label is what is checked for.
    expect(element.shadowRoot.querySelector('.member-count').textContent).toBe(
      'c.Core_HouseholdPanel_MemberCountMany'
    );
    expect(element.shadowRoot.querySelector('.formal-greeting').textContent).toContain(
      'Mr. and Mrs. Luis Garcia'
    );
    expect(element.shadowRoot.querySelector('.empty-message')).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
  });

  it('works on a person account page as on a contact page', async () => {
    const element = createElement('c-household-of-person', { is: HouseholdOfPerson });
    element.recordId = '001000000000009AAA';
    document.body.appendChild(element);
    getHouseholdsForPerson.emit([GARCIA]);
    await flush();

    expect(getHouseholdsForPerson.getLastConfig()).toEqual({ personId: '001000000000009AAA' });
    expect(element.shadowRoot.querySelectorAll('.household-row').length).toBe(1);
  });

  it('says one member without a plural', async () => {
    const element = build();
    getHouseholdsForPerson.emit([{ ...GARCIA, memberCount: 1 }]);
    await flush();

    expect(element.shadowRoot.querySelector('.member-count').textContent).toBe(
      'c.Core_HouseholdPanel_MemberCountOne'
    );
  });

  it('lists every household a person belongs to', async () => {
    const element = build();
    getHouseholdsForPerson.emit([
      GARCIA,
      { householdId: '001000000000002AAA', name: 'The Lee Family', memberCount: 2 }
    ]);
    await flush();

    expect(element.shadowRoot.querySelectorAll('.household-row').length).toBe(2);
  });

  it('says in plain words when the person is in no household', async () => {
    const element = build();
    getHouseholdsForPerson.emit([]);
    await flush();

    expect(element.shadowRoot.querySelector('.empty-message').textContent).toBe(
      'c.Core_HouseholdPanel_OfPersonEmpty'
    );
    expect(element.shadowRoot.querySelector('.household-row')).toBeNull();
  });

  it('shows a spinner with a spoken name until the answer arrives', async () => {
    const element = build();
    await flush();

    const spinner = element.shadowRoot.querySelector('lightning-spinner');
    expect(spinner).not.toBeNull();
    expect(spinner.alternativeText).toBe('c.Core_HouseholdPanel_OfPersonLoading');
    expect(element.shadowRoot.querySelector('.empty-message')).toBeNull();
  });

  it('shows what went wrong when the household cannot be read', async () => {
    const element = build();
    getHouseholdsForPerson.error({ body: { message: 'boom' } });
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent).toBe('c.Core_HouseholdPanel_OfPersonLoadFailed');
    expect(element.shadowRoot.querySelector('.empty-message')).toBeNull();
  });
});

describe('c-household-of-person in a console', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function click(link, init = {}) {
    const event = new MouseEvent('click', { bubbles: true, cancelable: true, ...init });
    link.dispatchEvent(event);
    return event;
  }

  it('lets the browser follow the link outside a console', async () => {
    const element = build();
    getHouseholdsForPerson.emit([GARCIA]);
    await flush();

    const event = click(element.shadowRoot.querySelector('.household-link'));
    await flush();

    expect(event.defaultPrevented).toBe(false);
    expect(openSubtab).not.toHaveBeenCalled();
  });

  it('opens the household as a subtab beside the person', async () => {
    getTabInfo.mockResolvedValueOnce({ tabId: 'tab0', isSubtab: false });
    const element = build();
    getHouseholdsForPerson.emit([GARCIA]);
    EnclosingTabId.emit('tab0');
    await flush();

    const event = click(element.shadowRoot.querySelector('.household-link'));
    await flush();
    await flush();

    expect(event.defaultPrevented).toBe(true);
    expect(openSubtab).toHaveBeenCalledWith('tab0', { recordId: HOUSEHOLD_ID, focus: true });
  });

  it('leaves a click for a new browser tab to the browser', async () => {
    const element = build();
    getHouseholdsForPerson.emit([GARCIA]);
    EnclosingTabId.emit('tab0');
    await flush();

    const event = click(element.shadowRoot.querySelector('.household-link'), { metaKey: true });
    await flush();

    expect(event.defaultPrevented).toBe(false);
    expect(openSubtab).not.toHaveBeenCalled();
  });
});
