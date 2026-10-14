import { createElement } from 'lwc';
import AffiliationPanel from 'c/affiliationPanel';
import getCardContext from '@salesforce/apex/AffiliationController.getCardContext';
import { graphql } from 'lightning/graphql';
import { notifyRecordUpdateAvailable, updateRecord } from 'lightning/uiRecordApi';

const HARPER = '0031000000000001AA';
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

function build(objectApiName = 'Contact', recordId = HARPER) {
  const element = createElement('c-affiliation-panel', { is: AffiliationPanel });
  element.recordId = recordId;
  element.objectApiName = objectApiName;
  document.body.appendChild(element);
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
    const buttons = element.shadowRoot.querySelectorAll('.make-primary');
    expect(buttons.length).toBe(1);
    expect(buttons[0].dataset.id).toBe(CONGREGATION.Id);
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

    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
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

    element.shadowRoot.querySelector('.make-primary').click();
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

    element.shadowRoot.querySelector('.make-primary').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
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
