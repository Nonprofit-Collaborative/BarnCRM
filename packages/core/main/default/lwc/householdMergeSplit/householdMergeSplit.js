import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import Toast from 'lightning/toast';
import BarnConfirmModal from 'c/barnConfirmModal';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { openInWorkspace, refreshEnclosingTab } from 'c/workspaceTabs';
import { createDragController } from 'c/barnDrag';
import { dragInstructions, dragMessages } from 'c/barnDragText';
import canEdit from '@salesforce/apex/HouseholdMergeController.canEdit';
import getPreview from '@salesforce/apex/HouseholdMergeController.preview';
import mergeHouseholds from '@salesforce/apex/HouseholdMergeController.mergeHouseholds';
import splitHousehold from '@salesforce/apex/HouseholdMergeController.splitHousehold';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';
import {
  comparisonRows,
  householdPickerFilter,
  splitColumns,
  STAYS,
  MOVES
} from './mergeSplitModel';

import TITLE from '@salesforce/label/c.Core_HouseholdMerge_Title';
import TAB_MERGE from '@salesforce/label/c.Core_HouseholdMerge_MergeButton';
import TAB_SPLIT from '@salesforce/label/c.Core_HouseholdMerge_SplitButton';
import SEARCH_LABEL from '@salesforce/label/c.Core_HouseholdMerge_SearchLabel';
import COMPARISON_TABLE from '@salesforce/label/c.Core_HouseholdMerge_ComparisonTable';
import COLUMN_FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import COLUMN_THIS from '@salesforce/label/c.Core_HouseholdMerge_ColumnThis';
import COLUMN_OTHER from '@salesforce/label/c.Core_HouseholdMerge_ColumnOther';
import MEMBERS_HEADING from '@salesforce/label/c.Core_HouseholdMerge_MembersHeading';
import KEEP_THIS from '@salesforce/label/c.Core_HouseholdMerge_KeepSurvivor';
import KEEP_OTHER from '@salesforce/label/c.Core_HouseholdMerge_KeepVictim';
import KEEP_OTHER_INSTEAD from '@salesforce/label/c.Core_HouseholdMerge_KeepOtherInstead';
import KEEP_THIS_INSTEAD from '@salesforce/label/c.Core_HouseholdMerge_KeepThisInstead';
import MEMBER_FROM_THIS from '@salesforce/label/c.Core_HouseholdMerge_MemberFromThis';
import MEMBER_FROM_OTHER from '@salesforce/label/c.Core_HouseholdMerge_MemberFromOther';
import MERGE_BUTTON from '@salesforce/label/c.Core_HouseholdMerge_MergeButton';
import CONFIRM_HEADING from '@salesforce/label/c.Core_HouseholdMerge_ConfirmHeading';
import CONFIRM_BODY from '@salesforce/label/c.Core_HouseholdMerge_ConfirmBody';
import CONFIRM_BUTTON from '@salesforce/label/c.Core_Duplicates_MergeButton';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import MERGE_SUCCESS from '@salesforce/label/c.Core_HouseholdMerge_Success';
import CUSTOM_NAME_KEPT from '@salesforce/label/c.Core_HouseholdMerge_CustomNameKept';
import READ_ONLY from '@salesforce/label/c.Core_HouseholdMerge_ReadOnly';
import NOT_A_HOUSEHOLD from '@salesforce/label/c.Core_HouseholdMerge_NotAHousehold';
import SPLIT_HEADING from '@salesforce/label/c.Core_HouseholdMerge_SplitHeading';
import SPLIT_NEW from '@salesforce/label/c.Core_HouseholdMerge_SplitNewHousehold';
import SPLIT_EXISTING from '@salesforce/label/c.Core_HouseholdMerge_SplitExistingHousehold';
import SPLIT_BUTTON from '@salesforce/label/c.Core_HouseholdMerge_SplitButton';
import SPLIT_CONFIRM_BODY from '@salesforce/label/c.Core_HouseholdMerge_SplitConfirmBody';
import SPLIT_CONFIRM_HEADING from '@salesforce/label/c.Core_HouseholdMerge_SplitConfirmHeading';
import SPLIT_SUCCESS from '@salesforce/label/c.Core_HouseholdMerge_SplitSuccess';
import MOVE_TO from '@salesforce/label/c.Core_Shared_MoveTo';
import LOADING_COMPARISON from '@salesforce/label/c.Core_HouseholdScreens_LoadingComparison';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const RECORD_TYPE_FIELD = 'Account.RecordType.DeveloperName';
const RECORD_TYPE_ID_FIELD = 'Account.RecordTypeId';
const NAME_FIELD = 'Account.Name';
const HOUSEHOLD = 'Household';
const NEW_HOUSEHOLD = 'New';
const EXISTING_HOUSEHOLD = 'Existing';

