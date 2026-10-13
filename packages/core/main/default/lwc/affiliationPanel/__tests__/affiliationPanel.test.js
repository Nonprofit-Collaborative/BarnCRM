import { createElement } from 'lwc';
import AffiliationPanel from 'c/affiliationPanel';
import getAffiliations from '@salesforce/apex/AffiliationController.getAffiliations';
import makePrimary from '@salesforce/apex/AffiliationController.makePrimary';
import getCardContext from '@salesforce/apex/AffiliationController.getCardContext';

jest.mock(
  '@salesforce/apex/AffiliationController.getAffiliations',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/AffiliationController.makePrimary', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/AffiliationController.getCardContext',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn() }), { virtual: true });

const FOUNDATION = {
  id: 'a0300000000000AAAA',
  affiliationNumber: 'AF-000001',
  personId: '0031000000000001AA',
  personName: 'Harper Garcia',
  organizationId: '0011000000000009AA',
  organizationName: 'The Union Foundation',
  role: 'Program Officer',
  status: 'Current',
  isFormer: false,
  isPrimary: true,
  description: null,
  readFromOrganization: false
};

const CONGREGATION = {
  id: 'a0300000000000BBBB',
  affiliationNumber: 'AF-000002',
  personId: '0031000000000001AA',
  personName: 'Harper Garcia',
  organizationId: '0011000000000010AA',
  organizationName: 'Summit Congregation',
  role: 'Board chair',
  status: 'Current',
  isFormer: false,
  isPrimary: false,
  description: null,
  readFromOrganization: false
};

const FROM_THE_ORGANIZATION = { ...FOUNDATION, readFromOrganization: true };

function build(objectApiName = 'Contact') {
  const element = createElement('c-affiliation-panel', { is: AffiliationPanel });
  element.recordId = '0031000000000001AA';
  element.objectApiName = objectApiName;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-affiliation-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('names the organization on a person record', async () => {
    const element = build();
    getAffiliations.emit([FOUNDATION, CONGREGATION]);
    await flush();

    const headlines = Array.from(
      element.shadowRoot.querySelectorAll('[data-id="affiliation-headline"]')
    ).map((node) => node.textContent);
    expect(headlines).toEqual(['The Union Foundation', 'Summit Congregation']);
  });

  it('names the person when the card is read from the organization', async () => {
    const element = build('Account');
    getAffiliations.emit([FROM_THE_ORGANIZATION]);
    await flush();

    const headline = element.shadowRoot.querySelector('[data-id="affiliation-headline"]');
    expect(headline.textContent).toBe('Harper Garcia');
  });

  it('badges the primary organization and offers to move the badge', async () => {
    const element = build();
    getAffiliations.emit([FOUNDATION, CONGREGATION]);
    await flush();

    expect(element.shadowRoot.querySelectorAll('[data-id="primary-badge"]').length).toBe(1);
    const buttons = element.shadowRoot.querySelectorAll('.make-primary');
    expect(buttons.length).toBe(1);
    expect(buttons[0].dataset.id).toBe(CONGREGATION.id);
  });

  it('never offers to make a former affiliation the primary one', async () => {
    const element = build();
    getAffiliations.emit([{ ...CONGREGATION, status: 'Former', isFormer: true }]);
    await flush();

    expect(element.shadowRoot.querySelectorAll('.make-primary').length).toBe(0);
    expect(element.shadowRoot.querySelectorAll('[data-id="former-badge"]').length).toBe(1);
  });

  it('says so when there are no affiliations yet', async () => {
    const element = build();
    getAffiliations.emit([]);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
  });

  it('shows a message when the affiliations cannot be read', async () => {
    const element = build();
    getAffiliations.error();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
  });

  it('moves the badge when another affiliation is made primary', async () => {
    makePrimary.mockResolvedValue([
      { ...CONGREGATION, isPrimary: true },
      { ...FOUNDATION, isPrimary: false }
    ]);
    const element = build();
    getAffiliations.emit([FOUNDATION, CONGREGATION]);
    await flush();

    element.shadowRoot.querySelector('.make-primary').click();
    await flush();

    expect(makePrimary).toHaveBeenCalledWith({
      affiliationId: CONGREGATION.id,
      ownerId: '0031000000000001AA'
    });
    const buttons = element.shadowRoot.querySelectorAll('.make-primary');
    expect(buttons[0].dataset.id).toBe(FOUNDATION.id);
  });

  it('shows a message when the primary organization cannot be changed', async () => {
    makePrimary.mockRejectedValue(new Error('no'));
    const element = build();
    getAffiliations.emit([FOUNDATION, CONGREGATION]);
    await flush();

    element.shadowRoot.querySelector('.make-primary').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
  });

  it('fills in the person lookup on a person record and the organization lookup on an organization', async () => {
    const asContact = build('Contact');
    getAffiliations.emit([]);
    getCardContext.emit({ ownerField: 'Contact__c', otherEndField: 'Organization__c' });
    await flush();
    asContact.shadowRoot.querySelector('[data-id="add-affiliation"]').click();
    await flush();

    let fields = Array.from(asContact.shadowRoot.querySelectorAll('lightning-input-field')).map(
      (node) => node.fieldName
    );
    expect(fields[0]).toBe('Contact__c');
    expect(fields[1]).toBe('Organization__c');

    // An organization with no affiliations yet: the server still says it is one, and the
    // other end is a contact in an org that stores people as contacts.
    const asOrganization = build('Account');
    getAffiliations.emit([]);
    getCardContext.emit({ ownerField: 'Organization__c', otherEndField: 'Contact__c' });
    await flush();
    asOrganization.shadowRoot.querySelector('[data-id="add-affiliation"]').click();
    await flush();

    fields = Array.from(asOrganization.shadowRoot.querySelectorAll('lightning-input-field')).map(
      (node) => node.fieldName
    );
    expect(fields[0]).toBe('Organization__c');
    expect(fields[1]).toBe('Contact__c');
  });

  it('fills in the person account lookups the server names in a person account org', async () => {
    const asOrganization = build('Account');
    getAffiliations.emit([FROM_THE_ORGANIZATION]);
    getCardContext.emit({ ownerField: 'Organization__c', otherEndField: 'Person_Account__c' });
    await flush();
    asOrganization.shadowRoot.querySelector('[data-id="add-affiliation"]').click();
    await flush();

    const fields = Array.from(
      asOrganization.shadowRoot.querySelectorAll('lightning-input-field')
    ).map((node) => node.fieldName);
    expect(fields[0]).toBe('Organization__c');
    expect(fields[1]).toBe('Person_Account__c');
  });
});
