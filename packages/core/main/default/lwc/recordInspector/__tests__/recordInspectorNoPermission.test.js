import { createElement } from 'lwc';
import RecordInspector from 'c/recordInspector';

jest.mock('@salesforce/apex/RecordInspectorController.inspect', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});

describe('c-record-inspector without Manage BarnCRM Settings', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows nothing', () => {
    const element = createElement('c-record-inspector', { is: RecordInspector });
    element.recordId = '003000000000001AAA';
    document.body.appendChild(element);

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });
});
