import { createElement } from 'lwc';
import GenericMerge from 'c/genericMerge';
import BarnConfirmModal from 'c/barnConfirmModal';
import getView from '@salesforce/apex/GenericMergeController.getView';
import compare from '@salesforce/apex/GenericMergeController.compare';
import mergeRecords from '@salesforce/apex/GenericMergeController.mergeRecords';
import undo from '@salesforce/apex/GenericMergeController.undo';
import { fromOther, initialChoices, visibleRows } from '../mergeChoices';

jest.mock('@salesforce/apex/GenericMergeController.getView', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GenericMergeController.compare', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GenericMergeController.mergeRecords', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GenericMergeController.undo', () => ({ default: jest.fn() }), {
  virtual: true
});

const VIEW = {
  enabled: true,
  objects: [{ label: 'Fund', value: 'Fund__c' }],
  merges: [
    {
      journalId: 'a0J000000000001',
      objectLabel: 'Fund',
      mergedName: 'Building Fund copy',
      mergedAt: '2026-11-10T10:00:00Z',
      status: 'Merged',
      canUndo: true,
      notes: ''
    }
  ]
};

const COMPARISON = {
  objectLabel: 'Fund',
  firstName: 'Building Fund',
  secondName: 'Building Fund copy',
  fields: [
    {
      name: 'Description__c',
      label: 'Description',
      first: '',
      second: 'Roof',
      differs: true,
      takeSecond: true
    },
    { name: 'Code__c', label: 'Code', first: 'B1', second: 'B2', differs: true, takeSecond: false },
    { name: 'Active__c', label: 'Active', first: 'true', second: 'true', differs: false }
  ]
};

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build() {
  const element = createElement('c-generic-merge', { is: GenericMerge });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

/** Chooses the object and both records, then compares. */
async function compared(element) {
  find(element, 'object').dispatchEvent(
    new CustomEvent('change', { detail: { value: 'Fund__c' } })
  );
  await flushPromises();
  find(element, 'first').dispatchEvent(
    new CustomEvent('change', { detail: { recordId: 'a01000000000001' } })
  );
  find(element, 'second').dispatchEvent(
    new CustomEvent('change', { detail: { recordId: 'a01000000000002' } })
  );
  await flushPromises();
  find(element, 'compare').click();
  await flushPromises();
}

describe('mergeChoices', () => {
  it('starts from the rules and sends only the other side differences', () => {
    const choices = initialChoices(COMPARISON.fields);
    expect(choices).toEqual({ Description__c: 'second', Code__c: 'first', Active__c: 'first' });
    expect(fromOther(COMPARISON.fields, choices, 'first')).toEqual(['Description__c']);
    expect(fromOther(COMPARISON.fields, choices, 'second')).toEqual(['Code__c']);
    expect(visibleRows(COMPARISON.fields, choices, true).map((row) => row.name)).toEqual([
      'Description__c',
      'Code__c'
    ]);
  });
});

describe('c-generic-merge', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says it is off and offers nothing while the setting is off', async () => {
    getView.mockResolvedValue({ enabled: false, objects: [], merges: [] });
    const element = await build();

    expect(find(element, 'off')).not.toBeNull();
    expect(find(element, 'object')).toBeNull();
    expect(find(element, 'merges')).toBeNull();
  });

  it('compares only once both records are chosen, then shows the rules choice', async () => {
    getView.mockResolvedValue(VIEW);
    compare.mockResolvedValue(COMPARISON);
    const element = await build();
    expect(find(element, 'compare').disabled).toBe(true);
    expect(find(element, 'merges')).not.toBeNull();

    await compared(element);

    expect(compare).toHaveBeenCalledWith({
      objectName: 'Fund__c',
      firstId: 'a01000000000001',
      secondId: 'a01000000000002'
    });
    expect(element.shadowRoot.querySelectorAll('[data-id="field-row"]')).toHaveLength(3);
    const description = element.shadowRoot.querySelector(
      'input[data-field="Description__c"][data-side="second"]'
    );
    expect(description.checked).toBe(true);

    const only = find(element, 'only-differences');
    only.checked = true;
    only.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
    expect(element.shadowRoot.querySelectorAll('[data-id="field-row"]')).toHaveLength(2);
  });

  it('merges after a confirm with the chosen values, keeping the chosen record', async () => {
    getView.mockResolvedValue(VIEW);
    compare.mockResolvedValue(COMPARISON);
    mergeRecords.mockResolvedValue({ moved: 2, changed: 1 });
    BarnConfirmModal.open = jest.fn(() => Promise.resolve(true));
    const element = await build();
    await compared(element);

    find(element, 'keep').dispatchEvent(new CustomEvent('change', { detail: { value: 'second' } }));
    await flushPromises();
    find(element, 'merge').click();
    await flushPromises();

    expect(BarnConfirmModal.open).toHaveBeenCalled();
    expect(mergeRecords).toHaveBeenCalledWith({
      objectName: 'Fund__c',
      keepId: 'a01000000000002',
      otherId: 'a01000000000001',
      fromOther: ['Code__c']
    });
    expect(find(element, 'status')).not.toBeNull();
    expect(find(element, 'fields')).toBeNull();
  });

  it('does nothing when the merge is not confirmed', async () => {
    getView.mockResolvedValue(VIEW);
    compare.mockResolvedValue(COMPARISON);
    BarnConfirmModal.open = jest.fn(() => Promise.resolve(false));
    const element = await build();
    await compared(element);

    find(element, 'merge').click();
    await flushPromises();

    expect(mergeRecords).not.toHaveBeenCalled();
    expect(find(element, 'fields')).not.toBeNull();
  });

  it('undoes a recent merge after a confirm', async () => {
    getView.mockResolvedValue(VIEW);
    undo.mockResolvedValue({
      ...VIEW,
      merges: [{ ...VIEW.merges[0], status: 'Undone', canUndo: false }]
    });
    BarnConfirmModal.open = jest.fn(() => Promise.resolve(true));
    const element = await build();

    find(element, 'undo').click();
    await flushPromises();

    expect(undo).toHaveBeenCalledWith({ journalId: 'a0J000000000001' });
    expect(find(element, 'undo')).toBeNull();
    expect(find(element, 'status')).not.toBeNull();
  });

  it('shows the server message when a merge is refused', async () => {
    getView.mockResolvedValue(VIEW);
    compare.mockRejectedValue({ body: { message: 'Choose two different records.' } });
    const element = await build();
    await compared(element);

    expect(find(element, 'error').message).toBe('Choose two different records.');
    expect(find(element, 'fields')).toBeNull();
  });
});
