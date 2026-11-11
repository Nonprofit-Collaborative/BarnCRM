import { createElement } from 'lwc';
import HubCompleteCycle from 'c/hubCompleteCycle';
import completeCycle from '@salesforce/apex/CorporateHubController.completeCycle';

jest.mock('@salesforce/apex/CorporateHubController.completeCycle', () => ({ default: jest.fn() }), {
  virtual: true
});

const RECORD_ID = 'a04000000000001AAA';
function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}
const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function mount() {
  const element = createElement('c-hub-complete-cycle', { is: HubCompleteCycle });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  return element;
}

describe('c-hub-complete-cycle', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('records the cycle with what was entered, then offers the evidence upload', async () => {
    completeCycle.mockResolvedValue('a05000000000001AAA');
    const element = mount();
    expect(find(element, 'evidence')).toBeNull();

    const outcome = find(element, 'outcome');
    outcome.value = 'Done Late';
    outcome.dispatchEvent(new CustomEvent('change'));
    const notes = find(element, 'notes');
    notes.value = 'Filed online';
    notes.dispatchEvent(new CustomEvent('change'));
    find(element, 'complete').click();
    await flush();

    expect(completeCycle).toHaveBeenCalledWith(
      expect.objectContaining({
        obligationId: RECORD_ID,
        outcome: 'Done Late',
        notes: 'Filed online'
      })
    );
    expect(find(element, 'evidence').recordId).toBe('a05000000000001AAA');
  });

  it('shows why it could not be done', async () => {
    completeCycle.mockRejectedValue({ body: { message: 'Completed On is required' } });
    const element = mount();

    find(element, 'complete').click();
    await flush();

    expect(find(element, 'error-message').message).toBe('Completed On is required');
    expect(find(element, 'evidence')).toBeNull();
  });
});
