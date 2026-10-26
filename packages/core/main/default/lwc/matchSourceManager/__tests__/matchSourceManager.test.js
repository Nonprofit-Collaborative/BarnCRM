import { createElement } from 'lwc';
import MatchSourceManager from 'c/matchSourceManager';
import getView from '@salesforce/apex/MatchSourceController.getView';
import describeObject from '@salesforce/apex/MatchSourceController.describeObject';
import tryValue from '@salesforce/apex/MatchSourceController.tryValue';
import saveRow from '@salesforce/apex/CustomMetadataManagerController.saveRow';
import setArchived from '@salesforce/apex/CustomMetadataManagerController.setArchived';
import getOutcome from '@salesforce/apex/CustomMetadataManagerController.getOutcome';

jest.mock('@salesforce/apex/MatchSourceController.getView', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MatchSourceController.describeObject', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MatchSourceController.tryValue', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/CustomMetadataManagerController.saveRow',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/CustomMetadataManagerController.setArchived',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/CustomMetadataManagerController.getOutcome',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_CmdtManager_Saved',
  () => ({ default: 'Saved. {0} is in the list.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_MatchLogic_TryComparedAs',
  () => ({ default: 'Compared as: {0}' }),
  {
    virtual: true
  }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

function source(overrides) {
  return {
    developerName: 'Address_Person',
    label: 'Address (person)',
    shipped: true,
    active: true,
    usable: true,
    objectLabel: 'Address',
    valueFieldLabel: 'Street',
    postalFieldLabel: 'Postal Code',
    parentFieldLabel: 'Contact',
    linksTo: 'A person',
    values: {
      Object_Name__c: 'Address__c',
      Value_Field__c: 'Street__c',
      Postal_Code_Field__c: 'Postal_Code__c',
      Parent_Field__c: 'Contact__c',
      Normalization__c: 'Address'
    },
    ...overrides
  };
}

function view(canEdit, sources) {
  return {
    canEdit,
    sources,
    normalizations: [
      { label: 'Email: spaces trimmed', value: 'Email' },
      { label: 'Phone: digits only', value: 'Phone' },
      { label: 'Address: street and postal code', value: 'Address' }
    ]
  };
}

async function render() {
  const element = createElement('c-match-source-manager', { is: MatchSourceManager });
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => Array.from(element.shadowRoot.querySelectorAll(selector));
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-match-source-manager', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it('says what each source compares, in words, and which the org cannot use', async () => {
    getView.mockResolvedValue(
      view(false, [
        source(),
        source({
          developerName: 'Org_Gone_abcd',
          label: 'Gone',
          shipped: false,
          usable: false,
          objectLabel: null,
          values: { Object_Name__c: 'Gone__c', Normalization__c: 'Email' }
        })
      ])
    );
    const element = await render();

    const sources = all(element, '[data-id="source"]');
    expect(sources).toHaveLength(2);
    expect(sources[0].querySelector('[data-id="object"]').textContent).toBe('Address');
    expect(sources[0].querySelector('[data-id="links-to"]').textContent).toBe('A person');
    expect(sources[0].querySelector('[data-id="compare"]').textContent).toBe(
      'Address: street and postal code'
    );
    expect(sources[0].querySelector('[data-id="not-usable"]')).toBeNull();
    expect(sources[1].querySelector('[data-id="object"]').textContent).toBe('Gone__c');
    expect(sources[1].querySelector('[data-id="not-usable"]')).not.toBeNull();
  });

  it('is read only without Metadata Admin, though a value can still be tried', async () => {
    getView.mockResolvedValue(view(false, [source({ shipped: false })]));
    const element = await render();

    expect(one(element, '[data-id="read-only"]')).not.toBeNull();
    expect(one(element, '[data-id="add"]')).toBeNull();
    expect(one(element, '[data-id="edit"]')).toBeNull();
    expect(one(element, '[data-id="toggle"]')).toBeNull();
    expect(one(element, '[data-id="try"]')).not.toBeNull();
  });

  it('lets a shipped source be deactivated but not edited', async () => {
    getView.mockResolvedValue(view(true, [source()]));
    setArchived.mockResolvedValue('0Af000000000001');
    const element = await render();

    expect(one(element, '[data-id="edit"]')).toBeNull();
    one(element, '[data-id="toggle"]').click();
    await flush();

    expect(setArchived).toHaveBeenCalledWith({
      typeName: 'Match_Source__mdt',
      developerName: 'Address_Person',
      archived: true
    });
    expect(one(element, '[data-id="status"]')).not.toBeNull();
  });

  it('adds a source with the fields its object offers, and waits for the save', async () => {
    jest.useFakeTimers();
    getView.mockResolvedValue(view(true, []));
    describeObject.mockResolvedValue({
      objectName: 'Volunteer_Email__c',
      objectLabel: 'Volunteer Email',
      valueFields: [{ label: 'Email (Email__c)', value: 'Email__c' }],
      parentFields: [{ label: 'Contact (Contact__c)', value: 'Contact__c' }]
    });
    saveRow.mockResolvedValue('0Af000000000002');
    getOutcome.mockResolvedValue({ status: 'Succeeded' });
    const element = await render();

    one(element, '[data-id="add"]').click();
    await flush();
    const change = (id, value) => {
      const input = one(element, `[data-id="${id}"]`);
      input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
    };
    change('form-name', 'Volunteer email');
    change('form-object', 'Volunteer_Email__c');
    await flush();
    one(element, '[data-id="find-fields"]').click();
    await flush();
    expect(describeObject).toHaveBeenCalledWith({ objectName: 'Volunteer_Email__c' });
    expect(one(element, '[data-id="form-value"]').options).toEqual([
      { label: 'Email (Email__c)', value: 'Email__c' }
    ]);
    expect(one(element, '[data-id="form-postal"]')).toBeNull();
    change('form-value', 'Email__c');
    change('form-parent', 'Contact__c');
    change('form-normalization', 'Email');
    await flush();
    one(element, '[data-id="form-save"]').click();
    await flush();

    expect(saveRow).toHaveBeenCalledWith({
      typeName: 'Match_Source__mdt',
      input: {
        developerName: null,
        label: 'Volunteer email',
        values: {
          Object_Name__c: 'Volunteer_Email__c',
          Value_Field__c: 'Email__c',
          Postal_Code_Field__c: '',
          Parent_Field__c: 'Contact__c',
          Normalization__c: 'Email'
        }
      }
    });
    expect(one(element, '[data-id="form"]')).toBeNull();

    jest.advanceTimersByTime(3000);
    await flush();
    await flush();
    expect(getOutcome).toHaveBeenCalledWith({ deploymentId: '0Af000000000002' });
    expect(one(element, '[data-id="status"]').textContent).toContain(
      'Saved. Volunteer email is in the list.'
    );
    expect(getView).toHaveBeenCalledTimes(2);
  });

  it('shows a refused save as it is', async () => {
    getView.mockResolvedValue(
      view(true, [source({ shipped: false, developerName: 'Org_Mine_abcd' })])
    );
    describeObject.mockResolvedValue({ valueFields: [], parentFields: [] });
    saveRow.mockRejectedValue({
      body: { message: 'An address source needs a postal code field.' }
    });
    const element = await render();

    one(element, '[data-id="edit"]').click();
    await flush();
    expect(describeObject).toHaveBeenCalledWith({ objectName: 'Address__c' });
    expect(one(element, '[data-id="form-value"]').options).toEqual([
      { label: 'Street__c', value: 'Street__c' }
    ]);
    one(element, '[data-id="form-save"]').click();
    await flush();

    expect(one(element, '[data-id="error"]').textContent).toContain(
      'An address source needs a postal code field.'
    );
    expect(one(element, '[data-id="form"]')).not.toBeNull();
  });

  it('tries a value and lists the records that would match', async () => {
    getView.mockResolvedValue(view(false, [source()]));
    tryValue.mockResolvedValue({
      comparedAs: '12 n main st|02139',
      records: [{ label: 'Person: Ana Ruiz', value: '003000000000001' }]
    });
    const element = await render();

    one(element, '[data-id="try"]').click();
    await flush();
    one(element, '[data-id="try-value"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '12 North Main Street' } })
    );
    one(element, '[data-id="try-postal"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '02139' } })
    );
    one(element, '[data-id="try-run"]').click();
    await flush();

    expect(tryValue).toHaveBeenCalledWith({
      label: 'Address (person)',
      values: source().values,
      value: '12 North Main Street',
      postal: '02139'
    });
    expect(one(element, '[data-id="try-compared"]').textContent).toContain(
      'Compared as: 12 n main st|02139'
    );
    expect(one(element, '[data-id="try-records"]').textContent).toContain('Person: Ana Ruiz');
    expect(one(element, '[data-id="try-none"]')).toBeNull();
  });

  it('says so when nobody holds the value', async () => {
    getView.mockResolvedValue(view(false, [source({ values: { Normalization__c: 'Email' } })]));
    tryValue.mockResolvedValue({ comparedAs: 'nobody@example.org', records: [] });
    const element = await render();

    one(element, '[data-id="try"]').click();
    await flush();
    expect(one(element, '[data-id="try-postal"]')).toBeNull();
    one(element, '[data-id="try-run"]').click();
    await flush();

    expect(one(element, '[data-id="try-none"]')).not.toBeNull();
  });

  it('says why the list could not be read', async () => {
    getView.mockRejectedValue({ body: { message: 'Matching logic needs a permission.' } });
    const element = await render();

    expect(one(element, '[data-id="error"]').textContent).toContain(
      'Matching logic needs a permission.'
    );
    expect(all(element, '[data-id="source"]')).toHaveLength(0);
  });
});
