import { createElement } from 'lwc';
import GiftAllocations from 'c/giftAllocations';
import getState from '@salesforce/apex/GiftAllocationController.getState';
import save from '@salesforce/apex/GiftAllocationController.save';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

jest.mock('@salesforce/apex/GiftAllocationController.getState', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GiftAllocationController.save', () => ({ default: jest.fn() }), {
  virtual: true
});

const GIFT = 'a0B000000000001AAA';
const GENERAL = 'a01000000000002AAA';
const BUILDING = 'a01000000000001AAA';

const OPEN = {
  giftAmount: 200,
  canEdit: true,
  lockedMessage: null,
  rows: [{ id: 'a0C1', fundId: GENERAL, fundName: 'General', amount: 200, percent: 100 }]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(state) {
  getState.mockResolvedValue(state);
  const element = createElement('c-gift-allocations', { is: GiftAllocations });
  element.recordId = GIFT;
  document.body.appendChild(element);
  await flush();
  return element;
}

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-gift-allocations', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the funds with Edit Funds', async () => {
    const element = await render(OPEN);
    expect(getState).toHaveBeenCalledWith({ giftId: GIFT });
    const rows = element.shadowRoot.querySelectorAll('[data-id="row"]');
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain('General');
    expect(one(element, 'edit-funds')).not.toBeNull();
    expect(one(element, 'locked')).toBeNull();
    const table = one(element, 'list');
    expect(table.className).toContain('slds-max-medium-table_stacked');
    table.querySelectorAll('td').forEach((cell) => {
      expect(cell.getAttribute('data-label')).toBeTruthy();
    });
  });

  it('says why a locked gift keeps its funds, without the button', async () => {
    const element = await render({ ...OPEN, canEdit: false, lockedMessage: 'In the books.' });
    expect(one(element, 'edit-funds')).toBeNull();
    expect(one(element, 'locked').message).toBe('In the books.');
  });

  it('shows a compact empty state for a gift with no fund', async () => {
    const element = await render({ ...OPEN, rows: [] });
    const empty = one(element, 'empty');
    expect(empty.size).toBe('compact');
    expect(empty.heading).toBe('c.Giving_GiftAllocations_None');
  });

  it('saves a split and refreshes the page', async () => {
    const saved = {
      ...OPEN,
      rows: [
        { id: 'a0C1', fundId: GENERAL, fundName: 'General', amount: 100, percent: 50 },
        { id: 'a0C2', fundId: BUILDING, fundName: 'Building Fund', amount: 100, percent: 50 }
      ]
    };
    save.mockResolvedValue(saved);
    const element = await render(OPEN);
    one(element, 'edit-funds').click();
    await flush();

    const editor = one(element, 'editor');
    expect(editor.total).toBe(200);
    expect(editor.allocations).toEqual([{ fundId: GENERAL, amount: 200 }]);
    expect(one(element, 'save').disabled).toBe(true);

    editor.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          allocations: [
            { fundId: GENERAL, amount: 100 },
            { fundId: BUILDING, amount: 100 }
          ],
          valid: true
        }
      })
    );
    await flush();
    expect(one(element, 'save').disabled).toBe(false);
    one(element, 'save').click();
    await flush();

    expect(save).toHaveBeenCalledWith({
      giftId: GIFT,
      allocations: [
        { fundId: GENERAL, amount: 100 },
        { fundId: BUILDING, amount: 100 }
      ]
    });
    expect(one(element, 'editor')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="row"]')).toHaveLength(2);
    expect(one(element, 'saved').message).toBe('c.Giving_GiftAllocations_Saved');
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: GIFT }]);
  });

  it('keeps the editor open and shows a refused save', async () => {
    save.mockRejectedValue({ body: { message: 'The allocations of this gift total 90.' } });
    const element = await render(OPEN);
    one(element, 'edit-funds').click();
    await flush();
    one(element, 'editor').dispatchEvent(
      new CustomEvent('change', {
        detail: { allocations: [{ fundId: BUILDING, amount: 200 }], valid: true }
      })
    );
    await flush();
    one(element, 'save').click();
    await flush();
    expect(one(element, 'error').message).toBe('The allocations of this gift total 90.');
    expect(one(element, 'editor')).not.toBeNull();

    one(element, 'cancel').click();
    await flush();
    expect(one(element, 'editor')).toBeNull();
    expect(one(element, 'error')).toBeNull();
  });

  it('shows a load failure', async () => {
    getState.mockRejectedValue({ body: { message: 'That gift could not be found.' } });
    const element = createElement('c-gift-allocations', { is: GiftAllocations });
    element.recordId = GIFT;
    document.body.appendChild(element);
    await flush();
    expect(one(element, 'error').message).toBe('That gift could not be found.');
  });
});
