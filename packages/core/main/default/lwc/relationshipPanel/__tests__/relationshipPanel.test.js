// The object info test wire adapter is emitted to on purpose, which is how a wired component
// is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import RelationshipPanel from 'c/relationshipPanel';
import { graphql } from 'lightning/graphql';
import { deleteRecord, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import getTurnedOffTypes from '@salesforce/apex/RelationshipController.getTurnedOffTypes';
import isFeatureOn from '@salesforce/apex/RelationshipController.isFeatureOn';
import BarnConfirmModal from 'c/barnConfirmModal';

jest.mock(
  '@salesforce/apex/RelationshipController.getTurnedOffTypes',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/RelationshipController.isFeatureOn',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

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

/** Picks an action from the first row's menu (Edit, End It or Remove). */
function choose(element, value) {
  element.shadowRoot
    .querySelector('.row-menu')
    .dispatchEvent(new CustomEvent('select', { detail: { value } }));
}

/** One relationship as the GraphQL query returns it. */
function node({ id, relatedName, type, status, description = null, asAccount = false }) {
  return {
    Id: id,
    Related_Contact__r: asAccount ? null : { Name: { value: relatedName } },
    Related_Person_Account__r: asAccount ? { Name: { value: relatedName } } : null,
    Type__c: { value: type, displayValue: type },
    Status__c: { value: status },
    Description__c: { value: description }
  };
}

function response(nodes) {
  return { uiapi: { query: { Relationship__c: { edges: nodes.map((n) => ({ node: n })) } } } };
}

const SPOUSE = node({
  id: 'a0200000000000AAAA',
  relatedName: 'Luis Garcia',
  type: 'Spouse',
  status: 'Current'
});

const FORMER_COLLEAGUE = node({
  id: 'a0200000000000BBBB',
  relatedName: 'Jordan Reyes',
  type: 'Colleague',
  status: 'Former',
  description: 'Worked together at the food bank'
});

/** What the platform says a user may do with relationships: Staff can, Read Only only reads. */
const STAFF_ACCESS = { createable: true, updateable: true, deletable: true, fields: {} };
const READ_ONLY_ACCESS = { createable: false, updateable: false, deletable: false, fields: {} };

function build(objectApiName = 'Contact', access = STAFF_ACCESS) {
  const element = createElement('c-relationship-panel', { is: RelationshipPanel });
  element.recordId = HARPER;
  element.objectApiName = objectApiName;
  document.body.appendChild(element);
  getObjectInfo.emit(access);
  isFeatureOn.emit(true);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function names(element) {
  return Array.from(element.shadowRoot.querySelectorAll('[data-id="related-person"]')).map(
    (n) => n.textContent
  );
}

describe('c-relationship-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows nothing while the Relationships feature is off (D-184)', async () => {
    const element = build();
    isFeatureOn.emit(false);
    graphql.emit(response([SPOUSE]));
    await flush();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
    isFeatureOn.emit(true);
    await flush();
    expect(element.shadowRoot.querySelector('lightning-card')).not.toBeNull();
  });

  it('offers neither Add relationship nor Remove to someone who can only read relationships', async () => {
    const element = build('Contact', READ_ONLY_ACCESS);
    graphql.emit(response([SPOUSE, FORMER_COLLEAGUE]));
    await flush();

    expect(names(element)).toEqual(['Luis Garcia', 'Jordan Reyes']);
    expect(element.shadowRoot.querySelector('[data-id="add-relationship"]')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('.remove-relationship').length).toBe(0);
  });

  it('offers Remove only to someone who can delete relationships', async () => {
    const element = build('Contact', { ...STAFF_ACCESS, deletable: false });
    graphql.emit(response([SPOUSE]));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-relationship"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('.remove-relationship').length).toBe(0);
  });

  it('asks for the relationships of the person it sits on', async () => {
    build();
    await flush();
    expect(graphql.getLastConfig().variables).toEqual({ personId: HARPER });
  });

  it('shows a loading state, not "no relationships", until the relationships arrive', async () => {
    const element = build();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="loading"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();

    graphql.emit(response([SPOUSE]));
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="loading"]')).toBeNull();
  });

  it('shows a card for every relationship this person has, current ones first', async () => {
    const element = build();
    graphql.emit(response([FORMER_COLLEAGUE, SPOUSE]));
    await flush();

    const cards = element.shadowRoot.querySelectorAll('[data-id="relationship-card"]');
    expect(cards.length).toBe(2);
    expect(names(element)).toEqual(['Luis Garcia', 'Jordan Reyes']);
  });

  it('names a related person held as an account, and stands in when there is no name', async () => {
    const element = build('Account');
    graphql.emit(
      response([
        node({
          id: 'a0200000000000CCCC',
          relatedName: 'Luis Garcia',
          type: 'Spouse',
          status: 'Current',
          asAccount: true
        }),
        { ...FORMER_COLLEAGUE, Related_Contact__r: null }
      ])
    );
    await flush();

    expect(names(element)).toEqual(['Luis Garcia', 'c.Core_Affiliation_UnnamedPerson']);
  });

  it('names the type from this side and badges the ones that have ended', async () => {
    const element = build();
    graphql.emit(response([SPOUSE, FORMER_COLLEAGUE]));
    await flush();

    const types = Array.from(
      element.shadowRoot.querySelectorAll('[data-id="relationship-type"]')
    ).map((n) => n.textContent);
    expect(types).toEqual(['Spouse', 'Colleague']);
    expect(element.shadowRoot.querySelectorAll('[data-id="former-badge"]').length).toBe(1);
  });

  it('says so when the person has no relationships yet', async () => {
    const element = build();
    graphql.emit(response([]));
    await flush();

    const empty = element.shadowRoot.querySelector('[data-id="empty"]');
    expect(empty.heading).toBe('c.Core_Relationship_EmptyHeading');
    expect(element.shadowRoot.querySelectorAll('[data-id="relationship-card"]').length).toBe(0);

    element.shadowRoot.querySelector('[data-id="empty-add"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).not.toBeNull();
  });

  it('shows a message when the relationships cannot be read', async () => {
    const element = build();
    graphql.emitErrors([{ message: 'no access' }]);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();
  });

  it('asks before removing, and removes nothing when the person keeps it', async () => {
    BarnConfirmModal.open.mockResolvedValueOnce(false);
    const element = build();
    graphql.emit(response([SPOUSE]));
    await flush();

    choose(element, 'remove');
    await flush();

    const asked = BarnConfirmModal.open.mock.calls[0][0];
    expect(asked.label).toBe('c.Core_Relationship_RemoveConfirmTitle');
    expect(asked.message).toBe('c.Core_Relationship_RemoveConfirm');
    expect(asked.confirmVariant).toBe('destructive');
    expect(deleteRecord).not.toHaveBeenCalled();
  });

  it('removes a relationship as the user and reads the card again', async () => {
    BarnConfirmModal.open.mockResolvedValueOnce(true);
    const refresh = jest.fn().mockResolvedValue();
    const element = build();
    graphql.emit(response([SPOUSE, FORMER_COLLEAGUE]), undefined, refresh);
    await flush();

    choose(element, 'remove');
    await flush();

    expect(deleteRecord).toHaveBeenCalledWith(SPOUSE.Id);
    expect(refresh).toHaveBeenCalledTimes(1);

    graphql.emit(response([FORMER_COLLEAGUE]), undefined, refresh);
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="relationship-card"]').length).toBe(1);
  });

  it('shows a message when a relationship cannot be removed', async () => {
    BarnConfirmModal.open.mockResolvedValueOnce(true);
    deleteRecord.mockRejectedValueOnce(new Error('no'));
    const element = build();
    graphql.emit(response([SPOUSE]));
    await flush();

    choose(element, 'remove');
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]').message).toBe(
      'c.Core_Relationship_RemoveFailed'
    );
  });

  it('links each row to its relationship and opens the edit form from the row menu', async () => {
    const element = build();
    graphql.emit(response([SPOUSE]));
    await flush();

    const link = element.shadowRoot.querySelector('[data-id="related-person"]');
    expect(link.getAttribute('href')).toBe(`/${SPOUSE.Id}`);

    choose(element, 'edit');
    await flush();
    expect(mockNavigate.mock.calls[0][0]).toEqual({
      type: 'standard__recordPage',
      attributes: { recordId: SPOUSE.Id, objectApiName: 'Relationship__c', actionName: 'edit' }
    });
  });

  it('ends a current relationship today after a confirm, offering End It only on current ones', async () => {
    BarnConfirmModal.open.mockResolvedValueOnce(true);
    const refresh = jest.fn().mockResolvedValue();
    const element = build('Contact', {
      ...STAFF_ACCESS,
      fields: { End_Date__c: { updateable: true } }
    });
    graphql.emit(response([SPOUSE, FORMER_COLLEAGUE]), undefined, refresh);
    await flush();

    expect(element.shadowRoot.querySelectorAll('.end-relationship').length).toBe(1);
    choose(element, 'end');
    await flush();

    expect(BarnConfirmModal.open.mock.calls[0][0].label).toBe(
      'c.Core_Relationship_EndConfirmTitle'
    );
    const fields = updateRecord.mock.calls[0][0].fields;
    expect(fields.Id).toBe(SPOUSE.Id);
    expect(fields.End_Date__c).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it('offers no End It without edit access to End Date', async () => {
    const element = build();
    graphql.emit(response([SPOUSE]));
    await flush();
    expect(element.shadowRoot.querySelectorAll('.end-relationship').length).toBe(0);
  });

  it('reads the card again after a new relationship is saved', async () => {
    const refresh = jest.fn().mockResolvedValue();
    const element = build();
    graphql.emit(response([]), undefined, refresh);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-relationship"]').click();
    await flush();

    element.shadowRoot
      .querySelector('lightning-record-edit-form')
      .dispatchEvent(new CustomEvent('success'));
    await flush();

    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it('fills in the contact lookups on a contact record and the account lookups on an account', async () => {
    const asContact = build('Contact');
    graphql.emit(response([]));
    await flush();
    asContact.shadowRoot.querySelector('[data-id="add-relationship"]').click();
    await flush();

    let fields = Array.from(asContact.shadowRoot.querySelectorAll('lightning-input-field')).map(
      (n) => n.fieldName
    );
    expect(fields[0]).toBe('Contact__c');
    expect(fields[1]).toBe('Related_Contact__c');

    const asAccount = build('Account');
    graphql.emit(response([]));
    await flush();
    asAccount.shadowRoot.querySelector('[data-id="add-relationship"]').click();
    await flush();

    fields = Array.from(asAccount.shadowRoot.querySelectorAll('lightning-input-field')).map(
      (n) => n.fieldName
    );
    expect(fields[0]).toBe('Person_Account__c');
    expect(fields[1]).toBe('Related_Person_Account__c');
  });

  it('offers every Type but the ones turned off, and saves the one chosen', async () => {
    const element = build();
    graphql.emit(response([]));
    getPicklistValues.emit({
      values: [
        { label: 'Spouse', value: 'Spouse' },
        { label: 'Grandparent', value: 'Grandparent' },
        { label: 'Friend', value: 'Friend' }
      ]
    });
    getTurnedOffTypes.emit(['grandparent']);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-relationship"]').click();
    await flush();

    const fields = Array.from(element.shadowRoot.querySelectorAll('lightning-input-field')).map(
      (n) => n.fieldName
    );
    expect(fields).not.toContain('Type__c');
    const picker = element.shadowRoot.querySelector('[data-id="type"]');
    expect(picker.options.map((o) => o.value)).toEqual(['Spouse', 'Friend']);

    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'Friend' } }));
    await flush();
    const form = element.shadowRoot.querySelector('lightning-record-edit-form');
    form.submit = jest.fn();
    picker.reportValidity = () => true;
    form.dispatchEvent(
      new CustomEvent('submit', { detail: { fields: { Status__c: 'Current' } }, cancelable: true })
    );

    expect(form.submit).toHaveBeenCalledWith({ Status__c: 'Current', Type__c: 'Friend' });
  });

  it('saves nothing until a Type is chosen', async () => {
    const element = build();
    graphql.emit(response([]));
    await flush();
    element.shadowRoot.querySelector('[data-id="add-relationship"]').click();
    await flush();

    const form = element.shadowRoot.querySelector('lightning-record-edit-form');
    form.submit = jest.fn();
    element.shadowRoot.querySelector('[data-id="type"]').reportValidity = () => false;
    form.dispatchEvent(new CustomEvent('submit', { detail: { fields: {} }, cancelable: true }));

    expect(form.submit).not.toHaveBeenCalled();
  });
});
