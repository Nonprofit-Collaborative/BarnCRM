import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
// Bare, and correctly so: a custom permission in the same package resolves without a prefix.
import canManageSettings from '@salesforce/customPermission/Manage_Nonprofit_Settings';
import DISMISSAL_OBJECT from '@salesforce/schema/Duplicate_Dismissal__c';
import getView from '@salesforce/apex/DuplicateController.getView';
import startScan from '@salesforce/apex/DuplicateController.startScan';
import dismissSuggestion from '@salesforce/apex/DuplicateController.dismiss';
import previewMerge from '@salesforce/apex/DuplicateController.previewMerge';
import mergeHouseholds from '@salesforce/apex/DuplicateController.mergeHouseholds';

import TITLE from '@salesforce/label/c.Core_Duplicates_Title';
import RULES_HEADING from '@salesforce/label/c.Core_Duplicates_RulesHeading';
import RULE_ACTIVE from '@salesforce/label/c.Core_Duplicates_RuleActive';
import RULE_INACTIVE from '@salesforce/label/c.Core_Duplicates_RuleInactive';
import ACTIVATE_LINK from '@salesforce/label/c.Core_Duplicates_ActivateLink';
import NO_RULES_NOTICE from '@salesforce/label/c.Core_Duplicates_NoRulesNotice';
import SCAN_BUTTON from '@salesforce/label/c.Core_Duplicates_ScanButton';
import SCAN_STARTED from '@salesforce/label/c.Core_Duplicates_ScanStarted';
import SCAN_RUNNING from '@salesforce/label/c.Core_Duplicates_ScanRunning';
import LAST_SCAN from '@salesforce/label/c.Core_Duplicates_LastScan';
import REFRESH from '@salesforce/label/c.Core_Duplicates_Refresh';
import SUGGESTIONS_HEADING from '@salesforce/label/c.Core_Duplicates_SuggestionsHeading';
import EMPTY from '@salesforce/label/c.Core_Duplicates_Empty';
import OBJECT_PERSON from '@salesforce/label/c.Core_Duplicates_ObjectPerson';
import OBJECT_HOUSEHOLD from '@salesforce/label/c.Core_Duplicates_ObjectHousehold';
import PEOPLE_MERGE_NOTICE from '@salesforce/label/c.Core_Duplicates_PeopleMergeNotice';
import MERGE_BUTTON from '@salesforce/label/c.Core_Duplicates_MergeButton';
import MERGE_HEADING from '@salesforce/label/c.Core_Duplicates_MergeHeading';
import MERGE_BODY from '@salesforce/label/c.Core_Duplicates_MergeBody';
import MERGE_KEEP_LABEL from '@salesforce/label/c.Core_Duplicates_MergeKeepLabel';
import MERGE_KEEPING from '@salesforce/label/c.Core_Duplicates_MergeKeeping';
import MERGE_DROPPING from '@salesforce/label/c.Core_Duplicates_MergeDropping';
import MERGE_FULL_SCREEN from '@salesforce/label/c.Core_Duplicates_MergeFullScreen';
import MERGE_CONFIRM from '@salesforce/label/c.Core_Duplicates_MergeConfirm';
import MERGE_SUCCESS from '@salesforce/label/c.Core_Duplicates_MergeSuccess';
import DISMISS_BUTTON from '@salesforce/label/c.Core_Duplicates_DismissButton';
import DISMISS_HEADING from '@salesforce/label/c.Core_Duplicates_DismissHeading';
import DISMISS_BODY from '@salesforce/label/c.Core_Duplicates_DismissBody';
import DISMISS_REASON_LABEL from '@salesforce/label/c.Core_Duplicates_DismissReasonLabel';
import DISMISS_SUCCESS from '@salesforce/label/c.Core_Duplicates_DismissSuccess';
import DISMISSED_COUNT from '@salesforce/label/c.Core_Duplicates_DismissedCount';
import VIEW_DISMISSED from '@salesforce/label/c.Core_Duplicates_ViewDismissed';
import READ_ONLY from '@salesforce/label/c.Core_Duplicates_ReadOnlyNotice';
import CANCEL from '@salesforce/label/c.Core_Duplicates_Cancel';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Duplicates_ErrorUnexpected';
import NO_ACCESS from '@salesforce/label/c.Core_Duplicates_NoSuggestionAccessNotice';
import SHOWING_COUNT from '@salesforce/label/c.Core_Duplicates_ShowingCount';
import SHOWING_COUNT_MORE from '@salesforce/label/c.Core_Duplicates_ShowingCountMore';

