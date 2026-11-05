// The test wire adapters below are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import Toast from 'lightning/toast';
import BarnConfirmModal from 'c/barnConfirmModal';
import HouseholdMergeSplit from 'c/householdMergeSplit';
import canEdit from '@salesforce/apex/HouseholdMergeController.canEdit';
import getPreview from '@salesforce/apex/HouseholdMergeController.preview';
import mergeHouseholds from '@salesforce/apex/HouseholdMergeController.mergeHouseholds';
import splitHousehold from '@salesforce/apex/HouseholdMergeController.splitHousehold';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';
import { EnclosingTabId, getTabInfo, openSubtab, refreshTab } from 'lightning/platformWorkspaceApi';
import { clearHelpTextForTest, setHelpTextForTest } from 'c/barnHelpText';
import { comparisonRows, householdPickerFilter, splitColumns } from '../mergeSplitModel';

const MESSAGES = {
  Core_HouseholdMerge_CustomNameKept:
    "The name you chose is kept as this household's own name; the naming automation will not change it. Clear Custom Name on the household if you want it to follow the members again.",
  Core_HouseholdMerge_ConfirmBody: '{0} will be combined into {1}.'
};

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

// Stubbed to real-looking wording so a test can check the sentence reached the toast; jest's
// default stub for a label is just its API name, which would never contain "Custom Name".

// Stubbed as the "{0} ... {1}" template so a test can check both names reach the confirm dialog.

jest.mock('@salesforce/label/c.Core_Shared_MoveTo', () => ({ default: 'Move to {0}' }), {
  virtual: true
});

const HOUSEHOLD_ID = '001000000000001AAA';
const OTHER_HOUSEHOLD_ID = '001000000000002AAA';
const TARGET_HOUSEHOLD_ID = '001000000000003AAA';
const HOUSEHOLD_TYPE_ID = '012000000000001AAA';
const MARIA_ID = '003000000000001AAA';
const WEI_ID = '003000000000002AAA';

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

