import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import BarnConfirmModal from 'c/barnConfirmModal';
import SampleDataManager from 'c/sampleDataManager';
import getStatus from '@salesforce/apex/SampleDataController.getStatus';
import loadSampleData from '@salesforce/apex/SampleDataController.loadSampleData';
import removeSampleData from '@salesforce/apex/SampleDataController.removeSampleData';
import canManageSampleData from '@salesforce/apex/SampleDataController.canManageSampleData';

jest.mock('@salesforce/apex/SampleDataController.getStatus', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SampleDataController.loadSampleData', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/SampleDataController.removeSampleData',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/SampleDataController.canManageSampleData',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const NOT_LOADED_STATUS = {
  householdCount: 0,
  contactCount: 0,
  organizationCount: 0,
  relationshipCount: 0,
  affiliationCount: 0,
  moduleCounts: [],
  loaded: false,
  loading: false,
  junctionMembership: false
};

// An org with Giving installed: Core's own five numbers, then the module's own tile,
// labelled by the module rather than by this component.
const LOADED_STATUS = {
  householdCount: 200,
  contactCount: 440,
  organizationCount: 25,
  relationshipCount: 60,
  affiliationCount: 80,
  moduleCounts: [{ name: 'Giving', label: 'Gifts', recordCount: 709 }],
  loaded: true,
  loading: false,
  junctionMembership: false
};

// The card has exactly two buttons, Load then Remove (see sampleDataManager.html); each asks
// for confirmation in c/barnConfirmModal, whose answer a test sets on BarnConfirmModal.open.
const LOAD_BUTTON_INDEX = 0;
const REMOVE_BUTTON_INDEX = 1;

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

// For tests under jest.useFakeTimers(): a real setTimeout never fires, so drain
// microtasks directly instead of using flushPromises.
async function flushMicrotasks() {
  for (let i = 0; i < 6; i += 1) {
    await Promise.resolve();
  }
}

function createManager() {
  const element = createElement('c-sample-data-manager', { is: SampleDataManager });
  document.body.appendChild(element);
  return element;
}

function buttons(element) {
  return element.shadowRoot.querySelectorAll('lightning-button');
}

