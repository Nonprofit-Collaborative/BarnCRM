import { createElement } from 'lwc';
import HubBoardPanel from 'c/hubBoardPanel';
import getBoard from '@salesforce/apex/HubBoardController.getBoard';
import requestFromBoard from '@salesforce/apex/HubBoardController.requestFromBoard';
import startAssessment from '@salesforce/apex/HubBoardController.startAssessment';

jest.mock('@salesforce/apex/HubBoardController.getBoard', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubBoardController.requestFromBoard', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubBoardController.startAssessment', () => ({ default: jest.fn() }), {
  virtual: true
});

const RECORD_ID = 'a05000000000001AAA';
const BOARD = {
  seats: [
    { id: 's1', name: 'Ade', status: 'Chair', due: '2000-01-02', flag: true, values: ['Finance'] },
    { id: 's2', name: 'Bea', status: 'Member', due: '2099-01-01', flag: false, values: [] }
  ],
  neededSkills: ['Finance', 'Legal'],
  actionItems: [{ id: 'i1', name: 'Send the audit letter', status: 'Ade', due: null }],
  documents: [{ id: 'd1', name: 'Conflict of Interest' }],
  givers: 1,
  alertDays: 30,
  showDemographics: false,
  canManage: true
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}
const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function mount() {
  const element = createElement('c-hub-board-panel', { is: HubBoardPanel });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  return element;
}

describe('c-hub-board-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the seats, the ending term, the gap, giving and the action items', async () => {
    getBoard.mockResolvedValue(BOARD);
    const element = mount();
    await flush();
    expect(getBoard).toHaveBeenCalledWith({ boardId: RECORD_ID });
    expect(element.shadowRoot.querySelectorAll('[data-id="seat"]')).toHaveLength(2);
    expect(find(element, 'expiring')).not.toBeNull();
    expect(find(element, 'gaps')).not.toBeNull();
    expect(find(element, 'giving')).not.toBeNull();
    expect(find(element, 'items')).not.toBeNull();
    expect(find(element, 'demographics')).toBeNull();
  });

  it('hides giving without Giving and the manager actions from staff', async () => {
    getBoard.mockResolvedValue({ ...BOARD, givers: null, canManage: false, seats: [] });
    const element = mount();
    await flush();
    expect(find(element, 'giving')).toBeNull();
    expect(find(element, 'request')).toBeNull();
    expect(find(element, 'assess')).toBeNull();
    expect(find(element, 'no-seats')).not.toBeNull();
  });

  it('requests a disclosure from the board and starts a self-assessment', async () => {
    getBoard.mockResolvedValue(BOARD);
    requestFromBoard.mockResolvedValue(2);
    startAssessment.mockResolvedValue('a06000000000001AAA');
    const element = mount();
    await flush();
    const combo = find(element, 'document');
    combo.dispatchEvent(new CustomEvent('change', { detail: { value: 'd1' } }));
    await flush();
    find(element, 'request').click();
    await flush();
    expect(requestFromBoard).toHaveBeenCalledWith({ boardId: RECORD_ID, documentId: 'd1' });
    find(element, 'assess').click();
    await flush();
    expect(startAssessment).toHaveBeenCalledWith({ boardId: RECORD_ID });
  });

  it('shows a refusal as a notice', async () => {
    getBoard.mockRejectedValue({ body: { message: 'No access' } });
    const element = mount();
    await flush();
    expect(find(element, 'error-message')).not.toBeNull();
  });
});
