import { createElement } from 'lwc';
import GiftDonorPanel, { money, day } from 'c/giftDonorPanel';
import getPanel from '@salesforce/apex/GiftDonorPanelController.getPanel';

jest.mock('@salesforce/apex/GiftDonorPanelController.getPanel', () => ({ default: jest.fn() }), {
  virtual: true
});

const PANEL = {
  householdId: '001000000000001AAA',
  householdName: 'Rivera Household',
  totalGiving: 1250,
  lastGiftDate: '2026-10-01',
  gifts: [
    {
      id: 'a01000000000001AAA',
      giftDate: '2026-10-01',
      amount: 250,
      paymentMethod: 'Check',
      status: 'Received'
    }
  ],
  commitments: [
    {
      id: 'a02000000000001AAA',
      name: 'C-0001',
      type: 'Pledge',
      amount: 1000,
      frequency: 'Monthly',
      status: 'Active',
      balance: 600,
      nextDueDate: '2026-12-01',
      nextDueAmount: 100
    }
  ]
};

function flush() {
  return Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
}

function render(donorId) {
  const element = createElement('c-gift-donor-panel', { is: GiftDonorPanel });
  element.donorId = donorId;
  document.body.appendChild(element);
  return element;
}

describe('c-gift-donor-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('formats money and dates and tolerates blanks', () => {
    expect(money(null, 'en-US', 'USD')).toBe('');
    expect(money(12.5, 'en-US', 'USD')).toBe('$12.50');
    expect(day('', 'en-US')).toBe('');
    expect(day('2026-12-01', 'en-US')).toBe('Dec 1, 2026');
  });

  it('shows nothing and calls nothing with no donor', async () => {
    const element = render(undefined);
    await flush();
    expect(getPanel).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="donor-panel"]')).toBeNull();
  });

  it('shows the household, recent gifts and open commitments', async () => {
    getPanel.mockResolvedValue(PANEL);
    const element = render('003000000000001AAA');
    await flush();
    expect(getPanel).toHaveBeenCalledWith({ donorId: '003000000000001AAA' });
    const root = element.shadowRoot;
    expect(root.querySelector('[data-id="household"] a').textContent).toBe('Rivera Household');
    expect(root.querySelectorAll('[data-id="gifts"] li')).toHaveLength(1);
    expect(root.querySelector('[data-id="gifts"] li').textContent).toContain('Check');
    const commitment = root.querySelector('[data-id="commitments"] li');
    expect(commitment.textContent).toContain('C-0001');
    expect(commitment.textContent).toContain('Pledge');
    expect(root.querySelector('[data-id="no-gifts"]')).toBeNull();
  });

  it('shows the empty notes for a donor with no history', async () => {
    getPanel.mockResolvedValue({ totalGiving: 0, gifts: [], commitments: [] });
    const element = render('003000000000002AAA');
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector('[data-id="no-gifts"]')).not.toBeNull();
    expect(root.querySelector('[data-id="no-commitments"]')).not.toBeNull();
    expect(root.querySelector('[data-id="household"]')).toBeNull();
  });

  it('shows a quiet note when loading fails', async () => {
    getPanel.mockRejectedValue(new Error('boom'));
    const element = render('003000000000003AAA');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="panel-error"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="donor-panel"]')).toBeNull();
  });
});