describe('c-sample-data-manager', () => {
  beforeEach(() => {
    BarnConfirmModal.open.mockResolvedValue(true);
    jest.spyOn(Toast, 'show');
  });

  afterEach(() => {
    jest.clearAllMocks();
    jest.useRealTimers();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the read-only message when the user cannot manage sample data', async () => {
    canManageSampleData.mockResolvedValue(false);
    getStatus.mockResolvedValue(NOT_LOADED_STATUS);

    const element = createManager();
    await flushPromises();

    const readOnly = element.shadowRoot.querySelector('.slds-text-color_weak');
    expect(readOnly).not.toBeNull();
    expect(buttons(element).length).toBe(0);
  });

  it('says how sample data arrives in a junction membership org, and still offers it', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue({ ...NOT_LOADED_STATUS, junctionMembership: true });

    const element = createManager();
    await flushPromises();

    expect(element.shadowRoot.querySelector('[data-id="junction-mode-note"]')).not.toBeNull();
    expect(buttons(element)[LOAD_BUTTON_INDEX].disabled).toBe(false);
  });

  it('leaves the junction note out of a contact membership org', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue(NOT_LOADED_STATUS);

    const element = createManager();
    await flushPromises();

    expect(element.shadowRoot.querySelector('[data-id="junction-mode-note"]')).toBeNull();
  });

  it('shows Load enabled and Remove disabled when nothing is loaded', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue(NOT_LOADED_STATUS);

    const element = createManager();
    await flushPromises();

    const actionButtons = buttons(element);
    expect(actionButtons.length).toBe(2);
    expect(actionButtons[LOAD_BUTTON_INDEX].disabled).toBe(false);
    expect(actionButtons[REMOVE_BUTTON_INDEX].disabled).toBe(true);
  });

  it('shows Remove enabled once sample data is loaded', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue(LOADED_STATUS);

    const element = createManager();
    await flushPromises();

    const actionButtons = buttons(element);
    expect(actionButtons[LOAD_BUTTON_INDEX].disabled).toBe(true);
    expect(actionButtons[REMOVE_BUTTON_INDEX].disabled).toBe(false);
  });

  it('disables both actions while a load is running', async () => {
    jest.useFakeTimers();
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue({
      householdCount: 200,
      contactCount: 120,
      organizationCount: 25,
      loaded: false,
      loading: true
    });

    const element = createManager();
    await flushMicrotasks();

    const actionButtons = buttons(element);
    expect(actionButtons[LOAD_BUTTON_INDEX].disabled).toBe(true);
    // Removing mid-chain would delete the households the next contact chunk needs.
    expect(actionButtons[REMOVE_BUTTON_INDEX].disabled).toBe(true);
  });

  it('shows the counts once loaded', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue(LOADED_STATUS);

    const element = createManager();
    await flushPromises();

    const headings = element.shadowRoot.querySelectorAll('.slds-text-heading_medium');
    const values = Array.from(headings).map((el) => el.textContent);
    expect(values).toEqual(['200', '440', '25', '60', '80', '709']);
  });

  it('shows a tile for each module sample set, labelled by the module', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue(LOADED_STATUS);

    const element = createManager();
    await flushPromises();

    const captions = Array.from(element.shadowRoot.querySelectorAll('.slds-text-body_small')).map(
      (el) => el.textContent
    );
    expect(captions[captions.length - 1]).toBe('Gifts');
  });

  it('shows only the Core numbers in an org with no module sample data', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue({ ...LOADED_STATUS, moduleCounts: [] });

    const element = createManager();
    await flushPromises();

    const headings = element.shadowRoot.querySelectorAll('.slds-text-heading_medium');
    expect(Array.from(headings).map((el) => el.textContent)).toEqual([
      '200',
      '440',
      '25',
      '60',
      '80'
    ]);
  });

  it('asks for confirmation before loading, then calls the Apex load method', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue(NOT_LOADED_STATUS);
    loadSampleData.mockResolvedValue();

    const element = createManager();
    await flushPromises();

    buttons(element)[LOAD_BUTTON_INDEX].click();
    await flushPromises();

    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        label: 'c.Core_SampleData_LoadConfirmTitle',
        message: 'c.Core_SampleData_LoadConfirmBody'
      })
    );
    expect(loadSampleData).toHaveBeenCalledTimes(1);
  });

  it('cancelling the confirmation does not call Apex', async () => {
    BarnConfirmModal.open.mockResolvedValue(false);
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue(NOT_LOADED_STATUS);

    const element = createManager();
    await flushPromises();

    buttons(element)[LOAD_BUTTON_INDEX].click();
    await flushPromises();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
    expect(loadSampleData).not.toHaveBeenCalled();
    expect(buttons(element).length).toBe(2);
  });

  it('polls status every 3 seconds while a load is running', async () => {
    jest.useFakeTimers();
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue({
      householdCount: 50,
      contactCount: 100,
      organizationCount: 10,
      loaded: false,
      loading: true
    });

    createManager();
    await flushMicrotasks();
    expect(getStatus).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(3000);
    await flushMicrotasks();
    expect(getStatus).toHaveBeenCalledTimes(2);

    jest.advanceTimersByTime(3000);
    await flushMicrotasks();
    expect(getStatus).toHaveBeenCalledTimes(3);
  });

  it('stops polling once status reports the load is no longer running', async () => {
    jest.useFakeTimers();
    canManageSampleData.mockResolvedValue(true);
    getStatus
      .mockResolvedValueOnce({
        householdCount: 50,
        contactCount: 100,
        organizationCount: 10,
        loaded: false,
        loading: true
      })
      .mockResolvedValue(LOADED_STATUS);

    createManager();
    await flushMicrotasks();
    expect(getStatus).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(3000);
    await flushMicrotasks();
    expect(getStatus).toHaveBeenCalledTimes(2);

    jest.advanceTimersByTime(3000);
    await flushMicrotasks();
    // No further polling once loading is false.
    expect(getStatus).toHaveBeenCalledTimes(2);
  });

  it('removes sample data after confirmation', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue(LOADED_STATUS);
    removeSampleData.mockResolvedValue({
      householdCount: 200,
      contactCount: 440,
      organizationCount: 25
    });

    const element = createManager();
    await flushPromises();

    buttons(element)[REMOVE_BUTTON_INDEX].click();
    await flushPromises();

    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ label: 'c.Core_SampleData_RemoveConfirmTitle' })
    );
    expect(removeSampleData).toHaveBeenCalledTimes(1);
    expect(Toast.show).toHaveBeenCalledWith(
      { label: 'c.Core_SampleData_RemoveSuccess', message: '', variant: 'success' },
      expect.anything()
    );
  });

  it('shows an error toast when removing fails', async () => {
    canManageSampleData.mockResolvedValue(true);
    getStatus.mockResolvedValue(LOADED_STATUS);
    removeSampleData.mockRejectedValue({ body: { message: 'Locked row' } });

    const element = createManager();
    await flushPromises();

    buttons(element)[REMOVE_BUTTON_INDEX].click();
    await flushPromises();

    expect(Toast.show).toHaveBeenCalledWith(
      expect.objectContaining({ label: 'c.Core_SampleData_RemoveError', variant: 'error' }),
      expect.anything()
    );
  });
});
