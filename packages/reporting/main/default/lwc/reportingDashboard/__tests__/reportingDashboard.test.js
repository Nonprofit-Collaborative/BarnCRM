import { createElement } from 'lwc';
import ReportingDashboard from 'c/reportingDashboard';
import BarnConfirmModal from 'c/barnConfirmModal';
import runReport from '@salesforce/apex/ReportingQueryService.run';
import load from '@salesforce/apex/ReportingLibrary.load';
import save from '@salesforce/apex/ReportingLibrary.save';
import share from '@salesforce/apex/ReportingLibrary.share';
import remove from '@salesforce/apex/ReportingLibrary.remove';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/ReportingQueryService.run', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingQueryService.page', () => ({ default: jest.fn() }), {
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
  '@salesforce/apex/QueryFieldCatalog.getObjectInfo',
  () => ({ default: jest.fn(() => Promise.resolve({ label: 'X', fields: [] })) }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/ReportingLibrary.load', () => ({ default: jest.fn() }), {
  virtual: true
});
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

const GIVING = {
  title: 'Giving',
  description: 'Giving at a glance',
  filters: [
    { key: 'dates', kind: 'date', label: 'Gift Date' },
    { key: 'fund', kind: 'record', label: 'Fund', object: 'Fund__c' }
  ],
  widgets: [
    {
      key: 'total',
      title: 'Total',
      size: 'small',
      bindings: {
        dates: { field: 'Gift_Date__c', type: 'date' },
        fund: { field: 'Fund__c', related: { object: 'Gift_Allocation__c', field: 'Gift__c' } }
      },
      report: {
        object: 'Gift__c',
        measures: [{ fn: 'sum', path: 'Amount__c', label: 'Total', type: 'currency' }],
        view: { type: 'metric' }
      }
    },
    {
      key: 'people',
      title: 'Donors',
      size: 'large',
      report: { object: 'Contact', columns: [{ path: 'Name', label: 'Name' }] }
    }
  ]
};

