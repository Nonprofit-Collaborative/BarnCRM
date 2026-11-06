import { createElement } from 'lwc';
import RecordInspectorButton from 'c/recordInspectorButton';
import pageLink from '@salesforce/apex/RecordInspectorController.pageLink';

jest.mock(
  '@salesforce/apex/RecordInspectorController.pageLink',
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
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_RecordInspector_Inspect',
  () => ({ default: 'Inspect This Record' }),
  {
    virtual: true
  }
);

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});

const RECORD_ID = '003000000000001AAA';
const flush = () => Promise.resolve();

function mount() {
  const element = createElement('c-record-inspector-button', { is: RecordInspectorButton });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  return element;
}

const button = (element) => element.shadowRoot.querySelector('[data-id="inspect-button"]');

describe('c-record-inspector-button', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('opens the Record Inspector page on this record', async () => {
    const element = mount();
    pageLink.emit({ tabApiName: 'Record_Inspector', recordIdKey: 'c__recordId' });
    await flush();

    expect(button(element).label).toBe('Inspect This Record');
    expect(button(element).disabled).toBe(false);
    button(element).click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Record_Inspector' },
      state: { c__recordId: RECORD_ID }
    });
  });

  it('uses the tab and key Apex qualifies for the namespace', async () => {
    const element = mount();
    pageLink.emit({ tabApiName: 'ns__Record_Inspector', recordIdKey: 'ns__recordId' });
    await flush();

    button(element).click();

    expect(mockNavigate).toHaveBeenCalledWith(
      expect.objectContaining({
        attributes: { apiName: 'ns__Record_Inspector' },
        state: { ns__recordId: RECORD_ID }
      })
    );
  });

  it('waits for the page link before it can be clicked', () => {
    const element = mount();

    expect(button(element).disabled).toBe(true);
    button(element).click();
    expect(mockNavigate).not.toHaveBeenCalled();
  });
});
