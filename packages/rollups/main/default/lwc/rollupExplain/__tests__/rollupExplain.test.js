import { createElement } from 'lwc';
import RollupExplain from 'c/rollupExplain';
import explain from '@salesforce/apex/RollupExplainController.explain';

jest.mock('@salesforce/apex/RollupExplainController.explain', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupEase_ExplainAdmin',
  () => ({ default: 'For admins: {0}' }),
  { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const EXPLAINED = {
  definitionId: 'a01000000000001AAA',
  fieldLabel: 'Total Giving',
  value: '4,250',
  sentence: 'Total of Amount from Gifts by Donor, shown in Total Giving on each Contact.',
  counts: '12 of the 15 records read count; 3 are left out.',
  lastCalculated: 'Last calculated 10/26/2026, 2:01 AM.',
  rows: {
    total: 15,
    counted: 12,
    summary: 'Showing 2 of the 15 records read for this record.',
    rows: [
      { recordId: 'a02000000000001AAA', name: 'G-0001', counted: true, reason: 'Counted' },
      {
        recordId: 'a02000000000002AAA',
        name: 'G-0002',
        counted: false,
        reason: 'Left out: does not meet condition 1'
      }
    ]
  }
};

async function build(result) {
  explain.mockResolvedValue(result);
  const element = createElement('c-rollup-explain', { is: RollupExplain });
  element.recordId = '003000000000001AAA';
  document.body.appendChild(element);
  await flush();
  return element;
}

const query = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-rollup-explain', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('explains each total with its counts, last calculation and records read (U5)', async () => {
    const element = await build([EXPLAINED]);

    expect(explain).toHaveBeenCalledWith({ recordId: '003000000000001AAA' });
    expect(query(element, 'heading').textContent).toBe('Total Giving: 4,250');
    expect(query(element, 'sentence').textContent).toBe(EXPLAINED.sentence);
    expect(query(element, 'counts').textContent).toBe(EXPLAINED.counts);
    expect(query(element, 'last').textContent).toBe(EXPLAINED.lastCalculated);
    expect(query(element, 'admin')).toBeNull();
    const rows = element.shadowRoot.querySelectorAll('[data-id="row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].querySelector('a').getAttribute('href')).toBe('/a02000000000001AAA');
    expect(rows[1].textContent).toContain('Left out: does not meet condition 1');
    expect(query(element, 'seen')).not.toBeNull();
  });

  it('shows an administrator what it would calculate now, and a household note', async () => {
    const element = await build([
      {
        ...EXPLAINED,
        calculatedNow: 'Calculated: 4,300. On the record now: 4,250.',
        rows: { total: 0, counted: 0, rows: [], note: 'Read through a household.' }
      }
    ]);

    expect(query(element, 'admin').textContent).toBe(
      'For admins: Calculated: 4,300. On the record now: 4,250.'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="row"]')).toHaveLength(0);
    expect(query(element, 'rows-note').textContent).toBe('Read through a household.');
  });

  it('says so when no rollup fills the record, and reads again on Refresh', async () => {
    const element = await build([]);
    expect(query(element, 'empty')).not.toBeNull();

    explain.mockResolvedValue([EXPLAINED]);
    query(element, 'refresh').click();
    await flush();
    expect(explain).toHaveBeenCalledTimes(2);
    expect(query(element, 'empty')).toBeNull();
    expect(query(element, 'heading').textContent).toBe('Total Giving: 4,250');
  });

  it('shows the reason when the totals cannot be read', async () => {
    explain.mockRejectedValue({ body: { message: 'No access.' } });
    const element = createElement('c-rollup-explain', { is: RollupExplain });
    element.recordId = '003000000000001AAA';
    document.body.appendChild(element);
    await flush();
    expect(query(element, 'error').textContent).toBe('No access.');
  });
});
