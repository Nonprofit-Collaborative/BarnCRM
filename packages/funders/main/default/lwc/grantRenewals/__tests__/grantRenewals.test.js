import { createElement } from 'lwc';
import GrantRenewals from 'c/grantRenewals';
import getRenewals from '@salesforce/apex/GrantManagementController.getRenewals';
import startRenewal from '@salesforce/apex/GrantManagementController.startRenewal';

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
jest.mock(
  '@salesforce/apex/GrantManagementController.getRenewals',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GrantManagementController.startRenewal',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const CHAIN = [
  { id: 'g1', name: 'Literacy 2025', stage: 'Closed', awarded: 30000, current: false },
  { id: 'g2', name: 'Literacy 2026', stage: 'Awarded', awarded: 35000, current: true }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(card) {
  getRenewals.mockResolvedValue(card);
  const element = createElement('c-grant-renewals', { is: GrantRenewals });
  element.recordId = 'g2';
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-grant-renewals', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the history with this grant marked, and starts the renewal', async () => {
    startRenewal.mockResolvedValue('g3');
    const element = await render({ chain: CHAIN, canStart: true });
    expect(element.shadowRoot.querySelectorAll('[data-id="grant"]')).toHaveLength(2);
    expect(element.shadowRoot.querySelectorAll('[data-id="this-grant"]')).toHaveLength(1);

    element.shadowRoot.querySelector('[data-id="start"]').click();
    await flush();
    expect(startRenewal).toHaveBeenCalledWith({ grantId: 'g2' });
    expect(mockNavigate.mock.calls[0][0].attributes.recordId).toBe('g3');
  });

  it('says there is no history for a first-year grant, and offers no start when renewed', async () => {
    const element = await render({ chain: [CHAIN[1]], canStart: false });
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="start"]')).toBeNull();
  });

  it('keeps the page when the renewal is refused', async () => {
    startRenewal.mockRejectedValue({ body: { message: 'Not allowed.' } });
    const element = await render({ chain: CHAIN, canStart: true });
    const toasts = jest.fn();
    element.addEventListener('lightning__showtoast', toasts);
    element.shadowRoot.querySelector('[data-id="start"]').click();
    await flush();
    expect(toasts.mock.calls[0][0].detail).toMatchObject({
      message: 'Not allowed.',
      variant: 'error'
    });
    expect(mockNavigate).not.toHaveBeenCalled();
  });
});
