import { createElement } from 'lwc';
import AskPipeline from 'c/askPipeline';
import getBoard from '@salesforce/apex/AskPipelineController.getBoard';
import moveStage from '@salesforce/apex/AskPipelineController.moveStage';
import closeAsk from '@salesforce/apex/AskPipelineController.closeAsk';

jest.mock('@salesforce/apex/AskPipelineController.getBoard', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/AskPipelineController.moveStage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/AskPipelineController.closeAsk', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Giving_AskPipeline_MoveTo', () => ({ default: 'Move to {0}' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Giving_AskPipeline_DaysInStage',
  () => ({ default: '{0} days in this stage' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Giving_AskPipeline_OtherColumn',
  () => ({ default: 'Not in Your Stage List' }),
  { virtual: true }
);

const BOARD = {
  stages: ['Identified', 'Asked'],
  stageTotals: [
    { stage: 'Asked', count: 1, amount: 2500 },
    { stage: 'Retired', count: 1, amount: 100 }
  ],
  cards: [
    {
      id: 'a01000000000001AAA',
      name: 'ASK-00000001',
      stage: 'Asked',
      donorId: '003000000000001AAA',
      donorName: 'Jordan Lee',
      amount: 2500,
      stageChangedDate: '2026-10-21',
      ownerName: 'Maria'
    },
    {
      id: 'a01000000000002AAA',
      name: 'ASK-00000002',
      stage: 'Retired',
      donorId: null,
      donorName: null,
      amount: 100,
      stageChangedDate: '2026-10-31',
      ownerName: 'Maria'
    }
  ],
  truncated: false,
  openCount: 2,
  openAmount: 2600,
  wonCount: 1,
  wonAmount: 500,
  declinedCount: 0,
  canEdit: true,
  canCreate: true,
  giftTypes: [{ label: 'Check', value: 'Check' }],
  frequencies: [{ label: 'Monthly', value: 'Monthly' }],
  today: '2026-10-31'
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(board = BOARD) {
  getBoard.mockResolvedValue(board);
  const element = createElement('c-ask-pipeline', { is: AskPipeline });
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-ask-pipeline', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws a column per stage, then one for stages no longer in the list', async () => {
    const element = await render();
    const titles = all(element, '[data-id="column"] h2').map((node) => node.textContent.trim());
    expect(titles).toEqual(['Identified', 'Asked', 'Not in Your Stage List']);
    expect(all(element, '[data-card]')).toHaveLength(2);
    expect(one(element, '[data-id="days"]').textContent.trim()).toBe('10 days in this stage');
    expect(getBoard).toHaveBeenCalledWith({ mineOnly: false });
  });

  it('offers a move to every other stage and moves through the menu', async () => {
    moveStage.mockResolvedValue();
    const element = await render();
    const menu = all(element, 'lightning-button-menu')[0];
    const items = [...menu.querySelectorAll('lightning-menu-item')].map((item) => item.label);
    expect(items).toContain('Move to Identified');
    expect(items).not.toContain('Move to Asked');

    menu.dispatchEvent(new CustomEvent('select', { detail: { value: 'move:Identified' } }));
    await flush();

    expect(moveStage).toHaveBeenCalledWith({ askId: 'a01000000000001AAA', stage: 'Identified' });
    expect(getBoard).toHaveBeenCalledTimes(2);
  });

  it('moves a card dropped on another column', async () => {
    moveStage.mockResolvedValue();
    const element = await render();
    const card = all(element, '[data-card]')[0];
    card.dispatchEvent(new CustomEvent('dragstart'));
    const identified = all(element, '[data-id="column"]')[0];
    identified.dispatchEvent(new CustomEvent('drop'));
    await flush();
    expect(moveStage).toHaveBeenCalledWith({ askId: 'a01000000000001AAA', stage: 'Identified' });
  });

  it('switches to My Asks and to the list', async () => {
    const element = await render();
    one(element, '[data-id="scope"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'mine' } })
    );
    await flush();
    expect(getBoard).toHaveBeenLastCalledWith({ mineOnly: true });

    one(element, '[data-id="view"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'list' } })
    );
    await flush();
    const table = one(element, 'lightning-datatable');
    expect(table.data.map((row) => row.id)).toEqual(['a01000000000001AAA', 'a01000000000002AAA']);
    expect(one(element, '[data-id="board"]')).toBeNull();
  });

  it('closes an ask as won with the gift now', async () => {
    closeAsk.mockResolvedValue({ success: true });
    const element = await render();
    all(element, 'lightning-button-menu')[0].dispatchEvent(
      new CustomEvent('select', { detail: { value: 'close' } })
    );
    await flush();
    const type = one(element, '[data-field="giftType"]');
    type.dispatchEvent(new CustomEvent('change', { detail: { value: 'Check' } }));
    await flush();
    one(element, '[data-id="close-save"]').click();
    await flush();

    expect(closeAsk).toHaveBeenCalledWith({
      input: expect.objectContaining({
        askId: 'a01000000000001AAA',
        outcome: 'Won',
        result: 'gift',
        amount: 2500,
        giftDate: '2026-10-31',
        giftType: 'Check'
      })
    });
    expect(one(element, '[data-id="close-dialog"]')).toBeNull();
  });

  it('keeps the dialog open and shows the reason when closing is refused', async () => {
    closeAsk.mockResolvedValue({ success: false, error: 'Another donor' });
    const element = await render();
    all(element, 'lightning-button-menu')[0].dispatchEvent(
      new CustomEvent('select', { detail: { value: 'close' } })
    );
    await flush();
    one(element, '[data-field="outcome"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Declined' } })
    );
    await flush();
    expect(one(element, '[data-field="result"]')).toBeNull();
    one(element, '[data-id="close-save"]').click();
    await flush();

    expect(closeAsk.mock.calls[0][0].input.result).toBeNull();
    expect(one(element, '[data-id="close-error"]').textContent.trim()).toBe('Another donor');
  });

  it('offers a reader nothing to change', async () => {
    const element = await render({ ...BOARD, canEdit: false, canCreate: false });
    expect(one(element, '[data-id="read-only"]')).not.toBeNull();
    expect(one(element, '[data-id="new-ask"]')).toBeNull();
    const items = [
      ...all(element, 'lightning-button-menu')[0].querySelectorAll('lightning-menu-item')
    ].map((item) => item.value);
    expect(items).toEqual(['open']);
    expect(all(element, '[data-card]')[0].getAttribute('draggable')).toBe('false');
  });

  it('says so when there are no open asks, and shows a load failure', async () => {
    const empty = await render({ ...BOARD, stageTotals: [], cards: [], openCount: 0 });
    expect(one(empty, '[data-id="empty-state"]')).not.toBeNull();
    document.body.removeChild(empty);

    getBoard.mockRejectedValue({ body: { message: 'Could not load' } });
    const element = createElement('c-ask-pipeline', { is: AskPipeline });
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]').textContent.trim()).toBe('Could not load');
  });
});
