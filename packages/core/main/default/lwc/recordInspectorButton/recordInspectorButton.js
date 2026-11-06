import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import pageLink from '@salesforce/apex/RecordInspectorController.pageLink';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import INSPECT from '@salesforce/label/c.Core_RecordInspector_Inspect';

/**
 * The Inspect This Record button (C-55): opens the Record Inspector page (c/recordInspector on
 * the Record Inspector tab) on this record, with the record ID in the page state. The tab name
 * and state key come from Apex, qualified for the org's namespace. Renders nothing for anyone
 * without Manage BarnCRM Settings.
 */
export default class RecordInspectorButton extends NavigationMixin(LightningElement) {
  @api recordId;

  label = INSPECT;
  /** The Record Inspector tab and state key, qualified for the org. */
  link;

  @wire(pageLink)
  wiredPageLink({ data }) {
    if (data) {
      this.link = data;
    }
  }

  get canUse() {
    return !!canManageSettings;
  }

  get notReady() {
    return !this.link || !this.recordId;
  }

  handleClick() {
    if (this.notReady) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: this.link.tabApiName },
      state: { [this.link.recordIdKey]: this.recordId }
    });
  }
}
