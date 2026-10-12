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

// The organization step as it arrives with a module installed: Core's two fields and the
// fields a stand-in module adds, matching SetupAssistantTestExtension (ADR-0059, C-29).
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
  {
    fieldType: 'Text',
    key: 'Organization_Address__c',
    label: 'Address',
    maxLength: 255,
    fullWidth: true
  },
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
    expect(inputs).toHaveLength(3);
    expect(inputs[0].value).toBe('Riverside Community Aid');
    expect(inputs[0].label).toBe('Legal name');
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
      Organization_Address__c: null,
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
