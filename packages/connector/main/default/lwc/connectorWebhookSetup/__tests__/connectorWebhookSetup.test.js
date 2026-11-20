import { createElement } from 'lwc';
import ConnectorWebhookSetup from 'c/connectorWebhookSetup';
import getWebhook from '@salesforce/apex/ConnectorWebhooksController.getWebhook';
import newWebhookToken from '@salesforce/apex/ConnectorWebhooksController.newWebhookToken';
import saveWebhookCap from '@salesforce/apex/ConnectorWebhooksController.saveWebhookCap';
import BarnConfirmModal from 'c/barnConfirmModal';
import { expectAccessible } from 'barn/a11y';

jest.mock(
  '@salesforce/apex/ConnectorWebhooksController.getWebhook',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorWebhooksController.newWebhookToken',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorWebhooksController.saveWebhookCap',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const ADDRESS =
  'https://example.my.salesforce-sites.com/services/apexrest/barncrm/connector/v1/hook';
const VIEW = { hasToken: false, hourlyCap: 500, header: 'X-BarnCRM-Token', addresses: [ADDRESS] };
const TRIGGER = { kind: 'webhook', eventId: '', reply: { status: 202, challenge: '' } };

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render(recipeId, canManage = true, view = VIEW) {
  getWebhook.mockResolvedValue(view);
  const element = createElement('c-connector-webhook-setup', { is: ConnectorWebhookSetup });
  element.canManage = canManage;
  element.trigger = TRIGGER;
  element.recipeId = recipeId;
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-connector-webhook-setup', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('asks to save first when the recipe is new, and still edits the reply', async () => {
    const element = await render(undefined);
    expect(getWebhook).not.toHaveBeenCalled();
    expect(find(element, 'save-first')).not.toBeNull();
    expect(find(element, 'reply-body').value).toBe(
      '{"received": true, "reference": "{reference}"}'
    );
    await expectAccessible(element);
  });

  it('shows each address, the header and no token until one is made', async () => {
    const element = await render('a0R000000000001');
    expect(getWebhook).toHaveBeenCalledWith({ recipeId: 'a0R000000000001' });
    const inputs = element.shadowRoot.querySelectorAll('[data-id="address"] lightning-input');
    expect(inputs[0].value).toBe(ADDRESS);
    expect(inputs[1].value).toBe(`${ADDRESS}?token=<token>`);
    expect(find(element, 'header').value).toBe('X-BarnCRM-Token');
    expect(find(element, 'token')).toBeNull();
    expect(find(element, 'token-state')).not.toBeNull();
    await expectAccessible(element);
  });

  it('warns when no Site is active', async () => {
    const element = await render('a0R000000000001', true, { ...VIEW, addresses: [] });
    expect(find(element, 'no-site')).not.toBeNull();
  });

  it('shows a new token once, asking first when one exists', async () => {
    const element = await render('a0R000000000001', true, { ...VIEW, hasToken: true });
    BarnConfirmModal.open = jest.fn().mockResolvedValueOnce(false).mockResolvedValue(true);
    newWebhookToken.mockResolvedValue({ ...VIEW, hasToken: true, token: 'ab'.repeat(32) });

    find(element, 'new-token').click();
    await flush();
    expect(newWebhookToken).not.toHaveBeenCalled();

    find(element, 'new-token').click();
    await flush();
    expect(newWebhookToken).toHaveBeenCalledWith({ recipeId: 'a0R000000000001' });
    expect(find(element, 'token').value).toBe('ab'.repeat(32));
    const inputs = element.shadowRoot.querySelectorAll('[data-id="address"] lightning-input');
    expect(inputs[1].value).toBe(`${ADDRESS}?token=${'ab'.repeat(32)}`);
    expect(find(element, 'message')).not.toBeNull();
  });

  it('saves the hourly cap and shows a refusal', async () => {
    const element = await render('a0R000000000001');
    saveWebhookCap.mockResolvedValueOnce({ ...VIEW, hourlyCap: 50 });
    const cap = find(element, 'hourly-cap');
    cap.dispatchEvent(new CustomEvent('change', { detail: { value: '50' } }));
    find(element, 'save-cap').click();
    await flush();
    expect(saveWebhookCap).toHaveBeenCalledWith({ recipeId: 'a0R000000000001', hourlyCap: 50 });
    expect(find(element, 'message')).not.toBeNull();

    saveWebhookCap.mockRejectedValueOnce({ body: { message: 'Between 1 and 5000.' } });
    find(element, 'save-cap').click();
    await flush();
    expect(find(element, 'error').message).toBe('Between 1 and 5000.');
  });

  it('hands Event Id and reply changes to the editor', async () => {
    const element = await render('a0R000000000001');
    const changes = [];
    element.addEventListener('triggerchange', (event) => changes.push(event.detail));

    find(element, 'event-id').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'trigger.id' } })
    );
    find(element, 'reply-status').dispatchEvent(
      new CustomEvent('change', { detail: { value: '200' } })
    );
    find(element, 'challenge').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'challenge' } })
    );

    expect(changes[0]).toEqual({ eventId: 'trigger.id' });
    expect(changes[1]).toEqual({ reply: { status: 200, challenge: '' } });
    expect(changes[2]).toEqual({ reply: { status: 202, challenge: 'challenge' } });
  });

  it('is read-only without manage access', async () => {
    const element = await render('a0R000000000001', false);
    expect(find(element, 'new-token')).toBeNull();
    expect(find(element, 'save-cap')).toBeNull();
    expect(find(element, 'event-id').readOnly).toBe(true);
    expect(find(element, 'reply-status').disabled).toBe(true);
  });
});
