import { createElement } from 'lwc';
import RollupDefinitions from 'c/rollupDefinitions';
import getPage from '@salesforce/apex/RollupController.getPage';
import recalculate from '@salesforce/apex/RollupController.recalculate';
import setSchedule from '@salesforce/apex/RollupController.setSchedule';
import setActive from '@salesforce/apex/RollupController.setActive';
import restoreDefaults from '@salesforce/apex/RollupController.restoreDefaults';
import recalculateAll from '@salesforce/apex/RollupController.recalculateAll';
import estimateFullRun from '@salesforce/apex/RollupController.estimateFullRun';
import runTonight from '@salesforce/apex/RollupController.runTonight';

jest.mock(
  '@salesforce/apex/RollupController.getPage',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/RollupController.recalculate', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupController.recalculateAll', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupController.setSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupController.setActive', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupController.setMode', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupController.restoreDefaults', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupController.estimateFullRun', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupController.runTonight', () => ({ default: jest.fn() }), {
  virtual: true
});

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

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Core_Rollups_FreshnessStale',
  () => ({ default: 'Rollups have not been calculated in more than 36 hours.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_Rollups_RecalculateStarted',
  () => ({ default: 'Recalculation started.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_Rollups_ScheduleActive',
  () => ({ default: 'Nightly recalculation is scheduled for {0}.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_Rollups_CountsSeparatedBy',
  () => ({ default: 'separated by {0}' }),
  { virtual: true }
);

const ROLLUP = {
  recordId: 'a01000000000001AAA',
  name: 'Household total giving',
  description: 'Everything this household has given.',
  definitionKey: 'Household_Total_Giving',
  sourceObject: 'Gift__c',
  targetObject: 'Account',
  targetField: 'Total_Giving__c',
  relationshipPath: 'Household__c',
  aggregate: 'SUM',
  sourceField: 'Amount__c',
  mode: 'Both',
  fiscalYearAware: false,
  fiscalYearOffset: null,
  active: true,
  packageDefault: true,
  lastCalculated: '2026-09-08T02:00:00.000Z',
  filterJson: null,
  targetFilterJson: null
};

const PAGE = {
  canManage: true,
  scheduled: true,
  nextRunAt: '2026-09-09T02:00:00.000Z',
  nightlyTime: '10:00 PM',
  lastCalculated: '2026-09-08T02:00:00.000Z',
  stale: false,
  defaultMode: 'Both',
  modes: ['Real-time', 'Scheduled', 'Both'],
  modeOptions: [
    { value: 'Real-time', label: 'Instantly' },
    { value: 'Scheduled', label: 'Every night' },
    { value: 'Both', label: 'Both (recommended)' }
  ],
  rollups: [ROLLUP]
};

const EMPTY_PAGE = { ...PAGE, scheduled: false, lastCalculated: null, stale: true, rollups: [] };

function createComponent() {
  const element = createElement('c-rollup-definitions', { is: RollupDefinitions });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-rollup-definitions', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every rollup with what it counts and where it shows', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const rows = element.shadowRoot.querySelectorAll('[data-id="rollup-row"]');
    expect(rows.length).toBe(1);
    expect(rows[0].textContent).toContain('Household total giving');
    expect(rows[0].textContent).toContain('SUM Amount__c on Gift__c');
    expect(rows[0].textContent).toContain('Account.Total_Giving__c');
  });

  it('names each calculation as the administrator reads it, with a text list separator', async () => {
    const programs = {
      ...ROLLUP,
      recordId: 'a01000000000002AAA',
      name: 'Contact programs',
      sourceObject: 'Program_Enrollment__c',
      targetObject: 'Contact',
      targetField: 'Programs__c',
      aggregate: 'TEXT_LIST_DISTINCT',
      aggregateLabel: 'Text list, each value once',
      delimiterLabel: 'Semicolon',
      sourceField: 'Program_Name__c'
    };
    const major = {
      ...ROLLUP,
      recordId: 'a01000000000003AAA',
      name: 'Has given a major gift',
      targetField: 'Major_Donor__c',
      aggregate: 'ANY',
      aggregateLabel: 'Any',
      delimiterLabel: null,
      sourceField: null
    };
    const element = createComponent();
    getPage.emit({ ...PAGE, rollups: [programs, major] });
    await flush();

    const rows = element.shadowRoot.querySelectorAll('[data-id="rollup-row"]');
    expect(rows[0].textContent).toContain(
      'Text list, each value once Program_Name__c on Program_Enrollment__c, separated by semicolon'
    );
    expect(rows[1].textContent).toContain('Any on Gift__c');
    expect(rows[1].textContent).not.toContain('separated by');
  });

  it('offers the modes by the names an administrator reads, keeping the stored values', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const combobox = element.shadowRoot.querySelector('lightning-combobox');
    expect(combobox.options).toEqual([
      { value: 'Real-time', label: 'Instantly' },
      { value: 'Scheduled', label: 'Every night' },
      { value: 'Both', label: 'Both (recommended)' }
    ]);
    expect(combobox.value).toBe('Both');
  });

  it('warns when the rollups have not run inside the freshness window', async () => {
    const element = createComponent();
    getPage.emit(EMPTY_PAGE);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="stale-warning"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="never-calculated"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty-message"]')).not.toBeNull();
  });

  it('recalculates one rollup and says so', async () => {
    recalculate.mockResolvedValue(PAGE);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector(`lightning-button[data-id="${ROLLUP.recordId}"]`).click();
    await flush();

    expect(recalculate).toHaveBeenCalledWith({ definitionId: ROLLUP.recordId });
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]').textContent).toContain(
      'Recalculation started.'
    );
  });

  it('says the hour the nightly run is scheduled for', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="schedule-message"]').textContent).toBe(
      'Nightly recalculation is scheduled for 10:00 PM.'
    );
  });

  it('starts and stops the nightly recalculation', async () => {
    setSchedule.mockResolvedValue({ ...PAGE, scheduled: false });
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="schedule-button"]').click();
    await flush();

    expect(setSchedule).toHaveBeenCalledWith({ scheduled: false });
  });

  it('puts a refused switch back where it was', async () => {
    setActive.mockRejectedValue({ body: { message: 'You do not have permission.' } });
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const toggle = element.shadowRoot.querySelector(
      `lightning-input[data-id="${ROLLUP.recordId}"]`
    );
    toggle.checked = false;
    toggle.dispatchEvent(new CustomEvent('change'));
    await flush();

    expect(setActive).toHaveBeenCalledWith({ definitionId: ROLLUP.recordId, active: false });
    expect(toggle.checked).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toContain(
      'You do not have permission.'
    );
  });

  it('restores the shipped rollups', async () => {
    restoreDefaults.mockResolvedValue(PAGE);
    const element = createComponent();
    getPage.emit(EMPTY_PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="restore-defaults"]').click();
    await flush();

    expect(restoreDefaults).toHaveBeenCalled();
  });

  it('links to the Rollup Builder from the settings page', async () => {
    const element = createComponent();
    getPage.emit({ ...PAGE, builderTabApiName: 'Rollup_Builder' });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="new-rollup"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="open-builder"]').click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Rollup_Builder' }
    });
  });

  it('asks the Builder to open a new, edited or copied rollup', async () => {
    const element = createComponent();
    element.builder = true;
    getPage.emit({ ...PAGE, builderTabApiName: 'Rollup_Builder' });
    await flush();

    const events = [];
    ['new', 'edit', 'copy'].forEach((name) =>
      element.addEventListener(name, (event) => events.push([name, event.detail]))
    );
    expect(element.shadowRoot.querySelector('[data-id="open-builder"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="new-rollup"]').click();
    element.shadowRoot.querySelector('[data-action="edit"]').click();
    element.shadowRoot.querySelector('[data-action="copy"]').click();

    expect(events.map(([name]) => name)).toEqual(['new', 'edit', 'copy']);
    expect(events[1][1].recordId).toBe(ROLLUP.recordId);
    expect(events[2][1].recordId).toBe(ROLLUP.recordId);
  });

  it('says how many records and how long before Recalculate all, and starts on Start now', async () => {
    estimateFullRun.mockResolvedValue({
      summary: 'About 41,200 records, roughly 25 minutes.',
      workingHours: true
    });
    recalculateAll.mockResolvedValue(PAGE);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="recalculate-all"]').click();
    await flush();

    expect(recalculateAll).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="estimate-summary"]').textContent).toBe(
      'About 41,200 records, roughly 25 minutes.'
    );
    expect(element.shadowRoot.querySelector('[data-id="working-hours"]')).not.toBeNull();

    element.shadowRoot.querySelector('[data-id="start-now"]').click();
    await flush();

    expect(recalculateAll).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="estimate"]')).toBeNull();
  });

  it('runs it tonight instead and says what will happen', async () => {
    estimateFullRun.mockResolvedValue({ summary: 'About 12 records.', workingHours: false });
    runTonight.mockResolvedValue('One recalculation is set for 2:00 AM tonight.');
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="recalculate-all"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="working-hours"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="run-tonight"]').click();
    await flush();

    expect(runTonight).toHaveBeenCalled();
    expect(recalculateAll).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]').textContent).toBe(
      'One recalculation is set for 2:00 AM tonight.'
    );
  });
});
