// The object info test wire adapter is emitted to on purpose, which is how a wired component
// is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import AffiliationPanel from 'c/affiliationPanel';
import isFeatureOn from '@salesforce/apex/AffiliationController.isFeatureOn';
import getCardContext from '@salesforce/apex/AffiliationController.getCardContext';
import { graphql } from 'lightning/graphql';
import { notifyRecordUpdateAvailable, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import BarnConfirmModal from 'c/barnConfirmModal';

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

const HARPER = '0031000000000001AA';

/** Picks an action from one row's menu (Edit, Make Primary or End It). */
function choose(element, recordId, value) {
  element.shadowRoot
    .querySelector(`.row-menu[data-record-id="${recordId}"]`)
    .dispatchEvent(new CustomEvent('select', { detail: { value } }));
}
const FOUNDATION_ID = '0011000000000009AA';

/** One affiliation as the GraphQL query returns it. */
function node({ id, organizationId, organizationName, role, status, isPrimary }) {
  return {
    Id: id,
    Contact__c: { value: HARPER },
    Contact__r: { Name: { value: 'Harper Garcia' } },
    Person_Account__c: { value: null },
    Person_Account__r: null,
    Organization__c: { value: organizationId },
    Organization__r: { Name: { value: organizationName } },
    Role__c: { value: role },
    Status__c: { value: status },
    Is_Primary__c: { value: isPrimary },
    Description__c: { value: null }
  };
}

function response(nodes) {
  return { uiapi: { query: { Affiliation__c: { edges: nodes.map((n) => ({ node: n })) } } } };
}

jest.mock(
  '@salesforce/apex/AffiliationController.isFeatureOn',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AffiliationController.getCardContext',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const FOUNDATION = node({
  id: 'a0300000000000AAAA',
  organizationId: FOUNDATION_ID,
  organizationName: 'The Union Foundation',
  role: 'Program Officer',
  status: 'Current',
  isPrimary: true
});

const CONGREGATION = node({
  id: 'a0300000000000BBBB',
  organizationId: '0011000000000010AA',
  organizationName: 'Summit Congregation',
  role: 'Board chair',
  status: 'Current',
  isPrimary: false
});

/** What the platform says a user may do with affiliations: Staff can, Read Only only reads. */
const STAFF_ACCESS = {
  createable: true,
  updateable: true,
  deletable: true,
  fields: { Is_Primary__c: { updateable: true } }
};
const READ_ONLY_ACCESS = {
  createable: false,
  updateable: false,
  deletable: false,
  fields: { Is_Primary__c: { updateable: false } }
};

