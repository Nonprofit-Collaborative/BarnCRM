// The getRecord test adapter is emitted to on purpose, which is how a wired component is
// driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import GiftBatchEntry from 'c/giftBatchEntry';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getBatch from '@salesforce/apex/GiftBatchController.getBatch';
import saveLines from '@salesforce/apex/GiftBatchController.saveLines';
import postBatch from '@salesforce/apex/GiftBatchController.postBatch';

jest.mock('@salesforce/apex/GiftBatchController.getBatch', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GiftBatchController.saveLines', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GiftBatchController.postBatch', () => ({ default: jest.fn() }), {
  virtual: true
});

// The two labels that carry a line number are given their real wording, so the tests can
// read the number in them.
jest.mock('@salesforce/label/c.Giving_GiftBatch_CellLabel', () => ({ default: '{0}, line {1}' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Giving_GiftBatch_RemoveLine',
  () => ({ default: 'Remove line {0}' }),
  {
    virtual: true
  }
);

const BATCH_ID = 'a0B000000000001AAA';
const ANA = '003000000000001AAA';
const RIVERSIDE = '001000000000001AAA';

function view(overrides = {}) {
  return {
    id: BATCH_ID,
    posted: false,
    controlTotal: 350,
    enteredTotal: 0,
    hasPersonAccounts: false,
    canEdit: true,
    paymentMethods: [
      { label: 'Cash', value: 'Cash' },
      { label: 'Check', value: 'Check' }
    ],
    lines: [],
    ...overrides
  };
}

function line(id, amount, extra = {}) {
  return { id, donorContactId: ANA, donorAccountId: null, amount, ...extra };
}

async function settle() {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function build(batchView) {
  getBatch.mockResolvedValue(batchView);
  const element = createElement('c-gift-batch-entry', { is: GiftBatchEntry });
  element.recordId = BATCH_ID;
  document.body.appendChild(element);
  getRecord.emit({ id: BATCH_ID, fields: {} });
  await settle();
  return element;
}

function all(element, id) {
  return [...element.shadowRoot.querySelectorAll(`[data-id="${id}"]`)];
}

function pick(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function field(element, name) {
  return [...element.shadowRoot.querySelectorAll(`[data-field="${name}"]`)];
}

function change(target, detail) {
  target.dispatchEvent(new CustomEvent('change', { detail }));
}

describe('c-gift-batch-entry', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('names every input and remove button with its line number', async () => {
    const element = await build(view({ lines: [line('a0C1', 100), line('a0C2', 25)] }));

    const amounts = field(element, 'amount');
    expect(amounts[0].label).toBe('c.Giving_GiftBatch_ColumnAmount, line 1');
    expect(amounts[1].label).toBe('c.Giving_GiftBatch_ColumnAmount, line 2');
    expect(field(element, 'fundId')[1].label).toBe('c.Giving_GiftBatch_ColumnFund, line 2');
    expect(all(element, 'donor')[1].label).toBe('c.Giving_GiftBatch_ColumnDonor, line 2');
    expect(all(element, 'kind')[0].label).toBe('c.Giving_GiftBatch_DonorKind, line 1');
    const removes = all(element, 'remove');
    expect(removes[0].alternativeText).toBe('Remove line 1');
    expect(removes[1].alternativeText).toBe('Remove line 2');
  });

  it('renumbers the labels when a line is removed', async () => {
    const element = await build(view({ lines: [line('a0C1', 100), line('a0C2', 25)] }));

    all(element, 'remove')[0].click();
    await settle();

    expect(field(element, 'amount')[0].label).toBe('c.Giving_GiftBatch_ColumnAmount, line 1');
    expect(all(element, 'remove')[0].alternativeText).toBe('Remove line 1');
  });

  it('shows no phone note on a computer', async () => {
    const element = await build(view({ lines: [line('a0C1', 100)] }));

    expect(pick(element, 'use-computer')).toBeNull();
  });

  it('opens an empty batch with its control total and says it is short', async () => {
    const element = await build(view());

    expect(getBatch).toHaveBeenCalledWith({ batchId: BATCH_ID });
    expect(pick(element, 'control-total').textContent).toBeDefined();
    expect(pick(element, 'balance').textContent).toBe(
      'c.Giving_GiftBatch_ErrorShortOfControlTotal'
    );
    expect(pick(element, 'no-lines')).not.toBeNull();
    expect(pick(element, 'post').disabled).toBe(true);
  });

  it('keeps a running total as lines are typed and allows posting once it balances', async () => {
    const element = await build(view({ controlTotal: 150 }));

    pick(element, 'add').click();
    await settle();
    change(field(element, 'amount')[0], { value: '100' });
    await settle();
    expect(pick(element, 'balance').textContent).toBe(
      'c.Giving_GiftBatch_ErrorShortOfControlTotal'
    );

    pick(element, 'add').click();
    await settle();
    change(field(element, 'amount')[1], { value: '75' });
    await settle();
    expect(pick(element, 'balance').textContent).toBe('c.Giving_GiftBatch_ErrorOverControlTotal');

    change(field(element, 'amount')[1], { value: '50' });
    await settle();
    expect(pick(element, 'balance').textContent).toBe('c.Giving_GiftBatch_Balanced');
    expect(pick(element, 'post').disabled).toBe(false);
    expect(pick(element, 'unsaved')).not.toBeNull();
  });

  it('saves the whole grid, sending new, changed and removed lines', async () => {
    const element = await build(view({ lines: [line('a0C1', 100), line('a0C2', 25)] }));
    saveLines.mockResolvedValue(view({ lines: [line('a0C1', 100), line('a0C3', 200)] }));

    all(element, 'remove')[1].click();
    pick(element, 'add').click();
    await settle();
    const rows = all(element, 'line');
    expect(rows).toHaveLength(2);
    change(all(element, 'kind')[1], { value: 'organization' });
    await settle();
    change(all(element, 'donor')[1], { recordId: RIVERSIDE });
    change(field(element, 'amount')[1], { value: '200' });
    change(field(element, 'paymentMethod')[1], { value: '' });
    await settle();

    pick(element, 'save').click();
    await settle();

    const sent = saveLines.mock.calls[0][0];
    expect(sent.batchId).toBe(BATCH_ID);
    expect(sent.removedLineIds).toEqual(['a0C2']);
    expect(sent.lines).toHaveLength(2);
    expect(sent.lines[1]).toMatchObject({
      id: null,
      donorContactId: null,
      donorAccountId: RIVERSIDE,
      amount: 200,
      paymentMethod: null
    });
    expect(pick(element, 'unsaved')).toBeNull();
  });

  it('shows why a post was refused beside each line', async () => {
    const element = await build(
      view({ controlTotal: 100, lines: [line('a0C1', 60), line('a0C2', 40)] })
    );
    postBatch.mockResolvedValue({
      success: false,
      formError: 'Some lines are not finished.',
      lineErrors: [{ lineId: 'a0C2', lineNumber: 2, message: 'This line has no donor.' }]
    });

    pick(element, 'post').click();
    await settle();

    expect(saveLines).not.toHaveBeenCalled();
    expect(pick(element, 'form-error').textContent).toBe('Some lines are not finished.');
    const errors = all(element, 'line-error');
    expect(errors).toHaveLength(1);
    expect(errors[0].textContent).toBe('This line has no donor.');
  });

  it('saves unsaved lines before posting, then shows the posted batch', async () => {
    const element = await build(view({ controlTotal: 100, lines: [line('a0C1', 60)] }));
    saveLines.mockResolvedValue(view({ controlTotal: 100, lines: [line('a0C1', 100)] }));
    postBatch.mockResolvedValue({ success: true, giftCount: 1, lineErrors: [] });

    change(field(element, 'amount')[0], { value: '100' });
    await settle();
    getBatch.mockResolvedValue(
      view({
        posted: true,
        controlTotal: 100,
        lines: [line('a0C1', 100, { giftId: 'a0D1', giftName: 'G-000001' })]
      })
    );
    pick(element, 'post').click();
    await settle();

    expect(saveLines).toHaveBeenCalled();
    expect(postBatch).toHaveBeenCalledWith({ batchId: BATCH_ID });
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: BATCH_ID }]);
    expect(pick(element, 'posted-note')).not.toBeNull();
    expect(pick(element, 'gift-link').textContent).toBe('G-000001');
    expect(pick(element, 'post')).toBeNull();
    expect(field(element, 'amount')[0].disabled).toBe(true);
  });

  it('offers only an account search for the donor where people are person accounts', async () => {
    const element = await build(
      view({ hasPersonAccounts: true, lines: [line('a0C1', 10, { donorContactId: null })] })
    );

    expect(pick(element, 'kind')).toBeNull();
    expect(pick(element, 'donor').objectApiName).toBe('Account');
  });

  it('offers someone who may only read the batch no way to change or post it', async () => {
    const element = await build(view({ canEdit: false, lines: [line('a0C1', 100)] }));

    expect(pick(element, 'read-only-note')).not.toBeNull();
    expect(pick(element, 'balance')).not.toBeNull();
    expect(pick(element, 'add')).toBeNull();
    expect(pick(element, 'save')).toBeNull();
    expect(pick(element, 'post')).toBeNull();
    expect(pick(element, 'remove')).toBeNull();
    expect(field(element, 'amount')[0].disabled).toBe(true);
  });

  it('says so when the batch cannot be opened', async () => {
    getBatch.mockRejectedValue({ body: { message: 'This batch could not be found.' } });
    const element = createElement('c-gift-batch-entry', { is: GiftBatchEntry });
    element.recordId = BATCH_ID;
    document.body.appendChild(element);
    getRecord.emit({ id: BATCH_ID, fields: {} });
    await settle();

    expect(pick(element, 'form-error').textContent).toBe('This batch could not be found.');
  });
});
