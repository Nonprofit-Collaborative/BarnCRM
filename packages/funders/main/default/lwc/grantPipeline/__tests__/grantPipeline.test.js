import { createElement } from 'lwc';
import GrantPipeline from 'c/grantPipeline';
import getBoard from '@salesforce/apex/GrantPipelineController.getBoard';
import moveStage from '@salesforce/apex/GrantPipelineController.moveStage';
import markSubmitted from '@salesforce/apex/GrantPipelineController.markSubmitted';
import undoSubmitted from '@salesforce/apex/GrantPipelineController.undoSubmitted';
import GrantAwardModal from 'c/grantAwardModal';

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
jest.mock(
  '@salesforce/apex/GrantPipelineController.undoSubmitted',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/apex/GrantPipelineController.getBoard', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/GrantPipelineController.markSubmitted',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Funders_Pipeline_KindApplication',
  () => ({ default: 'Application' }),
  { virtual: true }
);
jest.mock('@salesforce/apex/GrantPipelineController.moveStage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Shared_MoveTo', () => ({ default: 'Move to {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Pipeline_DaysLeft', () => ({ default: '{0} days left' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Pipeline_Overdue', () => ({ default: '{0} days overdue' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Pipeline_NoFunder', () => ({ default: 'No funder' }), {
  virtual: true
});

const ALL_STAGES = [
  'Prospect',
  'Letter of Inquiry',
  'Invited to Apply',
  'Applied',
  'Awarded',
  'Declined',
  'Withdrawn'
];

const BOARD = {
  stages: ALL_STAGES.slice(0, 4),
  allStages: ALL_STAGES,
  stageTotals: [
    { stage: 'Prospect', count: 1, amount: 10000 },
    { stage: 'Applied', count: 1, amount: 25000 }
  ],
  cards: [
    {
      id: 'a01000000000001AAA',
      name: 'Literacy Grant',
      stage: 'Prospect',
      funderId: '001000000000001AAA',
      funderName: 'Lakeside Foundation',
      amountRequested: 10000,
      deadline: '2026-11-12',
      ownerName: 'Maria'
    },
    {
      id: 'a01000000000002AAA',
      name: 'Youth Grant',
      stage: 'Applied',
      funderId: '001000000000002AAA',
      funderName: 'River Trust',
      amountRequested: 25000,
      deadline: null,
      ownerName: 'Maria'
    }
  ],
  deadlines: [
    {
      id: 'a01000000000001AAA',
      name: 'Literacy Grant',
      stage: 'Prospect',
      funderName: 'Lakeside Foundation',
      deadline: '2026-11-12'
    },
    { id: 'a01000000000003AAA', name: 'Late Grant', stage: 'Prospect', deadline: '2026-10-30' }
  ],
  truncated: false,
  openCount: 2,
  openAmount: 35000,
  awardedCount: 1,
  awardedAmount: 5000,
  canEdit: true,
  canCreate: true,
  today: '2026-11-02'
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(board = BOARD) {
  getBoard.mockResolvedValue(board);
  const element = createElement('c-grant-pipeline', { is: GrantPipeline });
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-grant-pipeline', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws a column per open stage with its cards', async () => {
    const element = await render();
    const titles = all(element, '[data-id="column"] h2').map((node) => node.textContent.trim());
    expect(titles).toEqual(['Prospect', 'Letter of Inquiry', 'Invited to Apply', 'Applied']);
    expect(all(element, '[data-card]')).toHaveLength(2);
    expect(getBoard).toHaveBeenCalledWith({ mineOnly: false });
  });

  it('lists the deadlines soonest first and marks the overdue one', async () => {
    const element = await render();
    const when = all(element, '[data-id="when"]');
    expect(when[0].status).toBe('overdue');
    expect(when[0].label).toBe('3 days overdue');
    expect(when[1].status).toBe('due soon');
    expect(when[1].label).toBe('10 days left');
    expect(all(element, '[data-deadline]')[0].textContent).toContain('No funder');
  });

  it('moves a grant through the menu to any other stage', async () => {
    moveStage.mockResolvedValue();
    const element = await render();
    const menu = all(element, 'lightning-button-menu')[0];
    const items = [...menu.querySelectorAll('lightning-menu-item')].map((item) => item.label);
    expect(items).toContain('Move to Applied');
    expect(items).toContain('Move to Declined');
    expect(items).not.toContain('Move to Prospect');

    menu.dispatchEvent(new CustomEvent('select', { detail: { value: 'move:Applied' } }));
    await flush();

    expect(moveStage).toHaveBeenCalledWith({
      grantId: 'a01000000000001AAA',
      stage: 'Applied',
      amountAwarded: null
    });
    expect(getBoard).toHaveBeenCalledTimes(2);
  });

  it('opens Record the Award with the card and reloads once it is saved', async () => {
    GrantAwardModal.open.mockResolvedValue({ saved: true });
    const element = await render();
    const toasts = [];
    element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    all(element, 'lightning-button-menu')[1].dispatchEvent(
      new CustomEvent('select', { detail: { value: 'move:Awarded' } })
    );
    await flush();
    await flush();

    const options = GrantAwardModal.open.mock.calls[0][0];
    expect(options.grant.id).toBe('a01000000000002AAA');
    expect(options.label).toContain('Youth Grant');
    expect(moveStage).not.toHaveBeenCalled();
    expect(toasts[0].messageData[0].label).toBe('Youth Grant');
    expect(toasts[0].messageData[0].url).toContain('a01000000000002AAA');
    expect(getBoard).toHaveBeenCalledTimes(2);
  });

  it('changes nothing when Record the Award is closed', async () => {
    GrantAwardModal.open.mockResolvedValue(undefined);
    const element = await render();
    all(element, 'lightning-button-menu')[1].dispatchEvent(
      new CustomEvent('select', { detail: { value: 'move:Awarded' } })
    );
    await flush();
    expect(getBoard).toHaveBeenCalledTimes(1);
  });

  it('links each grant name and shows how soon it is due', async () => {
    const element = await render();
    const link = one(element, '[data-name-link]');
    expect(link.getAttribute('href')).toContain('a01000000000001AAA');
    link.click();
    expect(mockNavigate).toHaveBeenCalled();
    const urgency = all(element, '[data-id="card-urgency"]');
    expect(urgency).toHaveLength(1);
    expect(urgency[0].status).toBe('due soon');
    expect(urgency[0].label).toBe('10 days left');
    expect(all(element, 'c-barn-stat-tile')).toHaveLength(3);
    expect(all(element, 'lightning-avatar')[0].initials).toBe('M');
  });

  it('lists a requirement coming due and marks it submitted', async () => {
    markSubmitted.mockResolvedValue({
      id: 'a03000000000001AAA',
      status: 'In Progress',
      dateValue: null
    });
    undoSubmitted.mockResolvedValue();
    const element = await render({
      ...BOARD,
      canMarkSubmitted: true,
      deadlines: [
        ...BOARD.deadlines,
        {
          id: 'a03000000000001AAA',
          name: 'Year 1 report',
          kind: 'requirement',
          requirementType: 'Narrative Report',
          grantName: 'Youth Grant',
          funderName: 'River Trust',
          deadline: '2026-11-05'
        }
      ]
    });
    const rows = all(element, '[data-deadline]');
    expect(rows).toHaveLength(3);
    expect(rows[1].querySelector('[data-id="what"]').textContent.trim()).toBe(
      'Narrative Report: Youth Grant'
    );
    expect(rows[0].querySelector('[data-id="what"]').textContent.trim()).toBe('Application');
    expect(all(element, '[data-mark]')).toHaveLength(1);

    all(element, '[data-mark]')[0].click();
    await flush();
    expect(markSubmitted).toHaveBeenCalledWith({ requirementId: 'a03000000000001AAA' });
    expect(getBoard).toHaveBeenCalledTimes(2);

    const notice = one(element, '[data-id="undo-marked"]');
    expect(notice.actionLabel).toBe('c.Core_AutoMerge_Undo');
    notice.dispatchEvent(new CustomEvent('action'));
    await flush();
    await flush();
    expect(undoSubmitted).toHaveBeenCalledWith({
      requirementId: 'a03000000000001AAA',
      status: 'In Progress',
      submittedDate: null
    });
    expect(one(element, '[data-id="undo-marked"]')).toBeNull();
    expect(getBoard).toHaveBeenCalledTimes(3);
  });

  it('offers no Mark Submitted to someone who cannot change requirements', async () => {
    const element = await render({
      ...BOARD,
      canMarkSubmitted: false,
      deadlines: [
        {
          id: 'a03000000000001AAA',
          name: 'Year 1 report',
          kind: 'requirement',
          deadline: '2026-11-05'
        }
      ]
    });
    expect(all(element, '[data-mark]')).toHaveLength(0);
  });

  it('switches to Mine', async () => {
    const element = await render();
    one(element, '[data-id="scope"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'mine' } })
    );
    await flush();
    expect(getBoard).toHaveBeenLastCalledWith({ mineOnly: true });
  });

  it('offers a reader nothing to change', async () => {
    const element = await render({ ...BOARD, canEdit: false, canCreate: false });
    expect(one(element, '[data-id="read-only"]')).not.toBeNull();
    expect(one(element, '[data-id="new-grant"]')).toBeNull();
    expect(one(element, '[data-drag-id]')).toBeNull();
    expect(one(element, '[data-id="drop-zone"]')).toBeNull();
    const items = [
      ...all(element, 'lightning-button-menu')[0].querySelectorAll('lightning-menu-item')
    ].map((item) => item.value);
    expect(items).toEqual(['open']);
  });

  it('moves a grant by keyboard drag to the next column (DnD-1)', async () => {
    moveStage.mockResolvedValue();
    const element = await render();
    const zones = all(element, '[data-id="drop-zone"]').map((zone) => zone.dataset.dropZone);
    expect(zones).toEqual(['Awarded', 'Declined', 'Withdrawn']);

    const handle = one(element, '[data-drag-id="a01000000000001AAA"]');
    expect(handle.getAttribute('tabindex')).toBe('0');
    const press = (key) =>
      handle.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
    press(' ');
    await flush();
    expect(one(element, '[data-id="drag-announcer"]').textContent).toContain('Core_Drag_PickedUp');
    press('ArrowRight');
    press('Enter');
    await flush();

    expect(moveStage).toHaveBeenCalledWith({
      grantId: 'a01000000000001AAA',
      stage: 'Letter of Inquiry',
      amountAwarded: null
    });
    // The card menu is still there for the same move.
    expect(all(element, 'lightning-button-menu')).toHaveLength(2);
  });

  it('opens Record the Award when a card is dropped on Awarded', async () => {
    GrantAwardModal.open.mockResolvedValue(undefined);
    const element = await render();
    const handle = one(element, '[data-drag-id="a01000000000002AAA"]');
    const press = (key) =>
      handle.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
    press(' ');
    press('ArrowRight');
    press(' ');
    await flush();

    expect(GrantAwardModal.open).toHaveBeenCalled();
    expect(GrantAwardModal.open.mock.calls[0][0].grant.id).toBe('a01000000000002AAA');
    expect(moveStage).not.toHaveBeenCalled();
  });

  it('cancels a keyboard drag with Escape and moves nothing', async () => {
    const element = await render();
    const handle = one(element, '[data-drag-id="a01000000000001AAA"]');
    const press = (key) =>
      handle.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
    press(' ');
    press('ArrowRight');
    press('Escape');
    await flush();
    expect(moveStage).not.toHaveBeenCalled();
    expect(GrantAwardModal.open).not.toHaveBeenCalled();
  });

  it('says so when there are no open grants or deadlines', async () => {
    const element = await render({
      ...BOARD,
      stageTotals: [],
      cards: [],
      deadlines: [],
      openCount: 0
    });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
    expect(one(element, '[data-id="board"]')).toBeNull();
    expect(one(element, '[data-id="deadlines-empty"]')).not.toBeNull();
  });

  it('shows the reason when the board cannot load', async () => {
    getBoard.mockRejectedValue({ body: { message: 'No access' } });
    const element = createElement('c-grant-pipeline', { is: GrantPipeline });
    document.body.appendChild(element);
    await flush();
    await flush();
    const notice = one(element, '[data-id="error-message"]');
    expect(notice.variant).toBe('error');
    expect(notice.message).toBe('No access');
  });
});
