import { createElement } from 'lwc';
import RollupWizard from 'c/rollupWizard';
import getTargetFields from '@salesforce/apex/RollupBuilderController.getTargetFields';
import getSources from '@salesforce/apex/RollupBuilderController.getSources';
import getSourceFields from '@salesforce/apex/RollupBuilderController.getSourceFields';
import save from '@salesforce/apex/RollupBuilderController.save';
import preview from '@salesforce/apex/RollupBuilderController.preview';

jest.mock(
  '@salesforce/apex/RollupBuilderController.getTargetFields',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/RollupBuilderController.getSources', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/RollupBuilderController.getSourceFields',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/RollupBuilderController.save', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupBuilderController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_CurrencyWarning',
  () => ({ default: 'More than one currency.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_RollupBuilder_FilledBy', () => ({ default: '{0} ({1})' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_Summary',
  () => ({ default: '{0} of {1}, shown in {2}.' }),
  { virtual: true }
);

const MODEL = {
  multiCurrency: true,
  defaultMode: 'Both',
  targets: [{ value: 'Account', label: 'Account' }],
  aggregates: ['SUM', 'COUNT', 'ANY', 'FIRST', 'LAST', 'TEXT_LIST'].map((value) => ({
    value,
    label: value
  })),
  delimiters: [],
  modes: [{ value: 'Both', label: 'Both (recommended)' }]
};

const DRAFT = {
  recordId: 'a01000000000001AAA',
  name: 'Household total giving',
  targetObject: 'Account',
  targetField: 'Total_Giving__c',
  sourceObject: 'Gift__c',
  relationshipPath: 'Household__c',
  aggregate: 'SUM',
  sourceField: 'Amount__c',
  mode: 'Both',
  active: true
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function build(draft) {
  getTargetFields.mockResolvedValue([
    { value: 'Total_Giving__c', label: 'Total Giving', type: 'currency' },
    { value: 'Has_Given__c', label: 'Has Given', type: 'boolean', filledBy: 'Another rollup' }
  ]);
  getSources.mockResolvedValue([
    {
      value: 'Gift__c|Household__c',
      label: 'Gift, by Household',
      sourceObject: 'Gift__c',
      relationshipPath: 'Household__c',
      recordsLabel: 'Gifts'
    }
  ]);
  getSourceFields.mockResolvedValue([
    { value: 'Amount__c', label: 'Amount', type: 'currency' },
    { value: 'Gift_Date__c', label: 'Gift Date', type: 'date' },
    { value: 'Received_At__c', label: 'Received At', type: 'datetime' }
  ]);
  preview.mockResolvedValue({ maintains: 'This rollup will maintain about 1,204 records.' });
  const element = createElement('c-rollup-wizard', { is: RollupWizard });
  element.model = MODEL;
  element.draft = draft;
  document.body.appendChild(element);
  await flush();
  return element;
}

const query = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function next(element) {
  query(element, 'next').click();
  await flush();
}

async function toLastStep(element) {
  await next(element);
  await next(element);
  await next(element);
  await next(element);
}

describe('c-rollup-wizard', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('marks a field another rollup fills', async () => {
    const element = await build(DRAFT);
    const labels = query(element, 'target-field').options.map((option) => option.label);
    expect(labels).toContain('Total Giving');
    expect(labels.some((label) => label.includes('Another rollup'))).toBe(true);
  });

  it('will not move on from step 1 without a field', async () => {
    const element = await build(null);
    await next(element);
    expect(query(element, 'error-message')).not.toBeNull();
    expect(query(element, 'target-object')).not.toBeNull();
  });

  it('offers only calculations the field can hold, and warns on currency', async () => {
    const element = await build(DRAFT);
    await next(element);
    await next(element);
    const offered = query(element, 'aggregate').options.map((option) => option.value);
    expect(offered).toEqual(['SUM', 'COUNT', 'FIRST', 'LAST']);
    expect(query(element, 'currency-warning').textContent).toBe('More than one currency.');
  });

  it('asks First for the field that decides the order', async () => {
    const element = await build({ ...DRAFT, aggregate: 'FIRST' });
    await next(element);
    await next(element);
    await next(element);
    expect(query(element, 'error-message')).not.toBeNull();
    expect(query(element, 'order-by')).not.toBeNull();
  });

  it('measures a fiscal year window on date fields only', async () => {
    const element = await build({ ...DRAFT, fiscalYearAware: true, fiscalYearOffset: 0 });
    await next(element);
    await next(element);
    const offered = query(element, 'window-date').options.map((option) => option.value);
    expect(offered).toEqual(['Gift_Date__c']);
  });

  it('saves the draft and reports the notice', async () => {
    save.mockResolvedValue({ recordId: DRAFT.recordId, notice: 'Rollup saved.' });
    const element = await build(DRAFT);
    const saved = jest.fn();
    element.addEventListener('saved', saved);
    await toLastStep(element);
    expect(query(element, 'summary').textContent).toContain('Gift, by Household');

    query(element, 'save-and-calculate').click();
    await flush();

    expect(save).toHaveBeenCalledWith({
      draft: expect.objectContaining({ targetField: 'Total_Giving__c', aggregate: 'SUM' }),
      calculateNow: true
    });
    expect(saved.mock.calls[0][0].detail.notice).toBe('Rollup saved.');
  });

  it('shows the server refusal on the last step', async () => {
    save.mockRejectedValue({ body: { message: 'Another rollup fills this field.' } });
    const element = await build(DRAFT);
    await toLastStep(element);
    query(element, 'save').click();
    await flush();
    expect(query(element, 'error-message').textContent).toBe('Another rollup fills this field.');
  });

  it('previews the total on a picked record and counts what it maintains', async () => {
    const element = await build(DRAFT);
    await toLastStep(element);
    expect(preview).toHaveBeenCalledWith({
      draft: expect.objectContaining({ targetField: 'Total_Giving__c' }),
      recordId: null
    });
    expect(query(element, 'maintains').textContent).toBe(
      'This rollup will maintain about 1,204 records.'
    );

    preview.mockResolvedValue({
      maintains: 'This rollup will maintain about 1,204 records.',
      result: 'Calculated: 250. On the record now: 200.'
    });
    query(element, 'preview-record').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '001000000000001AAA' } })
    );
    await flush();

    expect(preview).toHaveBeenLastCalledWith({
      draft: expect.objectContaining({ aggregate: 'SUM' }),
      recordId: '001000000000001AAA'
    });
    expect(query(element, 'preview-result').textContent).toBe(
      'Calculated: 250. On the record now: 200.'
    );
  });
});
