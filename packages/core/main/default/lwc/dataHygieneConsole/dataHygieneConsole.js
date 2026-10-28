import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import Toast from 'lightning/toast';
import getChecks from '@salesforce/apex/DataHygieneController.getChecks';
import openInFind from '@salesforce/apex/DataHygieneController.openInFind';

import PAGE_TITLE from '@salesforce/label/c.Core_DataHygiene_PageTitle';
import INTRO from '@salesforce/label/c.Core_DataHygiene_Intro';
import HEALTH_CHECK_NOTE from '@salesforce/label/c.Core_DataHygiene_HealthCheckNote';
import RECOUNT from '@salesforce/label/c.Core_DataHygiene_Recount';
import LOADING from '@salesforce/label/c.Core_DataHygiene_Loading';
import OPEN_IN_FIND from '@salesforce/label/c.Core_DataHygiene_OpenInFind';
import RECORDS_FOUND from '@salesforce/label/c.Core_DataHygiene_RecordsFound';
import OPENED_NOTICE from '@salesforce/label/c.Core_DataHygiene_OpenedNotice';
import CHECK_FAILED from '@salesforce/label/c.Core_DataHygiene_CheckFailed';
import NEEDS_ATTENTION from '@salesforce/label/c.Core_DataHygiene_NeedsAttention';
import ALL_CLEAR from '@salesforce/label/c.Core_OrgOptimizer_BadgeAllClear';

/**
 * Org Optimizer's Data Quality section (C-28, admin guide data-hygiene.md): every check with
 * its count and a Needs Attention or All Clear badge, read with the person's own access, and
 * "Open in Find", which saves the check's query as the person's own saved query and opens the
 * Find tab. The tab name and the page state key come from Apex, because both carry the package
 * namespace. After each count it fires `summary` with `detail.needsAttention`, the number of
 * checks that found records, for the Overview tile. Nothing here changes a record.
 */
export default class DataHygieneConsole extends NavigationMixin(LightningElement) {
  labels = {
    pageTitle: PAGE_TITLE,
    intro: INTRO,
    healthCheckNote: HEALTH_CHECK_NOTE,
    recount: RECOUNT,
    loading: LOADING,
    openInFind: OPEN_IN_FIND,
    recordsFound: RECORDS_FOUND
  };

  checks = [];
  busy = false;
  errorMessage;

  connectedCallback() {
    this.load();
  }

  get rows() {
    return this.checks.map((check) => {
      const found = check.count > 0;
      return {
        ...check,
        headingId: `heading-${check.key}`,
        hasCount: check.count !== undefined && check.count !== null,
        badgeLabel: found ? NEEDS_ATTENTION : ALL_CLEAR,
        badgeClass: found ? 'slds-theme_warning' : 'slds-theme_success'
      };
    });
  }

  get ariaBusy() {
    return this.busy ? 'true' : 'false';
  }

  async load() {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      this.checks = (await getChecks()) || [];
      const needsAttention = this.checks.filter((check) => check.count > 0).length;
      this.dispatchEvent(new CustomEvent('summary', { detail: { needsAttention } }));
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  handleRecount() {
    this.load();
  }

  async handleOpen(event) {
    const key = event.currentTarget.dataset.key;
    this.busy = true;
    this.errorMessage = undefined;
    try {
      const target = await openInFind({ checkKey: key });
      Toast.show(
        { label: OPENED_NOTICE.replace('{0}', target.savedQueryName), variant: 'info' },
        this
      );
      this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: target.findTabApiName },
        state: { [target.stateKey]: target.savedQueryId }
      });
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  messageFrom(error) {
    return (error && error.body && error.body.message) || CHECK_FAILED;
  }
}
