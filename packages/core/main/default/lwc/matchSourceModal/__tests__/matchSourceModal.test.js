import { createElement } from 'lwc';
import MatchSourceModal from 'c/matchSourceModal';
import describeObject from '@salesforce/apex/MatchSourceController.describeObject';
import saveRow from '@salesforce/apex/CustomMetadataManagerController.saveRow';

jest.mock('@salesforce/apex/MatchSourceController.describeObject', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/CustomMetadataManagerController.saveRow',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

const NORMALIZATIONS = [
  { label: 'Email: spaces trimmed', value: 'Email' },
  { label: 'Address: street and postal code', value: 'Address' }
];

async function render(source) {
  const element = createElement('c-match-source-modal', { is: MatchSourceModal });
  element.label = 'New Match Source';
  element.source = source;
  element.normalizations = NORMALIZATIONS;
  const closed = jest.fn();
  element.addEventListener('close', (event) => closed(event.detail));
  document.body.appendChild(element);
  await flush();
  return { element, closed };
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);
const change = (element, id, value) =>
  one(element, `[data-id="${id}"]`).dispatchEvent(new CustomEvent('change', { detail: { value } }));

describe('c-match-source-modal', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('adds a source with the fields its object offers, and closes once the save starts', async () => {
    describeObject.mockResolvedValue({
      valueFields: [{ label: 'Email (Email__c)', value: 'Email__c' }],
      parentFields: [{ label: 'Contact (Contact__c)', value: 'Contact__c' }]
    });
    saveRow.mockResolvedValue('0Af000000000002');
    const { element, closed } = await render(undefined);

    expect(describeObject).not.toHaveBeenCalled();
    expect(one(element, '[data-id="form-normalization"]').options).toEqual(NORMALIZATIONS);
    change(element, 'form-name', 'Volunteer email');
    change(element, 'form-object', 'Volunteer_Email__c');
    await flush();
    one(element, '[data-id="find-fields"]').click();
    await flush();
    expect(describeObject).toHaveBeenCalledWith({ objectName: 'Volunteer_Email__c' });
    expect(one(element, '[data-id="form-value"]').options).toEqual([
      { label: 'Email (Email__c)', value: 'Email__c' }
    ]);
    expect(one(element, '[data-id="form-postal"]')).toBeNull();
    change(element, 'form-value', 'Email__c');
    change(element, 'form-parent', 'Contact__c');
    change(element, 'form-normalization', 'Email');
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
    expect(closed).toHaveBeenCalledWith({ jobId: '0Af000000000002', label: 'Volunteer email' });
  });

  it('edits a source, asks for a postal code field on an address, and keeps a refused save open', async () => {
    describeObject.mockResolvedValue({ valueFields: [], parentFields: [] });
    saveRow.mockRejectedValue({
      body: { message: 'An address source needs a postal code field.' }
    });
    const { element, closed } = await render({
      developerName: 'Org_Mine_abcd',
      label: 'Mine',
      values: {
        Object_Name__c: 'Address__c',
        Value_Field__c: 'Street__c',
        Parent_Field__c: 'Contact__c',
        Normalization__c: 'Address'
      }
    });

    expect(describeObject).toHaveBeenCalledWith({ objectName: 'Address__c' });
    expect(one(element, '[data-id="form-value"]').options).toEqual([
      { label: 'Street__c', value: 'Street__c' }
    ]);
    expect(one(element, '[data-id="form-postal"]')).not.toBeNull();
    one(element, '[data-id="form-save"]').click();
    await flush();

    expect(saveRow.mock.calls[0][0].input.developerName).toBe('Org_Mine_abcd');
    expect(one(element, '[data-id="error"]').textContent).toContain(
      'An address source needs a postal code field.'
    );
    expect(closed).not.toHaveBeenCalled();
  });

  it('closes with nothing on Cancel, and says why an object could not be read', async () => {
    describeObject.mockRejectedValue({
      body: { message: 'Not_An_Object__c is not an object in this org.' }
    });
    const { element, closed } = await render(undefined);

    change(element, 'form-object', 'Not_An_Object__c');
    one(element, '[data-id="find-fields"]').click();
    await flush();
    expect(one(element, '[data-id="error"]').textContent).toContain('is not an object');

    one(element, '[data-id="form-cancel"]').click();
    expect(closed).toHaveBeenCalledTimes(1);
    expect(closed.mock.calls[0][0]).toBeFalsy();
  });
});