function build(objectApiName = 'Contact', recordId = HARPER, access = STAFF_ACCESS) {
  const element = createElement('c-affiliation-panel', { is: AffiliationPanel });
  element.recordId = recordId;
  element.objectApiName = objectApiName;
  document.body.appendChild(element);
  getObjectInfo.emit(access);
  isFeatureOn.emit(true);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function headlines(element) {
  return Array.from(element.shadowRoot.querySelectorAll('[data-id="affiliation-headline"]')).map(
    (n) => n.textContent
  );
}

describe('c-affiliation-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows nothing while the Affiliations feature is off (D-185)', async () => {
    const element = build();
    isFeatureOn.emit(false);
    graphql.emit(response([FOUNDATION]));
    await flush();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
    isFeatureOn.emit(true);
    await flush();
    expect(element.shadowRoot.querySelector('lightning-card')).not.toBeNull();
  });

  it('asks for the affiliations of the record it sits on', async () => {
    build();
    await flush();
    expect(graphql.getLastConfig().variables).toEqual({ recordId: HARPER });
  });

  it('shows a loading state, not "no affiliations", until the affiliations arrive', async () => {
    const element = build();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="loading"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();

    graphql.emit(response([FOUNDATION]));
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="loading"]')).toBeNull();
  });

  it('names the organization on a person record, the primary first', async () => {
    const element = build();
    graphql.emit(response([CONGREGATION, FOUNDATION]));
    await flush();

    expect(headlines(element)).toEqual(['The Union Foundation', 'Summit Congregation']);
  });

  it('lists current affiliations before former ones', async () => {
    const element = build();
    graphql.emit(
      response([
        { ...FOUNDATION, Status__c: { value: 'Former' }, Is_Primary__c: { value: false } },
        CONGREGATION
      ])
    );
    await flush();

    expect(headlines(element)).toEqual(['Summit Congregation', 'The Union Foundation']);
  });

  it('names the person when the card is read from the organization', async () => {
    const element = build('Account', FOUNDATION_ID);
    graphql.emit(response([FOUNDATION]));
    await flush();

    expect(headlines(element)).toEqual(['Harper Garcia']);
  });

  it('names a person held as an account', async () => {
    const element = build('Account', FOUNDATION_ID);
    graphql.emit(
      response([
        {
          ...FOUNDATION,
          Contact__c: { value: null },
          Contact__r: null,
          Person_Account__c: { value: '0011000000000002AA' },
          Person_Account__r: { Name: { value: 'Luis Garcia' } }
        }
      ])
    );
    await flush();

    expect(headlines(element)).toEqual(['Luis Garcia']);
  });

  it('badges the primary organization and offers to move the badge', async () => {
    const element = build();
    graphql.emit(response([FOUNDATION, CONGREGATION]));
    await flush();

    expect(element.shadowRoot.querySelectorAll('[data-id="primary-badge"]').length).toBe(1);
    expect(element.shadowRoot.querySelector('[data-id="primary-badge"]').iconName).toBe(
      'utility:favorite'
    );
    const buttons = element.shadowRoot.querySelectorAll('.make-primary');
    expect(buttons.length).toBe(1);
    expect(buttons[0].closest('.row-menu').dataset.recordId).toBe(CONGREGATION.Id);
  });

  it('links each row to its affiliation and opens the edit form from the row menu', async () => {
    const element = build();
    graphql.emit(response([FOUNDATION]));
    await flush();

    expect(
      element.shadowRoot.querySelector('[data-id="affiliation-headline"]').getAttribute('href')
    ).toBe(`/${FOUNDATION.Id}`);
    choose(element, FOUNDATION.Id, 'edit');
    await flush();
    expect(mockNavigate.mock.calls[0][0]).toEqual({
      type: 'standard__recordPage',
      attributes: { recordId: FOUNDATION.Id, objectApiName: 'Affiliation__c', actionName: 'edit' }
    });
  });

  it('ends a current affiliation today after a confirm, and tells the person page', async () => {
    BarnConfirmModal.open.mockResolvedValueOnce(true);
    const element = build('Contact', HARPER, {
      ...STAFF_ACCESS,
      fields: { ...STAFF_ACCESS.fields, End_Date__c: { updateable: true } }
    });
    graphql.emit(response([FOUNDATION]));
    await flush();

    choose(element, FOUNDATION.Id, 'end');
    await flush();

    expect(BarnConfirmModal.open.mock.calls[0][0].label).toBe('c.Core_Affiliation_EndConfirmTitle');
    const fields = updateRecord.mock.calls[0][0].fields;
    expect(fields.Id).toBe(FOUNDATION.Id);
    expect(fields.End_Date__c).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: HARPER }]);
  });

  it('changes nothing when ending is cancelled, and never offers End It on a former one', async () => {
    BarnConfirmModal.open.mockResolvedValueOnce(false);
    const element = build('Contact', HARPER, {
      ...STAFF_ACCESS,
      fields: { ...STAFF_ACCESS.fields, End_Date__c: { updateable: true } }
    });
    graphql.emit(response([FOUNDATION, { ...CONGREGATION, Status__c: { value: 'Former' } }]));
    await flush();

    expect(element.shadowRoot.querySelectorAll('.end-affiliation').length).toBe(1);
    choose(element, FOUNDATION.Id, 'end');
    await flush();
    expect(updateRecord).not.toHaveBeenCalled();
  });

  it('offers neither Add affiliation nor Make primary to someone who can only read affiliations', async () => {
    const element = build('Contact', HARPER, READ_ONLY_ACCESS);
    graphql.emit(response([FOUNDATION, CONGREGATION]));
    await flush();

    expect(headlines(element)).toEqual(['The Union Foundation', 'Summit Congregation']);
    expect(element.shadowRoot.querySelector('[data-id="add-affiliation"]')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('.make-primary').length).toBe(0);
  });

  it('hides Make primary when the primary field cannot be edited', async () => {
    const element = build('Contact', HARPER, { ...STAFF_ACCESS, fields: {} });
    graphql.emit(response([FOUNDATION, CONGREGATION]));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-affiliation"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('.make-primary').length).toBe(0);
  });

  it('never offers to make a former affiliation the primary one', async () => {
    const element = build();
    graphql.emit(response([{ ...CONGREGATION, Status__c: { value: 'Former' } }]));
    await flush();

    expect(element.shadowRoot.querySelectorAll('.make-primary').length).toBe(0);
    expect(element.shadowRoot.querySelectorAll('[data-id="former-badge"]').length).toBe(1);
  });

  it('says so when there are no affiliations yet', async () => {
    const element = build();
    graphql.emit(response([]));
    await flush();

    const empty = element.shadowRoot.querySelector('[data-id="empty"]');
    expect(empty.heading).toBe('c.Core_Affiliation_EmptyHeading');

    element.shadowRoot.querySelector('[data-id="empty-add"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).not.toBeNull();
  });

  it('shows a message when the affiliations cannot be read', async () => {
    const element = build();
    graphql.emitErrors([{ message: 'no access' }]);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();
  });

  it('makes another affiliation primary as the user, then reads the card and the person again', async () => {
    const refresh = jest.fn().mockResolvedValue();
    const element = build('Account', FOUNDATION_ID);
    graphql.emit(
      response([
        { ...FOUNDATION, Is_Primary__c: { value: false } },
        { ...CONGREGATION, Organization__c: { value: FOUNDATION_ID } }
      ]),
      undefined,
      refresh
    );
    await flush();

    choose(element, FOUNDATION.Id, 'makePrimary');
    await flush();

    expect(updateRecord).toHaveBeenCalledWith({
      fields: { Id: FOUNDATION.Id, Is_Primary__c: true }
    });
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: FOUNDATION_ID },
      { recordId: HARPER }
    ]);
  });

  it('shows a message when the primary organization cannot be changed', async () => {
    updateRecord.mockRejectedValueOnce(new Error('no'));
    const element = build();
    graphql.emit(response([FOUNDATION, CONGREGATION]));
    await flush();

    choose(element, CONGREGATION.Id, 'makePrimary');
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]').message).toBe(
      'c.Core_Affiliation_MakePrimaryFailed'
    );
    expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
  });

  it('reads the card and the record again after a new affiliation is saved', async () => {
    const refresh = jest.fn().mockResolvedValue();
    const element = build();
    graphql.emit(response([]), undefined, refresh);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-affiliation"]').click();
    await flush();

    element.shadowRoot
      .querySelector('lightning-record-edit-form')
      .dispatchEvent(new CustomEvent('success'));
    await flush();

    expect(refresh).toHaveBeenCalledTimes(1);
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: HARPER }]);
  });

  it('fills in the person lookup on a person record and the organization lookup on an organization', async () => {
    const asContact = build('Contact');
    graphql.emit(response([]));
    getCardContext.emit({ ownerField: 'Contact__c', otherEndField: 'Organization__c' });
    await flush();
    asContact.shadowRoot.querySelector('[data-id="add-affiliation"]').click();
    await flush();

    let fields = Array.from(asContact.shadowRoot.querySelectorAll('lightning-input-field')).map(
      (n) => n.fieldName
    );
    expect(fields[0]).toBe('Contact__c');
    expect(fields[1]).toBe('Organization__c');

    // An organization with no affiliations yet: the server still says it is one, and the
    // other end is a contact in an org that stores people as contacts.
    const asOrganization = build('Account', FOUNDATION_ID);
    graphql.emit(response([]));
    getCardContext.emit({ ownerField: 'Organization__c', otherEndField: 'Contact__c' });
    await flush();
    asOrganization.shadowRoot.querySelector('[data-id="add-affiliation"]').click();
    await flush();

    fields = Array.from(asOrganization.shadowRoot.querySelectorAll('lightning-input-field')).map(
      (n) => n.fieldName
    );
    expect(fields[0]).toBe('Organization__c');
    expect(fields[1]).toBe('Contact__c');
  });

  it('fills in the person account lookups the server names in a person account org', async () => {
    const asOrganization = build('Account', FOUNDATION_ID);
    graphql.emit(response([FOUNDATION]));
    getCardContext.emit({ ownerField: 'Organization__c', otherEndField: 'Person_Account__c' });
    await flush();
    asOrganization.shadowRoot.querySelector('[data-id="add-affiliation"]').click();
    await flush();

    const fields = Array.from(
      asOrganization.shadowRoot.querySelectorAll('lightning-input-field')
    ).map((input) => input.fieldName);
    expect(fields[0]).toBe('Organization__c');
    expect(fields[1]).toBe('Person_Account__c');
  });
});
