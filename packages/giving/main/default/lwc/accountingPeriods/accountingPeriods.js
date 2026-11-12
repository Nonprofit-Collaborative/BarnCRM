import { LightningElement } from 'lwc';
import getPeriod from '@salesforce/apex/AccountingPeriodController.getPeriod';
import closeThrough from '@salesforce/apex/AccountingPeriodController.closeThrough';

import TITLE from '@salesforce/label/c.Giving_Periods_Title';
import CLOSED_THROUGH_HEADING from '@salesforce/label/c.Giving_Periods_ClosedThroughHeading';
import SAVE_BUTTON from '@salesforce/label/c.Core_Kit_Save';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The Accounting Periods page (G-20, ADR-0053), reached from the Giving section of the Nonprofit
 * Settings console.
 *
 * It shows the date the books are closed through and moves it. The rules live in the controller:
 * the date moves forward only, never past the day before yesterday, and moving it back needs Override Posting
 * Lock. The page only offers the field to someone who can use it and shows what the controller
 * says when it refuses.
 */
export default class AccountingPeriods extends LightningElement {
  helpReady = isHelpLoaded('Giving');

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Giving', 'Giving_Periods_Intro');
    },
    closedThroughHeading: CLOSED_THROUGH_HEADING,
    get notClosed() {
      return helpText('Giving', 'Giving_Periods_NotClosed');
    },
    save: SAVE_BUTTON,
    get reopenNote() {
      return helpText('Giving', 'Giving_Periods_ReopenNote');
    },
    get readOnly() {
      return helpText('Giving', 'Giving_Periods_ReadOnly');
    }
  };

  view;
  draftDate;
  errorMessage;
  noticeMessage;
  busy = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    try {
      this.show(await getPeriod());
    } catch (error) {
      this.errorMessage = bodyMessage(error, helpText('Giving', 'Giving_Periods_UnexpectedError'));
    }
  }

  show(view) {
    this.view = view;
    this.draftDate = view ? view.closedThrough : undefined;
  }

  get loaded() {
    return !!this.view;
  }

  get closedThrough() {
    return this.view ? this.view.closedThrough : undefined;
  }

  get isClosed() {
    return !!this.closedThrough;
  }

  get canManage() {
    return !!(this.view && this.view.canManage);
  }

  get showReadOnlyNote() {
    return this.loaded && !this.canManage;
  }

  get latestAllowed() {
    return this.view ? this.view.latestAllowed : undefined;
  }

  get saveDisabled() {
    return this.busy || !this.draftDate || this.draftDate === this.closedThrough;
  }

  handleDateChange(event) {
    this.draftDate = event.detail.value;
    this.noticeMessage = undefined;
  }

  async handleSave() {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.show(await closeThrough({ closeDate: this.draftDate }));
      this.noticeMessage = helpText('Giving', 'Giving_Periods_Saved');
    } catch (error) {
      this.errorMessage = bodyMessage(error, helpText('Giving', 'Giving_Periods_UnexpectedError'));
    } finally {
      this.busy = false;
    }
  }
}