const SWAPPED_PREVIEW = {
  ...PREVIEW,
  survivorId: OTHER_HOUSEHOLD_ID,
  survivorName: 'Garcia Household',
  victimId: HOUSEHOLD_ID,
  victimName: 'The Garcia Family',
  fields: PREVIEW.fields.map((field) => ({
    ...field,
    survivorValue: field.victimValue,
    victimValue: field.survivorValue
  })),
  members: PREVIEW.members.map((member) => ({ ...member, fromSurvivor: !member.fromSurvivor }))
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
      RecordType: { value: { fields: { DeveloperName: { value: developerName } } } },
      RecordTypeId: { value: HOUSEHOLD_TYPE_ID },
      Name: { value: 'The Garcia Family' }
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

/** Picks a household in a record picker, the way lightning-record-picker reports it. */
async function pick(element, selector, recordId) {
  element.shadowRoot
    .querySelector(selector)
    .dispatchEvent(new CustomEvent('change', { detail: { recordId } }));
  await flush();
  await flush();
}

/** Picks the other household, then presses Merge and lets the confirm answer. */
async function mergeFlow(element) {
  await pick(element, '.merge-picker', OTHER_HOUSEHOLD_ID);
  element.shadowRoot.querySelector('.merge-button').dispatchEvent(new CustomEvent('click'));
  await settle();
}

async function tick(element, index) {
  const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
  checkboxes[index].checked = true;
  checkboxes[index].dispatchEvent(new CustomEvent('change'));
  await flush();
}

function chooseExisting(element) {
  element.shadowRoot
    .querySelector('.destination-choice')
    .dispatchEvent(new CustomEvent('change', { detail: { value: 'Existing' } }));
  return flush();
}

describe('c-household-merge-split', () => {
  beforeEach(() => {
    BarnConfirmModal.open.mockResolvedValue(true);
    jest.spyOn(Toast, 'show');
    setHelpTextForTest({
      ...MESSAGES,
      Core_HouseholdMerge_StaysIn: 'Stays in {0}',
      Core_HouseholdMerge_MovesTo: 'Moves to {0}',
      Core_HouseholdMerge_PlaceNew: 'a New Household',
      Core_HouseholdMerge_PlaceChosen: 'the Household You Choose',
      Core_Drag_Dropped: 'Moved {0} to {1}.'
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    clearHelpTextForTest();
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

  it('offers households only, with their city, in a record picker (people-giving-1, 17)', async () => {
    const element = await openOn('Household', true);
    const picker = element.shadowRoot.querySelector('.merge-picker');

    expect(picker.objectApiName).toBe('Account');
    expect(picker.filter).toEqual(householdPickerFilter(HOUSEHOLD_TYPE_ID, HOUSEHOLD_ID));
    expect(picker.displayInfo.additionalFields).toEqual(['BillingCity']);
    expect(element.shadowRoot.querySelector('.swap-button')).toBeNull();
  });

  it('compares the two households after one is picked', async () => {
    getPreview.mockResolvedValue(PREVIEW);
    const element = await openOn('Household', true);

    await pick(element, '.merge-picker', OTHER_HOUSEHOLD_ID);

    expect(getPreview).toHaveBeenCalledWith({
      survivorId: HOUSEHOLD_ID,
      victimId: OTHER_HOUSEHOLD_ID
    });
    const rows = element.shadowRoot.querySelectorAll('.comparison-row');
    expect(rows.length).toBe(2);
    const table = element.shadowRoot.querySelector('.comparison-table');
    expect(table.getAttribute('aria-label')).toBeTruthy();
    expect(table.classList).toContain('slds-max-medium-table_stacked');
    expect(element.shadowRoot.querySelectorAll('.field-choice').length).toBe(1);
    expect(element.shadowRoot.querySelectorAll('.merge-member').length).toBe(2);
    expect(element.shadowRoot.querySelector('.swap-button')).not.toBeNull();
  });

  it('clears the comparison when the picker is cleared', async () => {
    getPreview.mockResolvedValue(PREVIEW);
    const element = await openOn('Household', true);
    await pick(element, '.merge-picker', OTHER_HOUSEHOLD_ID);
    await pick(element, '.merge-picker', null);

    expect(element.shadowRoot.querySelectorAll('.comparison-row').length).toBe(0);
    expect(element.shadowRoot.querySelector('.select-other')).not.toBeNull();
  });

  it('shows a spinner while the merge preview is loading', async () => {
    let resolvePreview;
    getPreview.mockReturnValue(
      new Promise((resolve) => {
        resolvePreview = resolve;
      })
    );
    const element = await openOn('Household', true);

    expect(element.shadowRoot.querySelector('.loading-spinner')).toBeNull();
    element.shadowRoot
      .querySelector('.merge-picker')
      .dispatchEvent(new CustomEvent('change', { detail: { recordId: OTHER_HOUSEHOLD_ID } }));
    await flush();

    expect(element.shadowRoot.querySelector('.loading-spinner')).not.toBeNull();

    resolvePreview(PREVIEW);
    await settle();

    expect(element.shadowRoot.querySelector('.loading-spinner')).toBeNull();
  });

  it('asks for confirmation and then merges with the values chosen', async () => {
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockResolvedValue({ survivorId: HOUSEHOLD_ID, customNameKept: false });
    const element = await openOn('Household', true);
    await pick(element, '.merge-picker', OTHER_HOUSEHOLD_ID);

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

  it('keeps the other household instead: the roles swap and the page goes to the one kept', async () => {
    getPreview.mockResolvedValueOnce(PREVIEW).mockResolvedValueOnce(SWAPPED_PREVIEW);
    mergeHouseholds.mockResolvedValue({ survivorId: OTHER_HOUSEHOLD_ID, customNameKept: false });
    const element = await openOn('Household', true);
    await pick(element, '.merge-picker', OTHER_HOUSEHOLD_ID);
    const swap = element.shadowRoot.querySelector('.swap-button');
    expect(swap.label).toBe('c.Core_HouseholdMerge_KeepOtherInstead');

    swap.dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(getPreview).toHaveBeenLastCalledWith({
      survivorId: OTHER_HOUSEHOLD_ID,
      victimId: HOUSEHOLD_ID
    });
    expect(element.shadowRoot.querySelector('.swap-button').label).toBe(
      'c.Core_HouseholdMerge_KeepThisInstead'
    );
    // The columns stay This Household, then The Other Household.
    expect(element.shadowRoot.querySelector('.this-value').textContent).toBe('The Garcia Family');
    expect(element.shadowRoot.querySelector('.other-value').textContent).toBe('Garcia Household');

    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);
    element.shadowRoot.querySelector('.merge-button').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(BarnConfirmModal.open.mock.calls[0][0].message).toBe(
      'The Garcia Family will be combined into Garcia Household.'
    );
    expect(mergeHouseholds).toHaveBeenCalledWith({
      survivorId: OTHER_HOUSEHOLD_ID,
      victimId: HOUSEHOLD_ID,
      fieldChoices: {}
    });
    expect(closed).toHaveBeenCalled();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__recordPage',
      attributes: { recordId: OTHER_HOUSEHOLD_ID, objectApiName: 'Account', actionName: 'view' }
    });
  });

  it('does not merge when the confirmation is cancelled or dismissed', async () => {
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
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockResolvedValue({ survivorId: HOUSEHOLD_ID, customNameKept: false });
    const element = await openOn('Household', true);

    await mergeFlow(element);

    expect(Toast.show).toHaveBeenCalledTimes(1);
    expect(Toast.show.mock.calls[0][0].variant).toBe('success');
    expect(Toast.show.mock.calls[0][0].label).not.toMatch(/Custom Name/);
  });

  it('tells the person in the success toast when their chosen name is now held as a custom one', async () => {
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockResolvedValue({ survivorId: HOUSEHOLD_ID, customNameKept: true });
    const element = await openOn('Household', true);

    await mergeFlow(element);

    expect(Toast.show).toHaveBeenCalledTimes(1);
    expect(Toast.show.mock.calls[0][0].label).toMatch(/Custom Name/);
  });

  it('shows the message when a merge is refused, and leaves the action open', async () => {
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockRejectedValue({
      body: { message: 'Both records must be households.' }
    });
    const element = await openOn('Household', true);
    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);

    await mergeFlow(element);

    const notice = element.shadowRoot.querySelector('c-barn-notice.merge-error');
    expect(notice.variant).toBe('error');
    expect(notice.message).toBe('Both records must be households.');
    expect(closed).not.toHaveBeenCalled();
  });

  describe('split board (Drag and Drop 3)', () => {
    function columns(element) {
      return Array.from(element.shadowRoot.querySelectorAll('[data-drop-zone]'));
    }

    function namesIn(column) {
      return Array.from(column.querySelectorAll('[data-drag-id]')).map(
        (tile) => tile.dataset.dragLabel
      );
    }

    it('shows who stays and who moves in two columns, with a checkbox in each tile', async () => {
      const element = await openOn('Household', true);
      const [stays, moves] = columns(element);

      expect(stays.dataset.dropZone).toBe('stays');
      expect(stays.querySelector('.split-column-heading').textContent).toContain(
        'Stays in The Garcia Family'
      );
      expect(moves.querySelector('.split-column-heading').textContent).toContain(
        'Moves to a New Household'
      );
      expect(namesIn(stays)).toEqual(['Maria Garcia', 'Wei Lee']);
      expect(namesIn(moves)).toEqual([]);

      await tick(element, 1);
      const [staysAfter, movesAfter] = columns(element);
      expect(namesIn(staysAfter)).toEqual(['Maria Garcia']);
      expect(namesIn(movesAfter)).toEqual(['Wei Lee']);
      expect(movesAfter.querySelector('.member-checkbox').checked).toBe(true);
    });

    it('moves a tile with its Move menu and announces it', async () => {
      const element = await openOn('Household', true);
      const menu = element.shadowRoot.querySelectorAll('.move-menu')[1];
      expect(menu.alternativeText).toBe('Move to a New Household');

      menu.dispatchEvent(new CustomEvent('select', { detail: { value: 'move' } }));
      await flush();

      expect(namesIn(columns(element)[1])).toEqual(['Wei Lee']);
      expect(element.shadowRoot.querySelector('.split-announcer').textContent).toBe(
        'Moved Wei Lee to a New Household.'
      );
    });

    it('marks every tile as draggable by pointer and keyboard', async () => {
      const element = await openOn('Household', true);
      const tile = element.shadowRoot.querySelector('[data-drag-id]');

      expect(tile.getAttribute('tabindex')).toBe('0');
      expect(tile.getAttribute('aria-describedby')).toBeTruthy();
      expect(element.shadowRoot.querySelector('[aria-live="polite"]')).not.toBeNull();
    });

    it('names the chosen household in the Moves column', async () => {
      const element = await openOn('Household', true);
      await chooseExisting(element);

      expect(columns(element)[1].querySelector('.split-column-heading').textContent).toContain(
        'Moves to the Household You Choose'
      );
    });
  });

  it('splits the people ticked into a new household', async () => {
    splitHousehold.mockResolvedValue(TARGET_HOUSEHOLD_ID);
    const element = await openOn('Household', true);

    expect(element.shadowRoot.querySelectorAll('.member-checkbox').length).toBe(2);
    await tick(element, 1);

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
    await tick(element, 1);

    element.shadowRoot.querySelector('.split-button').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(splitHousehold).not.toHaveBeenCalled();
  });

  it('splits into a household that already exists when one is chosen', async () => {
    splitHousehold.mockResolvedValue(TARGET_HOUSEHOLD_ID);
    const element = await openOn('Household', true);
    await tick(element, 1);
    await chooseExisting(element);

    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(true);
    await pick(element, '.split-picker', TARGET_HOUSEHOLD_ID);
    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(false);

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
    await tick(element, 0);

    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(false);
  });

  describe('when the action finishes', () => {
    async function merge(element) {
      await mergeFlow(element);
      await settle();
    }

    async function split(element) {
      await tick(element, 1);
      element.shadowRoot.querySelector('.split-button').dispatchEvent(new CustomEvent('click'));
      await settle();
    }

    beforeEach(() => {
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

  describe('mergeSplitModel', () => {
    it('keeps the This and Other columns in place when the roles swap', () => {
      const labels = { keepThis: 'This', keepOther: 'Other' };
      const [row] = comparisonRows(SWAPPED_PREVIEW.fields, true, labels);
      expect(row.thisValue).toBe('The Garcia Family');
      expect(row.otherValue).toBe('Garcia Household');
      expect(row.options).toEqual([
        { label: 'This', value: 'Victim' },
        { label: 'Other', value: 'Survivor' }
      ]);
      expect(comparisonRows(null, false, labels)).toEqual([]);
    });

    it('marks the drag target column and the dragged tile', () => {
      const [stays, moves] = splitColumns(MEMBERS, {
        active: true,
        itemId: WEI_ID,
        fromZone: 'stays',
        overZone: 'moves'
      });
      expect(moves.isTarget).toBe(true);
      expect(stays.isTarget).toBe(false);
      expect(stays.tiles[1].isDragging).toBe(true);
      expect(householdPickerFilter(undefined, undefined)).toEqual({
        criteria: [{ fieldPath: 'RecordTypeId', operator: 'eq', value: '' }]
      });
    });
  });
});
