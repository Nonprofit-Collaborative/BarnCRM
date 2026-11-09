import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplications from '@salesforce/apex/EventApplicationsController.getApplications';
import saveReview from '@salesforce/apex/EventApplicationsController.saveReview';
import decide from '@salesforce/apex/EventApplicationsController.decide';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import EventRecordModal from 'c/eventRecordModal';
import BarnConfirmModal from 'c/barnConfirmModal';
import {
  averageText,
  isUndecided,
  isValidScore,
  scoreOptions,
  statusWord
} from 'c/eventApplicationsModel';

import TAB from '@salesforce/label/c.Events_EventTab_Applications';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';

const HELP_PACKAGES = ['Events'];
const APPLICATION_FIELDS = ['Name', 'Contact__c', 'Track__c', 'Abstract__c', 'Status__c'];
const NEW_APPLICATION_FIELDS = ['Name', 'Contact__c', 'Track__c', 'Abstract__c'];

/** The sentence about how a notice went, empty when none was asked for. */
function noticeText(notice) {
  switch (notice) {
    case 'Sent':
      return helpText('Events', 'Events_Notice_Sent');
    case 'NoTemplate':
      return helpText('Events', 'Events_Notice_NoTemplate');
    case 'TemplateMissing':
      return helpText('Events', 'Events_Notice_TemplateMissing');
    case 'NoEmail':
      return helpText('Events', 'Events_Notice_NoEmail');
    case 'SendFailed':
      return helpText('Events', 'Events_Notice_SendFailed');
    default:
      return '';
  }
}

/**
 * The Applications tab of the event page (EV-06): the call for speakers. Proposals are listed
 * best average first; a reviewer scores one (a second save replaces their first), and staff
 * accept or decline. Accepting makes the applicant a speaker at the event, or links the speaker
 * they already are, and the applicant gets the notice template chosen in Events settings.
 */
export default class EventApplications extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  /** The application whose review form is open, with its score and notes. */
  reviewing;

  labels = {
    tab: TAB,
    save: SAVE,
    cancel: CANCEL,
    actions: ACTIONS,
    get intro() {
      return helpText('Events', 'Events_Applications_Intro');
    },
    get empty() {
      return helpText('Events', 'Events_Applications_Empty');
    },
    get addApplication() {
      return helpText('Events', 'Events_Applications_Add');
    }
  };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.data = await getApplications({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Applications_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get fieldLabels() {
    return (this.data && this.data.fieldLabels) || {};
  }

  get canAdd() {
    return Boolean(this.data && this.data.canAdd);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get scoreChoices() {
    return scoreOptions();
  }

  get rows() {
    const applications = (this.data && this.data.applications) || [];
    return applications.map((application) => {
      const items = [];
      if (isUndecided(application.status)) {
        if (this.data.canReview) {
          items.push({ value: 'review', label: helpText('Events', 'Events_Applications_Review') });
        }
        if (this.data.canDecide) {
          items.push({ value: 'accept', label: helpText('Events', 'Events_Applications_Accept') });
          items.push({
            value: 'decline',
            label: helpText('Events', 'Events_Applications_Decline')
          });
        }
      }
      if (this.data.canDecide) {
        items.push({ value: 'edit', label: EDIT });
      }
      return {
        ...application,
        href: application.contactId ? `/lightning/r/${application.contactId}/view` : null,
        statusWord: statusWord(application.status),
        averageText: averageText(application.averageScore, application.reviewCount),
        menuLabel: format(ACTIONS_FOR, application.name),
        menuItems: items,
        isReviewing: Boolean(this.reviewing && this.reviewing.applicationId === application.id),
        hasReviews: application.reviews.length > 0,
        reviews: application.reviews.map((review, index) => ({
          key: `${application.id}-${index}`,
          text: [`${review.reviewer || ''}: ${review.score}`, review.notes]
            .filter(Boolean)
            .join(', ')
        }))
      };
    });
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && Boolean(this.data) && !this.hasRows;
  }

  get cannotSaveReview() {
    return this.busy || !this.reviewing || !isValidScore(this.reviewing.score);
  }

  async handleAdd() {
    const saved = await EventRecordModal.open({
      label: helpText('Events', 'Events_Applications_Add'),
      size: 'small',
      objectApiName: 'Speaker_Application__c',
      fields: NEW_APPLICATION_FIELDS,
      defaults: { Event__c: this.recordId }
    });
    if (saved) {
      await this.load();
    }
  }

  handleMenu(event) {
    const application = this.rows.find((row) => row.id === event.target.dataset.id);
    if (!application) {
      return;
    }
    const value = event.detail.value;
    if (value === 'review') {
      this.reviewing = {
        applicationId: application.id,
        score: application.myScore ? String(application.myScore) : null,
        notes: application.myNotes || ''
      };
    } else if (value === 'edit') {
      this.edit(application);
    } else {
      this.confirmDecision(application, value === 'accept' ? 'Accepted' : 'Declined');
    }
  }

  handleScore(event) {
    this.reviewing = { ...this.reviewing, score: event.detail.value };
  }

  handleNotes(event) {
    this.reviewing = { ...this.reviewing, notes: event.detail.value };
  }

  handleReviewCancel() {
    this.reviewing = undefined;
  }

  async handleReviewSave() {
    const { applicationId, score, notes } = this.reviewing;
    await this.run(async () => {
      await saveReview({ applicationId, score: Number(score), notes });
      this.reviewing = undefined;
    });
  }

  async edit(application) {
    const saved = await EventRecordModal.open({
      label: `${EDIT}: ${application.name}`,
      size: 'small',
      objectApiName: 'Speaker_Application__c',
      recordId: application.id,
      fields: APPLICATION_FIELDS
    });
    if (saved) {
      await this.load();
    }
  }

  async confirmDecision(application, decision) {
    const accepting = decision === 'Accepted';
    const who = application.applicant || application.name;
    const confirmLabel = accepting
      ? helpText('Events', 'Events_Applications_Accept')
      : helpText('Events', 'Events_Applications_Decline');
    const confirmed = await BarnConfirmModal.open({
      label: `${confirmLabel}: ${application.name}`,
      message: accepting
        ? helpText('Events', 'Events_Applications_AcceptConfirm', who)
        : helpText('Events', 'Events_Applications_DeclineConfirm', who),
      confirmLabel,
      cancelLabel: CANCEL,
      confirmVariant: accepting ? 'brand' : 'destructive',
      size: 'small'
    });
    if (!confirmed) {
      return;
    }
    await this.run(async () => {
      const result = await decide({ applicationId: application.id, decision, notify: true });
      const done =
        result.status === 'Accepted'
          ? helpText('Events', 'Events_Applications_Done_Accepted')
          : helpText('Events', 'Events_Applications_Done_Declined');
      this.dispatchEvent(
        new ShowToastEvent({
          message: [done, noticeText(result.notice)].filter(Boolean).join(' '),
          variant: result.notice === 'Sent' || result.notice === 'None' ? 'success' : 'warning'
        })
      );
    });
  }

  /** Runs a change, then reloads; a refusal shows in a toast in plain words. */
  async run(change) {
    this.busy = true;
    try {
      await change();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')),
          variant: 'error'
        })
      );
    } finally {
      this.busy = false;
    }
    await this.load();
  }
}
