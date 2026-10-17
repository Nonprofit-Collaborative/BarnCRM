// The test wire adapters below are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import Toast from 'lightning/toast';
import BarnConfirmModal from 'c/barnConfirmModal';
import HouseholdMergeSplit from 'c/householdMergeSplit';
import canEdit from '@salesforce/apex/HouseholdMergeController.canEdit';
import searchHouseholds from '@salesforce/apex/HouseholdMergeController.searchHouseholds';
import getPreview from '@salesforce/apex/HouseholdMergeController.preview';
import mergeHouseholds from '@salesforce/apex/HouseholdMergeController.mergeHouseholds';
import splitHousehold from '@salesforce/apex/HouseholdMergeController.splitHousehold';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';
import { EnclosingTabId, getTabInfo, openSubtab, refreshTab } from 'lightning/platformWorkspaceApi';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdMergeController.canEdit',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdController.getMembers',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdMergeController.searchHouseholds',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdMergeController.preview',
  () => ({ default: jest.fn(() => Promise.resolve({ fields: [], members: [] })) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdMergeController.mergeHouseholds',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdMergeController.splitHousehold',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

// The real label is a translatable "{0}, {1}" template; jest does not evaluate label content,
// so it is stubbed here the same way the template renders in an org.
jest.mock(
  '@salesforce/label/c.Core_HouseholdScreens_ResultAccessibleName',
  () => ({ default: '{0}, {1}' }),
  { virtual: true }
);

// Stubbed to real-looking wording so a test can check the sentence reached the toast; jest's
// default stub for a label is just its API name, which would never contain "Custom Name".
jest.mock(
  '@salesforce/label/c.Core_HouseholdMerge_CustomNameKept',
  () => ({
    default:
      "The name you chose is kept as this household's own name; the naming automation will not change it. Clear Custom Name on the household if you want it to follow the members again."
  }),
  { virtual: true }
);

// Stubbed as the "{0} ... {1}" template so a test can check both names reach the confirm dialog.
jest.mock(
  '@salesforce/label/c.Core_HouseholdMerge_ConfirmBody',
  () => ({ default: '{0} will be combined into {1}.' }),
  { virtual: true }
);

const HOUSEHOLD_ID = '001000000000001AAA';
const OTHER_HOUSEHOLD_ID = '001000000000002AAA';
const TARGET_HOUSEHOLD_ID = '001000000000003AAA';
const MARIA_ID = '003000000000001AAA';
const WEI_ID = '003000000000002AAA';

const SEARCH_RESULTS = [
  { id: OTHER_HOUSEHOLD_ID, name: 'Garcia Household', memberCount: 1, location: 'Oakland, CA' }
];

const PREVIEW = {
  survivorId: HOUSEHOLD_ID,
  survivorName: 'The Garcia Family',
  victimId: OTHER_HOUSEHOLD_ID,
  victimName: 'Garcia Household',
  canEdit: true,
  fields: [
    {
      fieldName: 'Name',
      label: 'Account Name',
      survivorValue: 'The Garcia Family',
      victimValue: 'Garcia Household',
      inConflict: true
    },
    {
      fieldName: 'BillingCity',
      label: 'Billing City',
      survivorValue: 'Oakland',
      victimValue: 'Oakland',
      inConflict: false
    }
  ],
  members: [
    { personId: MARIA_ID, name: 'Maria Garcia', role: 'Head', fromSurvivor: true },
    { personId: WEI_ID, name: 'Wei Lee', role: 'Spouse or Partner', fromSurvivor: false }
  ]
};

const MEMBERS = [
  { personId: MARIA_ID, name: 'Maria Garcia', role: 'Head', isPrimary: true, isDeceased: false },
  {
    personId: WEI_ID,
    name: 'Wei Lee',
    role: 'Spouse or Partner',
    isPrimary: false,
    isDeceased: false
  }
];

function recordOfType(developerName) {
  return {
    fields: {
      RecordType: { value: { fields: { DeveloperName: { value: developerName } } } }
    }
  };
}

function flush() {
  return Promise.resolve();
}

function build() {
  const element = createElement('c-household-merge-split', { is: HouseholdMergeSplit });
  element.recordId = HOUSEHOLD_ID;
  document.body.appendChild(element);
  return element;
}

async function openOn(recordType, editable) {
  const element = build();
  getRecord.emit(recordOfType(recordType));
  canEdit.emit(editable);
  getMembers.emit(MEMBERS);
  await flush();
  return element;
}

async function settle() {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await flush();
  }
}

/** Searches, picks the other household, then presses Merge and lets the confirm answer. */
async function mergeFlow(element) {
  element.shadowRoot.querySelector('.search-button').dispatchEvent(new CustomEvent('click'));
  await flush();
  await flush();
  element.shadowRoot.querySelector('.pick-button').dispatchEvent(new CustomEvent('click'));
  await flush();
  await flush();
  element.shadowRoot.querySelector('.merge-button').dispatchEvent(new CustomEvent('click'));
  await settle();
}

describe('c-household-merge-split', () => {
  beforeEach(() => {
    BarnConfirmModal.open.mockResolvedValue(true);
    jest.spyOn(Toast, 'show');
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says so politely on a record that is not a household', async () => {
    const element = await openOn('Organization', true);

    expect(element.shadowRoot.querySelector('.not-a-household')).not.toBeNull();
    expect(element.shadowRoot.querySelector('lightning-tabset')).toBeNull();
  });

  it('shows a read only notice and no actions when the person cannot edit', async () => {
    const element = await openOn('Household', false);

    expect(element.shadowRoot.querySelector('.read-only-notice')).not.toBeNull();
    expect(element.shadowRoot.querySelector('lightning-tabset')).toBeNull();
  });

  it('compares the two households after one is picked from the search', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    const element = await openOn('Household', true);

    element.shadowRoot.querySelector('.search-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();

    const results = element.shadowRoot.querySelectorAll('.search-result');
    expect(results.length).toBe(1);

    element.shadowRoot.querySelector('.pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();

    expect(getPreview).toHaveBeenCalledWith({
      survivorId: HOUSEHOLD_ID,
      victimId: OTHER_HOUSEHOLD_ID
    });
    const rows = element.shadowRoot.querySelectorAll('.comparison-row');
    expect(rows.length).toBe(2);
    const table = element.shadowRoot.querySelector('.comparison-table');
    expect(table.getAttribute('aria-label')).toBeTruthy();
    const choices = element.shadowRoot.querySelectorAll('.field-choice');
    expect(choices.length).toBe(1);
    expect(element.shadowRoot.querySelectorAll('.merge-member').length).toBe(2);
  });

  it('gives a search result button an accessible name that includes the location, since duplicate households can share a name', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    const element = await openOn('Household', true);

    element.shadowRoot.querySelector('.search-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();

    const pickButton = element.shadowRoot.querySelector('.pick-button');
    expect(pickButton.getAttribute('aria-label')).toBe('Garcia Household, Oakland, CA');
  });

  it('shows a spinner while the merge preview is loading', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    let resolvePreview;
    getPreview.mockReturnValue(
      new Promise((resolve) => {
        resolvePreview = resolve;
      })
    );
    const element = await openOn('Household', true);

    element.shadowRoot.querySelector('.search-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();

    expect(element.shadowRoot.querySelector('.loading-spinner')).toBeNull();
    element.shadowRoot.querySelector('.pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(element.shadowRoot.querySelector('.loading-spinner')).not.toBeNull();

    resolvePreview(PREVIEW);
    await flush();
    await flush();
    await flush();
    await flush();

    expect(element.shadowRoot.querySelector('.loading-spinner')).toBeNull();
  });

  it('asks for confirmation and then merges with the values chosen', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockResolvedValue({ survivorId: HOUSEHOLD_ID, customNameKept: false });
    const element = await openOn('Household', true);

    element.shadowRoot.querySelector('.search-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();
    element.shadowRoot.querySelector('.pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();

    element.shadowRoot
      .querySelector('.field-choice')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Victim' } }));
    await flush();

    element.shadowRoot.querySelector('.merge-button').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
    const dialog = BarnConfirmModal.open.mock.calls[0][0];
    expect(dialog.message).toBe('Garcia Household will be combined into The Garcia Family.');
    expect(dialog.confirmVariant).toBe('destructive');
    expect(mergeHouseholds).toHaveBeenCalledWith({
      survivorId: HOUSEHOLD_ID,
      victimId: OTHER_HOUSEHOLD_ID,
      fieldChoices: { Name: 'Victim' }
    });
  });

  it('does not merge when the confirmation is cancelled or dismissed', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    BarnConfirmModal.open.mockResolvedValueOnce(false).mockResolvedValueOnce(undefined);
    const element = await openOn('Household', true);

    await mergeFlow(element);
    element.shadowRoot.querySelector('.merge-button').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(2);
    expect(mergeHouseholds).not.toHaveBeenCalled();
  });

  it('closes the quick action and refreshes the household after a merge, without navigating to the page it is on', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockResolvedValue({ survivorId: HOUSEHOLD_ID, customNameKept: false });
    const element = await openOn('Household', true);
    const closed = jest.fn();
    const refreshed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);
    element.addEventListener('lightning__refresh', refreshed);

    await mergeFlow(element);

    expect(closed).toHaveBeenCalledTimes(1);
    expect(refreshed).toHaveBeenCalledTimes(1);
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: HOUSEHOLD_ID }]);
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('does not mention Custom Name in the success toast when the survivor keeps an ordinary name', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockResolvedValue({ survivorId: HOUSEHOLD_ID, customNameKept: false });
    const element = await openOn('Household', true);

    await mergeFlow(element);

    expect(Toast.show).toHaveBeenCalledTimes(1);
    expect(Toast.show.mock.calls[0][0].variant).toBe('success');
    expect(Toast.show.mock.calls[0][0].label).not.toMatch(/Custom Name/);
  });

  it('tells the person in the success toast when their chosen name is now held as a custom one', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockResolvedValue({ survivorId: HOUSEHOLD_ID, customNameKept: true });
    const element = await openOn('Household', true);

    await mergeFlow(element);

    expect(Toast.show).toHaveBeenCalledTimes(1);
    expect(Toast.show.mock.calls[0][0].label).toMatch(/Custom Name/);
  });

  it('shows the message when a merge is refused, and leaves the action open', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockRejectedValue({
      body: { message: 'Both records must be households.' }
    });
    const element = await openOn('Household', true);
    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);

    await mergeFlow(element);

    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain(
      'Both records must be households.'
    );
    expect(closed).not.toHaveBeenCalled();
  });

  it('splits the people ticked into a new household', async () => {
    splitHousehold.mockResolvedValue(TARGET_HOUSEHOLD_ID);
    const element = await openOn('Household', true);

    const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
    expect(checkboxes.length).toBe(2);
    checkboxes[1].checked = true;
    checkboxes[1].dispatchEvent(new CustomEvent('change'));
    await flush();

    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);
    element.shadowRoot.querySelector('.split-button').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
    expect(splitHousehold).toHaveBeenCalledWith({
      householdId: HOUSEHOLD_ID,
      personIds: [WEI_ID],
      targetHouseholdId: null
    });
    // The split-off household is another record, so the person is taken there.
    expect(closed).toHaveBeenCalledTimes(1);
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: HOUSEHOLD_ID }]);
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__recordPage',
      attributes: { recordId: TARGET_HOUSEHOLD_ID, objectApiName: 'Account', actionName: 'view' }
    });
  });

  it('does not split when the confirmation is cancelled', async () => {
    BarnConfirmModal.open.mockResolvedValueOnce(false);
    const element = await openOn('Household', true);
    const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
    checkboxes[1].checked = true;
    checkboxes[1].dispatchEvent(new CustomEvent('change'));
    await flush();

    element.shadowRoot.querySelector('.split-button').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(splitHousehold).not.toHaveBeenCalled();
  });

  it('splits into a household that already exists when one is chosen', async () => {
    splitHousehold.mockResolvedValue(TARGET_HOUSEHOLD_ID);
    searchHouseholds.mockResolvedValue([
      { id: TARGET_HOUSEHOLD_ID, name: 'Lee Household', memberCount: 2, location: 'Oakland, CA' }
    ]);
    const element = await openOn('Household', true);

    const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
    checkboxes[1].checked = true;
    checkboxes[1].dispatchEvent(new CustomEvent('change'));
    await flush();

    element.shadowRoot
      .querySelector('.destination-choice')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Existing' } }));
    await flush();

    element.shadowRoot
      .querySelector('.split-search-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();
    element.shadowRoot.querySelector('.split-pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    element.shadowRoot.querySelector('.split-button').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(splitHousehold).toHaveBeenCalledWith({
      householdId: HOUSEHOLD_ID,
      personIds: [WEI_ID],
      targetHouseholdId: TARGET_HOUSEHOLD_ID
    });
  });

  it('will not split until somebody is ticked', async () => {
    const element = await openOn('Household', true);

    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(true);

    const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
    checkboxes[0].checked = true;
    checkboxes[0].dispatchEvent(new CustomEvent('change'));
    await flush();

    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(false);
  });

  it('will not split into an existing household until one is picked', async () => {
    searchHouseholds.mockResolvedValue([
      { id: TARGET_HOUSEHOLD_ID, name: 'Lee Household', memberCount: 2, location: 'Oakland, CA' }
    ]);
    const element = await openOn('Household', true);

    const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
    checkboxes[1].checked = true;
    checkboxes[1].dispatchEvent(new CustomEvent('change'));
    await flush();
    element.shadowRoot
      .querySelector('.destination-choice')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Existing' } }));
    await flush();

    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(true);

    element.shadowRoot
      .querySelector('.split-search-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();
    element.shadowRoot.querySelector('.split-pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(element.shadowRoot.querySelector('.split-target-name').textContent).toBe(
      'Lee Household'
    );
    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(false);
  });

  describe('when the action finishes', () => {
    async function merge(element) {
      await mergeFlow(element);
      await settle();
    }

    async function split(element) {
      const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
      checkboxes[1].checked = true;
      checkboxes[1].dispatchEvent(new CustomEvent('change'));
      await flush();
      element.shadowRoot.querySelector('.split-button').dispatchEvent(new CustomEvent('click'));
      await settle();
    }

    beforeEach(() => {
      searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
      getPreview.mockResolvedValue(PREVIEW);
      mergeHouseholds.mockResolvedValue({ survivorId: HOUSEHOLD_ID, customNameKept: false });
      splitHousehold.mockResolvedValue(TARGET_HOUSEHOLD_ID);
    });

    it('refreshes the merged household in place outside a console', async () => {
      const element = await openOn('Household', true);
      const closeHandler = jest.fn();
      element.addEventListener('lightning__closeactionscreen', closeHandler);
      await merge(element);

      expect(refreshTab).not.toHaveBeenCalled();
      expect(closeHandler).toHaveBeenCalled();
      expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: HOUSEHOLD_ID }]);
      expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('refreshes the household tab after a merge in a console', async () => {
      const element = await openOn('Household', true);
      EnclosingTabId.emit('tab0');
      const closeHandler = jest.fn();
      element.addEventListener('lightning__closeactionscreen', closeHandler);
      await merge(element);

      expect(refreshTab).toHaveBeenCalledWith('tab0', { includeAllSubtabs: false });
      expect(closeHandler).toHaveBeenCalled();
      expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
      expect(openSubtab).not.toHaveBeenCalled();
      expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('goes to the other household outside a console after a split', async () => {
      const element = await openOn('Household', true);
      await split(element);

      expect(mockNavigate).toHaveBeenCalledWith({
        type: 'standard__recordPage',
        attributes: { recordId: TARGET_HOUSEHOLD_ID, objectApiName: 'Account', actionName: 'view' }
      });
    });

    it('refreshes the tab and opens the other household as a subtab after a split in a console', async () => {
      getTabInfo.mockResolvedValueOnce({ tabId: 'tab0', isSubtab: false });
      const element = await openOn('Household', true);
      EnclosingTabId.emit('tab0');
      await split(element);

      expect(refreshTab).toHaveBeenCalledWith('tab0', { includeAllSubtabs: false });
      expect(openSubtab).toHaveBeenCalledWith('tab0', {
        recordId: TARGET_HOUSEHOLD_ID,
        focus: true
      });
      expect(mockNavigate).not.toHaveBeenCalled();
    });
  });
});
