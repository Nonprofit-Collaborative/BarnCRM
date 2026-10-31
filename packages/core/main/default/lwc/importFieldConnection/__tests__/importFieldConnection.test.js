import { createElement } from 'lwc';
import ImportFieldConnection from 'c/importFieldConnection';
import getConnection from '@salesforce/apex/ImportNewFieldController.getConnection';
import setUpConnection from '@salesforce/apex/ImportNewFieldController.setUpConnection';

jest.mock(
  '@salesforce/apex/ImportNewFieldController.getConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ImportNewFieldController.setUpConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

async function flush() {
  for (let i = 0; i < 10; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}
const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render(connection) {
  getConnection.mockResolvedValue(connection);
  const element = createElement('c-import-field-connection', { is: ImportFieldConnection });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-import-field-connection', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('sets up the connection once and then shows it as connected', async () => {
    setUpConnection.mockResolvedValue({ canCreate: true, connected: true });
    const element = await render({ canCreate: true, connected: false });
    expect(one(element, 'status').textContent).toContain('PanelNotConnected');
    one(element, 'set-up').click();
    await flush();
    expect(setUpConnection).toHaveBeenCalled();
    expect(one(element, 'status').textContent).toContain('PanelConnected');
    expect(one(element, 'set-up')).toBeNull();
  });

  it('shows the Setup step while callouts are off, and checks again', async () => {
    setUpConnection.mockResolvedValue({ canCreate: true, connected: false, calloutsOff: true });
    const element = await render({ canCreate: true, connected: false, calloutsOff: false });
    one(element, 'set-up').click();
    await flush();
    expect(one(element, 'status').textContent).toContain('PanelCalloutsOff');
    expect(one(element, 'enable-steps').textContent).toContain('PanelEnableSteps');
    expect(one(element, 'set-up')).toBeNull();

    getConnection.mockResolvedValue({ canCreate: true, connected: true, calloutsOff: false });
    one(element, 'check-again').click();
    await flush();
    expect(getConnection).toHaveBeenCalledTimes(2);
    expect(one(element, 'status').textContent).toContain('PanelConnected');
    expect(one(element, 'enable-steps')).toBeNull();
    expect(one(element, 'check-again')).toBeNull();
  });

  it('says what is missing to someone who may not set it up', async () => {
    const element = await render({ canCreate: false, connected: false });
    expect(one(element, 'set-up')).toBeNull();
    expect(one(element, 'needs-permission')).not.toBeNull();
  });

  it('shows a failure in words', async () => {
    getConnection.mockRejectedValue({ body: { message: 'No access.' } });
    const element = createElement('c-import-field-connection', { is: ImportFieldConnection });
    document.body.appendChild(element);
    await flush();
    expect(one(element, 'error').textContent).toContain('No access.');
  });
});
