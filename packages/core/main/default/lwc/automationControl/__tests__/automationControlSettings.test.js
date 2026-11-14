import { createElement } from 'lwc';
import AutomationControl from 'c/automationControl';
import BarnConfirmModal from 'c/barnConfirmModal';
import getPage from '@salesforce/apex/AutomationControlController.getPage';
import saveControl from '@salesforce/apex/AutomationControlController.saveControl';
import addControl from '@salesforce/apex/AutomationControlController.addControl';
import removeControl from '@salesforce/apex/AutomationControlController.removeControl';
import addFlow from '@salesforce/apex/AutomationControlController.addFlow';
import removeFlow from '@salesforce/apex/AutomationControlController.removeFlow';
import catchUpNow from '@salesforce/apex/AutomationControlController.catchUpNow';
import { setHelpTextForTest } from 'c/barnHelpText';

setHelpTextForTest({
  Core_AutomationControl_PausedForEveryone: 'Pause All is on for the whole organization.',
  Core_AutomationControl_CatchUpStarted: 'Catching up has started.',
  Core_AutomationControl_NoFlowsToAdd: 'No active flow of your own is waiting to be listed.'
});

jest.mock(
  '@salesforce/apex/AutomationControlController.getPage',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AutomationControlController.saveControl',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AutomationControlController.addControl',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AutomationControlController.removeControl',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/AutomationControlController.addFlow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/AutomationControlController.removeFlow',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AutomationControlController.catchUpNow',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_AutomationControl_WholeOrganization',
  () => ({ default: 'Whole Organization' }),
  { virtual: true }
);

const ORG_ID = '00D000000000001AAA';
const PROFILE_ID = '00e000000000001AAA';

const PAGE = {
  paused: false,
  pausedUntil: null,
  canManage: true,
  pauseHourOptions: [1, 2, 4, 8, 24],
  pauseAllLabel: 'Pause All',
  bypassLabel: 'Bypass',
  pausedForEveryone: false,
  automations: [
    {
      recordId: 'a01000000000001AAA',
      automationName: 'Flow:My_Gift_Flow',
      label: 'My Gift Flow',
      description: 'Your own flow.',
      objectName: null,
      enabled: true,
      alwaysRuns: false,
      removable: true
    }
  ],
  controlRows: [
    { ownerId: ORG_ID, ownerName: null, level: 'Organization', pauseAll: false, bypass: false },
    {
      ownerId: PROFILE_ID,
      ownerName: 'Integration',
      level: 'Profile',
      pauseAll: false,
      bypass: true
    }
  ],
  profileOptions: [{ value: PROFILE_ID, label: 'Integration' }],
  flowOptions: [{ value: 'Other_Flow', label: 'Other Flow (Other_Flow)' }]
};

