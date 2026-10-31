import { createElement } from 'lwc';
import DonorSegments from 'c/donorSegments';
import { BYTE_ORDER_MARK } from 'c/findCsv';
import getPage from '@salesforce/apex/DonorSegmentController.getPage';
import saveFromTemplate from '@salesforce/apex/DonorSegmentController.saveFromTemplate';
import countSegment from '@salesforce/apex/DonorSegmentController.countSegment';
import listSegment from '@salesforce/apex/DonorSegmentController.listSegment';
import exportPage from '@salesforce/apex/DonorSegmentController.exportPage';
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
jest.mock('@salesforce/label/c.Giving_Segments_OptionMine', () => ({ default: '{0} ({1})' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Giving_Segments_OptionShared',
  () => ({ default: '{0} ({1}, shared by {2})' }),
  { virtual: true }
);

jest.mock('@salesforce/label/c.Giving_Segments_Count', () => ({ default: '{0} records' }), {
  virtual: true
});

function readBlob(blob) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.readAsText(blob);
  });
}

jest.mock('@salesforce/apex/DonorSegmentController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/DonorSegmentController.saveFromTemplate',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/DonorSegmentController.countSegment', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/DonorSegmentController.listSegment', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/DonorSegmentController.exportPage', () => ({ default: jest.fn() }), {
  virtual: true
});

const TEMPLATES = [
  {
    key: 'lapsed',
    label: 'Lapsed Donors',
    description: 'Gave last year.',
    forPeople: true,
    forOrganizations: true
  },
  {
    key: 'new',
    label: 'New Donors',
    description: 'First gift.',
    forPeople: true,
    forOrganizations: true
  }
];

const PEOPLE_SEGMENT = {
  recordId: 'a01000000000001',
  name: 'Lapsed people',
  objectName: 'Contact',
  people: true,
  shared: false,
  mine: true
};
const ORG_SEGMENT = {
  recordId: 'a01000000000002',
  name: 'Big funders',
  objectName: 'Account',
  people: false,
  shared: true,
  mine: false,
  ownerName: 'Maria'
};

function page(overrides) {
  return {
    templates: TEMPLATES,
    segments: [PEOPLE_SEGMENT, ORG_SEGMENT],
    exportLimit: 50000,
    findTabApiName: 'Find',
    stateKey: 'c__savedQueryId',
    ...overrides
  };
}

// A macrotask, so every awaited server call and FileReader in the component has settled.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  const element = createElement('c-donor-segments', { is: DonorSegments });
  document.body.appendChild(element);
  await flush();
  return element;
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function choose(element, id, value) {
  byId(element, id).dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
}