/**
 * Merge or Split Households, on a household page or as its quick action.
 *
 * Merge: the other household is chosen with a record picker limited to households, showing
 * each one's city (people-giving-1, 17). This household is kept by default; Keep the Other
 * Household Instead swaps the roles, so someone who opened the duplicate does not have to
 * start over.
 *
 * Split: two columns, Stays in {household} and Moves to {new or chosen household}, with a
 * tile per member (Drag and Drop 3). A tile moves by its checkbox (ticked = moves), by its
 * Move menu, or by dragging it (c/barnDrag: pointer, touch press and hold, or keyboard), and
 * every move is announced.
 */
export default class HouseholdMergeSplit extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  @api recordId;

  label = {
    title: TITLE,
    tabMerge: TAB_MERGE,
    tabSplit: TAB_SPLIT,
    searchLabel: SEARCH_LABEL,
    get selectOther() {
      return helpText('Core', 'Core_HouseholdMerge_SelectOther');
    },
    comparisonTable: COMPARISON_TABLE,
    columnField: COLUMN_FIELD,
    columnThis: COLUMN_THIS,
    columnOther: COLUMN_OTHER,
    membersHeading: MEMBERS_HEADING,
    mergeButton: MERGE_BUTTON,
    readOnly: READ_ONLY,
    notAHousehold: NOT_A_HOUSEHOLD,
    splitHeading: SPLIT_HEADING,
    splitNew: SPLIT_NEW,
    splitExisting: SPLIT_EXISTING,
    splitButton: SPLIT_BUTTON,
    loadingComparison: LOADING_COMPARISON
  };

  recordTypeName;
  householdRecordTypeId;
  householdName;
  canEditThis = false;
  errorMessage;
  busy = false;

  otherHouseholdId;
  /** True when the other household is the one kept (Keep the Other Household Instead). */
  swapped = false;
  preview;

  @track comparison = [];
  @track mergeMembers = [];
  choices = {};

  @track splitMembers = [];
  splitDestination = NEW_HOUSEHOLD;
  splitTargetId;
  splitTargetName;

  liveText = '';
  dragState;
  drag;

  @wire(EnclosingTabId) enclosingTabId;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.drag = createDragController({
      root: this.template,
      layout: 'columns',
      // Read when spoken, not now: the help catalog may still be on its way.
      messages: {
        pickedUp: (name) => dragMessages().pickedUp(name),
        position: (zone, position, count) => dragMessages().position(zone, position, count),
        dropped: (name, zone) => dragMessages().dropped(name, zone),
        cancelled: (name) => dragMessages().cancelled(name)
      },
      announce: (text) => {
        this.liveText = text;
      },
      onChange: (state) => {
        this.dragState = state;
      },
      onDrop: ({ itemId, fromZone, toZone }) => {
        if (fromZone === toZone) {
          return false;
        }
        this.setMoves(itemId, toZone === MOVES);
        return true;
      }
    });
  }

  disconnectedCallback() {
    if (this.drag) {
      this.drag.destroy();
    }
  }

  @wire(getRecord, {
    recordId: '$recordId',
    fields: [RECORD_TYPE_FIELD, RECORD_TYPE_ID_FIELD, NAME_FIELD]
  })
  wiredAccount({ data, error }) {
    if (data) {
      const recordType = data.fields.RecordType;
      this.recordTypeName =
        recordType && recordType.value ? recordType.value.fields.DeveloperName.value : undefined;
      this.householdRecordTypeId = data.fields.RecordTypeId
        ? data.fields.RecordTypeId.value
        : undefined;
      this.householdName = data.fields.Name ? data.fields.Name.value : undefined;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(getRecord, { recordId: '$splitTargetId', fields: [NAME_FIELD] })
  wiredSplitTarget({ data }) {
    this.splitTargetName = data && data.fields.Name ? data.fields.Name.value : undefined;
  }

  @wire(canEdit, { householdId: '$recordId' })
  wiredCanEdit({ data, error }) {
    if (data !== undefined) {
      this.canEditThis = data === true;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(getMembers, { householdId: '$recordId' })
  wiredMembers({ data, error }) {
    if (data) {
      this.splitMembers = data.map((member) => ({ ...member, selected: false }));
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  // ---------------------------------------------------------------- state

  get isHousehold() {
    return this.recordTypeName === HOUSEHOLD;
  }

  get showReadOnlyNotice() {
    return this.isHousehold && !this.canEditThis;
  }

  get isUsable() {
    return this.isHousehold && this.canEditThis;
  }

  /** Households only, never this one: the picker offers nothing else to merge with. */
  get householdFilter() {
    return householdPickerFilter(this.householdRecordTypeId, this.recordId);
  }

  /** Each household with its city, so two Garcia households are told apart (people-giving-1). */
  get householdDisplayInfo() {
    return { additionalFields: ['BillingCity'] };
  }

  get householdMatchingInfo() {
    return {
      primaryField: { fieldPath: 'Name' },
      additionalFields: [{ fieldPath: 'BillingCity' }]
    };
  }

  get hasComparison() {
    return this.comparison.length > 0;
  }

  get swapLabel() {
    return this.swapped ? KEEP_THIS_INSTEAD : KEEP_OTHER_INSTEAD;
  }

  /** What is kept and what is folded in, for the confirm dialog: the preview names both. */
  get confirmBody() {
    const preview = this.preview || {};
    return CONFIRM_BODY.replace('{0}', preview.victimName || '').replace(
      '{1}',
      preview.survivorName || ''
    );
  }

  get selectedPersonIds() {
    return this.splitMembers.filter((member) => member.selected).map((member) => member.personId);
  }

  get canSplit() {
    if (this.selectedPersonIds.length === 0) {
      return false;
    }
    return this.splitDestination === NEW_HOUSEHOLD ? true : !!this.splitTargetId;
  }

  get isSplittingToExisting() {
    return this.splitDestination === EXISTING_HOUSEHOLD;
  }

  get cannotSplit() {
    return this.busy || !this.canSplit;
  }

  get destinationOptions() {
    return [
      { label: this.label.splitNew, value: NEW_HOUSEHOLD },
      { label: this.label.splitExisting, value: EXISTING_HOUSEHOLD }
    ];
  }

  /** Where a tile in each column ends up: this household, or the new or chosen one. */
  get placeNames() {
    let moves;
    if (!this.isSplittingToExisting) {
      moves = helpText('Core', 'Core_HouseholdMerge_PlaceNew');
    } else {
      moves = this.splitTargetName || helpText('Core', 'Core_HouseholdMerge_PlaceChosen');
    }
    return { [STAYS]: this.householdName || '', [MOVES]: moves };
  }

  get staysHeading() {
    return helpText('Core', 'Core_HouseholdMerge_StaysIn', this.placeNames[STAYS]);
  }

  get movesHeading() {
    return helpText('Core', 'Core_HouseholdMerge_MovesTo', this.placeNames[MOVES]);
  }

  get dragHelp() {
    return dragInstructions();
  }

  /** The two columns with their tiles, the drag highlight and each tile's Move menu item. */
  get splitBoard() {
    const columns = splitColumns(this.splitMembers, this.dragState);
    const headings = { [STAYS]: this.staysHeading, [MOVES]: this.movesHeading };
    const places = this.placeNames;
    return columns.map((column) => {
      const otherPlace = places[column.id === STAYS ? MOVES : STAYS];
      return {
        ...column,
        heading: headings[column.id],
        place: places[column.id],
        headingId: `split-heading-${column.id}`,
        zoneClass:
          'split-column slds-box slds-box_x-small slds-var-p-around_small' +
          (column.isTarget ? ' split-column_target' : ''),
        tiles: column.tiles.map((tile) => ({
          ...tile,
          tileClass:
            'slds-item split-member split-tile slds-var-m-bottom_x-small' +
            (tile.isDragging ? ' split-tile_dragging' : ''),
          moveLabel: MOVE_TO.replace('{0}', otherPlace)
        }))
      };
    });
  }

  // ---------------------------------------------------------------- merge

  handleOtherHouseholdChange(event) {
    const chosenId = event.detail ? event.detail.recordId : undefined;
    this.otherHouseholdId = chosenId || undefined;
    this.swapped = false;
    if (!this.otherHouseholdId) {
      this.preview = undefined;
      this.comparison = [];
      this.mergeMembers = [];
      return undefined;
    }
    return this.loadPreview();
  }

  /** Keep the Other Household Instead, and back: the same two households, roles swapped. */
  handleSwap() {
    this.swapped = !this.swapped;
    return this.loadPreview();
  }

  get survivorId() {
    return this.swapped ? this.otherHouseholdId : this.recordId;
  }

  get victimId() {
    return this.swapped ? this.recordId : this.otherHouseholdId;
  }

  loadPreview() {
    this.busy = true;
    return getPreview({ survivorId: this.survivorId, victimId: this.victimId })
      .then((preview) => {
        this.preview = preview;
        this.choices = {};
        this.comparison = comparisonRows(preview.fields, this.swapped, {
          keepThis: KEEP_THIS,
          keepOther: KEEP_OTHER
        });
        this.mergeMembers = preview.members.map((member) => {
          const fromThis = member.fromSurvivor !== this.swapped;
          return {
            ...member,
            origin: fromThis ? MEMBER_FROM_THIS : MEMBER_FROM_OTHER,
            originStatus: fromThis ? 'neutral' : 'info'
          };
        });
        this.errorMessage = undefined;
      })
      .catch((error) => {
        this.comparison = [];
        this.mergeMembers = [];
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleChoiceChange(event) {
    const fieldName = event.target.dataset.fieldName;
    const value = event.detail.value;
    this.choices = { ...this.choices, [fieldName]: value };
    this.comparison = this.comparison.map((field) => {
      return field.fieldName === fieldName ? { ...field, selected: value } : field;
    });
  }

  async handleMergeClick() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: CONFIRM_HEADING,
      message: this.confirmBody,
      confirmLabel: CONFIRM_BUTTON,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive'
    });
    return confirmed ? this.merge() : undefined;
  }

  merge() {
    this.busy = true;
    const swapped = this.swapped;
    return mergeHouseholds({
      survivorId: this.survivorId,
      victimId: this.victimId,
      fieldChoices: this.choices
    })
      .then((result) => {
        this.errorMessage = undefined;
        // The person is not told anywhere else that choosing a name during a merge locks
        // it against the naming automation, so the success message is where that is said.
        const message = result.customNameKept
          ? `${MERGE_SUCCESS} ${CUSTOM_NAME_KEPT}`
          : MERGE_SUCCESS;
        this.toast(message, 'success');
        if (swapped) {
          // This household no longer exists: go straight to the one that was kept.
          this.dispatchEvent(new CloseActionScreenEvent());
          this.goTo(result.survivorId);
          return undefined;
        }
        return this.finish(result.survivorId);
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  // ---------------------------------------------------------------- split

  handleMemberToggle(event) {
    this.setMoves(event.target.dataset.personId, event.target.checked);
  }

  /** The tile's Move menu: the keyboard, screen reader and phone way to change column. */
  handleMoveMenu(event) {
    const personId = event.target.dataset.personId;
    const member = this.splitMembers.find((candidate) => candidate.personId === personId);
    if (!member) {
      return;
    }
    this.setMoves(personId, !member.selected);
    const place = this.placeNames[member.selected ? STAYS : MOVES];
    this.liveText = dragMessages().dropped(member.name, place);
  }

  setMoves(personId, moves) {
    this.splitMembers = this.splitMembers.map((member) => {
      return member.personId === personId ? { ...member, selected: moves } : member;
    });
  }

  handleDragPointerDown(event) {
    this.drag.pointerDown(event);
  }

  handleDragKeyDown(event) {
    this.drag.keyDown(event);
  }

  handleDestinationChange(event) {
    this.splitDestination = event.detail.value;
    this.splitTargetId = undefined;
    this.splitTargetName = undefined;
  }

  /**
   * The destination of a split is chosen the same way the other household in a merge is, so
   * that only households are ever offered and an organization cannot be picked by accident.
   * The household being split is left out.
   */
  handleSplitTargetChange(event) {
    const chosenId = event.detail ? event.detail.recordId : undefined;
    this.splitTargetId = chosenId || undefined;
    if (!this.splitTargetId) {
      this.splitTargetName = undefined;
    }
  }

  async handleSplitClick() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: SPLIT_CONFIRM_HEADING,
      message: SPLIT_CONFIRM_BODY,
      confirmLabel: SPLIT_BUTTON,
      cancelLabel: CANCEL
    });
    return confirmed ? this.split() : undefined;
  }

  split() {
    this.busy = true;
    return splitHousehold({
      householdId: this.recordId,
      personIds: this.selectedPersonIds,
      targetHouseholdId: this.splitDestination === NEW_HOUSEHOLD ? null : this.splitTargetId
    })
      .then((destinationId) => {
        this.errorMessage = undefined;
        this.toast(SPLIT_SUCCESS, 'success');
        return this.finish(destinationId);
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  // ---------------------------------------------------------------- helpers

  /**
   * After a merge or split: close the quick action if this runs in one (a no-op on a record
   * page) and show that this household changed. In a console its tab is refreshed in place;
   * everywhere else LDS and the page are told (its header and the members panel otherwise
   * stay stale until a reload). The page moves only when the action ended on another
   * household, since a merge ends on the page it started from: in a console a split's other
   * household opens beside it as a subtab, elsewhere the page goes to it.
   */
  async finish(recordId) {
    const refreshedTab = await refreshEnclosingTab(this);
    this.dispatchEvent(new CloseActionScreenEvent());
    if (!refreshedTab) {
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      this.dispatchEvent(new RefreshEvent());
    }
    if (!recordId || recordId === this.recordId) {
      return;
    }
    if (!refreshedTab || !(await openInWorkspace(this, { recordId }))) {
      this.goTo(recordId);
    }
  }

  goTo(recordId) {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId, objectApiName: 'Account', actionName: 'view' }
    });
  }

  toast(message, variant) {
    Toast.show({ label: message, variant }, this);
  }

  readError(error) {
    if (!error) {
      return undefined;
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message;
  }
}
