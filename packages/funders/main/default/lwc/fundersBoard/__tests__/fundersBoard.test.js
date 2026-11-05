import { createElement } from 'lwc';
import FundersBoard from 'c/fundersBoard';
import getBoard from '@salesforce/apex/FundersBoardController.getBoard';

jest.mock('@salesforce/apex/FundersBoardController.getBoard', () => ({ default: jest.fn() }), {
  virtual: true
});

const BOARD = {
  grantsBySource: [{ key: 'Federal', name: 'Federal', amount: 60000 }],
  grantsByFunder: [{ key: 'a1', name: 'Lakeside Foundation', amount: 60000 }],
  givingAvailable: true,
  giftsThisYear: 40000,
  givingByAccount: [{ key: 'a3', name: 'Corner Bakery', amount: 1000 }],
  restrictedFunds: [{ key: 'f1', name: 'Scholarships', amount: 12000 }],
  ledgerAvailable: false,
  restrictedGrants: [],
  currencyCode: 'USD'
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(board) {
  getBoard.mockResolvedValue(board);
  const element = createElement('c-funders-board', { is: FundersBoard });
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-funders-board', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the mix, the flags and the restricted funds', async () => {
    const element = await render(BOARD);
    const mix = all(element, '[data-id="mix"] tr').map((row) => row.textContent);
    expect(mix).toHaveLength(3);
    expect(mix[0]).toContain('Federal');
    expect(mix[0]).toContain('60%');
    expect(one(element, '[data-id="mix-total"]').textContent).toContain('100,000');
    expect(all(element, '[data-id="flag"]')).toHaveLength(2);
    expect(all(element, '[data-id="sources"] tr')).toHaveLength(2);
    expect(one(element, '[data-id="funds"]').textContent).toContain('Scholarships');
    expect(one(element, '[data-id="grants"]')).toBeNull();
  });

  it('says when nothing is concentrated or restricted', async () => {
    const element = await render({
      grantsBySource: [{ key: 'State', name: 'State', amount: 100 }],
      grantsByFunder: [{ key: 'a', name: 'A', amount: 10 }],
      givingAvailable: false,
      restrictedFunds: [],
      restrictedGrants: [],
      currencyCode: 'USD'
    });
    expect(one(element, '[data-id="no-risk"]')).not.toBeNull();
    expect(all(element, '[data-id="flag"]')).toHaveLength(0);
    expect(one(element, '[data-id="restricted-empty"]')).not.toBeNull();
  });

  it('shows the restricted grants from the ledger, an empty year and a load error', async () => {
    let element = await render({
      grantsBySource: [],
      grantsByFunder: [],
      givingAvailable: false,
      restrictedFunds: [],
      ledgerAvailable: true,
      restrictedGrants: [{ key: 'g1', name: 'Youth Grant', amount: 2500 }],
      currencyCode: 'USD'
    });
    expect(one(element, '[data-id="mix-empty"]')).not.toBeNull();
    expect(one(element, '[data-id="grants"]').textContent).toContain('Youth Grant');
    document.body.removeChild(element);

    getBoard.mockRejectedValue({ body: { message: 'Broken' } });
    element = createElement('c-funders-board', { is: FundersBoard });
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]').textContent).toBe('Broken');
  });
});
