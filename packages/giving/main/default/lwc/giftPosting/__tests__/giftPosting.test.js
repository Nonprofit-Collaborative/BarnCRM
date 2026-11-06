import { createElement } from 'lwc';
import GiftPosting from 'c/giftPosting';
import getState from '@salesforce/apex/GiftPostingController.getState';
import unpost from '@salesforce/apex/GiftPostingController.unpost';
import { setHelpTextForTest } from 'c/barnHelpText';

jest.mock('@salesforce/apex/GiftPostingController.getState', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/GiftPostingController.unpost', () => ({ default: jest.fn() }), {
  virtual: true
});

setHelpTextForTest({ Giving_PostingCard_Unposted: 'Unposted. The reason is in the Error Log.' });

const POSTED = {
  inBooks: true,
  posted: true,
  postedAt: '2026-09-02T15:04:00.000Z',
  postedBy: 'Jen Park',
  inClosedPeriod: false,
  closedThrough: null,
  canUnpost: true
};

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(state) {
  getState.mockResolvedValue(state);
  const element = createElement('c-gift-posting', { is: GiftPosting });
  element.recordId = 'a0B000000000001AAA';
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

const byId = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function typeReason(element, value) {
  const input = byId(element, 'reason');
  input.value = value;
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-gift-posting', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('names who posted the gift', async () => {
    const element = await render(POSTED);
    expect(getState).toHaveBeenCalledWith({ giftId: 'a0B000000000001AAA' });
    expect(byId(element, 'posted').textContent).toContain('Jen Park');
    expect(byId(element, 'not-posted')).toBeNull();
  });

  it('says a gift is in a closed period', async () => {
    const element = await render({
      ...POSTED,
      posted: false,
      canUnpost: false,
      inClosedPeriod: true,
      closedThrough: '2026-08-31'
    });
    expect(byId(element, 'not-posted')).not.toBeNull();
    const formatted = byId(element, 'closed-period').querySelector('lightning-formatted-date-time');
    expect(formatted.value).toBe('2026-08-31');
    expect(byId(element, 'unpost')).toBeNull();
  });

  it('says a Pending gift is not in the books', async () => {
    const element = await render({ ...POSTED, inBooks: false, posted: false, canUnpost: false });
    expect(byId(element, 'not-in-books')).not.toBeNull();
    expect(byId(element, 'not-posted')).toBeNull();
  });

  it('keeps Unpost disabled until there is a reason', async () => {
    const element = await render(POSTED);
    expect(byId(element, 'unpost').disabled).toBe(true);
    typeReason(element, 'Wrong fund');
    await flushPromises();
    expect(byId(element, 'unpost').disabled).toBe(false);
  });

  it('unposts with the reason and shows the new state', async () => {
    const element = await render(POSTED);
    unpost.mockResolvedValue({ ...POSTED, posted: false, postedBy: null, canUnpost: false });

    typeReason(element, 'Wrong fund');
    await flushPromises();
    byId(element, 'unpost').click();
    await flushPromises();

    expect(unpost).toHaveBeenCalledWith({ giftId: 'a0B000000000001AAA', reason: 'Wrong fund' });
    expect(byId(element, 'notice').message).toContain('Unposted.');
    expect(byId(element, 'not-posted')).not.toBeNull();
  });

  it('shows the refusal the controller gives', async () => {
    const element = await render(POSTED);
    unpost.mockRejectedValue({ body: { message: 'You need the Post Gifts permission.' } });

    typeReason(element, 'Wrong fund');
    await flushPromises();
    byId(element, 'unpost').click();
    await flushPromises();

    expect(byId(element, 'error').message).toContain('Post Gifts');
  });
});
