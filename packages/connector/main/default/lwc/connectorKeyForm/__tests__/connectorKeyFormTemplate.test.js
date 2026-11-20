import { createElement } from 'lwc';
import ConnectorKeyForm from 'c/connectorKeyForm';
import createConnection from '@salesforce/apex/ConnectorConnectionsController.createConnection';

jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.createConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.replaceKey',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const PREFILL = {
  label: 'Mailchimp',
  authKind: 'BasicAuth',
  baseUrl: 'https://{dc}.api.mailchimp.com/3.0',
  urlParams: [
    {
      name: 'dc',
      label: 'Data center',
      pattern: '[a-z]{2}[0-9]{1,3}',
      fromParam: 'Password',
      after: '-'
    }
  ]
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function type(element, id, value) {
  const input = find(element, id);
  input.value = value;
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
}

async function render() {
  const element = createElement('c-connector-key-form', { is: ConnectorKeyForm });
  element.prefill = PREFILL;
  document.body.appendChild(element);
  await flush();
  await type(element, 'user-name', 'anyone');
  return element;
}

describe('c-connector-key-form from a template (CN-08, R-CR14)', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('locks the host and reads the data center from the key at saving only', async () => {
    createConnection.mockResolvedValue({ outcome: 'Created' });
    const element = await render();
    expect(find(element, 'label').value).toBe('Mailchimp');
    expect(find(element, 'base-url').readOnly).toBe(true);
    expect(find(element, 'url-dc')).not.toBeNull();
    find(element, 'secret').value = '0123456789abcdef-us21';
    find(element, 'save').click();
    await flush();
    expect(createConnection).toHaveBeenCalledWith(
      expect.objectContaining({
        authKind: 'BasicAuth',
        baseUrl: 'https://us21.api.mailchimp.com/3.0'
      })
    );
  });

  it('refuses a URL part that would move the host (F4)', async () => {
    const element = await render();
    await type(element, 'url-dc', 'evil.example.com/x');
    find(element, 'secret').value = 'key-us21';
    find(element, 'save').click();
    await flush();
    expect(createConnection).not.toHaveBeenCalled();
    expect(find(element, 'problems')).not.toBeNull();
  });
});
