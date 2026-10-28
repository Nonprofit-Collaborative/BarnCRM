import { createElement } from 'lwc';
import RollupWizard from 'c/rollupWizard';
import getTargetFields from '@salesforce/apex/RollupBuilderController.getTargetFields';
import getSources from '@salesforce/apex/RollupBuilderController.getSources';
import getSourceFields from '@salesforce/apex/RollupBuilderController.getSourceFields';
import getParentFields from '@salesforce/apex/RollupBuilderController.getParentFields';
import save from '@salesforce/apex/RollupBuilderController.save';
import preview from '@salesforce/apex/RollupBuilderController.preview';
import saveSwitchingOffDlrs from '@salesforce/apex/RollupBuilderController.saveSwitchingOffDlrs';
import LightningConfirm from 'lightning/confirm';
import previewSamples from '@salesforce/apex/RollupBuilderController.previewSamples';
import generateField from '@salesforce/apex/RollupFieldGenerator.generate';

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
jest.mock(
  '@salesforce/apex/RollupBuilderController.getParentFields',
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
  '@salesforce/apex/RollupBuilderController.saveSwitchingOffDlrs',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/RollupBuilderController.previewSamples',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/RollupFieldGenerator.generate', () => ({ default: jest.fn() }), {
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

jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_NoInstant',
  () => ({ default: 'Instant totals are not available yet for {0}.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_RollupEase_BuilderSentence',
  () => ({ default: 'Show {0} from {1}, counting {2}, in {3}. Updated: {4}.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_RollupEase_NotChosen', () => ({ default: '(not chosen)' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_RollupEase_EveryRecord', () => ({ default: 'every record' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_RollupEase_SomeRecords', () => ({ default: '{0} rules' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_RollupEase_TargetPart', () => ({ default: '{0}: {1}' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupEase_NotForField',
  () => ({ default: 'Not for {0}: {1}.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_RollupEase_FieldsNumbers',
  () => ({ default: 'Numbers for {0}.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_RollupEase_NoFieldFits',
  () => ({ default: 'Nothing fits {0}.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_RollupEase_ModeInstantAfter',
  () => ({ default: 'After the save: {0} when {1} change.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_RollupEase_ModeInstantDuring',
  () => ({ default: 'During the save: {0} when {1} change.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_RollupEase_ModeInstantNone',
  () => ({ default: 'Not until {0} have instant totals.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_RollupEase_ModeNightly',
  () => ({ default: 'Nightly: {0} at {1}.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_RollupEase_ModeBoth',
  () => ({ default: 'Both, and at {0}.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_RollupEase_ModeBothNoInstant',
  () => ({ default: 'Both: at {0}, instant once {1} have it.' }),
  { virtual: true }
);

const MODEL = {
  multiCurrency: true,
  nightlyTime: '2:00 AM',
  inSave: false,
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

async function build(draft, model = MODEL, instant = true) {
  getTargetFields.mockResolvedValue([
    { value: 'Total_Giving__c', label: 'Total Giving', type: 'currency' },
    { value: 'Has_Given__c', label: 'Has Given', type: 'boolean', filledBy: 'Another rollup' },
    { value: 'Last_Channel__c', label: 'Last Channel', type: 'picklist' }
  ]);
  getSources.mockResolvedValue([
    {
      value: 'Gift__c|Household__c',
      label: 'Gift, by Household',
      sourceObject: 'Gift__c',
      relationshipPath: 'Household__c',
      recordsLabel: 'Gifts',
      instant
    }
  ]);
  getSourceFields.mockResolvedValue([
    { value: 'Amount__c', label: 'Amount', type: 'currency' },
    { value: 'Gift_Date__c', label: 'Gift Date', type: 'date' },
    { value: 'Received_At__c', label: 'Received At', type: 'datetime' },
    { value: 'Channel__c', label: 'Channel', type: 'picklist' }
  ]);
  getParentFields.mockResolvedValue([
    { value: 'Appeal__r.Type__c', label: 'Appeal > Type', type: 'picklist' }
  ]);
  preview.mockResolvedValue({ maintains: 'This rollup will maintain about 1,204 records.' });
  const element = createElement('c-rollup-wizard', { is: RollupWizard });
  element.model = model;
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

  it('starts a new rollup in the Settings default mode, Both unless the org changed it', async () => {
    const fresh = await build(null);
    expect(fresh.draft.mode).toBe('Both');

    const changed = await build(null, { ...MODEL, defaultMode: 'Scheduled' });
    expect(changed.draft.mode).toBe('Scheduled');
  });

  it('keeps the mode of a rollup being edited', async () => {
    const element = await build(DRAFT, { ...MODEL, defaultMode: 'Scheduled' });
    expect(element.draft.mode).toBe('Both');
  });

  it('marks a field another rollup fills', async () => {
    const element = await build(DRAFT);
    const labels = query(element, 'target-field').options.map((option) => option.label);
    expect(labels).toContain('Total Giving');
    expect(labels.some((label) => label.includes('Another rollup'))).toBe(true);
  });

  it('lists the common objects first and finds any other by search', async () => {
    const element = await build(null, {
      ...MODEL,
      targets: [
        { value: 'Account', label: 'Account', common: true },
        { value: 'Asset', label: 'Asset', common: true },
        { value: 'WorkOrder', label: 'Work Order', common: false }
      ]
    });
    const values = () => query(element, 'target-object').options.map((option) => option.value);
    expect(values()).toEqual(['Account', 'Asset']);

    query(element, 'target-search').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'work' } })
    );
    await flush();

    expect(values()).toEqual(['WorkOrder']);
  });

  it('says plainly when the counted records have no instant updates', async () => {
    const element = await build(
      {
        ...DRAFT,
        sourceObject: undefined,
        relationshipPath: undefined,
        aggregate: 'COUNT',
        mode: 'Real-time'
      },
      {
        ...MODEL,
        modes: [
          { value: 'Real-time', label: 'Instantly' },
          { value: 'Scheduled', label: 'Every night' },
          { value: 'Both', label: 'Both (recommended)' }
        ]
      },
      false
    );
    await next(element);
    query(element, 'source').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Gift__c|Household__c' } })
    );
    await flush();
    await next(element);
    await next(element);
    await next(element);

    expect(query(element, 'no-instant').textContent).toBe(
      'Instant totals are not available yet for Gifts.'
    );
    const mode = query(element, 'mode');
    expect(mode.options.map((option) => option.value)).toEqual(['Scheduled', 'Both']);
    expect(mode.value).toBe('Both');
  });

  it('shows no notice for records that update instantly', async () => {
    const element = await build(DRAFT);
    await toLastStep(element);
    expect(query(element, 'no-instant')).toBeNull();
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

  it('fills a picklist with First or Last, copied from a picklist or text', async () => {
    const element = await build({ ...DRAFT, targetField: 'Last_Channel__c', aggregate: 'FIRST' });
    await next(element);
    await next(element);
    const offered = query(element, 'aggregate').options.map((option) => option.value);
    expect(offered).toEqual(['FIRST', 'LAST']);
    const copied = query(element, 'source-field').options.map((option) => option.value);
    expect(copied).toEqual(['Channel__c']);
  });

  it('filters on a field one lookup away, and says when it may not update at once', async () => {
    const element = await build(DRAFT);
    await next(element);
    await next(element);
    await next(element);
    const filter = element.shadowRoot.querySelector(
      'c-rollup-filter-builder[data-name="filterJson"]'
    );
    expect(filter.fields.map((field) => field.value)).toContain('Appeal__r.Type__c');
    expect(query(element, 'parent-field-note')).toBeNull();

    filter.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          value: JSON.stringify({
            version: 1,
            conditions: [{ id: 1, field: 'Appeal__r.Type__c', operator: 'equals', value: 'Mail' }]
          })
        }
      })
    );
    await flush();
    expect(query(element, 'parent-field-note')).not.toBeNull();
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

  it('saves the optional bypass custom permission from the last step', async () => {
    save.mockResolvedValue({ recordId: DRAFT.recordId, notice: 'Rollup saved.' });
    const element = await build(DRAFT);
    await toLastStep(element);
    const bypass = query(element, 'bypass-permission');
    expect(bypass.value).toBeUndefined();

    bypass.dispatchEvent(new CustomEvent('change', { detail: { value: 'Data_Migration' } }));
    await flush();
    query(element, 'save').click();
    await flush();

    expect(save).toHaveBeenCalledWith({
      draft: expect.objectContaining({ bypassPermission: 'Data_Migration' }),
      calculateNow: false
    });
  });

  it('asks before saving over a DLRS rollup and saves on yes', async () => {
    save.mockResolvedValue({ confirmation: 'The DLRS rollup Giving also fills Account.Total.' });
    saveSwitchingOffDlrs.mockResolvedValue({ recordId: DRAFT.recordId, notice: 'Rollup saved.' });
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    const element = await build(DRAFT);
    const saved = jest.fn();
    element.addEventListener('saved', saved);
    await toLastStep(element);

    query(element, 'save').click();
    await flush();
    await flush();

    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining('The DLRS rollup Giving also fills Account.Total.')
      })
    );
    expect(saveSwitchingOffDlrs).toHaveBeenCalledWith({
      draft: expect.objectContaining({ targetField: 'Total_Giving__c' }),
      calculateNow: false
    });
    expect(saved.mock.calls[0][0].detail.notice).toBe('Rollup saved.');
  });

  it('saves nothing over a DLRS rollup when the admin says no', async () => {
    save.mockResolvedValue({ confirmation: 'The DLRS rollup Giving also fills Account.Total.' });
    LightningConfirm.open = jest.fn().mockResolvedValue(false);
    const element = await build(DRAFT);
    const saved = jest.fn();
    element.addEventListener('saved', saved);
    await toLastStep(element);

    query(element, 'save').click();
    await flush();
    await flush();

    expect(saveSwitchingOffDlrs).not.toHaveBeenCalled();
    expect(saved).not.toHaveBeenCalled();
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

  it('offers a row limit to Sum, and asks it for an order and a direction', async () => {
    const element = await build({ ...DRAFT, rowLimit: 5 });
    await next(element);
    await next(element);
    expect(query(element, 'row-limit').value).toBe(5);
    expect(query(element, 'order-direction').value).toBe('Ascending');
    await next(element);
    expect(query(element, 'error-message')).not.toBeNull();
    expect(query(element, 'order-by')).not.toBeNull();
  });

  it('gives First no row limit or direction, and saves neither', async () => {
    save.mockResolvedValue({ recordId: DRAFT.recordId, notice: 'Rollup saved.' });
    const element = await build({
      ...DRAFT,
      aggregate: 'FIRST',
      orderByField: 'Gift_Date__c',
      orderDirection: 'Descending',
      rowLimit: 3
    });
    await next(element);
    await next(element);
    expect(query(element, 'row-limit')).toBeNull();
    expect(query(element, 'order-direction')).toBeNull();
    await next(element);
    await next(element);
    query(element, 'save').click();
    await flush();
    expect(save).toHaveBeenCalledWith({
      draft: expect.objectContaining({ rowLimit: null, orderDirection: 'Ascending' }),
      calculateNow: false
    });
  });

  it('saves a limited Sum with its order and direction', async () => {
    save.mockResolvedValue({ recordId: DRAFT.recordId, notice: 'Rollup saved.' });
    const element = await build({
      ...DRAFT,
      orderByField: 'Amount__c',
      orderDirection: 'Descending',
      rowLimit: '5'
    });
    await toLastStep(element);
    query(element, 'save').click();
    await flush();
    expect(save).toHaveBeenCalledWith({
      draft: expect.objectContaining({ rowLimit: 5, orderDirection: 'Descending' }),
      calculateNow: false
    });
  });

  it('asks a Custom delimiter for its characters', async () => {
    const element = await build({ ...DRAFT, aggregate: 'TEXT_LIST', delimiter: 'Custom' });
    await next(element);
    await next(element);
    expect(query(element, 'custom-delimiter')).not.toBeNull();
    await next(element);
    expect(query(element, 'error-message')).not.toBeNull();
    expect(query(element, 'custom-delimiter')).not.toBeNull();
  });

  it('saves Include deleted, and no custom delimiter unless Custom is chosen', async () => {
    save.mockResolvedValue({ recordId: DRAFT.recordId, notice: 'Rollup saved.' });
    const element = await build({ ...DRAFT, delimiter: 'Pipe', customDelimiter: ' / ' });
    await next(element);
    await next(element);
    await next(element);
    const includeDeleted = query(element, 'include-deleted');
    includeDeleted.checked = true;
    includeDeleted.dispatchEvent(new CustomEvent('change'));
    await next(element);
    query(element, 'save').click();
    await flush();
    expect(save).toHaveBeenCalledWith({
      draft: expect.objectContaining({ includeDeleted: true, customDelimiter: null }),
      calculateNow: false
    });
  });

  describe('Ease of use', () => {
    const parts = (element) =>
      [...element.shadowRoot.querySelectorAll('[data-id="sentence-part"]')].map((part) => ({
        label: part.label,
        step: part.dataset.step,
        disabled: part.disabled
      }));

    it('reads an edited rollup as one sentence whose parts open their steps (U3)', async () => {
      const element = await build(DRAFT);
      expect(query(element, 'builder-sentence').textContent).toContain('Show ');
      expect(parts(element)).toEqual([
        { label: 'SUM (Amount)', step: '3', disabled: false },
        { label: 'Gift, by Household', step: '2', disabled: false },
        { label: 'every record', step: '4', disabled: false },
        { label: 'Account: Total Giving', step: '1', disabled: false },
        { label: 'Both (recommended)', step: '5', disabled: false }
      ]);
      element.shadowRoot.querySelector('[data-step="3"]').click();
      await flush();
      expect(query(element, 'aggregate')).not.toBeNull();
    });

    it('opens only steps already reached for a new rollup (U3)', async () => {
      const element = await build(null);
      const shown = parts(element);
      expect(shown.every((part) => part.label === '(not chosen)')).toBe(true);
      expect(shown.filter((part) => !part.disabled).map((part) => part.step)).toEqual(['1']);
      element.shadowRoot.querySelector('[data-step="3"]').click();
      await flush();
      expect(query(element, 'target-object')).not.toBeNull();
    });

    it('says which calculations the field cannot hold and lists only fields Sum can read (U9)', async () => {
      const element = await build({ ...DRAFT, sourceField: undefined });
      await next(element);
      await next(element);
      expect(query(element, 'unavailable').textContent).toBe(
        'Not for Total Giving: ANY, TEXT_LIST.'
      );
      expect(query(element, 'source-field').options.map((option) => option.value)).toEqual([
        'Amount__c'
      ]);
      expect(query(element, 'field-guidance').textContent).toBe('Numbers for SUM.');
    });

    it('clears a field the new calculation cannot read (U9)', async () => {
      const element = await build({ ...DRAFT, aggregate: 'FIRST', sourceField: 'Gift_Date__c' });
      await next(element);
      await next(element);
      query(element, 'aggregate').dispatchEvent(
        new CustomEvent('change', { detail: { value: 'SUM' } })
      );
      await flush();
      expect(query(element, 'source-field').value).toBeUndefined();
    });

    it('explains each mode by when the field changes (U10)', async () => {
      const element = await build(DRAFT);
      await toLastStep(element);
      expect(query(element, 'instantly').textContent).toBe(
        'After the save: Total Giving when Gifts change.'
      );
      expect(query(element, 'nightly').textContent).toBe('Nightly: Total Giving at 2:00 AM.');
      expect(query(element, 'both').textContent).toBe('Both, and at 2:00 AM.');

      const during = await build(DRAFT, { ...MODEL, inSave: true });
      await toLastStep(during);
      expect(query(during, 'instantly').textContent).toBe(
        'During the save: Total Giving when Gifts change.'
      );

      const noTrigger = await build(DRAFT, MODEL, false);
      await toLastStep(noTrigger);
      expect(query(noTrigger, 'instantly').textContent).toBe(
        'Not until Gifts have instant totals.'
      );
      expect(query(noTrigger, 'both').textContent).toBe(
        'Both: at 2:00 AM, instant once Gifts have it.'
      );
    });

    it('picks sample records and lists the records read for one (U4)', async () => {
      previewSamples.mockResolvedValue([
        { recordId: '001000000000001AAA', name: 'Rivera Household', result: 'Calculated: 250.' },
        { recordId: '001000000000002AAA', name: 'Chen Household', result: 'Calculated: 0.' }
      ]);
      const element = await build(DRAFT);
      await toLastStep(element);
      expect(previewSamples).not.toHaveBeenCalled();
      expect(query(element, 'preview-rows')).toBeNull();

      query(element, 'pick-samples').click();
      await flush();
      expect(previewSamples).toHaveBeenCalledWith({
        draft: expect.objectContaining({ targetField: 'Total_Giving__c' })
      });
      const samples = element.shadowRoot.querySelectorAll('[data-id="sample"]');
      expect(samples).toHaveLength(2);
      expect(samples[0].textContent).toContain('Rivera Household');
      expect(samples[0].textContent).toContain('Calculated: 250.');

      preview.mockResolvedValue({
        maintains: 'This rollup will maintain about 1,204 records.',
        result: 'Calculated: 250. On the record now: 200.',
        rows: {
          total: 12,
          summary: 'Showing 2 of the 12 records read for this record.',
          rows: [
            { recordId: 'a01000000000001AAA', name: 'G-0001', counted: true, reason: 'Counted' },
            {
              recordId: 'a01000000000002AAA',
              name: 'G-0002',
              counted: false,
              reason: 'Left out: does not meet condition 1'
            }
          ]
        }
      });
      element.shadowRoot.querySelectorAll('[data-id="show-rows"]')[0].click();
      await flush();
      expect(preview).toHaveBeenLastCalledWith({
        draft: expect.objectContaining({ aggregate: 'SUM' }),
        recordId: '001000000000001AAA'
      });
      expect(query(element, 'rows-summary').textContent).toBe(
        'Showing 2 of the 12 records read for this record.'
      );
      const rows = element.shadowRoot.querySelectorAll('[data-id="preview-row"]');
      expect(rows).toHaveLength(2);
      expect(rows[0].querySelector('a').getAttribute('href')).toBe('/a01000000000001AAA');
      expect(rows[1].textContent).toContain('Left out: does not meet condition 1');
      // The samples stay, so another can be opened.
      expect(element.shadowRoot.querySelectorAll('[data-id="sample"]')).toHaveLength(2);
    });

    it('says so when there is no record to sample, and shows a household note (U4)', async () => {
      previewSamples.mockResolvedValue([]);
      const element = await build(DRAFT);
      await toLastStep(element);
      query(element, 'pick-samples').click();
      await flush();
      expect(query(element, 'samples-none')).not.toBeNull();

      preview.mockResolvedValue({
        maintains: 'This rollup will maintain about 1,204 records.',
        result: 'Calculated: 250. On the record now: 200.',
        rows: { total: 0, rows: [], note: 'Read through a household.' }
      });
      query(element, 'preview-record').dispatchEvent(
        new CustomEvent('change', { detail: { recordId: '001000000000001AAA' } })
      );
      await flush();
      expect(query(element, 'rows-note').textContent).toBe('Read through a household.');
      expect(query(element, 'rows-summary')).toBeNull();
    });

    const GENERATED = {
      apiName: 'Gift_Count__c',
      steps: ['Open Setup.', 'Choose Number.', 'Give access.', 'Come back.'],
      fieldPath: 'objects/Account/fields/Gift_Count__c.field-meta.xml',
      fieldXml: '<CustomField>Gift_Count__c</CustomField>',
      deployPackage: 'UEsDBA==',
      fileName: 'BarnRollupField_Account_Gift_Count__c.zip'
    };

    it('writes a field to create in Setup or deploy, and nothing more (U8)', async () => {
      generateField.mockResolvedValue(GENERATED);
      const element = await build(DRAFT);
      expect(query(element, 'create-field')).toBeNull();

      query(element, 'open-create-field').click();
      await flush();
      expect(query(element, 'new-field-kind').value).toBe('NUMBER');
      expect(query(element, 'write-field').disabled).toBe(true);

      query(element, 'new-field-label').dispatchEvent(
        new CustomEvent('change', { detail: { value: 'Gift Count' } })
      );
      await flush();
      expect(query(element, 'write-field').disabled).toBe(false);
      query(element, 'write-field').click();
      await flush();

      expect(generateField).toHaveBeenCalledWith({
        objectApiName: 'Account',
        fieldLabel: 'Gift Count',
        kind: 'NUMBER'
      });
      expect(element.shadowRoot.querySelectorAll('[data-id="field-steps"] li')).toHaveLength(4);
      expect(query(element, 'field-xml').textContent).toBe(GENERATED.fieldXml);
      const download = query(element, 'download-field');
      expect(download.getAttribute('href')).toBe('data:application/zip;base64,UEsDBA==');
      expect(download.getAttribute('download')).toBe(GENERATED.fileName);

      Object.assign(navigator, { clipboard: { writeText: jest.fn().mockResolvedValue() } });
      query(element, 'copy-field').click();
      await flush();
      expect(navigator.clipboard.writeText).toHaveBeenCalledWith(GENERATED.fieldXml);
      expect(query(element, 'field-notice').textContent).toBe('c.Core_RollupBuilder_InstantCopied');
    });

    it('chooses the new field once Refresh Fields finds it (U8)', async () => {
      generateField.mockResolvedValue(GENERATED);
      const element = await build({ ...DRAFT, targetField: undefined });
      query(element, 'open-create-field').click();
      await flush();
      query(element, 'new-field-label').dispatchEvent(
        new CustomEvent('change', { detail: { value: 'Gift Count' } })
      );
      query(element, 'write-field').click();
      await flush();

      getTargetFields.mockResolvedValue([
        { value: 'Total_Giving__c', label: 'Total Giving', type: 'currency' },
        { value: 'Gift_Count__c', label: 'Gift Count', type: 'double' }
      ]);
      query(element, 'refresh-fields').click();
      await flush();

      expect(element.draft.targetField).toBe('Gift_Count__c');
      expect(query(element, 'create-field')).toBeNull();
    });

    it('opens Create a Field filled in when a starter template names a missing field (U2)', async () => {
      const element = await build({
        ...DRAFT,
        targetField: 'Average_Gift__c',
        newFieldLabel: 'Average Gift',
        newFieldKind: 'CURRENCY'
      });

      expect(query(element, 'create-field')).not.toBeNull();
      expect(query(element, 'new-field-label').value).toBe('Average Gift');
      expect(query(element, 'new-field-kind').value).toBe('CURRENCY');
      expect(element.draft.newFieldLabel).toBeUndefined();
      expect(element.draft.targetField).toBe('Average_Gift__c');
    });
  });
});