describe('c-donor-segments', () => {
  let createdUrls;

  beforeEach(() => {
    getPage.mockResolvedValue(page());
    countSegment.mockResolvedValue({ count: 12, more: false });
    createdUrls = [];
    global.URL.createObjectURL = jest.fn((blob) => {
      createdUrls.push(blob);
      return 'blob:segment';
    });
    global.URL.revokeObjectURL = jest.fn();
    jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
    jest.clearAllMocks();
  });

  it('offers the templates with a default name and lists the segments', async () => {
    const element = await render();
    expect(byId(element, 'template').options.map((option) => option.value)).toEqual([
      'lapsed',
      'new'
    ]);
    expect(byId(element, 'name').value).toBe('Lapsed Donors (c.Giving_Segments_People)');
    expect(byId(element, 'template-description').textContent).toContain('Gave last year.');
    const options = byId(element, 'segment').options;
    expect(options).toHaveLength(2);
    expect(options[1].label).toContain('Maria');
  });

  it('follows the template and records choices in the default name', async () => {
    const element = await render();
    await choose(element, 'object', 'Account');
    expect(byId(element, 'name').value).toBe('Lapsed Donors (c.Giving_Segments_Organizations)');
    await choose(element, 'template', 'new');
    expect(byId(element, 'name').value).toBe('New Donors (c.Giving_Segments_Organizations)');
    await choose(element, 'name', 'My own name');
    await choose(element, 'template', 'lapsed');
    expect(byId(element, 'name').value).toBe('My own name');
  });

  it('says so when there are no segments yet', async () => {
    getPage.mockResolvedValue(page({ segments: [] }));
    const element = await render();
    expect(byId(element, 'empty-state')).not.toBeNull();
    expect(byId(element, 'segment')).toBeNull();
  });

  it('saves a template and opens the new segment with its count', async () => {
    saveFromTemplate.mockResolvedValue(page({ savedId: PEOPLE_SEGMENT.recordId }));
    const element = await render();
    byId(element, 'save').click();
    await flush();
    await flush();
    expect(saveFromTemplate).toHaveBeenCalledWith({
      templateKey: 'lapsed',
      objectName: 'Contact',
      name: 'Lapsed Donors (c.Giving_Segments_People)'
    });
    expect(byId(element, 'notice-message')).not.toBeNull();
    expect(countSegment).toHaveBeenCalledWith({ segmentId: PEOPLE_SEGMENT.recordId });
    expect(byId(element, 'count').textContent).toContain('12');
  });

  it('shows a refusal from the server', async () => {
    getPage.mockRejectedValue({ body: { message: 'Find is required.' } });
    const element = await render();
    expect(byId(element, 'error-message').textContent).toContain('Find is required.');
  });

  it('lists the segment in its own columns', async () => {
    listSegment.mockResolvedValue({
      columns: [
        { path: 'Name', label: 'Full Name' },
        { path: 'Total_Giving__c', label: 'Total Giving' }
      ],
      rows: [{ Id: '003A', Name: 'Ana Ruiz', Total_Giving__c: 250 }]
    });
    const element = await render();
    await choose(element, 'segment', PEOPLE_SEGMENT.recordId);
    byId(element, 'show-list').click();
    await flush();
    const table = byId(element, 'list');
    expect(table.columns.map((column) => column.label)).toEqual(['Full Name', 'Total Giving']);
    expect(table.data[0].Total_Giving__c).toBe('250');
  });

  it('offers only All Columns for organizations and says why', async () => {
    const element = await render();
    await choose(element, 'segment', ORG_SEGMENT.recordId);
    expect(byId(element, 'layout').options.map((option) => option.value)).toEqual(['all']);
    expect(byId(element, 'people-only')).not.toBeNull();
  });

  it('exports every page for Mailchimp, one row per address, as CSV', async () => {
    exportPage
      .mockResolvedValueOnce({
        columns: [],
        rows: [
          { Id: '1', Email: 'ana@example.org', FirstName: 'Ana', LastName: 'Ruiz' },
          { Id: '2', Email: 'ANA@example.org', FirstName: 'Luis', LastName: 'Ruiz' }
        ],
        lastId: '2',
        done: false
      })
      .mockResolvedValueOnce({
        columns: [],
        rows: [{ Id: '3', Email: 'bo@example.org', FirstName: 'Bo', LastName: 'Lee' }],
        lastId: '3',
        done: true
      });
    const element = await render();
    await choose(element, 'segment', PEOPLE_SEGMENT.recordId);
    byId(element, 'export').click();
    await flush();
    await flush();
    expect(exportPage).toHaveBeenNthCalledWith(2, {
      segmentId: PEOPLE_SEGMENT.recordId,
      layout: 'mailchimp',
      afterId: '2'
    });
    expect(createdUrls).toHaveLength(1);
    const text = await readBlob(createdUrls[0]);
    const lines = text.replace(BYTE_ORDER_MARK, '').trim().split('\r\n');
    expect(lines[0]).toBe('Email Address,First Name,Last Name,Tags');
    expect(lines).toHaveLength(3);
    expect(lines[1]).toBe('ana@example.org,Ana,Ruiz,Lapsed people');
    expect(byId(element, 'notice-message').textContent).toContain('c.Giving_Segments_Exported');
  });

  it('stops at the export row limit', async () => {
    getPage.mockResolvedValue(page({ exportLimit: 1 }));
    exportPage.mockResolvedValue({
      columns: [{ path: 'Name', label: 'Full Name' }],
      rows: [
        { Id: '1', Name: 'Ana' },
        { Id: '2', Name: 'Bo' }
      ],
      lastId: '2',
      done: false
    });
    const element = await render();
    await choose(element, 'segment', PEOPLE_SEGMENT.recordId);
    await choose(element, 'layout', 'all');
    byId(element, 'export').click();
    await flush();
    await flush();
    expect(exportPage).toHaveBeenCalledTimes(1);
    const text = await readBlob(createdUrls[0]);
    expect(text.trim().split('\r\n')).toHaveLength(2);
  });

  it('opens the segment in Find', async () => {
    const element = await render();
    await choose(element, 'segment', PEOPLE_SEGMENT.recordId);
    byId(element, 'edit-in-find').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Find' },
      state: { c__savedQueryId: PEOPLE_SEGMENT.recordId }
    });
  });
});
