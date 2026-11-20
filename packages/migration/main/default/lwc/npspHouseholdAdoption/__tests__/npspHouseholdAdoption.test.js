import { createElement } from 'lwc';
import NpspHouseholdAdoption from 'c/npspHouseholdAdoption';
import BarnConfirmModal from 'c/barnConfirmModal';
import getStatus from '@salesforce/apex/NpspHouseholdAdoptionController.getStatus';
import adopt from '@salesforce/apex/NpspHouseholdAdoptionController.adopt';
import undo from '@salesforce/apex/NpspHouseholdAdoptionController.undo';

jest.mock(
  '@salesforce/apex/NpspHouseholdAdoptionController.getStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/NpspHouseholdAdoptionController.adopt',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/NpspHouseholdAdoptionController.undo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('c/jobPoller', () => ({ startPolling: jest.fn(() => jest.fn()) }));

const READY = {
  available: true,
  blockedReason: null,
  running: false,
  candidateCount: 2,
  moreThanLimit: false,
  runLimit: 48000,
  sample: [
    {
      accountId: '001A',
      name: 'Smith Household',
      formalGreeting: 'Ms. Ann Smith and Mr. Bob Smith',
      informalGreeting: 'Ann and Bob',
      primaryContactName: 'Ann Smith',
      contactCount: 2
    }
  ],
  lastRun: null
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(status) {
  getStatus.mockResolvedValue(status);
  const element = createElement('c-npsp-household-adoption', { is: NpspHouseholdAdoption });
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-npsp-household-adoption', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the count, the sample and an enabled Adopt button', async () => {
    const element = await render(READY);
    expect(find(element, 'candidates')).not.toBeNull();
    expect(find(element, 'sample').querySelectorAll('tbody tr')).toHaveLength(1);
    expect(find(element, 'keep-names').checked).toBe(true);
    expect(find(element, 'adopt').disabled).toBe(false);
    expect(find(element, 'last-run')).toBeNull();
  });

  it('adopts the confirmed count, keeping names unless cleared', async () => {
    BarnConfirmModal.open.mockResolvedValue(true);
    adopt.mockResolvedValue('run-1');
    const element = await render(READY);
    const keep = find(element, 'keep-names');
    keep.checked = false;
    keep.dispatchEvent(new CustomEvent('change'));
    find(element, 'adopt').click();
    await flush();
    await flush();
    const dialog = BarnConfirmModal.open.mock.calls[0][0];
    expect(dialog.typeToConfirm).toBe('2');
    expect(adopt).toHaveBeenCalledWith({ keepNames: false, confirmedCount: 2 });
    expect(find(element, 'notice')).not.toBeNull();
  });

  it('does nothing when the confirmation is cancelled', async () => {
    BarnConfirmModal.open.mockResolvedValue(false);
    const element = await render(READY);
    find(element, 'adopt').click();
    await flush();
    expect(adopt).not.toHaveBeenCalled();
  });

  it('disables Adopt and says why when a run is blocked', async () => {
    const element = await render({ ...READY, blockedReason: 'Set membership to Contact.' });
    expect(find(element, 'blocked').message).toBe('Set membership to Contact.');
    expect(find(element, 'adopt').disabled).toBe(true);
  });

  it('says so when the org has no NPSP households', async () => {
    const element = await render({ ...READY, available: false, candidateCount: 0, sample: [] });
    expect(find(element, 'not-available')).not.toBeNull();
    expect(find(element, 'adopt')).toBeNull();
  });

  it('undoes the newest run with its count', async () => {
    BarnConfirmModal.open.mockResolvedValue(true);
    undo.mockResolvedValue(undefined);
    const element = await render({
      ...READY,
      candidateCount: 0,
      sample: [],
      lastRun: {
        runId: 'run-1',
        adoptedAt: '2026-11-02T10:00:00Z',
        adopted: 3,
        undone: 0,
        notRestored: 0
      }
    });
    expect(find(element, 'none-left')).not.toBeNull();
    find(element, 'undo').click();
    await flush();
    await flush();
    expect(BarnConfirmModal.open.mock.calls[0][0].typeToConfirm).toBe('3');
    expect(undo).toHaveBeenCalledWith({ runId: 'run-1', confirmedCount: 3 });
  });

  it('shows the server refusal', async () => {
    BarnConfirmModal.open.mockResolvedValue(true);
    adopt.mockRejectedValue({ body: { message: 'An adoption or undo is already running.' } });
    const element = await render(READY);
    find(element, 'adopt').click();
    await flush();
    await flush();
    expect(find(element, 'error').message).toBe('An adoption or undo is already running.');
  });

  it('shows a running run and refreshes on request', async () => {
    const element = await render({ ...READY, running: true });
    expect(find(element, 'running')).not.toBeNull();
    expect(find(element, 'adopt').disabled).toBe(true);
    await element.refresh();
    expect(getStatus).toHaveBeenCalledTimes(2);
  });
});
