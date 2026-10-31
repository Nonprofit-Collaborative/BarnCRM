import { createElement } from 'lwc';
import SetupChangeLog from 'c/setupChangeLog';
import getSummary from '@salesforce/apex/SetupChangeController.getSummary';
import getChanges from '@salesforce/apex/SetupChangeController.getChanges';
import copyNow from '@salesforce/apex/SetupChangeController.copyNow';
import {
  keptText,
  copyText,
  filterArgs,
  datesReversed,
  sectionOptions,
  csvRows
} from '../setupChangeModel';

jest.mock('@salesforce/apex/SetupChangeController.getSummary', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SetupChangeController.getChanges', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SetupChangeController.copyNow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/timeZone', () => ({ default: 'UTC' }), { virtual: true });
jest.mock(
  '@salesforce/label/c.Core_SetupChanges_Kept',
  () => ({ default: 'Kept: {0} changes, from {1} to {2}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SetupChanges_NothingKept',
  () => ({ default: 'Nothing kept.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_SetupChanges_Scheduled',
  () => ({ default: 'Copied nightly, kept {0} days.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SetupChanges_NotScheduled',
  () => ({ default: 'Not scheduled.' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Core_SetupChanges_CopyRunning', () => ({ default: 'Running.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_SetupChanges_CopyStarted', () => ({ default: 'Started.' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_SetupChanges_More',
  () => ({ default: 'Showing {0}; download up to {1}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SetupChanges_ScanStopped',
  () => ({ default: 'Stopped after {0}.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_SetupChanges_Downloaded', () => ({ default: 'Saved {0}.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_SetupChanges_DatesReversed', () => ({ default: 'Reversed.' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_SetupChanges_AllSections',
  () => ({ default: 'All Sections' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Core_SetupChanges_ColChangedAt', () => ({ default: 'Changed At' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_SetupChanges_ColChangedBy', () => ({ default: 'Changed By' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_SetupChanges_ColLoggedInAs',
  () => ({ default: 'Logged In As' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_SetupChanges_ColSection', () => ({ default: 'Section' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_SetupChanges_ColAction', () => ({ default: 'Action' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_SetupChanges_ColWhatChanged',
  () => ({ default: 'What Changed' }),
  { virtual: true }
);

const SUMMARY = {
  keptCount: 1240,
  oldest: '2026-05-03T10:00:00.000Z',
  newest: '2026-10-31T10:00:00.000Z',
  scheduled: true,
  running: false,
  retentionDays: 730,
  sections: ['Customize Accounts', 'Manage Users'],
  pageRows: 200,
  exportRows: 5000
};

const ROW = {
  id: 'a01',
  changedAt: '2026-10-31T10:00:00.000Z',
  changedBy: 'Pat Admin',
  delegateUser: null,
  section: 'Customize Accounts',
  action: 'changedFieldLabel',
  display: '=Changed, the "Phone" label'
};

const flush = async (turns = 30) => {
  if (turns > 0) {
    await Promise.resolve();
    await flush(turns - 1);
  }
};

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render() {
  const element = createElement('c-setup-change-log', { is: SetupChangeLog });
  document.body.appendChild(element);
  await flush();
  return element;
}

function setFilter(element, id, value) {
  const input = find(element, id);
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-setup-change-log', () => {
  beforeEach(() => {
    getSummary.mockResolvedValue(SUMMARY);
    getChanges.mockResolvedValue({ rows: [ROW], more: false, scanStopped: false, scanCap: 40000 });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows what is kept, the copy status and the newest changes as it opens', async () => {
    const element = await render();

    expect(find(element, 'kept').textContent).toBe(
      'Kept: 1,240 changes, from May 3, 2026 to Oct 31, 2026.'
    );
    expect(find(element, 'copy-status').textContent.trim()).toBe('Copied nightly, kept 730 days.');
    expect(getChanges).toHaveBeenCalledWith({
      fromDate: '',
      toDate: '',
      section: '',
      search: '',
      maxRows: 200
    });
    expect(find(element, 'results').data).toEqual([ROW]);
    expect(find(element, 'section').options.map((option) => option.value)).toEqual([
      '',
      'Customize Accounts',
      'Manage Users'
    ]);
    expect(find(element, 'empty')).toBeNull();
  });

  it('searches with the filters set, and says when more match or the search stopped', async () => {
    const element = await render();
    getChanges.mockResolvedValue({ rows: [ROW], more: true, scanStopped: true, scanCap: 40000 });

    setFilter(element, 'from', '2026-10-01');
    setFilter(element, 'section', 'Manage Users');
    setFilter(element, 'search', ' phone ');
    find(element, 'run-search').click();
    await flush();

    expect(getChanges).toHaveBeenLastCalledWith({
      fromDate: '2026-10-01',
      toDate: '',
      section: 'Manage Users',
      search: 'phone',
      maxRows: 200
    });
    expect(find(element, 'more').textContent).toBe('Showing 200; download up to 5,000.');
    expect(find(element, 'scan-stopped').textContent).toBe('Stopped after 40,000.');
  });

  it('refuses a From day after the To day without asking the server', async () => {
    const element = await render();
    getChanges.mockClear();

    setFilter(element, 'from', '2026-10-05');
    setFilter(element, 'to', '2026-10-01');
    find(element, 'run-search').click();
    await flush();

    expect(getChanges).not.toHaveBeenCalled();
    expect(find(element, 'error').textContent.trim()).toBe('Reversed.');
  });

  it('shows the empty state when nothing matches', async () => {
    getChanges.mockResolvedValue({ rows: [], more: false, scanStopped: false });
    const element = await render();

    expect(find(element, 'results')).toBeNull();
    expect(find(element, 'empty')).not.toBeNull();
    expect(find(element, 'download').disabled).toBe(true);
  });

  it('starts a copy and reads the status again', async () => {
    copyNow.mockResolvedValue({ started: true, scheduled: true });
    const element = await render();
    getSummary.mockResolvedValue({ ...SUMMARY, running: true });

    find(element, 'copy-now').click();
    await flush();

    expect(copyNow).toHaveBeenCalledTimes(1);
    expect(find(element, 'notice').textContent.trim()).toBe('Started.');
    expect(find(element, 'copy-status').textContent.trim()).toBe('Running.');
  });

  it('shows a server error', async () => {
    getSummary.mockRejectedValue({ body: { message: 'No access.' } });
    const element = await render();

    expect(find(element, 'error').textContent.trim()).toBe('No access.');
  });

  it('downloads every match up to the export size as a defused CSV', async () => {
    const element = await render();
    let blob;
    let name;
    URL.createObjectURL = jest.fn((made) => {
      blob = made;
      return 'blob:test';
    });
    URL.revokeObjectURL = jest.fn();
    const click = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function () {
      name = this.download;
    });

    find(element, 'download').click();
    await flush();
    click.mockRestore();

    expect(getChanges).toHaveBeenLastCalledWith(expect.objectContaining({ maxRows: 5000 }));
    const text = await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.readAsText(blob);
    });
    // Reading as text drops a leading byte-order mark; findCsv's own tests cover it.
    const bom = String.fromCharCode(0xfeff);
    const lines = (text.startsWith(bom) ? text.slice(bom.length) : text).split('\r\n');
    expect(lines[0]).toBe('Changed At,Changed By,Logged In As,Section,Action,What Changed');
    expect(lines[1]).toBe(
      '2026-10-31 10:00:00,Pat Admin,,Customize Accounts,changedFieldLabel,"\'=Changed, the ""Phone"" label"'
    );
    expect(name).toMatch(/^Setup_Changes-\d{4}-\d{2}-\d{2}\.csv$/);
    expect(find(element, 'notice').textContent.trim()).toBe('Saved 1.');
  });
});

describe('setupChangeModel', () => {
  const labels = {
    kept: '{0} from {1} to {2}',
    nothingKept: 'Nothing.',
    copyRunning: 'Running.',
    scheduled: 'Kept {0} days.',
    notScheduled: 'Off.'
  };

  it('says nothing is kept for an empty or missing summary', () => {
    expect(keptText({ keptCount: 0 }, labels, 'en-US', 'UTC')).toBe('Nothing.');
    expect(keptText(undefined, labels, 'en-US', 'UTC')).toBe('Nothing.');
  });

  it('puts running before scheduled, and says when nothing is scheduled', () => {
    expect(copyText({ running: true, scheduled: true }, labels)).toBe('Running.');
    expect(copyText({ scheduled: true, retentionDays: 180 }, labels)).toBe('Kept 180 days.');
    expect(copyText({ scheduled: false }, labels)).toBe('Off.');
    expect(copyText(undefined, labels)).toBe('');
  });

  it('sends blanks for unset filters and spots reversed dates', () => {
    expect(filterArgs({ search: null }, 5)).toEqual({
      fromDate: '',
      toDate: '',
      section: '',
      search: '',
      maxRows: 5
    });
    expect(datesReversed({ fromDate: '2026-01-02', toDate: '2026-01-01' })).toBe(true);
    expect(datesReversed({ fromDate: '2026-01-01', toDate: '' })).toBe(false);
  });

  it('offers every section first, and adds zoned text for the CSV', () => {
    expect(sectionOptions(undefined, 'All')).toEqual([{ label: 'All', value: '' }]);
    expect(csvRows([{ changedAt: 'x' }], (value) => `[${value}]`)).toEqual([
      { changedAt: 'x', changedAtText: '[x]' }
    ]);
    expect(csvRows(undefined, String)).toEqual([]);
  });
});
