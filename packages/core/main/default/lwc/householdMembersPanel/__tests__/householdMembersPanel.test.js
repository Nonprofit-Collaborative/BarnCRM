// The test wire adapters below are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getRecord, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getObjectInfos } from 'lightning/uiObjectInfoApi';
import HouseholdMembersPanel from 'c/householdMembersPanel';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';
import getMembershipMode from '@salesforce/apex/HouseholdController.getMembershipMode';
import moveContact from '@salesforce/apex/HouseholdController.moveContact';
import makePrimary from '@salesforce/apex/HouseholdOfPersonController.makePrimary';
import HouseholdAddMemberModal from 'c/householdAddMemberModal';
import Toast from 'lightning/toast';

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

const HOUSEHOLD_ID = '001000000000001AAA';
const OTHER_HOUSEHOLD_ID = '001000000000002AAA';
const PERSON_ID = '003000000000001AAA';
const PERSON_ACCOUNT_ID = '001000000000009AAA';
const HOUSEHOLD_RECORD_TYPE_ID = '012000000000001AAA';

const ACCOUNT_INFO = {
  updateable: true,
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

/** Chooses a member menu item the way the platform reports it: a select on its menu. */
function choose(item) {
  item
    .closest('lightning-button-menu')
    .dispatchEvent(new CustomEvent('select', { detail: { value: item.value } }));
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

/** Contact and Household Member access as the platform reports it, in that order. */
function accessInfos(createable, updateable, accountIdUpdateable = updateable) {
  const fields = { AccountId: { updateable: accountIdUpdateable } };
  const entry = { statusCode: 200, result: { createable, updateable, fields } };
  return { results: [entry, entry] };
}

/** A Staff user by default: may add, move and make primary. */
function build({
  accountUpdateable = true,
  createable = true,
  updateable = true,
  accountIdUpdateable = updateable
} = {}) {
  const element = createElement('c-household-members-panel', { is: HouseholdMembersPanel });
  element.recordId = HOUSEHOLD_ID;
  document.body.appendChild(element);
  getObjectInfo.emit({ ...ACCOUNT_INFO, updateable: accountUpdateable });
  getObjectInfos.emit(accessInfos(createable, updateable, accountIdUpdateable));
  return element;
}

const READ_ONLY = { accountUpdateable: false, createable: false, updateable: false };

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

    choose(element.shadowRoot.querySelector('.make-primary-button'));
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

    choose(element.shadowRoot.querySelector('.make-primary-button'));
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

    choose(element.shadowRoot.querySelector('.make-primary-button'));
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent).toBe('c.Core_HouseholdPanel_MakePrimaryFailed');
  });

  it('draws each member as a tile with initials and a menu named for the person', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household', PERSON_ID));
    getMembershipMode.emit('Contact');
    getMembers.emit([...MEMBERS, { ...MEMBERS[1], personId: '003000000000003AAA', name: '' }]);
    await flush();

    const avatars = element.shadowRoot.querySelectorAll('.member-avatar');
    expect(Array.from(avatars).map((avatar) => avatar.initials)).toEqual(['JS', 'JS', '']);
    const menus = element.shadowRoot.querySelectorAll('.member-menu');
    expect(menus[0].alternativeText).toBe('c.Core_HouseholdMembersPanel_ActionsFor');
    // The primary contact's menu offers the move only; the others offer both actions.
    expect(menus[0].querySelector('.make-primary-button')).toBeNull();
    expect(menus[0].querySelector('.move-button').label).toBe(
      'c.Core_HouseholdMembersPanel_MoveMember'
    );
    expect(menus[1].querySelector('.make-primary-button').label).toBe(
      'c.Core_HouseholdPanel_MakePrimary'
    );
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

  it('offers no Add member, Move or Make primary to a Read Only user in the simple mode', async () => {
    const element = build(READ_ONLY);
    getRecord.emit(recordOfType('Household', PERSON_ID));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    expect(element.shadowRoot.querySelectorAll('.member-row').length).toBe(2);
    expect(element.shadowRoot.querySelector('.add-button')).toBeNull();
    expect(element.shadowRoot.querySelector('.member-menu')).toBeNull();
  });

  it('offers no Add member, Move or Make primary to a Read Only user in the flexible mode', async () => {
    const element = build(READ_ONLY);
    getRecord.emit(recordOfType('Household', null));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    expect(element.shadowRoot.querySelectorAll('.member-row').length).toBe(2);
    expect(element.shadowRoot.querySelector('.add-button')).toBeNull();
    expect(element.shadowRoot.querySelector('.move-button')).toBeNull();
    expect(element.shadowRoot.querySelector('.make-primary-button')).toBeNull();
  });

  it('offers no Move in the simple mode to someone who cannot edit Account Name', async () => {
    const element = build({ accountIdUpdateable: false });
    getRecord.emit(recordOfType('Household', PERSON_ID));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    expect(element.shadowRoot.querySelector('.move-button')).toBeNull();
    expect(element.shadowRoot.querySelector('.add-button')).not.toBeNull();
  });

  it('offers Make primary in the simple mode only to someone who can edit the household', async () => {
    const element = build({ accountUpdateable: false });
    getRecord.emit(recordOfType('Household', PERSON_ID));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    expect(element.shadowRoot.querySelector('.make-primary-button')).toBeNull();
    expect(element.shadowRoot.querySelector('.move-button')).not.toBeNull();
    expect(element.shadowRoot.querySelector('.add-button')).not.toBeNull();
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

    const empty = element.shadowRoot.querySelector('.empty-message');
    expect(empty.heading).toBe('c.Core_HouseholdMembersPanel_EmptyHeading');
    expect(empty.message).toBe('c.Core_HouseholdMembersPanel_Empty');
    expect(element.shadowRoot.querySelector('.empty-add-button')).not.toBeNull();
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

  it('opens the Add Member dialog in the way of belonging the org uses', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    const show = jest.spyOn(Toast, 'show');
    HouseholdAddMemberModal.open.mockResolvedValueOnce(undefined);
    element.shadowRoot.querySelector('.add-button').click();
    await flush();

    expect(HouseholdAddMemberModal.open).toHaveBeenCalledWith({
      label: 'c.Core_HouseholdMembersPanel_AddMember',
      size: 'small',
      householdId: HOUSEHOLD_ID,
      junctionMode: true
    });
    expect(show).not.toHaveBeenCalled();
    show.mockRestore();
  });

  it('confirms and reads the members again once the dialog added someone', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Contact');
    getMembers.emit([]);
    await flush();

    const show = jest.spyOn(Toast, 'show');
    HouseholdAddMemberModal.open.mockResolvedValueOnce(true);
    element.shadowRoot.querySelector('.empty-add-button').click();
    await flush();

    expect(HouseholdAddMemberModal.open.mock.calls[0][0].junctionMode).toBe(false);
    expect(show.mock.calls[0][0]).toEqual({
      label: 'c.Core_HouseholdMembersPanel_AddSuccess',
      variant: 'success'
    });
    show.mockRestore();
  });

  it('moves a person to the household that was chosen', async () => {
    moveContact.mockResolvedValue();
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getObjectInfo.emit(ACCOUNT_INFO);
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    choose(element.shadowRoot.querySelectorAll('.move-button')[0]);
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

    choose(element.shadowRoot.querySelectorAll('.move-button')[0]);
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

    choose(element.shadowRoot.querySelectorAll('.move-button')[0]);
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

    choose(element.shadowRoot.querySelectorAll('.move-button')[0]);
    await flush();
    element.shadowRoot.querySelector('.move-save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert).not.toBeNull();
    expect(alert.textContent).toContain('That account is not a household.');
  });
});
