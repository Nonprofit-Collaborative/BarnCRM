import { createElement } from 'lwc';
import ReportingHome from 'c/reportingHome';
import getContext from '@salesforce/apex/ReportingLibrary.getContext';
import listSaved from '@salesforce/apex/ReportingLibrary.listSaved';
import listObjects from '@salesforce/apex/ReportingQueryService.listObjects';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/ReportingLibrary.getContext', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingLibrary.listSaved', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingQueryService.listObjects', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ReportingQueryService.listChildren',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ReportingQueryService.run',
  () => ({ default: jest.fn(() => Promise.resolve({ rows: [] })) }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/ReportingQueryService.page', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/QueryFieldCatalog.getObjectInfo',
  () => ({ default: jest.fn(() => Promise.resolve({ label: 'X', fields: [] })) }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ReportingLibrary.load',
  () => ({ default: jest.fn(() => new Promise(() => {})) }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ReportingLibrary.save', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingLibrary.share', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingLibrary.remove', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingLibrary.findPeople', () => ({ default: jest.fn() }), {
  virtual: true
});

const TEMPLATES = {
  templates: [
    {
      key: 'giving',
      requires: ['Gift__c'],
      title: 'Giving Overview',
      description: 'Giving by month',
      widgets: [{ report: { object: 'Gift__c', columns: [{ path: 'Name' }] } }]
    },
    {
      key: 'board',
      requires: ['Board_Member__c'],
      title: 'Board',
      widgets: [{ report: { object: 'Board_Member__c' } }]
    }
  ]
};

const SAVED = [
  {
    id: '069000000000001AAA',
    kind: 'barndash',
    title: 'My Dash',
    ownerName: 'Ana',
    mine: true,
    canEdit: true,
    modified: '2026-05-01T10:00:00.000Z'
  },
  {
    id: '069000000000002AAA',
    kind: 'barnreport',
    title: 'Shared Report',
    ownerName: 'Ben',
    mine: false,
    canEdit: false
  }
];

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount() {
  const element = createElement('c-reporting-home', { is: ReportingHome });
  document.body.appendChild(element);
  for (let i = 0; i < 4; i++) {
    // eslint-disable-next-line no-await-in-loop
    await flush();
  }
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => [...element.shadowRoot.querySelectorAll(`[data-id="${id}"]`)];

describe('c-reporting-home', () => {
  beforeEach(() => {
    getContext.mockResolvedValue({ canSave: true, canExport: false });
    listObjects.mockResolvedValue([
      { value: 'Contact', label: 'Contact' },
      // A namespaced org's name for Gift__c, built so no prefixed name is written out.
      { value: ['ns', 'Gift__c'].join('__'), label: 'Gift' }
    ]);
    listSaved.mockResolvedValue(SAVED);
    global.fetch = jest.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve(TEMPLATES) })
    );
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    delete global.fetch;
  });

  it('lists templates for installed modules and saved dashboards and reports', async () => {
    const element = await mount();
    const templates = findAll(element, 'template');
    expect(templates).toHaveLength(1);
    expect(templates[0].textContent).toContain('Giving Overview');
    const dashRows = find(element, 'dashboards').querySelectorAll('tbody tr');
    expect(dashRows).toHaveLength(1);
    expect(dashRows[0].textContent).toContain('c.Reporting_Home_You');
    const reportRows = find(element, 'reports').querySelectorAll('tbody tr');
    expect(reportRows[0].textContent).toContain('Ben');
    expect(reportRows[0].textContent).toContain('c.Reporting_Share_View');
    await expectAccessible(element);
  });

  it('opens a template, a saved item, a new report and a new dashboard, and comes back', async () => {
    const element = await mount();
    find(element, 'template').click();
    await flush();
    const dashboard = find(element, 'dashboard');
    expect(dashboard.definition.title).toBe('Giving Overview');
    expect(dashboard.context).toEqual({ canSave: true, canExport: false });
    dashboard.dispatchEvent(new CustomEvent('close'));
    await flush();

    find(element, 'reports').querySelector('[data-id="open"]').click();
    await flush();
    const builder = find(element, 'builder');
    expect(builder.documentId).toBe('069000000000002AAA');
    builder.dispatchEvent(new CustomEvent('saved'));
    await flush();
    expect(listSaved).toHaveBeenCalledTimes(2);
    builder.dispatchEvent(new CustomEvent('close'));
    await flush();

    find(element, 'new-report').click();
    await flush();
    expect(find(element, 'builder').documentId).toBeNull();
    find(element, 'builder').dispatchEvent(new CustomEvent('close'));
    await flush();

    find(element, 'new-dashboard').click();
    await flush();
    expect(find(element, 'dashboard').definition.widgets).toEqual([]);
  });

  it('says when there is nothing to report on, and shows a load error', async () => {
    listObjects.mockResolvedValue([]);
    const element = await mount();
    expect(find(element, 'no-objects')).not.toBeNull();
    expect(find(element, 'new-report')).toBeNull();

    getContext.mockRejectedValue({ body: { message: 'Not allowed' } });
    global.fetch = jest.fn(() => Promise.reject(new Error('offline')));
    const failed = await mount();
    expect(find(failed, 'error').message).toBe('Not allowed');
  });

  it('shows no templates when the template file cannot be read', async () => {
    global.fetch = jest.fn(() => Promise.reject(new Error('offline')));
    const element = await mount();
    expect(findAll(element, 'template')).toHaveLength(0);
    expect(find(element, 'dashboards')).not.toBeNull();
  });
});
