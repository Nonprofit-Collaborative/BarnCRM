import { createElement } from 'lwc';
import GrantFund from 'c/grantFund';
import getFund from '@salesforce/apex/GrantFundController.getFund';
import setFund from '@salesforce/apex/GrantFundController.setFund';

jest.mock('@salesforce/apex/GrantFundController.getFund', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GrantFundController.setFund', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Fund_None', () => ({ default: 'No fund' }), {
  virtual: true
});

const GRANT_ID = 'a01000000000001AAA';
const FUND_ID = 'a03000000000001AAA';

const CARD = {
  available: true,
  canEdit: true,
  title: 'Giving Fund',
  fundId: null,
  fundName: null,
  missing: false,
  options: [{ label: 'Literacy Fund', value: FUND_ID }]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(card = CARD) {
  getFund.mockResolvedValue(card);
  const element = createElement('c-grant-fund', { is: GrantFund });
  element.recordId = GRANT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-grant-fund', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers No fund and every active fund, and saves the choice', async () => {
    setFund.mockResolvedValue();
    const element = await render();
    expect(one(element, 'lightning-card').title).toBe('Giving Fund');
    const combo = one(element, '[data-id="fund"]');
    expect(combo.options.map((option) => option.label)).toEqual(['No fund', 'Literacy Fund']);
    expect(one(element, '[data-id="save"]').disabled).toBe(true);

    combo.dispatchEvent(new CustomEvent('change', { detail: { value: FUND_ID } }));
    await flush();
    one(element, '[data-id="save"]').click();
    await flush();

    expect(setFund).toHaveBeenCalledWith({ grantId: GRANT_ID, fundId: FUND_ID });
    expect(getFund).toHaveBeenCalledTimes(2);
  });

  it('clears the fund with No fund', async () => {
    setFund.mockResolvedValue();
    const element = await render({ ...CARD, fundId: FUND_ID, fundName: 'Literacy Fund' });
    one(element, '[data-id="fund"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '' } })
    );
    await flush();
    one(element, '[data-id="save"]').click();
    await flush();
    expect(setFund).toHaveBeenCalledWith({ grantId: GRANT_ID, fundId: null });
  });

  it('says so without Giving, and when the named fund has gone', async () => {
    let element = await render({ ...CARD, available: false, canEdit: false, options: [] });
    expect(one(element, '[data-id="not-installed"]')).not.toBeNull();
    expect(one(element, '[data-id="fund"]')).toBeNull();
    document.body.removeChild(element);

    element = await render({ ...CARD, fundId: FUND_ID, missing: true });
    expect(one(element, '[data-id="missing"]')).not.toBeNull();
  });

  it('shows a reader the fund by name', async () => {
    const element = await render({ ...CARD, canEdit: false, fundName: 'Literacy Fund' });
    expect(one(element, '[data-id="read-only"]').textContent.trim()).toBe('Literacy Fund');
    expect(one(element, '[data-id="fund"]')).toBeNull();
  });

  it('shows the reason when the card cannot load or save', async () => {
    getFund.mockRejectedValue({ body: { message: 'No access' } });
    const element = createElement('c-grant-fund', { is: GrantFund });
    element.recordId = GRANT_ID;
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]').textContent.trim()).toBe('No access');

    getFund.mockResolvedValue(CARD);
    setFund.mockRejectedValue({ body: { message: 'Not a fund' } });
    const saved = await render();
    const toasts = [];
    saved.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    one(saved, '[data-id="fund"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: FUND_ID } })
    );
    await flush();
    one(saved, '[data-id="save"]').click();
    await flush();
    expect(toasts[0].variant).toBe('error');
  });
});
