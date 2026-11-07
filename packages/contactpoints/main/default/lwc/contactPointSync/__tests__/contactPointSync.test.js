import { createElement } from 'lwc';
import ContactPointSync from 'c/contactPointSync';
import getStatus from '@salesforce/apex/ContactPointSyncController.getStatus';
import runBackfill from '@salesforce/apex/ContactPointSyncController.runBackfill';

jest.mock('@salesforce/apex/ContactPointSyncController.getStatus', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ContactPointSyncController.runBackfill',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const READY = {
  kinds: [
    { kind: 'Email', ready: true, message: 'Email: copied after every save.' },
    { kind: 'Phone', ready: true, message: 'Phone: copied after every save.' },
    { kind: 'Address', ready: false, message: 'Address: turned off.' }
  ],
  anyReady: true,
  canRun: true,
  running: false,
  peopleCount: 251,
  peopleCountCapped: false,
  managedCount: 12,
  lastBackfill: null,
  lastSummary: null
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function render(status) {
  getStatus.mockResolvedValue(status);
  const element = createElement('c-contact-point-sync', { is: ContactPointSync });
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-contact-point-sync', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows each kind, the preview count and an enabled button', async () => {
    const element = await render(READY);
    const notices = find(element, 'kinds').querySelectorAll('c-barn-notice');
    expect(notices.length).toBe(3);
    expect(notices[2].variant).toBe('warning');
    expect(find(element, 'counts').textContent).toBe('c.ContactPoints_Page_Counts');
    expect(find(element, 'run').disabled).toBe(false);
    expect(find(element, 'no-manage')).toBeNull();
  });

  it('disables the button and explains when the person cannot manage settings', async () => {
    const element = await render({ ...READY, canRun: false });
    expect(find(element, 'run').disabled).toBe(true);
    expect(find(element, 'no-manage')).not.toBeNull();
  });

  it('disables the button while a backfill runs', async () => {
    const element = await render({ ...READY, running: true });
    expect(find(element, 'run').disabled).toBe(true);
    expect(find(element, 'running')).not.toBeNull();
  });

  it('starts the backfill and shows the status it returns', async () => {
    const element = await render(READY);
    runBackfill.mockResolvedValue({ ...READY, running: true });
    find(element, 'run').click();
    await flush();
    expect(runBackfill).toHaveBeenCalledTimes(1);
    expect(find(element, 'running')).not.toBeNull();
  });

  it('shows the refusal message when the backfill is refused', async () => {
    const element = await render(READY);
    runBackfill.mockRejectedValue({ body: { message: 'Nothing can be copied.' } });
    find(element, 'run').click();
    await flush();
    expect(find(element, 'error').message).toBe('Nothing can be copied.');
  });

  it('shows a general message when the status cannot load', async () => {
    getStatus.mockRejectedValue(new Error('offline'));
    const element = createElement('c-contact-point-sync', { is: ContactPointSync });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').message).toBe('c.ContactPoints_Page_Failed');
    expect(find(element, 'run')).toBeNull();
  });
});
