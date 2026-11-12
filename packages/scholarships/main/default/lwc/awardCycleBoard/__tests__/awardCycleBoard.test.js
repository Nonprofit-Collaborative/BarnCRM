import { createElement } from 'lwc';
import AwardCycleBoard from 'c/awardCycleBoard';
import getBoard from '@salesforce/apex/ScholarshipsController.getBoard';
import assignReviewers from '@salesforce/apex/ScholarshipsController.assignReviewers';
import decide from '@salesforce/apex/ScholarshipsController.decide';

jest.mock('@salesforce/apex/ScholarshipsController.getBoard', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ScholarshipsController.assignReviewers',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ScholarshipsController.decide', () => ({ default: jest.fn() }), {
  virtual: true
});

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const ROW = {
  id: 'a01000000000001AAA',
  name: 'APP-000001',
  status: 'In Review',
  requested: 900,
  average: 8,
  submitted: 2,
  rank: 1
};

function mount() {
  const element = createElement('c-award-cycle-board', { is: AwardCycleBoard });
  element.recordId = 'a02000000000001AAA';
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-award-cycle-board', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('assigns reviewers and awards the requested amount', async () => {
    getBoard.mockResolvedValue({
      canManage: true,
      rows: [ROW],
      budget: 5000,
      remaining: 5000,
      formLink: 'https://example.org/f'
    });
    assignReviewers.mockResolvedValue(2);
    decide.mockResolvedValue('a05000000000001AAA');
    const element = mount();
    await flush();
    expect(find(element, 'form-link')).not.toBeNull();
    find(element, 'assign').click();
    await flush();
    expect(assignReviewers).toHaveBeenCalledWith({ cycleId: 'a02000000000001AAA' });
    find(element, 'award').click();
    await flush();
    find(element, 'save-award').click();
    await flush();
    expect(decide).toHaveBeenCalledWith({ applicationId: ROW.id, award: true, amount: 900 });
  });

  it('offers no decisions to reviewers', async () => {
    getBoard.mockResolvedValue({ canManage: false, rows: [ROW] });
    const element = mount();
    await flush();
    expect(find(element, 'assign')).toBeNull();
    expect(find(element, 'award')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="row"]')).toHaveLength(1);
  });
});
