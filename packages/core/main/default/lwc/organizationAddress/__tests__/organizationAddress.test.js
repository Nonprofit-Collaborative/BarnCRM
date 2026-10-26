import { createElement } from 'lwc';
import OrganizationAddress from 'c/organizationAddress';

jest.mock(
  '@salesforce/label/c.Core_OrganizationAddress_Heading',
  () => ({ default: 'Organization address' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_OrganizationAddress_Hint',
  () => ({ default: 'Leave it blank, or fill in the required parts.' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Core_OrganizationAddress_Street', () => ({ default: 'Street' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_OrganizationAddress_Street2', () => ({ default: 'Street 2' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_OrganizationAddress_City', () => ({ default: 'City' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_OrganizationAddress_State', () => ({ default: 'State' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_OrganizationAddress_PostalCode',
  () => ({ default: 'Zip Code' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Core_OrganizationAddress_Country', () => ({ default: 'Country' }), {
  virtual: true
});

function build(props = {}) {
  const element = createElement('c-organization-address', { is: OrganizationAddress });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function inputs(element) {
  return Array.from(element.shadowRoot.querySelectorAll('lightning-input'));
}

function inputFor(element, key) {
  return element.shadowRoot.querySelector(`lightning-input[data-key="${key}"]`);
}

describe('c-organization-address', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('lays the address out like a Salesforce address, in order', () => {
    const element = build();

    expect(inputs(element).map((input) => input.label)).toEqual([
      'Street',
      'Street 2',
      'City',
      'State',
      'Zip Code',
      'Country'
    ]);
    const row = element.shadowRoot.querySelector('.slds-grid');
    expect(Array.from(row.querySelectorAll('lightning-input')).map((input) => input.label)).toEqual(
      ['City', 'State', 'Zip Code']
    );
  });

  it('shows the saved values', () => {
    const element = build({
      values: { Organization_Street__c: '14 Bridge Street', Organization_Country__c: 'USA' }
    });

    expect(inputFor(element, 'Organization_Street__c').value).toBe('14 Bridge Street');
    expect(inputFor(element, 'Organization_Country__c').value).toBe('USA');
    expect(inputFor(element, 'Organization_City__c').value).toBe('');
  });

  it('marks nothing required while the whole address is blank', () => {
    const element = build({ values: {} });

    inputs(element).forEach((input) => expect(input.required).toBeFalsy());
  });

  it('marks Street, City, State and Zip Code required once any part is filled', () => {
    const element = build({ values: { Organization_City__c: 'Springfield' } });

    expect(inputFor(element, 'Organization_Street__c').required).toBe(true);
    expect(inputFor(element, 'Organization_City__c').required).toBe(true);
    expect(inputFor(element, 'Organization_State__c').required).toBe(true);
    expect(inputFor(element, 'Organization_Postal_Code__c').required).toBe(true);
    expect(inputFor(element, 'Organization_Street_2__c').required).toBeFalsy();
    expect(inputFor(element, 'Organization_Country__c').required).toBeFalsy();
  });

  it('does not count Street 2 or Country as a blank address when they are the only parts', () => {
    const element = build({ values: { Organization_Country__c: 'USA' } });

    expect(inputFor(element, 'Organization_Street__c').required).toBe(true);
  });

  it('reports which part changed and its new value', () => {
    const element = build();
    const changed = jest.fn();
    element.addEventListener('partchange', changed);

    const state = inputFor(element, 'Organization_State__c');
    state.value = 'IL';
    state.dispatchEvent(new CustomEvent('change'));

    expect(changed.mock.calls[0][0].detail).toEqual({
      key: 'Organization_State__c',
      value: 'IL'
    });
  });

  it('shows the heading and the line about what may be left blank only when titled', () => {
    const plain = build();
    expect(plain.shadowRoot.querySelector('legend')).toBeNull();

    const titled = build({ titled: true });
    expect(titled.shadowRoot.querySelector('legend').textContent).toContain('Organization address');
    expect(titled.shadowRoot.textContent).toContain('Leave it blank');
  });

  it('is read only when disabled', () => {
    const element = build({ disabled: true });

    inputs(element).forEach((input) => expect(input.disabled).toBe(true));
  });

  it('asks every box to report, not only the first that is invalid', () => {
    const element = build({ values: { Organization_City__c: 'Springfield' } });
    const boxes = inputs(element);
    boxes.forEach((box) => {
      box.reportValidity = jest.fn(() => box.required !== true || box.value !== '');
    });

    const valid = element.reportValidity();

    expect(valid).toBe(false);
    boxes.forEach((box) => expect(box.reportValidity).toHaveBeenCalledTimes(1));
  });

  it('is valid when every box is', () => {
    const element = build();
    inputs(element).forEach((box) => {
      box.reportValidity = jest.fn(() => true);
    });

    expect(element.reportValidity()).toBe(true);
  });
});
