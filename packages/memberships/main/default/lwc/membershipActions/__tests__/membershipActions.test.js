import { createElement } from 'lwc';
import MembershipActions from 'c/membershipActions';
import getPanel from '@salesforce/apex/MembershipController.panel';
import renewTerm from '@salesforce/apex/MembershipController.renew';
import emailPaymentLink from '@salesforce/apex/MembershipController.emailPaymentLink';

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
jest.mock('@salesforce/apex/MembershipController.panel', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MembershipController.renew', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/MembershipController.emailPaymentLink',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const TERM = 'a0B000000000001AAA';
const NEW_TERM = 'a0B000000000002AAA';
const PANEL = {
  status: 'Current',
  levelId: 'a0A000000000001AAA',
  canRenew: true,
  paymentsReady: true,
  hasEmail: true,
  levels: [
    { value: 'a0A000000000001AAA', label: 'Individual', dues: 50 },
    { value: 'a0A000000000002AAA', label: 'Family', dues: 90 }
  ]
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function render(panel) {
  getPanel.mockResolvedValue(panel);
  const element = createElement('c-membership-actions', { is: MembershipActions });
  element.recordId = TERM;
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-membership-actions', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers the levels with the current one chosen, and both actions', async () => {
    const element = await render(PANEL);
    expect(getPanel).toHaveBeenCalledWith({ termId: TERM });
    const level = find(element, 'level');
    expect(level.options.length).toBe(2);
    expect(level.value).toBe(PANEL.levelId);
    expect(find(element, 'renew').disabled).toBe(false);
    expect(find(element, 'email-link')).not.toBeNull();
  });

  it('renews at the level chosen and opens the new membership', async () => {
    renewTerm.mockResolvedValue(NEW_TERM);
    const element = await render(PANEL);
    find(element, 'level').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'a0A000000000002AAA' } })
    );
    find(element, 'renew').click();
    await flush();
    expect(renewTerm).toHaveBeenCalledWith({ termId: TERM, levelId: 'a0A000000000002AAA' });
    expect(mockNavigate.mock.calls[0][0].attributes.recordId).toBe(NEW_TERM);
  });

  it('says why a membership cannot be renewed, and why no link can be sent', async () => {
    const element = await render({
      ...PANEL,
      canRenew: false,
      status: 'Renewed',
      paymentsReady: false
    });
    expect(find(element, 'renew')).toBeNull();
    expect(find(element, 'cannot-renew').textContent).toBe('c.Memberships_Panel_CannotRenew');
    expect(find(element, 'email-link')).toBeNull();
    expect(find(element, 'link-hint').textContent).toBe('c.Memberships_Panel_PaymentsOff');
  });

  it('asks for the member email when there is none', async () => {
    const element = await render({ ...PANEL, hasEmail: false });
    expect(find(element, 'link-hint').textContent).toBe('c.Memberships_Panel_NoEmail');
  });

  it('queues the payment link and says so', async () => {
    emailPaymentLink.mockResolvedValue(null);
    const element = await render(PANEL);
    find(element, 'email-link').click();
    await flush();
    expect(emailPaymentLink).toHaveBeenCalledWith({ termId: TERM });
    expect(find(element, 'notice').message).toBe('c.Memberships_Panel_LinkQueued');
  });

  it('shows the server message when an action fails', async () => {
    renewTerm.mockRejectedValue({ body: { message: 'Only a current membership renews.' } });
    const element = await render(PANEL);
    find(element, 'renew').click();
    await flush();
    expect(find(element, 'error').message).toBe('Only a current membership renews.');
  });

  it('falls back to its own message when the failure has none', async () => {
    getPanel.mockRejectedValue(new Error('down'));
    const element = createElement('c-membership-actions', { is: MembershipActions });
    element.recordId = TERM;
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').message).toBe('c.Memberships_Panel_Failed');
  });
});
