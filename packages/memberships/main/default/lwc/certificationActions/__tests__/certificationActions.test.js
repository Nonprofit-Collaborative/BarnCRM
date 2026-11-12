import { createElement } from 'lwc';
import CertificationActions from 'c/certificationActions';
import getPanel from '@salesforce/apex/CertificationController.panel';
import grant from '@salesforce/apex/CertificationController.grant';
import renew from '@salesforce/apex/CertificationController.renew';
import revoke from '@salesforce/apex/CertificationController.revoke';

jest.mock('@salesforce/apex/CertificationController.panel', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CertificationController.grant', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CertificationController.renew', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CertificationController.revoke', () => ({ default: jest.fn() }), {
  virtual: true
});

const HOLDING = 'a0C000000000001AAA';
const ACTIVE = {
  status: 'Active',
  expiresOn: '2028-11-30',
  openCredits: 12,
  creditsRequired: 20,
  canEdit: true,
  canGrant: false,
  canRevoke: true,
  renewRefusal: 'Not enough credits to renew: 12 earned, 20 needed.'
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function render(panel) {
  getPanel.mockResolvedValue(panel);
  const element = createElement('c-certification-actions', { is: CertificationActions });
  element.recordId = HOLDING;
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-certification-actions', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows credits and expiry, and says why it cannot renew yet', async () => {
    const element = await render(ACTIVE);
    expect(getPanel).toHaveBeenCalledWith({ holdingId: HOLDING });
    expect(find(element, 'credits').textContent).toBe('c.Memberships_Cert_Credits');
    expect(find(element, 'expires').textContent).toBe('c.Memberships_Cert_Expires');
    expect(find(element, 'renew')).toBeNull();
    expect(find(element, 'grant')).toBeNull();
    expect(find(element, 'revoke')).not.toBeNull();
    expect(find(element, 'renew-hint').textContent).toBe(ACTIVE.renewRefusal);
  });

  it('renews when the server allows it, and says it is saved', async () => {
    const allowed = { ...ACTIVE, renewRefusal: null };
    renew.mockResolvedValue({ ...allowed, openCredits: 0 });
    const element = await render(allowed);
    find(element, 'renew').click();
    await flush();
    expect(renew).toHaveBeenCalledWith({ holdingId: HOLDING });
    expect(find(element, 'notice').message).toBe('c.Memberships_Cert_Done');
  });

  it('grants a pending certification', async () => {
    const pending = {
      ...ACTIVE,
      status: 'Pending',
      expiresOn: null,
      canGrant: true,
      canRevoke: false
    };
    grant.mockResolvedValue(ACTIVE);
    const element = await render(pending);
    expect(find(element, 'expires').textContent).toBe('');
    find(element, 'grant').click();
    await flush();
    expect(grant).toHaveBeenCalledWith({ holdingId: HOLDING });
  });

  it('revokes and shows the server message when an action fails', async () => {
    revoke.mockRejectedValue({ body: { message: 'Revoke failed.' } });
    const element = await render(ACTIVE);
    find(element, 'revoke').click();
    await flush();
    expect(revoke).toHaveBeenCalledWith({ holdingId: HOLDING });
    expect(find(element, 'error').message).toBe('Revoke failed.');
  });

  it('shows no buttons or hint to a reader', async () => {
    const element = await render({ ...ACTIVE, canEdit: false, canRevoke: false });
    expect(find(element, 'revoke')).toBeNull();
    expect(find(element, 'renew-hint')).toBeNull();
  });

  it('falls back to its own message when the failure has none', async () => {
    getPanel.mockRejectedValue(new Error('down'));
    const element = createElement('c-certification-actions', { is: CertificationActions });
    element.recordId = HOLDING;
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').message).toBe('c.Memberships_Panel_Failed');
  });
});
