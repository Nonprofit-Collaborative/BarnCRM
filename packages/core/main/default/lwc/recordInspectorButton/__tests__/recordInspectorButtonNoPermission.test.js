import { createElement } from 'lwc';
import RecordInspectorButton from 'c/recordInspectorButton';

jest.mock(
  '@salesforce/apex/RecordInspectorController.pageLink',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});

describe('c-record-inspector-button without Manage BarnCRM Settings', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('renders nothing', () => {
    const element = createElement('c-record-inspector-button', { is: RecordInspectorButton });
    element.recordId = '003000000000001AAA';
    document.body.appendChild(element);

    expect(element.shadowRoot.querySelector('lightning-button')).toBeNull();
    expect(element.shadowRoot.childNodes.length).toBe(0);
  });
});
