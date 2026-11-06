/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import FundersBoard from 'c/fundersBoard';
import getBoard from '@salesforce/apex/FundersBoardController.getBoard';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import { loadStyle } from 'lightning/platformResourceLoader';

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
const getNavigateCalledWith = () => mockNavigate.mock.calls[mockNavigate.mock.calls.length - 1][0];

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

  it('opens on the shell with the year as tiles', async () => {
    const element = await render(BOARD);
    const shell = one(element, '[data-id="shell"]');
    expect(shell.titleHidden).toBe(true);
    expect(shell.iconName).toBe('custom:custom100');
    expect(one(element, '[data-id="revenue"]').value).toBe(100000);
    expect(one(element, '[data-id="revenue"]').formatStyle).toBe('currency');
    expect(one(element, '[data-id="awarded"]').value).toBe(60000);
    expect(one(element, '[data-id="gifts"]').value).toBe(40000);
    expect(one(element, '[data-id="restricted-total"]')).toBeNull();
  });

  it('shows the mix and the sources as meters, the flags in one notice and the funds', async () => {
    const element = await render(BOARD);
    const mix = all(element, '[data-id="mix-row"] c-barn-meter');
    expect(mix).toHaveLength(2);
    expect(mix[0].label).toContain('Federal');
    expect(mix[0].value).toBe(60);
    expect(mix[0].valueText).toBe('60%');
    expect(all(element, '[data-id="flags"] [data-id="flag"]')).toHaveLength(2);
    expect(one(element, '[data-id="flags"]').variant).toBe('warning');
    expect(all(element, '[data-id="source-row"]')).toHaveLength(2);
    expect(one(element, '[data-id="funds"]').textContent).toContain('Scholarships');
    expect(one(element, '[data-id="funds"]').className).toContain('slds-max-medium-table_stacked');
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
    expect(one(element, '[data-id="gifts"]')).toBeNull();
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
    expect(one(element, '[data-id="restricted-total"]').value).toBe(2500);
    document.body.removeChild(element);

    getBoard.mockRejectedValue({ body: { message: 'Broken' } });
    element = createElement('c-funders-board', { is: FundersBoard });
    document.body.appendChild(element);
    await flush();
    const notice = one(element, '[data-id="error-message"]');
    expect(notice.variant).toBe('error');
    expect(notice.message).toBe('Broken');
  });

  it('lists the Funders tools the person can see and opens one', async () => {
    const element = await render(BOARD);
    getObjectInfos.emit({
      results: [
        { statusCode: 200, result: { apiName: 'Grant__c', labelPlural: 'Grants' } },
        { statusCode: 403, result: null }
      ]
    });
    await flush();
    const grid = one(element, '[data-id="tools"]');
    const names = grid.groups[0].tiles.map((tile) => tile.name);
    expect(names).toEqual(['Grant_Pipeline', 'Grant_Calendar', 'Grant__c']);
    expect(grid.groups[0].tiles[2].label).toBe('Grants');

    grid.dispatchEvent(new CustomEvent('select', { detail: { name: 'Grant__c' } }));
    expect(getNavigateCalledWith().attributes.objectApiName).toBe('Grant__c');
    grid.dispatchEvent(new CustomEvent('select', { detail: { name: 'Grant_Calendar' } }));
    expect(getNavigateCalledWith().attributes.apiName).toBe('Grant_Calendar');
  });

  it('prints with the print stylesheet', async () => {
    const element = await render(BOARD);
    loadStyle.mockResolvedValue();
    window.print = jest.fn();
    one(element, '[data-id="print"]').click();
    await flush();
    expect(loadStyle).toHaveBeenCalled();
    expect(window.print).toHaveBeenCalled();
  });
});
