import { createElement } from 'lwc';
import ConnectorTemplates from 'c/connectorTemplates';
import importFile from '@salesforce/apex/ConnectorRecipesController.importFile';
import { expectAccessible } from 'barn/a11y';

jest.mock(
  '@salesforce/apex/ConnectorRecipesController.importFile',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const IMPORTED = {
  kind: 'template',
  label: 'Mailchimp',
  description: 'Subscribers',
  connection: {
    label: 'Mailchimp',
    authKind: 'BasicAuth',
    baseUrl: 'https://{dc}.api.mailchimp.com/3.0',
    urlParams: [{ name: 'dc', pattern: '[a-z]{2}[0-9]{1,3}' }]
  },
  recipes: [
    {
      name: 'Add New People',
      description: '',
      draftJson: '{"version":1,"trigger":{"kind":"manual"},"steps":[]}',
      blanks: ['send'],
      problems: ['Step send: choose a connection.']
    }
  ]
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render() {
  const element = createElement('c-connector-templates', { is: ConnectorTemplates });
  document.body.appendChild(element);
  await flush();
  return element;
}

async function paste(element, value) {
  const box = find(element, 'paste');
  box.value = value;
  box.dispatchEvent(new CustomEvent('change'));
  find(element, 'import').click();
  await flush();
}

describe('c-connector-templates', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers a file or pasted text and is accessible', async () => {
    const element = await render();
    expect(find(element, 'file')).not.toBeNull();
    expect(find(element, 'paste')).not.toBeNull();
    await expectAccessible(element);
  });

  it('refuses a file holding a secret in the browser, never sending it', async () => {
    const element = await render();
    await paste(element, JSON.stringify({ key: 'a', webhook: { apiKey: 'abc' } }));
    expect(importFile).not.toHaveBeenCalled();
    expect(find(element, 'error')).not.toBeNull();
    expect(find(element, 'imported')).toBeNull();
  });

  it('shows what a template offers and hands on the connection and each draft', async () => {
    importFile.mockResolvedValue(IMPORTED);
    const element = await render();
    const source = JSON.stringify({ key: 'mailchimp', label: 'Mailchimp', version: 1 });
    await paste(element, source);
    expect(importFile).toHaveBeenCalledWith({ fileText: source });
    expect(find(element, 'imported')).not.toBeNull();
    expect(find(element, 'recipe-0')).not.toBeNull();

    const connection = jest.fn();
    const opened = jest.fn();
    element.addEventListener('connection', connection);
    element.addEventListener('opendraft', opened);
    find(element, 'create-connection').click();
    find(element, 'open-draft-0').click();
    expect(connection.mock.calls[0][0].detail.prefill.baseUrl).toBe(IMPORTED.connection.baseUrl);
    expect(opened.mock.calls[0][0].detail).toEqual({
      name: 'Add New People',
      description: '',
      draftJson: IMPORTED.recipes[0].draftJson
    });
    await expectAccessible(element);
  });

  it('shows the server refusal', async () => {
    importFile.mockRejectedValue({ body: { message: 'Refused.' } });
    const element = await render();
    await paste(element, JSON.stringify({ key: 'a', label: 'A', version: 1 }));
    expect(find(element, 'error').message).toBe('Refused.');
  });
});
