import { createElement } from 'lwc';
import RollupDlrsImport from 'c/rollupDlrsImport';
import LightningConfirm from 'lightning/confirm';
import getCandidates from '@salesforce/apex/RollupDlrsImport.getCandidates';
import importRollups from '@salesforce/apex/RollupDlrsImport.importRollups';
import compare from '@salesforce/apex/RollupDlrsImport.compare';
import turnOn from '@salesforce/apex/RollupDlrsImport.turnOn';

jest.mock('@salesforce/apex/RollupDlrsImport.getCandidates', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupDlrsImport.importRollups', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupDlrsImport.compare', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupDlrsImport.turnOn', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_DlrsImportFills',
  () => ({ default: 'Fills {0} by {1}' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_DlrsImportBecomes',
  () => ({ default: 'Becomes a {0} on {1}' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_DlrsImportRefused',
  () => ({ default: 'Not copied: {0}' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_DlrsImportFinished',
  () => ({ default: '{0} turned on' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Core_RollupBuilder_DlrsImportSame', () => ({ default: 'Same' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_DlrsConfirmQuestion',
  () => ({ default: 'Click OK.' }),
  {
    virtual: true
  }
);

const MODEL = { aggregates: [{ value: 'COUNT', label: 'Count' }] };
const CANDIDATES = [
  {
    key: 'Child_Count',
    label: 'Child Count',
    parentObject: 'Account',
    targetField: 'Member_Count__c',
    operation: 'Count',
    importable: true,
    reasons: [],
    notes: ['DLRS listed records with a blank order field first; the copy lists them last.'],
    draft: { aggregate: 'COUNT' }
  },
  {
    key: 'Median_Gift',
    label: 'Median Gift',
    parentObject: 'Account',
    targetField: 'Median__c',
    operation: 'Median',
    importable: false,
    reasons: ['BarnCRM has no total like the DLRS operation Median.'],
    notes: [],
    draft: {}
  }
];
const COPIED = [
  {
    key: 'Child_Count',
    name: 'Child Count',
    outcome: 'created',
    recordId: 'a01000000000001',
    confirmation: 'The DLRS rollup Child Count also fills Account.Member_Count__c.'
  }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const $ = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const $$ = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);
const click = async (element, id) => {
  $(element, id).dispatchEvent(new CustomEvent('click'));
  await flush();
};

async function build(candidates = CANDIDATES) {
  getCandidates.mockResolvedValue(candidates);
  const element = createElement('c-rollup-dlrs-import', { is: RollupDlrsImport });
  element.model = MODEL;
  document.body.appendChild(element);
  await flush();
  return element;
}

/** Copies the chosen rollups and arrives on the compare step. */
async function copied(element) {
  importRollups.mockResolvedValue(COPIED);
  await click(element, 'next');
  await click(element, 'copy');
}

describe('c-rollup-dlrs-import', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists what can be copied, ticked, and what stays in DLRS with why', async () => {
    const element = await build();

    const copyable = $$(element, 'copyable');
    expect(copyable).toHaveLength(1);
    const box = copyable[0].querySelector('lightning-input');
    expect(box.label).toBe('Child Count');
    expect(box.checked).toBe(true);
    expect(copyable[0].textContent).toContain('Fills Account.Member_Count__c by Count');
    expect($$(element, 'staying')).toHaveLength(1);
    expect($(element, 'reason').textContent).toBe(
      'BarnCRM has no total like the DLRS operation Median.'
    );
    expect($(element, 'next').disabled).toBe(false);

    box.checked = false;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect($(element, 'next').disabled).toBe(true);
  });

  it('says so when DLRS has no active rollups', async () => {
    const element = await build([]);

    expect($(element, 'none-active')).not.toBeNull();
    expect($(element, 'next').disabled).toBe(true);
  });

  it('reviews what each becomes, then copies the chosen ones switched off', async () => {
    const element = await build();
    await click(element, 'next');

    expect($(element, 'becomes').textContent).toBe('Becomes a Count on Account.Member_Count__c');
    expect($(element, 'note').textContent).toContain('blank order field');

    importRollups.mockResolvedValue(COPIED);
    await click(element, 'copy');

    expect(importRollups).toHaveBeenCalledWith({ keys: ['Child_Count'] });
    expect($(element, 'outcome').textContent).toBe('c.Core_RollupBuilder_DlrsImportCreated');
  });

  it('says why a chosen rollup was not copied, and offers nothing to turn on', async () => {
    const element = await build();
    importRollups.mockResolvedValue([
      { key: 'Child_Count', name: 'Child Count', outcome: 'refused', reason: 'The field is gone.' }
    ]);
    await click(element, 'next');
    await click(element, 'copy');

    expect($(element, 'outcome').textContent).toBe('Not copied: The field is gone.');
    expect($(element, 'nothing-copied')).not.toBeNull();
    expect($(element, 'compare')).toBeNull();
    expect($(element, 'next')).toBeNull();
  });

  it('shows the value DLRS wrote beside the value BarnCRM calculates', async () => {
    const element = await build();
    await copied(element);
    compare.mockResolvedValue([
      {
        recordId: '001A',
        recordName: 'Parent Org',
        dlrsValue: '2',
        barncrmValue: '2',
        agree: true
      },
      {
        recordId: '001B',
        recordName: 'Stale Org',
        dlrsValue: '7',
        barncrmValue: '0',
        agree: false,
        difference: 'The values differ.'
      }
    ]);

    await click(element, 'compare');

    expect(compare).toHaveBeenCalledWith({ definitionId: 'a01000000000001' });
    const results = [...$$(element, 'result')].map((cell) => cell.textContent);
    expect(results).toEqual(['Same', 'The values differ.']);
  });

  it('finishes only once every copy is on, which asks first', async () => {
    const element = await build();
    await copied(element);
    await click(element, 'next');
    expect($(element, 'finish').disabled).toBe(true);

    LightningConfirm.open = jest.fn().mockResolvedValue(false);
    await click(element, 'turn-on');
    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({
        message: 'The DLRS rollup Child Count also fills Account.Member_Count__c. Click OK.'
      })
    );
    expect(turnOn).not.toHaveBeenCalled();
    expect($(element, 'finish').disabled).toBe(true);

    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    turnOn.mockResolvedValue({ outcome: 'active' });
    await click(element, 'turn-on');
    expect(turnOn).toHaveBeenCalledWith({
      definitionId: 'a01000000000001',
      dlrsOffConfirmed: true
    });
    expect($(element, 'turn-on')).toBeNull();
    expect($(element, 'finish').disabled).toBe(false);

    const closed = jest.fn();
    element.addEventListener('close', closed);
    await click(element, 'finish');
    expect(closed.mock.calls[0][0].detail).toEqual({ notice: '1 turned on' });
  });

  it('shows the reason when turning on is refused, and stays unfinished', async () => {
    const element = await build();
    await copied(element);
    await click(element, 'next');
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    turnOn.mockRejectedValue({ body: { message: 'The field is not writable.' } });

    await click(element, 'turn-on');

    expect($(element, 'error').textContent).toBe('The field is not writable.');
    expect($(element, 'finish').disabled).toBe(true);
  });

  it('closes without finishing, leaving the copies switched off', async () => {
    const element = await build();
    const closed = jest.fn();
    element.addEventListener('close', closed);

    await click(element, 'close');

    expect(closed.mock.calls[0][0].detail).toEqual({});
    expect(turnOn).not.toHaveBeenCalled();
  });
});
