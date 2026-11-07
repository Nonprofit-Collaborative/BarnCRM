import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { followLinkInWorkspace } from 'c/workspaceTabs';
// Bare, and correctly so: a custom permission in the same package resolves without a prefix.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import DISMISSAL_OBJECT from '@salesforce/schema/Duplicate_Dismissal__c';
import getView from '@salesforce/apex/DuplicateController.getView';
import startScan from '@salesforce/apex/DuplicateController.startScan';
import dismissSuggestion from '@salesforce/apex/DuplicateController.dismiss';
import previewMerge from '@salesforce/apex/DuplicateController.previewMerge';
import mergeHouseholds from '@salesforce/apex/DuplicateController.mergeHouseholds';

import TITLE from '@salesforce/label/c.Core_Duplicates_Title';
import RULES_HEADING from '@salesforce/label/c.Core_Duplicates_RulesHeading';
import RULE_ACTIVE from '@salesforce/label/c.Core_Feature_On';
import RULE_INACTIVE from '@salesforce/label/c.Core_Feature_Off';
import ACTIVATE_LINK from '@salesforce/label/c.Core_Duplicates_ActivateLink';
import SCAN_BUTTON from '@salesforce/label/c.Core_Duplicates_ScanButton';
import LAST_SCAN from '@salesforce/label/c.Core_Duplicates_LastScan';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import STARTER_TITLE from '@salesforce/label/c.Core_DuplicateStarter_Title';
import SUGGESTIONS_HEADING from '@salesforce/label/c.Core_Duplicates_SuggestionsHeading';
import OBJECT_PERSON from '@salesforce/label/c.Core_Section_Person';
import OBJECT_HOUSEHOLD from '@salesforce/label/c.Core_Section_Household';
import COMPARE_MERGE from '@salesforce/label/c.Core_Duplicates_CompareMerge';
import MERGE_BUTTON from '@salesforce/label/c.Core_Duplicates_MergeButton';
import MERGE_HEADING from '@salesforce/label/c.Core_Duplicates_MergeHeading';
import MERGE_KEEP_LABEL from '@salesforce/label/c.Core_Duplicates_MergeKeepLabel';
import MERGE_KEEPING from '@salesforce/label/c.Core_Duplicates_MergeKeeping';
import MERGE_DROPPING from '@salesforce/label/c.Core_Duplicates_MergeDropping';
import MERGE_CONFIRM from '@salesforce/label/c.Core_Duplicates_MergeConfirm';
import DISMISS_BUTTON from '@salesforce/label/c.Core_Duplicates_DismissButton';
import DISMISS_HEADING from '@salesforce/label/c.Core_Duplicates_DismissButton';
import DISMISS_REASON_LABEL from '@salesforce/label/c.Core_Import_ResultsReason';
import DISMISSED_COUNT from '@salesforce/label/c.Core_Duplicates_DismissedCount';
import VIEW_DISMISSED from '@salesforce/label/c.Core_FieldUtilization_HistoryView';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import SHOW_MORE from '@salesforce/label/c.Core_AccessExplorer_ShowMore';
import EMPTY_HEADING from '@salesforce/label/c.Core_Duplicates_EmptyHeading';
import COUNT_ALT from '@salesforce/label/c.Core_Duplicates_CountAlt';
import DIFFERENT from '@salesforce/label/c.Core_Duplicates_Different';
import DIFFERENT_FROM from '@salesforce/label/c.Core_Duplicates_DifferentFrom';
import BLANK from '@salesforce/label/c.Core_Duplicates_Blank';
import NEW_TAB from '@salesforce/label/c.Core_Kit_NewTab';
import { setupPath } from 'c/setupLinks';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const SETUP_DUPLICATE_RULES = setupPath('duplicateRules');
const PAGE_SIZE = 10;

/**
 * The review list on the Duplicate Matching tab (C-20, ADR-0139).
 *
 * Everything it lists was found by the org's own duplicate rules, so the first thing it shows
 * is whether those rules are on: "nothing to review" while nothing is being checked would be
 * worse than no panel. Two households are merged here in a short dialog, with the household
 * merge C-09 ships; field by field choices stay on the household record's own merge screen.
 * Two people are merged with the platform's merge, from the person's record page.
 */
