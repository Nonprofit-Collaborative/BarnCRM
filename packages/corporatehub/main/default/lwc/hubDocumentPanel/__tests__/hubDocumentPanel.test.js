import { createElement } from 'lwc';
import HubDocumentPanel from 'c/hubDocumentPanel';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getDocumentStatus from '@salesforce/apex/CorporateHubController.getDocumentStatus';
import requestAcknowledgments from '@salesforce/apex/CorporateHubController.requestAcknowledgments';
import publishNewVersion from '@salesforce/apex/CorporateHubController.publishNewVersion';
import acknowledge from '@salesforce/apex/CorporateHubController.acknowledge';

jest.mock(
  '@salesforce/apex/CorporateHubController.getDocumentStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/CorporateHubController.requestAcknowledgments',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/CorporateHubController.publishNewVersion',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/CorporateHubController.markReviewed', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CorporateHubController.retire', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CorporateHubController.acknowledge', () => ({ default: jest.fn() }), {
  virtual: true
});

const RECORD_ID = 'a02000000000001AAA';
const MANAGER = {
  version: 2,
  status: 'Active',
  needsAcknowledgment: true,
  acknowledged: 1,
  outstanding: 1,
  canManage: true,
  canEdit: true,
  people: [
    { id: 'a03000000000001AAA', name: 'Sam', status: 'Requested', due: '2027-01-01' },
    { id: 'a03000000000002AAA', name: 'Maria', status: 'Acknowledged', due: '2026-12-01' }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}
const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function mount() {
  const element = createElement('c-hub-document-panel', { is: HubDocumentPanel });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  return element;
}

describe('c-hub-document-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows a manager the counts, the actions and Record for the outstanding person only', async () => {
    getDocumentStatus.mockResolvedValue(MANAGER);
    const element = mount();
    await flush();

    expect(find(element, 'version').textContent).toBe('c.CorporateHub_Document_Version');
    expect(find(element, 'counts')).not.toBeNull();
    expect(find(element, 'publish')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="record"]')).toHaveLength(1);
  });

  it('asks one public group, by developer name', async () => {
    getDocumentStatus.mockResolvedValue(MANAGER);
    requestAcknowledgments.mockResolvedValue(4);
    const element = mount();
    await flush();

    const group = find(element, 'group');
    group.value = 'Board Members';
    group.dispatchEvent(new CustomEvent('change'));
    find(element, 'request').click();
    await flush();

    expect(requestAcknowledgments).toHaveBeenCalledWith({
      documentId: RECORD_ID,
      groupName: 'Board_Members'
    });
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: RECORD_ID }]);
  });

  it('publishes a new version and records a paper attestation', async () => {
    getDocumentStatus.mockResolvedValue(MANAGER);
    publishNewVersion.mockResolvedValue(undefined);
    acknowledge.mockResolvedValue(undefined);
    const element = mount();
    await flush();

    find(element, 'publish').click();
    await flush();
    find(element, 'record').click();
    await flush();

    expect(publishNewVersion).toHaveBeenCalledWith({ documentId: RECORD_ID });
    expect(acknowledge).toHaveBeenCalledWith({ acknowledgmentId: 'a03000000000001AAA' });
  });

  it('gives a staff editor Mark Reviewed and the upload but no manager actions', async () => {
    getDocumentStatus.mockResolvedValue({ ...MANAGER, canManage: false, people: [] });
    const element = mount();
    await flush();

    expect(find(element, 'reviewed')).not.toBeNull();
    expect(find(element, 'upload')).not.toBeNull();
    expect(find(element, 'publish')).toBeNull();
    expect(find(element, 'request')).toBeNull();
  });

  it('shows a refusal in its own words', async () => {
    getDocumentStatus.mockResolvedValue(MANAGER);
    publishNewVersion.mockRejectedValue({ body: { message: 'You need the permission' } });
    const element = mount();
    await flush();

    find(element, 'publish').click();
    await flush();

    expect(find(element, 'error-message').message).toBe('You need the permission');
  });
});