const SAVED_ROW = {
  id: '069000000000009AAA',
  kind: 'barndash',
  title: 'Giving',
  ownerName: 'Ana',
  mine: true,
  canEdit: true,
  definition: JSON.stringify({
    ...GIVING,
    sharing: { users: [], groups: [{ id: '00G000000000001AAA', name: 'Board', access: 'view' }] }
  })
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount(props) {
  const element = createElement('c-reporting-dashboard', { is: ReportingDashboard });
  Object.assign(
    element,
    { context: { canSave: true, canExport: true }, objects: [{ value: 'Fund__c', label: 'Fund' }] },
    props
  );
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => [...element.shadowRoot.querySelectorAll(`[data-id="${id}"]`)];

describe('c-reporting-dashboard', () => {
  beforeEach(() => {
    runReport.mockImplementation(({ requestJson }) => {
      const request = JSON.parse(requestJson);
      if (request.query.object === 'Fund__c') {
        return Promise.resolve({ rows: [{ Id: 'a01000000000001AAA', Name: 'General' }] });
      }
      return Promise.resolve(
        request.measures.length
          ? { groups: [{ keys: [], labels: [], values: [10] }] }
          : { rows: [] }
      );
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows a template with its filters and narrows bound widgets when a filter changes', async () => {
    const element = await mount({ definition: GIVING });
    expect(find(element, 'heading').textContent).toBe('Giving');
    expect(find(element, 'description').textContent).toBe('Giving at a glance');
    const views = findAll(element, 'widget-view');
    expect(views).toHaveLength(2);
    expect(views[0].heading).toBe('Total');
    const fundRequest = runReport.mock.calls
      .map((call) => JSON.parse(call[0].requestJson))
      .find((request) => request.query.object === 'Fund__c');
    expect(fundRequest.query.fields).toEqual(['Name']);
    const pick = find(element, 'record-pick');
    expect(pick.options.map((option) => option.label)).toEqual(['c.Reporting_Dash_All', 'General']);
    await expectAccessible(element);

    const before = views[1].report;
    pick.dispatchEvent(new CustomEvent('change', { detail: { value: 'a01000000000001AAA' } }));
    await flush();
    const after = findAll(element, 'widget-view');
    expect(after[0].report.related[0].filter.conditions[0].value).toBe('a01000000000001AAA');
    expect(after[1].report).toBe(before);
    expect(after[1].unfiltered).toEqual(['Fund']);

    const range = find(element, 'filters').querySelector('c-reporting-range');
    range.dispatchEvent(new CustomEvent('change', { detail: { value: { range: 'LAST_YEAR' } } }));
    await flush();
    expect(findAll(element, 'widget-view')[0].report.dateRange).toEqual({
      range: 'LAST_YEAR',
      field: 'Gift_Date__c',
      type: 'date'
    });

    const refresh = jest.fn();
    findAll(element, 'widget-view').forEach((view) => {
      view.refresh = refresh;
    });
    find(element, 'refresh').click();
    expect(refresh).toHaveBeenCalledTimes(2);
  });

  it('edits the layout: filters, widgets, sizes, order, bindings and a new widget report', async () => {
    load.mockResolvedValue({
      id: '069000000000002AAA',
      title: 'Saved',
      definition: JSON.stringify({ object: 'Contact', columns: [{ path: 'Name' }] })
    });
    const element = await mount({
      definition: GIVING,
      savedReports: [{ id: '069000000000002AAA', title: 'Saved' }]
    });
    find(element, 'edit').click();
    await flush();
    expect(findAll(element, 'widget-editor')).toHaveLength(2);
    await expectAccessible(element);

    find(element, 'filter-kind').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'record' } })
    );
    await flush();
    find(element, 'filter-object').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Fund__c' } })
    );
    await flush();
    expect(find(element, 'filter-label').value).toBe('Fund');
    find(element, 'add-filter').click();
    await flush();
    expect(findAll(element, 'filter')).toHaveLength(3);
    findAll(element, 'remove-filter')[2].click();
    await flush();
    expect(findAll(element, 'filter')).toHaveLength(2);

    find(element, 'pick-report').dispatchEvent(
      new CustomEvent('change', { detail: { value: '069000000000002AAA' } })
    );
    find(element, 'add-saved').click();
    await flush();
    await flush();
    expect(findAll(element, 'widget-view')).toHaveLength(3);
    expect(findAll(element, 'widget-view')[2].heading).toBe('Saved');

    findAll(element, 'remove-widget')[0].click();
    await flush();
    expect(findAll(element, 'widget-view').map((view) => view.heading)).toEqual([
      'Donors',
      'Saved'
    ]);

    const binding = findAll(element, 'widget-editor')[0].querySelector('c-reporting-field-picker');
    binding.dispatchEvent(
      new CustomEvent('change', { detail: { path: 'CreatedDate', type: 'datetime' } })
    );
    await flush();
    const range = find(element, 'filters').querySelector('c-reporting-range');
    range.dispatchEvent(new CustomEvent('change', { detail: { value: { range: 'TODAY' } } }));
    await flush();
    expect(findAll(element, 'widget-view')[0].report.dateRange.field).toBe('CreatedDate');

    find(element, 'new-widget').click();
    await flush();
    const builder = find(element, 'widget-builder');
    expect(builder.forWidget).toBe(true);
    builder.dispatchEvent(
      new CustomEvent('done', {
        detail: { report: { object: 'Contact', title: 'New One', columns: [{ path: 'Name' }] } }
      })
    );
    await flush();
    expect(findAll(element, 'widget-view').map((view) => view.heading)).toEqual([
      'Donors',
      'Saved',
      'New One'
    ]);

    findAll(element, 'edit-widget')[0].click();
    await flush();
    find(element, 'widget-builder').dispatchEvent(new CustomEvent('close'));
    await flush();
    expect(find(element, 'widget-builder')).toBeNull();
  });

  it('saves a new dashboard, then keeps sharing on save, shares and deletes a saved one', async () => {
    save.mockResolvedValue(SAVED_ROW);
    share.mockResolvedValue(SAVED_ROW);
    remove.mockResolvedValue();
    load.mockResolvedValue(SAVED_ROW);
    BarnConfirmModal.open = jest.fn(() => Promise.resolve(true));

    const fresh = await mount({ definition: { title: '' } });
    expect(find(fresh, 'empty')).not.toBeNull();
    expect(find(fresh, 'layout')).not.toBeNull();
    find(fresh, 'save').click();
    await flush();
    expect(find(fresh, 'error').message).toBe('c.Reporting_Error_Title');

    const element = await mount({ documentId: '069000000000009AAA' });
    const closed = jest.fn();
    element.addEventListener('close', closed);
    find(element, 'save').click();
    await flush();
    expect(JSON.parse(save.mock.calls[0][0].definitionJson).sharing.groups[0].id).toBe(
      '00G000000000001AAA'
    );
    expect(save.mock.calls[0][0].kind).toBe('barndash');

    find(element, 'share').click();
    await flush();
    find(element, 'share-panel').dispatchEvent(
      new CustomEvent('save', { detail: { sharing: { users: [], groups: [] } } })
    );
    await flush();
    expect(share).toHaveBeenCalled();

    find(element, 'delete').click();
    await flush();
    expect(remove).toHaveBeenCalledWith({ documentId: '069000000000009AAA' });
    expect(closed).toHaveBeenCalled();
  });

  it('opens a dashboard shared to view without editing', async () => {
    load.mockResolvedValue({ ...SAVED_ROW, mine: false, canEdit: false });
    const element = await mount({ documentId: '069000000000009AAA' });
    expect(find(element, 'read-only')).not.toBeNull();
    expect(find(element, 'edit')).toBeNull();
    expect(find(element, 'save')).toBeNull();
    expect(find(element, 'save-as')).not.toBeNull();
  });
});
