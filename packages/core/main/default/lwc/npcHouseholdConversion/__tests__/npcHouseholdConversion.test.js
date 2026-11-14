import { createElement } from 'lwc';
import NpcHouseholdConversion from 'c/npcHouseholdConversion';
import BarnConfirmModal from 'c/barnConfirmModal';
import getStatus from '@salesforce/apex/NpspHouseholdAdoptionController.getStatus';
import adopt from '@salesforce/apex/NpspHouseholdAdoptionController.adopt';

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
  candidateCount: 3,
  moreThanLimit: false,
  runLimit: 48000,
  sample: [
    {
      accountId: '001A',
      name: 'Lee Household',
      primaryContactName: 'Sam Lee',
      contactCount: 2
    }
  ],
  lastRun: null
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  getStatus.mockResolvedValue(READY);
  const element = createElement('c-npc-household-conversion', { is: NpcHouseholdConversion });
  document.body.appendChild(element);
  await flush();
  return element;
}

const panelOf = (element) => element.shadowRoot.querySelector('c-npsp-household-adoption');
const find = (element, id) => panelOf(element).shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-npc-household-conversion', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('asks Apex for the Nonprofit Cloud source and leaves the greeting columns out', async () => {
    const element = await render();
    expect(getStatus).toHaveBeenCalledWith({ source: 'NPC' });
    expect(find(element, 'sample').querySelectorAll('thead th')).toHaveLength(3);
    expect(find(element, 'sample').querySelectorAll('tbody td')).toHaveLength(2);
  });

  it('converts the confirmed count with the NPC source', async () => {
    BarnConfirmModal.open.mockResolvedValue(true);
    adopt.mockResolvedValue('NPC-1');
    const element = await render();
    find(element, 'adopt').click();
    await flush();
    await flush();
    expect(BarnConfirmModal.open.mock.calls[0][0].typeToConfirm).toBe('3');
    expect(adopt).toHaveBeenCalledWith({ source: 'NPC', keepNames: true, confirmedCount: 3 });
  });

  it('refreshes the panel when the console asks', async () => {
    const element = await render();
    await element.refresh();
    expect(getStatus).toHaveBeenCalledTimes(2);
  });
});