export default class DuplicateReview extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  labels = {
    newTab: NEW_TAB,
    title: TITLE,
    rulesHeading: RULES_HEADING,
    activateLink: ACTIVATE_LINK,
    get noRulesNotice() {
      return helpText('Core', 'Core_Duplicates_NoRulesNotice');
    },
    scanButton: SCAN_BUTTON,
    get scanRunning() {
      return helpText('Core', 'Core_Duplicates_ScanRunning');
    },
    lastScan: LAST_SCAN,
    refresh: REFRESH,
    suggestionsHeading: SUGGESTIONS_HEADING,
    get empty() {
      return helpText('Core', 'Core_Duplicates_Empty');
    },
    compareMerge: COMPARE_MERGE,
    merge: MERGE_BUTTON,
    mergeHeading: MERGE_HEADING,
    get mergeBody() {
      return helpText('Core', 'Core_Duplicates_MergeBody');
    },
    mergeKeepLabel: MERGE_KEEP_LABEL,
    get mergeFullScreen() {
      return helpText('Core', 'Core_Duplicates_MergeFullScreen');
    },
    mergeConfirm: MERGE_CONFIRM,
    dismiss: DISMISS_BUTTON,
    dismissHeading: DISMISS_HEADING,
    get dismissBody() {
      return helpText('Core', 'Core_Duplicates_DismissBody');
    },
    dismissReasonLabel: DISMISS_REASON_LABEL,
    dismissedCount: DISMISSED_COUNT,
    viewDismissed: VIEW_DISMISSED,
    get readOnly() {
      return helpText('Core', 'Core_Duplicates_ReadOnlyNotice');
    },
    get noAccess() {
      return helpText('Core', 'Core_Duplicates_NoAccessNotice');
    },
    cancel: CANCEL,
    showMore: SHOW_MORE,
    emptyHeading: EMPTY_HEADING,
    different: DIFFERENT
  };

  /** How many suggestions are shown; Show More adds a page. The server sends at most 50. */
  visibleCount = PAGE_SIZE;
  /** Set by Show More: the index of the first newly shown suggestion, focused after the render. */
  focusFrom;

  setupUrl = SETUP_DUPLICATE_RULES;
  starterOpen = false;
  starterLabel = STARTER_TITLE;

  view;
  errorMessage;
  noticeMessage;
  busy = false;

  dismissing;
  dismissReason = '';

  merging;
  mergePreview;
  keepId;
  previewRequest = 0;

  /** The data-id of the box heading already given focus, so it is focused once per opening. */
  focusedHeading;

  @wire(EnclosingTabId) enclosingTabId;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  /**
   * Moves focus to the heading of the dismiss or merge box when it opens, so a keyboard or
   * screen reader user lands on it rather than having to find it below the list.
   */
  renderedCallback() {
    let open;
    if (this.showDismissDialog) {
      open = 'dismiss-heading';
    } else if (this.showMergeDialog) {
      open = 'merge-heading';
    }
    if (open && open !== this.focusedHeading) {
      const heading = this.template.querySelector(`[data-id="${open}"]`);
      if (heading) {
        heading.focus();
      }
    }
    this.focusedHeading = open;

    // After Show More, keyboard and screen reader users land on the first new pair.
    if (this.focusFrom !== undefined) {
      const cards = this.template.querySelectorAll('[data-id="suggestion"]');
      const link = cards[this.focusFrom]
        ? cards[this.focusFrom].querySelector('[data-id="record-link"]')
        : undefined;
      this.focusFrom = undefined;
      if (link) {
        link.focus();
      }
    }
  }

  async load() {
    this.busy = true;
    try {
      this.view = await getView();
      this.errorMessage = undefined;
      this.announceCount();
    } catch (error) {
      this.errorMessage = bodyMessage(error, helpText('Core', 'Core_Duplicates_ErrorUnexpected'));
    } finally {
      this.busy = false;
    }
  }

  // ------------------------------------------------------------------ what is shown

  get rules() {
    if (!this.view || !this.view.rules) {
      return [];
    }
    return this.view.rules.map((rule) => ({
      key: `${rule.objectName}-${rule.ruleLabel}`,
      text: `${rule.ruleLabel} (${rule.active ? RULE_ACTIVE : RULE_INACTIVE})`
    }));
  }

  get showNoRulesNotice() {
    return !!this.view && this.view.anyRuleActive === false;
  }

  get scanRunning() {
    return !!(this.view && this.view.scanRunning);
  }

  get lastScanFinished() {
    return this.view ? this.view.lastScanFinished : undefined;
  }

  get hasLastScan() {
    return !!this.lastScanFinished;
  }

  /** What the latest scan said, including how many chunks it could not check. */
  get lastScanSummary() {
    return this.view ? this.view.lastScanSummary : undefined;
  }

  /** A scan that could not check some records says so in a warning notice, not red text. */
  get lastScanHadFailures() {
    return !!(this.view && this.view.lastScanHadFailures);
  }

  /** False when the viewer's license gives no access to duplicate record sets. */
  get canReviewSuggestions() {
    return !this.view || this.view.canReviewSuggestions !== false;
  }

  get showNoAccessNotice() {
    return !this.canReviewSuggestions;
  }

  /** Every suggestion waiting, as counted by the server; never fewer than it sent. */
  get totalCount() {
    if (!this.view) {
      return 0;
    }
    return Math.max(this.view.totalSuggestions || 0, (this.view.suggestions || []).length);
  }

  get moreNotCounted() {
    return !!(this.view && this.view.moreNotCounted);
  }

  /** "Showing 10 of 40", only when more are waiting than are shown. */
  get showingCount() {
    if (!this.view) {
      return undefined;
    }
    const shown = this.visibleSuggestions.length;
    const total = this.totalCount;
    if (!this.moreNotCounted && total <= shown) {
      return undefined;
    }
    const template = this.moreNotCounted
      ? helpText('Core', 'Core_Duplicates_ShowingCountMore')
      : helpText('Core', 'Core_Duplicates_ShowingCount');
    return template.replace('{0}', shown).replace('{1}', total);
  }

  get hasCount() {
    return this.canReviewSuggestions && this.totalCount > 0;
  }

  /** The badge beside Possible Duplicates: "40", or "50+" past what the server counted. */
  get countLabel() {
    return `${this.totalCount}${this.moreNotCounted ? '+' : ''}`;
  }

  get countAlt() {
    return COUNT_ALT.replace('{0}', this.countLabel);
  }

  /** Tells the Duplicate Matching tab the count for its Review tab name; empty for none. */
  announceCount() {
    this.dispatchEvent(
      new CustomEvent('countchange', { detail: { count: this.hasCount ? this.countLabel : '' } })
    );
  }

  get dismissedCount() {
    return this.view ? this.view.dismissedCount : 0;
  }

  get hasDismissed() {
    return this.dismissedCount > 0;
  }

  get suggestions() {
    if (!this.view || !this.view.suggestions) {
      return [];
    }
    return this.view.suggestions.map((suggestion) => {
      const records = suggestion.records || [];
      const first = records.length ? records[0].name : '';
      return {
        setId: suggestion.setId,
        reason: suggestion.reason,
        canMerge: suggestion.canMerge === true,
        // Two people merge with Salesforce's own Compare and merge, on the first one's page.
        isPeople: suggestion.canMerge !== true && records.length > 0 && !records[0].isHousehold,
        firstRecordId: records.length ? records[0].recordId : undefined,
        dismissOpen: this.dismissing === suggestion.setId,
        mergeOpen: !!this.merging && this.merging.setId === suggestion.setId,
        // A suggestion can hold three or more records: each is compared with the first.
        isGroup: records.length > 2,
        comparedWithFirst: helpText('Core', 'Core_Duplicates_ComparedWithFirst').replace(
          '{0}',
          first
        ),
        records: this.sideBySide(records)
      };
    });
  }

  /**
   * The records of one suggestion for the side-by-side card: each compared field with its
   * value, and a value held differently (spaces and capitals aside) marked Different, with
   * "from" and the other record's name for screen readers. In a pair each side is compared
   * with the other, so both carry the mark. A suggestion may hold three or more records: then
   * every record after the first is compared with the first, which carries no marks.
   */
  sideBySide(records) {
    const comparable = (value) => (value || '').trim().toLowerCase();
    const valuesOf = (record) => {
      const values = {};
      ((record && record.fields) || []).forEach((field) => {
        values[field.fieldName] = comparable(field.value);
      });
      return values;
    };
    const first = valuesOf(records[0]);
    const pair = records.length === 2;
    const nameOf = (record) => (record ? record.name : '');
    // Two records sit side by side; three or more wrap in up to three columns.
    const sizeClass =
      records.length > 2
        ? 'slds-col slds-size_1-of-1 slds-medium-size_1-of-2 slds-large-size_1-of-3 slds-var-m-bottom_x-small'
        : 'slds-col slds-size_1-of-1 slds-medium-size_1-of-2 slds-var-m-bottom_x-small';
    return records.map((record, index) => {
      // What this record is compared with: the other side of a pair, else the first record.
      const comparedWith = pair && index === 0 ? records[1] : records[0];
      const base = pair && index === 0 ? valuesOf(records[1]) : first;
      const marked = index > 0 || pair;
      const fields = (record.fields || []).map((field) => ({
        key: `${record.recordId}-${field.fieldName}`,
        label: field.label,
        text: field.value || BLANK,
        differs: marked && comparable(field.value) !== (base[field.fieldName] || '')
      }));
      const differentFrom = DIFFERENT_FROM.replace('{0}', nameOf(comparedWith));
      return {
        recordId: record.recordId,
        name: record.name,
        kind: record.isHousehold ? OBJECT_HOUSEHOLD : OBJECT_PERSON,
        detail: record.detail,
        url: `/lightning/r/${record.recordId}/view`,
        sizeClass,
        differentFrom,
        fields,
        hasFields: fields.length > 0
      };
    });
  }

  get visibleSuggestions() {
    return this.suggestions.slice(0, this.visibleCount);
  }

  get hasSuggestions() {
    return this.suggestions.length > 0;
  }

  get hasMoreToShow() {
    return this.suggestions.length > this.visibleCount;
  }

  handleShowMore() {
    this.focusFrom = this.visibleCount;
    this.visibleCount += PAGE_SIZE;
  }

  /** The controller checks this again; this only keeps buttons from offering what fails. */
  get canManage() {
    return canManageSettings === true;
  }

  get showReadOnlyNote() {
    return !this.canManage;
  }

  get controlsDisabled() {
    return this.busy || !this.canManage || !this.canReviewSuggestions;
  }

  /** A second scan beside a running one would record the same pairs twice; the server refuses it too. */
  get scanDisabled() {
    return this.controlsDisabled || this.scanRunning;
  }

  // ------------------------------------------------------------------ scan and refresh

  handleScan() {
    this.runAction(startScan(), helpText('Core', 'Core_Duplicates_ScanStarted'));
  }

  /** Opens or closes the Duplicate Rules Starter (C-61) under the rules box. */
  handleToggleStarter() {
    this.starterOpen = !this.starterOpen;
  }

  get starterExpanded() {
    return String(this.starterOpen);
  }

  handleRefresh() {
    this.noticeMessage = undefined;
    this.load();
  }

  /** In a console a suggested record opens as a subtab, so the review stays where it was. */
  handleRecordClick(event) {
    const recordId = event.currentTarget.dataset.recordId;
    followLinkInWorkspace(this, event, { recordId }, () =>
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId, actionName: 'view' }
      })
    );
  }

  /**
   * Compare and Merge on a person pair (admin-17): opens the first person's record page, where
   * the Potential Duplicates card runs Salesforce's own compare and merge (Salesforce gives no
   * supported link to its compare screen). In a console it opens as a subtab.
   */
  handleCompareClick(event) {
    const recordId = event.target.dataset.recordId;
    const navigate = () =>
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId, actionName: 'view' }
      });
    // A button has no link to fall back on, so outside a console it navigates itself.
    if (!followLinkInWorkspace(this, event, { recordId }, navigate)) {
      navigate();
    }
  }

  handleViewDismissed() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: DISMISSAL_OBJECT.objectApiName, actionName: 'list' }
    });
  }

  // ------------------------------------------------------------------ not a duplicate

  handleDismissClick(event) {
    this.merging = undefined;
    this.dismissing = event.target.dataset.setId;
    this.dismissReason = '';
  }

  handleReasonChange(event) {
    this.dismissReason = event.target.value;
  }

  handleDismissConfirm() {
    const setId = this.dismissing;
    this.dismissing = undefined;
    this.runAction(
      dismissSuggestion({ duplicateRecordSetId: setId, reason: this.dismissReason }),
      helpText('Core', 'Core_Duplicates_DismissSuccess')
    );
  }

  // ------------------------------------------------------------------ merge two households

  async handleMergeClick(event) {
    const setId = event.target.dataset.setId;
    const suggestion = this.suggestions.find((row) => row.setId === setId);
    if (!suggestion) {
      return;
    }
    this.dismissing = undefined;
    this.merging = suggestion;
    this.keepId = suggestion.records[0].recordId;
    await this.loadPreview();
  }

  handleKeepChange(event) {
    this.keepId = event.detail.value;
    this.loadPreview();
  }

  /**
   * Only the answer to the latest request is shown: after a quick change of the kept household
   * an earlier, slower answer would otherwise describe the other direction.
   */
  async loadPreview() {
    this.previewRequest += 1;
    const request = this.previewRequest;
    this.busy = true;
    this.errorMessage = undefined;
    try {
      const preview = await previewMerge({ survivorId: this.keepId, victimId: this.otherId });
      if (request === this.previewRequest) {
        this.mergePreview = preview;
      }
    } catch (error) {
      if (request === this.previewRequest) {
        this.errorMessage = bodyMessage(error, helpText('Core', 'Core_Duplicates_ErrorUnexpected'));
        this.merging = undefined;
      }
    } finally {
      if (request === this.previewRequest) {
        this.busy = false;
      }
    }
  }

  get otherId() {
    if (!this.merging) {
      return undefined;
    }
    const other = this.merging.records.find((record) => record.recordId !== this.keepId);
    return other ? other.recordId : undefined;
  }

  get keepOptions() {
    if (!this.merging) {
      return [];
    }
    return this.merging.records.map((record) => ({
      label: `${record.name} (${record.detail || record.kind})`,
      value: record.recordId
    }));
  }

  /** Only the fields the two households disagree about: the rest need no decision. */
  get conflictingFields() {
    if (!this.mergePreview || !this.mergePreview.fields) {
      return [];
    }
    return this.mergePreview.fields
      .filter((field) => field.inConflict)
      .map((field) => ({
        key: field.fieldName,
        text: `${field.label}: ${field.survivorValue || ''} (${MERGE_KEEPING}), ${
          field.victimValue || ''
        } (${MERGE_DROPPING})`
      }));
  }

  get hasConflictingFields() {
    return this.conflictingFields.length > 0;
  }

  handleMergeConfirm() {
    const setId = this.merging ? this.merging.setId : undefined;
    const survivorId = this.keepId;
    const victimId = this.otherId;
    this.merging = undefined;
    this.mergePreview = undefined;
    this.runAction(
      mergeHouseholds({ duplicateRecordSetId: setId, survivorId, victimId, fieldChoices: {} }),
      helpText('Core', 'Core_Duplicates_MergeSuccess')
    );
  }

  handleCancel() {
    this.dismissing = undefined;
    this.merging = undefined;
    this.mergePreview = undefined;
  }

  get showDismissDialog() {
    return !!this.dismissing;
  }

  get showMergeDialog() {
    return !!this.merging;
  }

  // ------------------------------------------------------------------ plumbing

  async runAction(promise, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.view = await promise;
      this.noticeMessage = notice;
      this.announceCount();
    } catch (error) {
      this.errorMessage = bodyMessage(error, helpText('Core', 'Core_Duplicates_ErrorUnexpected'));
    } finally {
      this.busy = false;
    }
  }
}
