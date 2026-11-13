import { createElement } from 'lwc';
import ApplicationReview from 'c/applicationReview';
import getReview from '@salesforce/apex/ScholarshipsController.getReview';
import saveReview from '@salesforce/apex/ScholarshipsController.saveReview';

jest.mock('@salesforce/apex/ScholarshipsController.getReview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ScholarshipsController.saveReview', () => ({ default: jest.fn() }), {
  virtual: true
});

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const REVIEW = {
  open: true,
  blind: true,
  criteria: [
    { key: 'need', label: 'Need', max: 10, weight: 2 },
    { key: 'essay', label: 'Essay', max: 10, weight: 1 }
  ],
  mine: { status: 'Assigned', scores: '{"need":8}' }
};

function mount() {
  const element = createElement('c-application-review', { is: ApplicationReview });
  element.recordId = 'a01000000000001AAA';
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-application-review', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('totals the scores as they are typed and submits them', async () => {
    getReview.mockResolvedValue(REVIEW);
    saveReview.mockResolvedValue({});
    const element = mount();
    await flush();
    expect(find(element, 'blind')).not.toBeNull();
    const essay = element.shadowRoot.querySelector('[data-key="essay"]');
    essay.value = 6;
    essay.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(find(element, 'total').textContent).toContain('22');
    find(element, 'submit').click();
    await flush();
    expect(saveReview).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'submit',
        scoresJson: JSON.stringify({ need: 8, essay: 6 })
      })
    );
  });

  it('recuses with a reason and shows a closed review as closed', async () => {
    getReview.mockResolvedValue(REVIEW);
    saveReview.mockResolvedValue({});
    const element = mount();
    await flush();
    find(element, 'recuse').click();
    await flush();
    const reason = find(element, 'reason');
    reason.value = 'My niece';
    reason.dispatchEvent(new CustomEvent('change'));
    getReview.mockResolvedValue({ ...REVIEW, mine: { status: 'Recused' } });
    find(element, 'confirm-recuse').click();
    await flush();
    await flush();
    expect(saveReview).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'recuse', reason: 'My niece' })
    );
    expect(find(element, 'closed')).not.toBeNull();
  });
});
