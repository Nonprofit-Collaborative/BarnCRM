import { createElement } from 'lwc';
import CampaignSync from 'c/campaignSync';
import getStatus from '@salesforce/apex/CampaignSyncController.getStatus';
import syncAll from '@salesforce/apex/CampaignSyncController.syncAll';

jest.mock('@salesforce/apex/CampaignSyncController.getStatus', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CampaignSyncController.syncAll', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Connect_CampaignSync_Counts',
  () => ({ default: '{0} of {1} appeals have a Campaign.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Connect_CampaignSync_ErrorFailed',
  () => ({ default: 'Something went wrong.' }),
  { virtual: true }
);

const READY = {
  available: true,
  switchedOn: true,
  canSync: true,
  canManage: true,
  running: false,
  appealCount: 6,
  linkedCount: 2
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function mount(status) {
  getStatus.mockResolvedValue(status);
  const element = createElement('c-campaign-sync', { is: CampaignSync });
  document.body.appendChild(element);
  await flush();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-campaign-sync', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says what Campaign sync needs from Setup at the top of the page', async () => {
    const element = await mount(READY);
    const notes = element.shadowRoot.querySelector('c-settings-setup-notes');
    expect(notes.notes).toHaveLength(1);
    expect(notes.notes[0].where).toBe('c.Connect_SetupNote_CampaignSync_Where');
  });

  it('counts the appeals with a Campaign and offers Sync all appeals', async () => {
    const element = await mount(READY);
    expect(find(element, 'on')).not.toBeNull();
    expect(find(element, 'counts').textContent).toBe('2 of 6 appeals have a Campaign.');
    expect(find(element, 'sync-all').disabled).toBe(false);
    expect(find(element, 'no-access')).toBeNull();
  });

  it('says the cap with a plus past the count limit', async () => {
    const element = await mount({
      ...READY,
      appealCount: 10000,
      appealCountCapped: true,
      linkedCount: 2,
      linkedCountCapped: false
    });
    expect(find(element, 'counts').textContent).toBe('2 of 10000+ appeals have a Campaign.');
  });

  it('says so, and offers nothing, where the org has no Campaigns', async () => {
    const element = await mount({ ...READY, available: false });
    expect(find(element, 'unavailable')).not.toBeNull();
    expect(find(element, 'sync-all')).toBeNull();
  });

  it('points at the setting while Campaign sync is off', async () => {
    const element = await mount({ ...READY, switchedOn: false });
    expect(find(element, 'off')).not.toBeNull();
    expect(find(element, 'sync-all')).toBeNull();
  });

  it('explains why the button is off for someone without Campaign access', async () => {
    const element = await mount({ ...READY, canSync: false });
    expect(find(element, 'no-access')).not.toBeNull();
    expect(find(element, 'sync-all').disabled).toBe(true);
  });

  it('keeps the button off for someone who cannot manage settings', async () => {
    const element = await mount({ ...READY, canManage: false });
    expect(find(element, 'no-manage')).not.toBeNull();
    expect(find(element, 'sync-all').disabled).toBe(true);
  });

  it('starts the sync and says it is running', async () => {
    syncAll.mockResolvedValue({ ...READY, running: true });
    const element = await mount(READY);
    find(element, 'sync-all').click();
    await flush();
    expect(syncAll).toHaveBeenCalled();
    expect(find(element, 'running')).not.toBeNull();
    expect(find(element, 'sync-all').disabled).toBe(true);
  });

  it('shows the refusal the controller gives, in its own words', async () => {
    syncAll.mockRejectedValue({ body: { message: 'Only someone with permission.' } });
    const element = await mount(READY);
    find(element, 'sync-all').click();
    await flush();
    expect(find(element, 'error').textContent).toBe('Only someone with permission.');
  });

  it('falls back to a plain message when loading fails without one', async () => {
    getStatus.mockRejectedValue({});
    const element = createElement('c-campaign-sync', { is: CampaignSync });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').textContent).toBe('Something went wrong.');
  });
});
