import { createElement } from 'lwc';
import RollupInstantTotals from 'c/rollupInstantTotals';
import getStates from '@salesforce/apex/RollupInstantTotals.getStates';
import getState from '@salesforce/apex/RollupInstantTotals.getState';
import getCode from '@salesforce/apex/RollupInstantTotals.getCode';
import setTurnedOn from '@salesforce/apex/RollupInstantTotals.setTurnedOn';

jest.mock('@salesforce/apex/RollupInstantTotals.getStates', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupInstantTotals.getState', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupInstantTotals.getCode', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupInstantTotals.setTurnedOn', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_InstantStatusOn',
  () => ({ default: 'On: the trigger {0} updates these totals at once.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_InstantCount',
  () => ({ default: '{0} instant rollups count this object.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_InstantTurnedOff',
  () => ({ default: 'Instant totals on {0} are turned off.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_RollupBuilder_InstantCopied', () => ({ default: 'Copied.' }), {
  virtual: true
});

const SHIFT = {
  objectApiName: 'Shift__c',
  objectLabel: 'Shift',
  status: 'notSetUp',
  triggerName: 'BarnRollup_Shift_c',
  testClassName: 'BarnRollup_Shift_c_Test',
  instantRollups: 2
};
const ON = {
  objectApiName: 'Visit__c',
  objectLabel: 'Visit',
  status: 'on',
  triggerName: 'BarnRollup_Visit_c',
  testClassName: 'BarnRollup_Visit_c_Test',
  instantRollups: 1
};
const BUILT_IN = { ...ON, objectApiName: 'Contact', objectLabel: 'Contact', status: 'builtIn' };
const CODE = {
  triggerName: 'BarnRollup_Shift_c',
  testClassName: 'BarnRollup_Shift_c_Test',
  triggerSource: 'trigger BarnRollup_Shift_c on Shift__c (...) { RollupInstantTrigger.run(); }',
  testSource: '@IsTest private class BarnRollup_Shift_c_Test {}',
  deployPackage: 'UEsDBA==',
  removalPackage: 'UEsFBg=='
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function build(props) {
  const element = createElement('c-rollup-instant-totals', { is: RollupInstantTotals });
  Object.assign(element, props);
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, id) => Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));
const query = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-rollup-instant-totals', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists each object with its state and only the actions that state allows', async () => {
    getStates.mockResolvedValue([SHIFT, ON]);
    const element = await build({ canManage: true });

    const statuses = all(element, 'status').map((node) => node.textContent);
    expect(statuses[1]).toBe('On: the trigger BarnRollup_Visit_c updates these totals at once.');
    expect(all(element, 'count')[0].textContent).toBe('2 instant rollups count this object.');
    expect(all(element, 'turn-on').map((node) => node.dataset.object)).toEqual(['Shift__c']);
    expect(all(element, 'turn-off').map((node) => node.dataset.object)).toEqual(['Visit__c']);
    expect(all(element, 'remove').map((node) => node.dataset.object)).toEqual(['Visit__c']);
  });

  it('shows nothing when no instant rollup counts another object', async () => {
    getStates.mockResolvedValue([]);
    const element = await build({});
    expect(element.shadowRoot.querySelector('section')).toBeNull();
  });

  it('opens the steps, the code and the deploy package for an object', async () => {
    getStates.mockResolvedValue([SHIFT]);
    getCode.mockResolvedValue(CODE);
    const element = await build({ canManage: true });

    query(element, 'turn-on').click();
    await flush();

    expect(getCode).toHaveBeenCalledWith({ objectApiName: 'Shift__c' });
    expect(query(element, 'setup')).not.toBeNull();
    expect(query(element, 'trigger-source').textContent).toBe(CODE.triggerSource);
    expect(query(element, 'test-source').textContent).toBe(CODE.testSource);
    const download = query(element, 'download-deploy');
    expect(download.getAttribute('href')).toBe('data:application/zip;base64,UEsDBA==');
    expect(download.getAttribute('download')).toBe('BarnRollup_Shift_c.zip');
    expect(query(element, 'deploy-command').textContent).toContain(
      '--test-level RunSpecifiedTests --tests BarnRollup_Shift_c_Test'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="setup"] li')).toHaveLength(5);

    query(element, 'close').click();
    await flush();
    expect(query(element, 'setup')).toBeNull();
  });

  it('copies the code to the clipboard', async () => {
    getStates.mockResolvedValue([SHIFT]);
    getCode.mockResolvedValue(CODE);
    const writeText = jest.fn().mockResolvedValue();
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
    const element = await build({ canManage: true });
    query(element, 'turn-on').click();
    await flush();

    query(element, 'copy-test').click();
    await flush();

    expect(writeText).toHaveBeenCalledWith(CODE.testSource);
    expect(query(element, 'notice').textContent).toBe('Copied.');
  });

  it('turns instant totals off with no deploy and says so', async () => {
    getStates.mockResolvedValue([ON]);
    setTurnedOn.mockResolvedValue({ ...ON, status: 'off' });
    const element = await build({ canManage: true });

    query(element, 'turn-off').click();
    await flush();

    expect(setTurnedOn).toHaveBeenCalledWith({ objectApiName: 'Visit__c', turnedOn: false });
    expect(query(element, 'notice').textContent).toBe('Instant totals on Visit are turned off.');
    expect(query(element, 'turn-off')).toBeNull();
    expect(query(element, 'turn-on')).not.toBeNull();
  });

  it('gives the removal package and command', async () => {
    getStates.mockResolvedValue([ON]);
    getCode.mockResolvedValue({ ...CODE, triggerName: 'BarnRollup_Visit_c' });
    const element = await build({ canManage: true });

    query(element, 'remove').click();
    await flush();

    expect(query(element, 'download-removal').getAttribute('download')).toBe(
      'BarnRollup_Visit_c_Removal.zip'
    );
    expect(query(element, 'removal-command').textContent).toContain('--test-level RunLocalTests');
  });

  it('in step 5 shows the one counted object, and nothing for a built-in one', async () => {
    getState.mockResolvedValue(SHIFT);
    const element = await build({ objectApiName: 'Shift__c' });
    expect(getState).toHaveBeenCalledWith({ objectApiName: 'Shift__c' });
    expect(getStates).not.toHaveBeenCalled();
    expect(query(element, 'intro')).toBeNull();
    expect(query(element, 'turn-on')).not.toBeNull();

    getState.mockResolvedValue(BUILT_IN);
    element.objectApiName = 'Contact';
    await flush();
    expect(element.shadowRoot.querySelector('section')).toBeNull();
  });

  it('shows a refusal in plain words', async () => {
    getStates.mockRejectedValue({
      body: { message: 'You need the Manage BarnCRM Settings permission.' }
    });
    const element = await build({});
    expect(query(element, 'error').textContent).toBe(
      'You need the Manage BarnCRM Settings permission.'
    );
  });
});
