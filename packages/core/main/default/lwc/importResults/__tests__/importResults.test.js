import { createElement } from 'lwc';
import ImportResults from 'c/importResults';

const DRY_RUN = {
  id: '001',
  name: 'IB-000001',
  status: 'Dry run complete',
  isDryRun: true,
  isFinished: true,
  rowCount: 10,
  created: 6,
  updated: 2,
  matched: 1,
  rejected: 1,
  runLog: 'Dry run. Nothing was written.\nThese columns were not loaded: Gift.'
};

const COMMITTED = { ...DRY_RUN, status: 'Complete', isDryRun: false, runLog: '' };

function render(properties) {
  const element = createElement('c-import-results', { is: ImportResults });
  Object.assign(element, properties);
  document.body.appendChild(element);
  return element;
}

describe('the import results view', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the four counts', () => {
    const element = render({ batch: DRY_RUN, rejectedRows: [] });
    const values = Array.from(
      element.shadowRoot.querySelectorAll('[data-id="created"], [data-id="rejected"]')
    ).map((node) => node.querySelector('p').textContent);
    expect(values).toEqual(['6', '1']);
  });

  it('says "would" on a dry run and not on a commit', () => {
    const preview = render({ batch: DRY_RUN, rejectedRows: [] });
    expect(preview.shadowRoot.querySelector('[data-id="created"]').textContent).toContain('Would');

    const done = render({ batch: COMMITTED, rejectedRows: [] });
    expect(done.shadowRoot.querySelector('[data-id="created"]').textContent).not.toContain('Would');
  });

  it('lists every rejected row with its reason', () => {
    const element = render({
      batch: DRY_RUN,
      rejectedRows: [
        { id: 'r1', rowNumber: 4, errorMessage: 'Required value missing: last name.' },
        { id: 'r2', rowNumber: 9, errorMessage: 'This row could not be read.' }
      ]
    });
    const rows = element.shadowRoot.querySelectorAll('[data-id="rejected-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain('Required value missing: last name.');
  });

  it('says plainly when nothing was rejected', () => {
    const element = render({ batch: COMMITTED, rejectedRows: [] });
    expect(element.shadowRoot.querySelector('[data-id="no-rejected"]')).not.toBeNull();
  });

  it('shows the run log a line at a time', () => {
    const element = render({ batch: DRY_RUN, rejectedRows: [] });
    const lines = element.shadowRoot.querySelectorAll('[data-id="run-log"] li');
    expect(lines).toHaveLength(2);
  });

  it('shows a spinner while the run is still going', () => {
    const element = render({ batch: { ...DRY_RUN, isFinished: false }, rejectedRows: [] });
    expect(element.shadowRoot.querySelector('[data-id="running"]')).not.toBeNull();
  });

  it('lists values a change rewrote, before and after, and nothing when none did', () => {
    const element = render({
      batch: DRY_RUN,
      rejectedRows: [],
      changedValues: [
        { rowNumber: 2, column: 'Email', before: 'ana at example.org', after: 'ana@example.org' }
      ]
    });
    const rows = element.shadowRoot.querySelectorAll('[data-id="changed-value"]');
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain('ana at example.org');
    expect(rows[0].textContent).toContain('ana@example.org');
    const none = render({ batch: DRY_RUN, rejectedRows: [] });
    expect(none.shadowRoot.querySelectorAll('[data-id="changed-value"]')).toHaveLength(0);
  });

  it('names each table for a screen reader and announces the counts as they change', () => {
    const element = render({
      batch: DRY_RUN,
      rejectedRows: [{ id: 'r1', rowNumber: 4, errorMessage: 'Required value missing.' }],
      changedValues: [{ rowNumber: 2, column: 'Email', before: 'a', after: 'b' }]
    });
    const root = element.shadowRoot;
    expect(root.querySelector('[data-id="rejected-table"]').getAttribute('aria-label')).toBe(
      'c.Core_Import_RejectedHeading'
    );
    expect(root.querySelector('[data-id="changed-values-table"]').getAttribute('aria-label')).toBe(
      'c.Core_Import_ChangedValuesHeading'
    );
    expect(root.querySelector('[data-id="counts"]').getAttribute('aria-live')).toBe('polite');
    root.querySelectorAll('th').forEach((header) => {
      expect(header.getAttribute('scope')).toBe('col');
    });
  });

  it('renders with no batch at all', () => {
    const element = render({ batch: undefined, rejectedRows: [] });
    expect(element.shadowRoot.querySelector('[data-id="created"]').textContent).toContain('0');
  });
});