function build() {
  const element = createElement('c-automation-control', { is: AutomationControl });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function all(element, id) {
  return Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));
}

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-automation-control: Automation Control rows, own flows, Catch Up Now', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists Whole Organization first, then the profile, and only the profile can be removed', async () => {
    const element = build();
    getPage.emit(PAGE);
    await flush();

    const rows = all(element, 'control-row');
    expect(rows.map((row) => row.querySelector('th').textContent)).toEqual([
      'Whole Organization',
      'Integration'
    ]);
    expect(all(element, 'control-bypass').map((box) => box.checked)).toEqual([false, true]);
    expect(all(element, 'remove-control').map((button) => button.dataset.owner)).toEqual([
      PROFILE_ID
    ]);
    expect(one(element, 'paused-for-everyone')).toBeNull();
  });

  it('saves a box at once, with the other box of its row', async () => {
    saveControl.mockResolvedValue(PAGE);
    const element = build();
    getPage.emit(PAGE);
    await flush();

    const pauseAll = all(element, 'control-pause-all')[0];
    pauseAll.checked = true;
    pauseAll.dispatchEvent(new CustomEvent('change'));
    await flush();

    expect(saveControl).toHaveBeenCalledWith({ ownerId: ORG_ID, pauseAll: true, bypass: false });
  });

  it('puts the box back when the server refuses', async () => {
    saveControl.mockRejectedValue({ body: { message: 'You need Manage BarnCRM Settings.' } });
    const element = build();
    getPage.emit(PAGE);
    await flush();

    const bypass = all(element, 'control-bypass')[1];
    bypass.checked = false;
    bypass.dispatchEvent(new CustomEvent('change'));
    await flush();
    await flush();

    expect(bypass.checked).toBe(true);
    expect(one(element, 'error-message').textContent).toBe('You need Manage BarnCRM Settings.');
  });

  it('shows Pause All for everyone with a Turn Off that clears it', async () => {
    saveControl.mockResolvedValue(PAGE);
    const element = build();
    getPage.emit({
      ...PAGE,
      pausedForEveryone: true,
      controlRows: [{ ...PAGE.controlRows[0], pauseAll: true }, PAGE.controlRows[1]]
    });
    await flush();

    const notice = one(element, 'paused-for-everyone');
    expect(notice.message).toBe('Pause All is on for the whole organization.');
    notice.dispatchEvent(new CustomEvent('action'));
    await flush();

    expect(saveControl).toHaveBeenCalledWith({ ownerId: ORG_ID, pauseAll: false, bypass: false });
  });

  it('adds a profile row and removes one', async () => {
    addControl.mockResolvedValue(PAGE);
    removeControl.mockResolvedValue(PAGE);
    const element = build();
    getPage.emit(PAGE);
    await flush();

    expect(one(element, 'add-control-button').disabled).toBe(true);
    one(element, 'add-kind').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Profile' } })
    );
    await flush();
    one(element, 'add-profile').dispatchEvent(
      new CustomEvent('change', { detail: { value: PROFILE_ID } })
    );
    await flush();
    one(element, 'add-control-button').click();
    await flush();
    expect(addControl).toHaveBeenCalledWith({ ownerId: PROFILE_ID });

    BarnConfirmModal.open.mockResolvedValue(false);
    one(element, 'remove-control').click();
    await flush();
    expect(removeControl).not.toHaveBeenCalled();

    BarnConfirmModal.open.mockResolvedValue(true);
    one(element, 'remove-control').click();
    await flush();
    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ confirmVariant: 'destructive' })
    );
    expect(removeControl).toHaveBeenCalledWith({ ownerId: PROFILE_ID });
  });

  it('adds a user picked in the record picker', async () => {
    addControl.mockResolvedValue(PAGE);
    const element = build();
    getPage.emit(PAGE);
    await flush();

    one(element, 'add-user').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '005000000000001AAA' } })
    );
    await flush();
    one(element, 'add-control-button').click();
    await flush();

    expect(addControl).toHaveBeenCalledWith({ ownerId: '005000000000001AAA' });
  });

  it('lists a flow of your own and removes a listed one', async () => {
    addFlow.mockResolvedValue(PAGE);
    removeFlow.mockResolvedValue(PAGE);
    const element = build();
    getPage.emit(PAGE);
    await flush();

    one(element, 'flow-choice').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Other_Flow' } })
    );
    await flush();
    one(element, 'add-flow-button').click();
    await flush();
    expect(addFlow).toHaveBeenCalledWith({ apiName: 'Other_Flow' });

    BarnConfirmModal.open.mockResolvedValue(false);
    one(element, 'remove-flow').click();
    await flush();
    expect(removeFlow).not.toHaveBeenCalled();

    BarnConfirmModal.open.mockResolvedValue(true);
    one(element, 'remove-flow').click();
    await flush();
    expect(removeFlow).toHaveBeenCalledWith({ automationName: 'Flow:My_Gift_Flow' });
  });

  it('says when no flow is waiting to be listed', async () => {
    const element = build();
    getPage.emit({ ...PAGE, flowOptions: [] });
    await flush();

    expect(one(element, 'add-flow')).toBeNull();
    expect(one(element, 'no-flows').textContent).toBe(
      'No active flow of your own is waiting to be listed.'
    );
  });

  it('starts the catch-up and says so', async () => {
    catchUpNow.mockResolvedValue(PAGE);
    const element = build();
    getPage.emit(PAGE);
    await flush();

    one(element, 'catch-up-button').click();
    await flush();
    await flush();

    expect(catchUpNow).toHaveBeenCalled();
    expect(one(element, 'catch-up-started').message).toBe('Catching up has started.');
  });
});
