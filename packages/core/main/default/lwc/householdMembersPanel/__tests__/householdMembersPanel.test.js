// The test wire adapters below are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getRecord, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import HouseholdMembersPanel from 'c/householdMembersPanel';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';
import getMembershipMode from '@salesforce/apex/HouseholdController.getMembershipMode';
import moveContact from '@salesforce/apex/HouseholdController.moveContact';
import makePrimary from '@salesforce/apex/HouseholdOfPersonController.makePrimary';
import searchPeople from '@salesforce/apex/HouseholdOfPersonController.searchPeople';
import addExistingPerson from '@salesforce/apex/HouseholdOfPersonController.addExistingPerson';
import addNewPerson from '@salesforce/apex/HouseholdOfPersonController.addNewPerson';

jest.mock(
  '@salesforce/apex/HouseholdController.getMembers',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdController.getMembershipMode',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdController.moveContact',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdOfPersonController.makePrimary',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdOfPersonController.searchPeople',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdOfPersonController.addExistingPerson',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdOfPersonController.addNewPerson',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const HOUSEHOLD_ID = '001000000000001AAA';
const OTHER_HOUSEHOLD_ID = '001000000000002AAA';
const PERSON_ID = '003000000000001AAA';
const PERSON_ACCOUNT_ID = '001000000000009AAA';
const HOUSEHOLD_RECORD_TYPE_ID = '012000000000001AAA';

const ACCOUNT_INFO = {
  recordTypeInfos: {
    [HOUSEHOLD_RECORD_TYPE_ID]: {
      recordTypeId: HOUSEHOLD_RECORD_TYPE_ID,
      developerName: 'Household',
      name: 'Household'
    },
    '012000000000002AAA': {
      recordTypeId: '012000000000002AAA',
      developerName: 'Organization',
      name: 'Organization'
    }
  }
};

const MEMBERS = [
  {
    personId: PERSON_ID,
    name: 'John Smith',
    role: 'Head',
    source: 'Contact',
    isPrimary: true,
    isDeceased: false
  },
  {
    personId: '003000000000002AAA',
    name: 'Jane Smith',
    role: 'Spouse or Partner',
    source: 'Contact',
    isPrimary: false,
    isDeceased: true
  }
];

function recordOfType(developerName, primaryContactId) {
  return {
    fields: {
      RecordType: { value: { fields: { DeveloperName: { value: developerName } } } },
      Primary_Contact__c: { value: primaryContactId || null }
    }
  };
}

function badgeLabels(element) {
  return Array.from(element.shadowRoot.querySelectorAll('lightning-badge')).map(
    (badge) => badge.label
  );
}

// Lets every promise the component started settle, including the settings load that the
// first preview waits for.
function flush() {
  return Promise.resolve()
    .then(() => {})
    .then(() => {})
    .then(() => {})
    .then(() => {})
    .then(() => {});
}

function build() {
  const element = createElement('c-household-members-panel', { is: HouseholdMembersPanel });
  element.recordId = HOUSEHOLD_ID;
  document.body.appendChild(element);
  return element;
}

describe('c-household-members-panel', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the members with their role and their badges', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household', PERSON_ID));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    const rows = element.shadowRoot.querySelectorAll('.member-row');
    expect(rows.length).toBe(2);
    expect(rows[0].textContent).toContain('John Smith');
    expect(rows[0].textContent).toContain('Head');

    const labels = badgeLabels(element);
    expect(labels).toContain('c.Core_HouseholdMembersPanel_Primary');
    expect(labels).toContain('c.Core_HouseholdMembersPanel_Deceased');
  });

  it('badges the household primary contact where a person belongs to one household', async () => {
    const element = build();
    // The server never marks anyone primary in this mode; the household's own field says.
    getRecord.emit(recordOfType('Household', '003000000000002AAA'));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS.map((member) => ({ ...member, isPrimary: false })));
    await flush();

    const rows = element.shadowRoot.querySelectorAll('.member-row');
    expect(rows[0].querySelector('lightning-badge')).toBeNull();
    expect(rows[1].querySelector('lightning-badge').label).toBe(
      'c.Core_HouseholdMembersPanel_Primary'
    );
    expect(rows[0].querySelector('.make-primary-button')).not.toBeNull();
    expect(rows[1].querySelector('.make-primary-button')).toBeNull();
  });

  it('shows no primary badge when the household has no primary contact yet', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household', null));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    expect(badgeLabels(element)).not.toContain('c.Core_HouseholdMembersPanel_Primary');
    expect(element.shadowRoot.querySelectorAll('.make-primary-button').length).toBe(2);
  });

  it('badges the membership marked primary in the flexible membership mode', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household', null));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    const rows = element.shadowRoot.querySelectorAll('.member-row');
    expect(rows[0].querySelector('lightning-badge').label).toBe(
      'c.Core_HouseholdMembersPanel_Primary'
    );
    expect(rows[0].querySelector('.make-primary-button')).toBeNull();
    expect(rows[1].querySelector('.make-primary-button')).not.toBeNull();
  });

  it('writes the household primary contact through the platform in the simple mode', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household', PERSON_ID));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot
      .querySelector('.make-primary-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(updateRecord).toHaveBeenCalledWith({
      fields: { Id: HOUSEHOLD_ID, Primary_Contact__c: '003000000000002AAA' }
    });
    expect(makePrimary).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
  });

  it('asks the server to move the primary mark in the flexible membership mode', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household', null));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot
      .querySelector('.make-primary-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(makePrimary).toHaveBeenCalledWith({
      householdId: HOUSEHOLD_ID,
      personId: '003000000000002AAA'
    });
    expect(updateRecord).not.toHaveBeenCalled();
  });

  it('says in plain words when the primary contact could not be changed', async () => {
    updateRecord.mockRejectedValueOnce({ body: { message: 'INSUFFICIENT_ACCESS' } });
    const element = build();
    getRecord.emit(recordOfType('Household', PERSON_ID));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot
      .querySelector('.make-primary-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent).toBe('c.Core_HouseholdPanel_MakePrimaryFailed');
  });

  it('names the person in what a screen reader hears for each action', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household', PERSON_ID));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    const move = element.shadowRoot.querySelectorAll('.move-button');
    expect(move[0].getAttribute('aria-label')).toBe('c.Core_HouseholdPanel_MoveFor');
    expect(move[1].getAttribute('aria-label')).toBe('c.Core_HouseholdPanel_MoveFor');
    const primary = element.shadowRoot.querySelector('.make-primary-button');
    expect(primary.getAttribute('aria-label')).toBe('c.Core_HouseholdPanel_MakePrimaryFor');
  });

  it('shows a spinner with a spoken name until the members arrive', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household', null));
    getMembershipMode.emit('Contact');
    await flush();

    const spinner = element.shadowRoot.querySelector('lightning-spinner');
    expect(spinner).not.toBeNull();
    expect(spinner.alternativeText).toBe('c.Core_HouseholdPanel_Loading');

    getMembers.emit(MEMBERS);
    await flush();
    expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
  });

  it('hides the move button on a person stored as an account where the move cannot work', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household', null));
    getMembershipMode.emit('Contact');
    getMembers.emit([
      {
        personId: PERSON_ACCOUNT_ID,
        name: 'Maria Garcia',
        role: 'Head',
        source: 'Account',
        isPrimary: false,
        isDeceased: false
      }
    ]);
    await flush();

    expect(element.shadowRoot.querySelector('.move-button')).toBeNull();
    expect(element.shadowRoot.querySelector('.make-primary-button')).toBeNull();
  });

  it('says so politely on a record that is not a household', async () => {
    const element = build();
    getRecord.emit(recordOfType('Organization'));
    getMembershipMode.emit('Contact');
    getMembers.emit([]);
    await flush();

    expect(element.shadowRoot.querySelector('.not-a-household')).not.toBeNull();
    expect(element.shadowRoot.querySelector('.member-list')).toBeNull();
  });

  it('says a household has nobody in it, with no empty list for a screen reader to announce', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Contact');
    getMembers.emit([]);
    await flush();

    expect(element.shadowRoot.querySelector('.empty-message')).not.toBeNull();
    expect(element.shadowRoot.querySelector('.member-list')).toBeNull();
    expect(element.shadowRoot.querySelector('.not-a-household')).toBeNull();
  });

  it('offers to add a member where a person belongs to one household', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    expect(element.shadowRoot.querySelector('.add-button')).not.toBeNull();
  });

  it('offers to add a member in the flexible membership mode too', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    expect(element.shadowRoot.querySelector('.add-button')).not.toBeNull();
  });

  it('shows the record edit form to add a member in the simple membership mode', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelector('.add-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(element.shadowRoot.querySelector('lightning-record-edit-form')).not.toBeNull();
    expect(element.shadowRoot.querySelector('.add-search-input')).toBeNull();
  });

  it('offers a search and a new person form to add a member in the flexible membership mode', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelector('.add-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(element.shadowRoot.querySelector('lightning-record-edit-form')).toBeNull();
    expect(element.shadowRoot.querySelector('.add-search-input')).not.toBeNull();
    expect(element.shadowRoot.querySelector('.add-new-last-name')).not.toBeNull();
  });

  it('searches for an existing person and joins the one chosen', async () => {
    searchPeople.mockResolvedValue([{ id: '003000000000009AAA', name: 'Maria Garcia' }]);
    addExistingPerson.mockResolvedValue();
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelector('.add-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    const search = element.shadowRoot.querySelector('.add-search-input');
    search.value = 'Maria';
    search.dispatchEvent(new CustomEvent('change', { detail: { value: 'Maria' } }));
    jest.runAllTimers();
    await flush();

    expect(searchPeople).toHaveBeenCalledWith({ searchTerm: 'Maria' });
    const result = element.shadowRoot.querySelector('.add-existing-button');
    expect(result.label).toBe('Maria Garcia');
    result.dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(addExistingPerson).toHaveBeenCalledWith({
      householdId: HOUSEHOLD_ID,
      personId: '003000000000009AAA'
    });
    expect(element.shadowRoot.querySelector('.add-box')).toBeNull();
  });

  it('ignores a slow search answer once the box was changed or cleared (UI-16)', async () => {
    let answerSlow;
    searchPeople.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          answerSlow = resolve;
        })
    );
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelector('.add-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    const search = element.shadowRoot.querySelector('.add-search-input');
    search.value = 'Maria';
    search.dispatchEvent(new CustomEvent('change', { detail: { value: 'Maria' } }));
    jest.runAllTimers();
    await flush();
    search.value = '';
    search.dispatchEvent(new CustomEvent('change', { detail: { value: '' } }));
    jest.runAllTimers();
    await flush();
    answerSlow([{ id: '003000000000009AAA', name: 'Maria Garcia' }]);
    await flush();

    expect(element.shadowRoot.querySelector('.add-existing-button')).toBeNull();
  });

  it('says so in plain words when adding an existing person is refused', async () => {
    searchPeople.mockResolvedValue([{ id: '003000000000009AAA', name: 'Maria Garcia' }]);
    addExistingPerson.mockRejectedValue({ body: { message: 'That person could not be added.' } });
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelector('.add-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    const search = element.shadowRoot.querySelector('.add-search-input');
    search.value = 'Maria';
    search.dispatchEvent(new CustomEvent('change', { detail: { value: 'Maria' } }));
    jest.runAllTimers();
    await flush();
    element.shadowRoot
      .querySelector('.add-existing-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent).toContain('That person could not be added.');
  });

  it('creates and joins a new person in the flexible membership mode', async () => {
    addNewPerson.mockResolvedValue();
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelector('.add-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    const salutation = element.shadowRoot.querySelector('.add-new-salutation');
    salutation.value = 'Mr.';
    salutation.dispatchEvent(new CustomEvent('change', { detail: { value: 'Mr.' } }));
    const firstName = element.shadowRoot.querySelector('.add-new-first-name');
    firstName.value = 'Wei';
    firstName.dispatchEvent(new CustomEvent('change', { detail: { value: 'Wei' } }));
    const lastName = element.shadowRoot.querySelector('.add-new-last-name');
    lastName.value = 'Lee';
    lastName.dispatchEvent(new CustomEvent('change', { detail: { value: 'Lee' } }));
    element.shadowRoot
      .querySelector('.add-new-save-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(addNewPerson).toHaveBeenCalledWith({
      householdId: HOUSEHOLD_ID,
      salutation: 'Mr.',
      firstName: 'Wei',
      lastName: 'Lee'
    });
    expect(element.shadowRoot.querySelector('.add-box')).toBeNull();
  });

  it('says so in plain words when adding a new person is refused', async () => {
    addNewPerson.mockRejectedValue({ body: { message: 'Enter at least a last name.' } });
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelector('.add-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    element.shadowRoot
      .querySelector('.add-new-save-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent).toContain('Enter at least a last name.');
  });

  it('moves a person to the household that was chosen', async () => {
    moveContact.mockResolvedValue();
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getObjectInfo.emit(ACCOUNT_INFO);
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelectorAll('.move-button')[0].dispatchEvent(new CustomEvent('click'));
    await flush();

    const picker = element.shadowRoot.querySelector('.move-target');
    picker.dispatchEvent(new CustomEvent('change', { detail: { recordId: OTHER_HOUSEHOLD_ID } }));
    element.shadowRoot.querySelector('.move-save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(moveContact).toHaveBeenCalledWith({
      contactId: PERSON_ID,
      targetHouseholdId: OTHER_HOUSEHOLD_ID,
      sourceHouseholdId: HOUSEHOLD_ID
    });
  });

  it('offers households to move to and not organizations', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getObjectInfo.emit(ACCOUNT_INFO);
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelectorAll('.move-button')[0].dispatchEvent(new CustomEvent('click'));
    await flush();

    const picker = element.shadowRoot.querySelector('.move-target');
    expect(picker.objectApiName).toBe('Account');
    expect(picker.filter).toEqual({
      criteria: [{ fieldPath: 'RecordTypeId', operator: 'eq', value: HOUSEHOLD_RECORD_TYPE_ID }]
    });
  });

  it('moves a person the org stores as an account', async () => {
    moveContact.mockResolvedValue();
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getObjectInfo.emit(ACCOUNT_INFO);
    getMembershipMode.emit('Junction');
    getMembers.emit([
      {
        personId: PERSON_ACCOUNT_ID,
        name: 'Maria Garcia',
        role: 'Head',
        source: 'Account',
        isPrimary: true,
        isDeceased: false
      }
    ]);
    await flush();

    element.shadowRoot.querySelectorAll('.move-button')[0].dispatchEvent(new CustomEvent('click'));
    await flush();

    const picker = element.shadowRoot.querySelector('.move-target');
    picker.dispatchEvent(new CustomEvent('change', { detail: { recordId: OTHER_HOUSEHOLD_ID } }));
    element.shadowRoot.querySelector('.move-save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(moveContact).toHaveBeenCalledWith({
      contactId: PERSON_ACCOUNT_ID,
      targetHouseholdId: OTHER_HOUSEHOLD_ID,
      sourceHouseholdId: HOUSEHOLD_ID
    });
  });

  it('shows what went wrong when a move is refused', async () => {
    moveContact.mockRejectedValue({ body: { message: 'That account is not a household.' } });
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getObjectInfo.emit(ACCOUNT_INFO);
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelectorAll('.move-button')[0].dispatchEvent(new CustomEvent('click'));
    await flush();
    element.shadowRoot.querySelector('.move-save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert).not.toBeNull();
    expect(alert.textContent).toContain('That account is not a household.');
  });
});
