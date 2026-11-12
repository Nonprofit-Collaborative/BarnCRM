import { createElement } from 'lwc';
import GrantDocuments from 'c/grantDocuments';
import getDocuments from '@salesforce/apex/GrantManagementController.getDocuments';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';

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
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);
jest.mock('lightning/pageReferenceUtils', () => ({ encodeDefaultFieldValues: (v) => v }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/GrantManagementController.getDocuments',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const DOCUMENTS = [
  {
    id: 'r1',
    name: 'Full application',
    type: 'Application',
    status: 'Submitted',
    dueDate: '2027-01-15',
    fileCount: 2,
    fileId: '069000000000001',
    fileTitle: 'Application v3',
    fileVersion: '3'
  },
  {
    id: 'r2',
    name: 'Letter of inquiry',
    type: 'Letter of Inquiry',
    status: 'Not Started',
    fileCount: 0
  }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(card) {
  getDocuments.mockResolvedValue(card);
  const element = createElement('c-grant-documents', { is: GrantDocuments });
  element.recordId = 'a01000000000001';
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-grant-documents', () => {
  beforeEach(() => {
    setHelpTextForTest({ Funders_Documents_Version: 'Version {0}, {1} files' });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    clearHelpTextForTest();
    jest.clearAllMocks();
  });

  it('shows each document with its latest file and version, and opens the file', async () => {
    const element = await render({ documents: DOCUMENTS, canUpload: true, canCreate: true });
    expect(element.shadowRoot.querySelectorAll('[data-id="document"]')).toHaveLength(2);
    expect(element.shadowRoot.querySelectorAll('[data-id="upload"]')).toHaveLength(2);
    expect(element.shadowRoot.querySelectorAll('[data-id="no-file"]')).toHaveLength(1);
    expect(element.shadowRoot.textContent).toContain('Version 3, 2 files');

    element.shadowRoot.querySelector('[data-id="file"]').click();
    expect(mockNavigate.mock.calls[0][0].state.selectedRecordId).toBe('069000000000001');
  });

  it('starts a new application requirement on this grant', async () => {
    const element = await render({ documents: [], canUpload: true, canCreate: true });
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    element.shadowRoot.querySelector('[data-id="new"]').click();
    const page = mockNavigate.mock.calls[0][0];
    expect(page.attributes).toEqual({ objectApiName: 'Grant_Requirement__c', actionName: 'new' });
    expect(page.state.defaultFieldValues).toEqual({
      Grant__c: 'a01000000000001',
      Type__c: 'Application'
    });
  });

  it('offers no upload and no new document to a reader', async () => {
    const element = await render({ documents: DOCUMENTS, canUpload: false, canCreate: false });
    expect(element.shadowRoot.querySelector('[data-id="upload"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="new"]')).toBeNull();
  });
});
