// The object info test wire adapter is emitted to on purpose, which is how a wired component
// is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import RelationshipPanel from 'c/relationshipPanel';
import { graphql } from 'lightning/graphql';
import { deleteRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

const HARPER = '0031000000000001AA';

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

    expect(names(element)).toEqual(['Luis Garcia', 'c.Core_Relationship_UnnamedPerson']);
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

  it('removes a relationship as the user and reads the card again', async () => {
    const refresh = jest.fn().mockResolvedValue();
    const element = build();
    graphql.emit(response([SPOUSE, FORMER_COLLEAGUE]), undefined, refresh);
    await flush();

    element.shadowRoot.querySelector('.remove-relationship').click();
    await flush();

    expect(deleteRecord).toHaveBeenCalledWith(SPOUSE.Id);
    expect(refresh).toHaveBeenCalledTimes(1);

    graphql.emit(response([FORMER_COLLEAGUE]), undefined, refresh);
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="relationship-card"]').length).toBe(1);
  });

  it('shows a message when a relationship cannot be removed', async () => {
    deleteRecord.mockRejectedValueOnce(new Error('no'));
    const element = build();
    graphql.emit(response([SPOUSE]));
    await flush();

    element.shadowRoot.querySelector('.remove-relationship').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
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
});