const SETUP_DUPLICATE_RULES = '/lightning/setup/DuplicateRules/home';

/**
 * The Duplicates panel on the Households page of BarnCRM Settings (C-20).
 *
 * Everything it lists was found by the org's own duplicate rules, so the first thing it shows
 * is whether those rules are on: "nothing to review" while nothing is being checked would be
 * worse than no panel. Two households are merged here in a short dialog, with the household
 * merge C-09 ships; field by field choices stay on the household record's own merge screen.
 * Two people are merged with the platform's merge, from the person's record page.
 */
export default class DuplicateReview extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    rulesHeading: RULES_HEADING,
    activateLink: ACTIVATE_LINK,
    noRulesNotice: NO_RULES_NOTICE,
    scanButton: SCAN_BUTTON,
    scanRunning: SCAN_RUNNING,
    lastScan: LAST_SCAN,
    refresh: REFRESH,
    suggestionsHeading: SUGGESTIONS_HEADING,
    empty: EMPTY,
    peopleMergeNotice: PEOPLE_MERGE_NOTICE,
    merge: MERGE_BUTTON,
    mergeHeading: MERGE_HEADING,
    mergeBody: MERGE_BODY,
    mergeKeepLabel: MERGE_KEEP_LABEL,
    mergeFullScreen: MERGE_FULL_SCREEN,
    mergeConfirm: MERGE_CONFIRM,
    dismiss: DISMISS_BUTTON,
    dismissHeading: DISMISS_HEADING,
    dismissBody: DISMISS_BODY,
    dismissReasonLabel: DISMISS_REASON_LABEL,
    dismissedCount: DISMISSED_COUNT,
    viewDismissed: VIEW_DISMISSED,
    readOnly: READ_ONLY,
    noAccess: NO_ACCESS,
    cancel: CANCEL
  };

  setupUrl = SETUP_DUPLICATE_RULES;

  view;
  errorMessage;
  noticeMessage;
  busy = false;

  dismissing;
  dismissReason = '';

  merging;
  mergePreview;
  keepId;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.busy = true;
    try {
      this.view = await getView();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
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

  get lastScanSummaryClass() {
    const failed = !!(this.view && this.view.lastScanHadFailures);
    return `slds-text-body_small slds-var-m-top_x-small${failed ? ' slds-text-color_error' : ''}`;
  }

  /** False when the viewer's license gives no access to duplicate record sets. */
  get canReviewSuggestions() {
    return !this.view || this.view.canReviewSuggestions !== false;
  }

  get showNoAccessNotice() {
    return !this.canReviewSuggestions;
  }

  /** "Showing 50 of 120", only when there are more than are listed. */
  get showingCount() {
    if (!this.view) {
      return undefined;
    }
    const shown = (this.view.suggestions || []).length;
    const total = this.view.totalSuggestions || 0;
    if (!this.view.moreNotCounted && total <= shown) {
      return undefined;
    }
    const template = this.view.moreNotCounted ? SHOWING_COUNT_MORE : SHOWING_COUNT;
    return template.replace('{0}', shown).replace('{1}', total);
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
    return this.view.suggestions.map((suggestion) => ({
      setId: suggestion.setId,
      canMerge: suggestion.canMerge === true,
      showPeopleNotice: suggestion.canMerge !== true,
      records: suggestion.records.map((record) => ({
        recordId: record.recordId,
        name: record.name,
        kind: record.isHousehold ? OBJECT_HOUSEHOLD : OBJECT_PERSON,
        detail: record.detail,
        url: `/lightning/r/${record.recordId}/view`
      }))
    }));
  }

  get hasSuggestions() {
    return this.suggestions.length > 0;
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

  // ------------------------------------------------------------------ scan and refresh

  handleScan() {
    this.runAction(startScan(), SCAN_STARTED);
  }

  handleRefresh() {
    this.noticeMessage = undefined;
    this.load();
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
      DISMISS_SUCCESS
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

  async loadPreview() {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      this.mergePreview = await previewMerge({ survivorId: this.keepId, victimId: this.otherId });
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
      this.merging = undefined;
    } finally {
      this.busy = false;
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
      MERGE_SUCCESS
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
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  messageFrom(error) {
    const body = error && error.body;
    return (body && body.message) || UNEXPECTED_ERROR;
  }
}
