import { createElement } from 'lwc';
import GrantPipeline from 'c/grantPipeline';
import getBoard from '@salesforce/apex/GrantPipelineController.getBoard';
import moveStage from '@salesforce/apex/GrantPipelineController.moveStage';
import markSubmitted from '@salesforce/apex/GrantPipelineController.markSubmitted';

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
jest.mock('@salesforce/label/c.Funders_Pipeline_MoveTo', () => ({ default: 'Move to {0}' }), {
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
    const when = all(element, '[data-id="when"]').map((node) => node.textContent.trim());
    expect(when[0]).toContain('3 days overdue');
    expect(when[1]).toContain('10 days left');
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

  it('asks the amount awarded, filled in with the amount requested', async () => {
    moveStage.mockResolvedValue();
    const element = await render();
    all(element, 'lightning-button-menu')[1].dispatchEvent(
      new CustomEvent('select', { detail: { value: 'move:Awarded' } })
    );
    await flush();
    const amount = one(element, '[data-id="award-amount"]');
    expect(amount.value).toBe(25000);
    amount.dispatchEvent(new CustomEvent('change', { detail: { value: '24000' } }));
    await flush();
    one(element, '[data-id="award-save"]').click();
    await flush();
    await flush();

    expect(moveStage).toHaveBeenCalledWith({
      grantId: 'a01000000000002AAA',
      stage: 'Awarded',
      amountAwarded: 24000
    });
    expect(one(element, '[data-id="award-dialog"]')).toBeNull();
  });

  it('keeps the award dialog open when the move is refused', async () => {
    moveStage.mockRejectedValue({ body: { message: 'Not allowed' } });
    const element = await render();
    all(element, 'lightning-button-menu')[1].dispatchEvent(
      new CustomEvent('select', { detail: { value: 'move:Awarded' } })
    );
    await flush();
    one(element, '[data-id="award-save"]').click();
    await flush();
    expect(one(element, '[data-id="award-dialog"]')).not.toBeNull();
    one(element, '[data-id="award-cancel"]').click();
    await flush();
    expect(one(element, '[data-id="award-dialog"]')).toBeNull();
  });

  it('lists a requirement coming due and marks it submitted', async () => {
    markSubmitted.mockResolvedValue();
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
    const items = [
      ...all(element, 'lightning-button-menu')[0].querySelectorAll('lightning-menu-item')
    ].map((item) => item.value);
    expect(items).toEqual(['open']);
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
    expect(one(element, '[data-id="error-message"]').textContent.trim()).toBe('No access');
  });
});
