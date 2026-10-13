import { createElement } from 'lwc';
import FieldUtilization from 'c/fieldUtilization';
import listObjects from '@salesforce/apex/FieldUtilizationController.listObjects';
import getPlan from '@salesforce/apex/FieldUtilizationController.getPlan';
import countFields from '@salesforce/apex/FieldUtilizationController.countFields';
import saveCounts from '@salesforce/apex/FieldUtilizationController.saveCounts';

jest.mock(
  '@salesforce/apex/FieldUtilizationController.listObjects',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/FieldUtilizationController.getPlan', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/FieldUtilizationController.countFields',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/FieldUtilizationController.saveCounts',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_FieldUtilization_Progress',
  () => ({ default: 'Counted {0} of {1} fields.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_FieldUtilization_Saved',
  () => ({ default: 'Saved {0} counts.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_FieldUtilization_TooLarge',
  () => ({ default: 'More than {0} records.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_FieldUtilization_NotCounted',
  () => ({ default: 'Not counted: {0}' }),
  { virtual: true }
);

const OPTIONS = [
  { value: 'Account', label: 'Account' },
  { value: 'Contact', label: 'Contact' }
];

const field = (name) => ({ fieldName: name, fieldLabel: name });

const row = (name, filled, percent) => ({
  key: `${name}|Organization`,
  fieldName: name,
  fieldLabel: name,
  recordType: 'Organization',
  recordTypeLabel: 'Organization',
  filled,
  total: 100,
  percent,
  sampled: false
});

const PLAN = {
  objectName: 'Account',
  objectLabel: 'Account',
  total: 100,
  tooLarge: false,
  largeObjectLimit: 1000000,
  chunkSize: 2,
  fields: [field('Phone'), field('Website'), field('Fax')],
  previousTakenAt: '2026-10-04T08:00:00.000Z',
  previous: [row('Phone', 75, 75.0)]
};

const flush = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function render() {
  const element = createElement('c-field-utilization', { is: FieldUtilization });
  document.body.appendChild(element);
  listObjects.emit(OPTIONS);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function choose(element, value) {
  find(element, 'object').dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
}

describe('c-field-utilization', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers the objects the controller lists and counts nothing until one is chosen', async () => {
    const element = render();
    await flush();

    expect(find(element, 'object').options).toEqual(OPTIONS);
    expect(getPlan).not.toHaveBeenCalled();
    expect(find(element, 'save').disabled).toBe(true);
    expect(find(element, 'results')).toBeNull();
  });

  it('counts the fields in chunks and fills the table with the change since the saved count', async () => {
    getPlan.mockResolvedValue(PLAN);
    countFields
      .mockResolvedValueOnce({
        rows: [row('Phone', 80, 80.0), row('Website', 10, 10.0)],
        failed: []
      })
      .mockResolvedValueOnce({ rows: [], failed: ['Fax'] });
    const element = render();
    await choose(element, 'Account');

    expect(getPlan).toHaveBeenCalledWith({ objectName: 'Account' });
    expect(countFields).toHaveBeenNthCalledWith(1, {
      objectName: 'Account',
      fieldNames: ['Phone', 'Website']
    });
    expect(countFields).toHaveBeenNthCalledWith(2, { objectName: 'Account', fieldNames: ['Fax'] });
    const rows = find(element, 'results').data;
    expect(rows).toHaveLength(2);
    expect(rows[0].share).toBeCloseTo(0.8);
    expect(rows[0].previousShare).toBeCloseTo(0.75);
    expect(rows[0].change).toBe(5);
    expect(rows[1].change).toBeNull();
    expect(element.shadowRoot.textContent).toContain('Counted 3 of 3 fields.');
    expect(find(element, 'not-counted').textContent).toContain('Not counted: Fax');
    expect(find(element, 'compared')).not.toBeNull();
    expect(find(element, 'save').disabled).toBe(false);
  });

  it('says an object over the size limit is not counted, and counts nothing', async () => {
    getPlan.mockResolvedValue({ ...PLAN, total: 2000000, tooLarge: true, fields: [] });
    const element = render();
    await choose(element, 'Account');

    expect(find(element, 'too-large').textContent).toContain('More than');
    expect(countFields).not.toHaveBeenCalled();
  });

  it('saves only the counted values and shows the saved count next', async () => {
    getPlan.mockResolvedValueOnce({ ...PLAN, chunkSize: 40, previousTakenAt: null, previous: [] });
    countFields.mockResolvedValue({ rows: [row('Phone', 80, 80.0)], failed: [] });
    saveCounts.mockResolvedValue(1);
    const element = render();
    await choose(element, 'Account');
    expect(find(element, 'never-saved')).not.toBeNull();

    getPlan.mockResolvedValueOnce({
      ...PLAN,
      previousTakenAt: '2026-10-13T08:00:00.000Z',
      previous: [row('Phone', 80, 80.0)]
    });
    find(element, 'save').click();
    await flush();

    expect(saveCounts).toHaveBeenCalledWith({
      objectName: 'Account',
      rows: [
        { fieldName: 'Phone', recordType: 'Organization', filled: 80, total: 100, sampled: false }
      ]
    });
    expect(find(element, 'notice').textContent).toContain('Saved 1 counts.');
    expect(find(element, 'results').data[0].change).toBe(0);
  });

  it('sorts by the chosen column', async () => {
    getPlan.mockResolvedValue({ ...PLAN, chunkSize: 40 });
    countFields.mockResolvedValue({
      rows: [row('Phone', 80, 80.0), row('Website', 10, 10.0)],
      failed: []
    });
    const element = render();
    await choose(element, 'Account');

    find(element, 'results').dispatchEvent(
      new CustomEvent('sort', { detail: { fieldName: 'share', sortDirection: 'asc' } })
    );
    await flush();

    expect(find(element, 'results').data.map((r) => r.fieldName)).toEqual(['Website', 'Phone']);
  });

  it('shows the server message when a count fails', async () => {
    getPlan.mockRejectedValue({ body: { message: 'You need the permission.' } });
    const element = render();
    await choose(element, 'Account');

    expect(find(element, 'error').textContent).toContain('You need the permission.');
  });
});
