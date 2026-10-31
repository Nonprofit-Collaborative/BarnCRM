import { createElement } from 'lwc';
import ImportRowCorrection from 'c/importRowCorrection';
import getRow from '@salesforce/apex/ImportRowCorrectionController.getRow';
import saveCorrections from '@salesforce/apex/ImportRowCorrectionController.saveCorrections';
import retryRow from '@salesforce/apex/ImportRowCorrectionController.retryRow';
import retryAllFixed from '@salesforce/apex/ImportRowCorrectionController.retryAllFixed';

jest.mock('@salesforce/apex/ImportRowCorrectionController.getRow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ImportRowCorrectionController.saveCorrections',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ImportRowCorrectionController.retryRow',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ImportRowCorrectionController.retryAllFixed',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const REJECTED = {
  id: 'a0R000000000001',
  name: 'IR-000014',
  rowNumber: 14,
  status: 'Rejected',
  errorMessage: 'A person needs a last name.',
  batchId: 'a0B000000000001',
  batchName: 'IB-000001',
  canCorrect: true,
  refusal: null,
  fixedCount: 0,
  columns: [
    { column: 'First Name', fileValue: 'Dee', correctedValue: 'Dee', corrected: false },
    { column: 'Last Name', fileValue: '', correctedValue: '', corrected: false }
  ]
};

/** Lets the component's chained awaits and its rerender finish. */
async function flush() {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function render(row) {
  getRow.mockResolvedValue(row);
  const element = createElement('c-import-row-correction', { is: ImportRowCorrection });
  element.recordId = row.id;
  document.body.appendChild(element);
  await flush();
  return element;
}

function query(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('the Super Importer Row card', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the reason and each file value beside an editable correction', async () => {
    const element = await render(REJECTED);
    expect(getRow).toHaveBeenCalledWith({ rowId: REJECTED.id });
    expect(query(element, 'reason').textContent).toBe('A person needs a last name.');
    const fileValues = Array.from(element.shadowRoot.querySelectorAll('[data-id="file-value"]'));
    expect(fileValues.map((cell) => cell.textContent)).toEqual(['Dee', '']);
    expect(element.shadowRoot.querySelectorAll('lightning-input')).toHaveLength(2);
    expect(query(element, 'retry-all').disabled).toBe(true);
  });

  it('saves every value on screen so Apex can keep only the corrections', async () => {
    const element = await render(REJECTED);
    saveCorrections.mockResolvedValue({ ...REJECTED, fixedCount: 1 });
    const lastName = element.shadowRoot.querySelectorAll('lightning-input')[1];
    lastName.value = 'Nolast';
    lastName.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(query(element, 'retry-all').disabled).toBe(false);

    query(element, 'save').click();
    await flush();

    expect(saveCorrections).toHaveBeenCalledWith({
      rowId: REJECTED.id,
      correctionsJson: JSON.stringify({ 'First Name': 'Dee', 'Last Name': 'Nolast' })
    });
    expect(query(element, 'message').textContent).toContain('c.Core_ImportRow_Saved');
    expect(query(element, 'fixed-count')).not.toBeNull();
  });

  it('saves unsaved edits before it retries the row', async () => {
    const element = await render(REJECTED);
    saveCorrections.mockResolvedValue(REJECTED);
    retryRow.mockResolvedValue('707000000000001');
    const lastName = element.shadowRoot.querySelectorAll('lightning-input')[1];
    lastName.value = 'Nolast';
    lastName.dispatchEvent(new CustomEvent('change'));

    query(element, 'retry-row').click();
    await flush();

    expect(saveCorrections).toHaveBeenCalled();
    expect(retryRow).toHaveBeenCalledWith({ rowId: REJECTED.id });
    expect(query(element, 'message').textContent).toContain('c.Core_ImportRow_RetryStarted');
  });

  it('retries every fixed row of the import', async () => {
    const element = await render({ ...REJECTED, fixedCount: 3 });
    retryAllFixed.mockResolvedValue('707000000000001');

    query(element, 'retry-all').click();
    await flush();

    expect(saveCorrections).not.toHaveBeenCalled();
    expect(retryAllFixed).toHaveBeenCalledWith({ rowId: REJECTED.id });
  });

  it('shows a refusal and no inputs when the row cannot be corrected', async () => {
    const element = await render({
      ...REJECTED,
      canCorrect: false,
      refusal: 'Only the person who committed this import can retry its rejected rows.'
    });
    expect(query(element, 'refusal').textContent).toContain('Only the person');
    expect(element.shadowRoot.querySelectorAll('lightning-input')).toHaveLength(0);
    expect(query(element, 'save')).toBeNull();
  });

  it('shows a created row read only, without a reason', async () => {
    const element = await render({
      ...REJECTED,
      status: 'Created',
      canCorrect: false,
      errorMessage: null
    });
    expect(query(element, 'reason')).toBeNull();
    expect(query(element, 'status').textContent).toBe('Created');
    expect(element.shadowRoot.querySelectorAll('[data-id="corrected-value"]')).toHaveLength(2);
  });

  it('says what went wrong when a call fails', async () => {
    const element = await render(REJECTED);
    retryRow.mockRejectedValue({
      body: { message: 'There are no corrected rejected rows to retry.' }
    });

    query(element, 'retry-row').click();
    await flush();

    expect(query(element, 'error').textContent).toContain('no corrected rejected rows');
    expect(query(element, 'message')).toBeNull();
  });
});
