import { createElement } from 'lwc';
import SetupStepFields from 'c/setupStepFields';

jest.mock('@salesforce/user/Id', () => ({ default: '005000000000001AAA' }), { virtual: true });

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
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);

// The six organization address parts, declared one per part and shown as one grouped block.
const ADDRESS_KEYS = [
  'Organization_Street__c',
  'Organization_Street_2__c',
  'Organization_City__c',
  'Organization_State__c',
  'Organization_Postal_Code__c',
  'Organization_Country__c'
];
const ADDRESS_FIELDS = ADDRESS_KEYS.map((key) => ({
  fieldType: 'Address',
  key,
  label: key,
  maxLength: 255
}));

// The organization step as it arrives with a module installed: Core's legal name and address
// and the fields a stand-in module adds, matching SetupAssistantTestExtension (ADR-0059, C-29).
const IDENTITY_FIELDS = [
  { fieldType: 'Text', key: 'Organization_Legal_Name__c', label: 'Legal name', maxLength: 255 },
  {
    fieldType: 'Text',
    key: 'Module_Code__c',
    label: 'Module code',
    maxLength: 20,
    pattern: '[A-Z]{2}-[0-9]{2}',
    patternMessage: 'Two letters, a hyphen and two digits.'
  },
  ...ADDRESS_FIELDS,
  {
    fieldType: 'File',
    key: 'Module_Image_Document_Id__c',
    label: 'Image',
    previewAlt: 'Your image'
  }
];

function build(fields, canEdit = true) {
  const element = createElement('c-setup-step-fields', { is: SetupStepFields });
  element.fields = fields;
  element.canEdit = canEdit;
  document.body.appendChild(element);
  return element;
}

function withValues(values) {
  return IDENTITY_FIELDS.map((field) => ({ ...field, value: values[field.key] }));
}

describe('c-setup-step-fields', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows what the org has already recorded', () => {
    const element = build(withValues({ Organization_Legal_Name__c: 'Riverside Community Aid' }));

    const inputs = element.shadowRoot.querySelectorAll('lightning-input');
    expect(inputs).toHaveLength(2);
    expect(inputs[0].value).toBe('Riverside Community Aid');
    expect(inputs[0].label).toBe('Legal name');
  });

  it('shows the six address parts as one grouped block, where the first part sits', () => {
    const element = build(
      withValues({ Organization_Street__c: '1 River Road', Organization_City__c: 'Riverside' })
    );

    const blocks = element.shadowRoot.querySelectorAll('c-organization-address');
    expect(blocks).toHaveLength(1);
    expect(blocks[0].titled).toBe(true);
    expect(blocks[0].values.Organization_Street__c).toBe('1 River Road');
    expect(blocks[0].values.Organization_City__c).toBe('Riverside');
    expect(Object.keys(blocks[0].values)).toEqual(ADDRESS_KEYS);
  });

  it('saves the address parts the block reports, keyed by setting', () => {
    const element = build(withValues({}));
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const block = element.shadowRoot.querySelector('c-organization-address');
    block.dispatchEvent(
      new CustomEvent('partchange', {
        detail: { key: 'Organization_Postal_Code__c', value: '92501' }
      })
    );
    element.shadowRoot.querySelector('[data-id="save-fields"]').click();

    expect(saved.mock.calls[0][0].detail.values.Organization_Postal_Code__c).toBe('92501');
  });

  it('sends nothing while the address block says a required part is still blank', () => {
    const element = build(withValues({ Organization_Street__c: '1 River Road' }));
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const block = element.shadowRoot.querySelector('c-organization-address');
    jest.spyOn(block, 'reportValidity').mockReturnValue(false);
    element.shadowRoot.querySelector('[data-id="save-fields"]').click();

    expect(block.reportValidity).toHaveBeenCalled();
    expect(saved).not.toHaveBeenCalled();
  });

  it('saves every field the step declares, keyed by setting', () => {
    const element = build(withValues({}));
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const input = element.shadowRoot.querySelector('lightning-input[data-key="Module_Code__c"]');
    input.value = 'RC-01';
    input.dispatchEvent(new CustomEvent('change'));
    element.shadowRoot.querySelector('[data-id="save-fields"]').click();

    expect(saved.mock.calls[0][0].detail.values).toEqual({
      Organization_Legal_Name__c: null,
      Module_Code__c: 'RC-01',
      Organization_Street__c: null,
      Organization_Street_2__c: null,
      Organization_City__c: null,
      Organization_State__c: null,
      Organization_Postal_Code__c: null,
      Organization_Country__c: null,
      Module_Image_Document_Id__c: null
    });
  });

  it('applies the limits and wording the field declares', () => {
    const element = build(withValues({}));

    const code = element.shadowRoot.querySelector('lightning-input[data-key="Module_Code__c"]');
    expect(code.pattern).toBe('[A-Z]{2}-[0-9]{2}');
    expect(code.maxLength).toBe(20);
    expect(code.messageWhenPatternMismatch).toBe('Two letters, a hyphen and two digits.');
  });

  it('shows an uploaded file rather than its record identifier', () => {
    const element = build(withValues({ Module_Image_Document_Id__c: '069000000000001' }));

    const preview = element.shadowRoot.querySelector('[data-id="file-preview"]');
    expect(preview.src).toContain('/sfc/servlet.shepherd/document/download/069000000000001');
    expect(preview.alt).toBe('Your image');
    expect(element.shadowRoot.textContent).not.toContain('069000000000001');
  });

  it('keeps an uploaded file as its identifier and saves it at once', () => {
    const element = build(withValues({}));
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const upload = element.shadowRoot.querySelector('lightning-file-upload');
    expect(upload.recordId).toBe('005000000000001AAA');
    upload.dispatchEvent(
      new CustomEvent('uploadfinished', { detail: { files: [{ documentId: '069000000000001' }] } })
    );

    expect(saved.mock.calls[0][0].detail.values.Module_Image_Document_Id__c).toBe(
      '069000000000001'
    );
  });

  it('saves a chosen record by its identifier', () => {
    const element = build([
      { fieldType: 'Record', key: 'Default_Contact__c', label: 'Contact', objectApiName: 'Contact' }
    ]);
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const picker = element.shadowRoot.querySelector('lightning-record-picker');
    expect(picker.objectApiName).toBe('Contact');
    picker.dispatchEvent(new CustomEvent('change', { detail: { recordId: '003000000000001' } }));
    element.shadowRoot.querySelector('[data-id="save-fields"]').click();

    expect(saved.mock.calls[0][0].detail.values).toEqual({ Default_Contact__c: '003000000000001' });
  });

  it('opens the tab a navigation field names, with no save button', () => {
    const element = build([
      { fieldType: 'Navigate', label: 'Open the module', navigationTarget: 'Module_Tab' }
    ]);

    expect(element.shadowRoot.querySelector('[data-id="save-fields"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="navigate"]').click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Module_Tab' }
    });
  });

  it('lets David read the answers without changing them', () => {
    const element = build(
      withValues({ Organization_Legal_Name__c: 'Riverside Community Aid' }),
      false
    );

    expect(element.shadowRoot.querySelectorAll('lightning-file-upload')).toHaveLength(0);
    expect(element.shadowRoot.querySelector('[data-id="save-fields"]')).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-input').disabled).toBe(true);
  });
});
