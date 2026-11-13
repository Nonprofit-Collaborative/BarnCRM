import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplications from '@salesforce/apex/EventApplicationsController.getApplications';
import saveReview from '@salesforce/apex/EventApplicationsController.saveReview';
import decide from '@salesforce/apex/EventApplicationsController.decide';
import saveCriteria from '@salesforce/apex/EventProposalReview.saveCriteria';
import addPresenter from '@salesforce/apex/EventProposalReview.addPresenter';
import removePresenter from '@salesforce/apex/EventProposalReview.removePresenter';
import assignReviewers from '@salesforce/apex/EventProposalReview.assignReviewers';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import EventRecordModal from 'c/eventRecordModal';
import APPLICATION from '@salesforce/schema/Speaker_Application__c';
import BarnConfirmModal from 'c/barnConfirmModal';
import {
  averageText,
  blinded,
  canCompare,
  criteriaValid,
  isUndecided,
  isValidScore,
  matrixRows,
  MAX_CRITERIA,
  roundScore,
  scoreOptions,
  scoresOf,
  statusWord,
  weightedScore
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
/** The Role values of a presenter (Proposal_Presenter__c.Role__c). */
const ROLES = ['Speaker', 'Moderator', 'Panelist'];

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
 * The Applications tab of the event page (EV-06, EV-21): the call for speakers. Proposals are
 * listed best weighted average first; a reviewer scores one (a second save replaces their first),
 * by the event's weighted criteria when it has them, and staff accept or decline. Staff name
 * co-presenters, assign reviewers, and see the Scoring Matrix and up to four proposals side by
 * side, all worked out in the browser. Blind review hides names until a proposal is decided.
 * Accepting makes the applicant and every presenter speakers at the event, and the applicant gets
 * the notice template chosen in Events settings.
 */
export default class EventApplications extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  /** The application whose review form is open, with its score, criteria scores and notes. */
  reviewing;
  /** The application a presenter is being added to, with the chosen person and role. */
  presenterForm;
  criteriaOpen = false;
  matrixOpen = false;
  compareOpen = false;
  assignOpen = false;
  mineOnly = false;
  /** Proposals chosen for Compare and Assign Reviewer, by record identifier. */
  selected = [];
  drafts = [];
  draftKey = 0;
  reviewerId;

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
    get emptyHeading() {
      return helpText('Events', 'Events_Applications_EmptyHeading');
    },
    get addApplication() {
      return helpText('Events', 'Events_Applications_Add');
    },
    get criteria() {
      return helpText('Events', 'Events_Applications_Criteria');
    },
    get criteriaIntro() {
      return helpText('Events', 'Events_Applications_CriteriaIntro');
    },
    get criterion() {
      return helpText('Events', 'Events_Applications_Criterion');
    },
    get weight() {
      return helpText('Events', 'Events_Applications_Weight');
    },
    get addCriterion() {
      return helpText('Events', 'Events_Applications_AddCriterion');
    },
    get matrix() {
      return helpText('Events', 'Events_Applications_Matrix');
    },
    get total() {
      return helpText('Events', 'Events_Applications_Total');
    },
    get reviews() {
      return helpText('Events', 'Events_Applications_Reviews');
    },
    get compare() {
      return helpText('Events', 'Events_Applications_Compare');
    },
    get assignReviewer() {
      return helpText('Events', 'Events_Applications_AssignReviewer');
    },
    get assign() {
      return helpText('Events', 'Events_Applications_Assign');
    },
    get myAssignments() {
      return helpText('Events', 'Events_Applications_MyAssignments');
    },
    get assigned() {
      return helpText('Events', 'Events_Applications_AssignedBadge');
    },
    get addPresenter() {
      return helpText('Events', 'Events_Applications_AddPresenter');
    },
    get presenter() {
      return helpText('Events', 'Events_Applications_Presenter');
    },
    get role() {
      return helpText('Events', 'Events_Applications_Role');
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

  get canEditEvent() {
    return Boolean(this.data && this.data.canEditEvent);
  }

  get canAssign() {
    return Boolean(this.data && this.data.canAssign);
  }

  get criteria() {
    return (this.data && this.data.criteria) || [];
  }

  get hasCriteria() {
    return this.criteria.length > 0;
  }

  get scoreHeading() {
    return this.hasCriteria
      ? this.fieldLabels.Weighted_Average__c
      : this.fieldLabels.Average_Score__c;
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get scoreChoices() {
    return scoreOptions();
  }

  get roleOptions() {
    return ROLES.map((role) => ({ label: role, value: role }));
  }

  /** The applications as shown: blind review applied, then My Assignments. */
  get shown() {
    const blind = Boolean(this.data && this.data.blindReview);
    const hidden = helpText('Events', 'Events_Applications_Hidden');
    return ((this.data && this.data.applications) || [])
      .map((application) => blinded(application, blind, hidden))
      .filter((application) => !this.mineOnly || application.assignedToMe);
  }

  get rows() {
    return this.shown.map((application) => {
      const open = isUndecided(application.status);
      const items = [];
      if (open) {
        if (this.data.canReview) {
          items.push({ value: 'review', label: helpText('Events', 'Events_Applications_Review') });
        }
        if (this.data.canDecide) {
          items.push({
            value: 'presenter',
            label: helpText('Events', 'Events_Applications_AddPresenter')
          });
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
      const average = this.hasCriteria ? application.weightedAverage : application.averageScore;
      return {
        ...application,
        href: application.contactId ? `/lightning/r/${application.contactId}/view` : null,
        statusWord: statusWord(application.status),
        averageText: averageText(average, application.reviewCount),
        menuLabel: format(ACTIONS_FOR, application.name),
        menuItems: items,
        selected: this.selected.includes(application.id),
        selectLabel: helpText('Events', 'Events_Applications_Select', application.name),
        canEditPresenters: open && Boolean(this.data.canDecide),
        presenters: (application.presenters || []).map((presenter) => ({
          ...presenter,
          text: `${presenter.name || ''} (${presenter.role})`,
          removeLabel: helpText(
            'Events',
            'Events_Applications_RemovePresenter',
            presenter.name || ''
          )
        })),
        isReviewing: Boolean(this.reviewing && this.reviewing.applicationId === application.id),
        isAddingPresenter: Boolean(
          this.presenterForm && this.presenterForm.applicationId === application.id
        ),
        hasReviews: application.reviews.length > 0,
        reviews: application.reviews.map((review, index) => ({
          key: `${application.id}-${index}`,
          text:
            review.score === null || review.score === undefined
              ? `${review.reviewer || ''}: ${helpText('Events', 'Events_Applications_AssignedBadge')}`
              : [
                  `${review.reviewer || ''}: ${
                    this.hasCriteria && review.weightedScore
                      ? Number(review.weightedScore).toFixed(2)
                      : review.score
                  }`,
                  review.notes
                ]
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

  get matrix() {
    return matrixRows(this.shown, this.criteria);
  }

  get compared() {
    const lines = new Map(this.matrix.map((line) => [line.id, line]));
    return this.rows
      .filter((row) => this.selected.includes(row.id))
      .map((row) => ({
        ...row,
        criterionLines: this.criteria.map((criterion, index) => ({
          key: `${row.id}-${criterion.label}`,
          text: `${criterion.label}: ${lines.get(row.id).cells[index].text}`
        }))
      }));
  }

  get draftRows() {
    return this.drafts.map((draft, index) => ({
      ...draft,
      index,
      removeLabel: helpText('Events', 'Events_Applications_RemoveCriterion', draft.label || '')
    }));
  }

  get draftCriteria() {
    return this.drafts.map((draft) => ({
      label: String(draft.label || '').trim(),
      weight: Number(draft.weight)
    }));
  }

  get cannotAddCriterion() {
    return this.drafts.length >= MAX_CRITERIA;
  }

  get cannotSaveCriteria() {
    return this.busy || !criteriaValid(this.draftCriteria);
  }

  get criterionScores() {
    const scores = (this.reviewing && this.reviewing.criteriaScores) || {};
    return this.criteria.map((criterion) => ({
      label: criterion.label,
      text: helpText(
        'Events',
        'Events_Applications_CriterionScore',
        criterion.label,
        criterion.weight
      ),
      value: scores[criterion.label] ? String(scores[criterion.label]) : null
    }));
  }

  get weighted() {
    return weightedScore(this.criteria, (this.reviewing && this.reviewing.criteriaScores) || {});
  }

  get weightedText() {
    const value = this.weighted;
    return value === null
      ? ''
      : helpText('Events', 'Events_Applications_WeightedScore', value.toFixed(2));
  }

  get cannotSaveReview() {
    if (this.busy || !this.reviewing) {
      return true;
    }
    return this.hasCriteria ? this.weighted === null : !isValidScore(this.reviewing.score);
  }

  get cannotAddPresenter() {
    return this.busy || !(this.presenterForm && this.presenterForm.contactId);
  }

  async handleAdd() {
    const saved = await EventRecordModal.open({
      label: helpText('Events', 'Events_Applications_Add'),
      size: 'small',
      objectApiName: APPLICATION.objectApiName,
      fields: NEW_APPLICATION_FIELDS,
      defaults: { Event__c: this.recordId }
    });
    if (saved) {
      await this.load();
    }
  }

  handleCriteriaToggle() {
    this.criteriaOpen = !this.criteriaOpen;
    this.drafts = this.criteria.map((criterion) => ({
      ...criterion,
      key: `c-${(this.draftKey += 1)}`
    }));
  }

  handleDraft(event) {
    const index = Number(event.target.dataset.index);
    const field = event.target.dataset.field;
    this.drafts = this.drafts.map((draft, i) => {
      return i === index ? { ...draft, [field]: event.detail.value } : draft;
    });
  }

  handleAddCriterion() {
    this.drafts = [...this.drafts, { label: '', weight: 1, key: `c-${(this.draftKey += 1)}` }];
  }

  handleRemoveCriterion(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.drafts = this.drafts.filter((draft, i) => i !== index);
  }

  async handleCriteriaSave() {
    const criteriaJson = JSON.stringify(this.draftCriteria);
    await this.run(async () => {
      await saveCriteria({ eventId: this.recordId, criteriaJson });
      this.criteriaOpen = false;
      this.toast(helpText('Events', 'Events_Applications_CriteriaSaved'), 'success');
    });
  }

  handleMatrixToggle() {
    this.matrixOpen = !this.matrixOpen;
  }

  handleCompare() {
    if (this.compareOpen) {
      this.compareOpen = false;
      return;
    }
    if (!canCompare(this.selected)) {
      this.toast(helpText('Events', 'Events_Applications_CompareSome'), 'info');
      return;
    }
    this.compareOpen = true;
  }

  handleSelect(event) {
    const id = event.target.dataset.row;
    this.selected = event.target.checked
      ? [...this.selected.filter((item) => item !== id), id]
      : this.selected.filter((item) => item !== id);
    if (this.compareOpen && !canCompare(this.selected)) {
      this.compareOpen = false;
    }
  }

  handleAssignToggle() {
    this.assignOpen = !this.assignOpen;
  }

  handleReviewer(event) {
    this.reviewerId = event.detail.recordId || null;
  }

  async handleAssign() {
    if (!this.reviewerId || !this.selected.length) {
      this.toast(helpText('Events', 'Events_Applications_ChooseFirst'), 'info');
      return;
    }
    const applicationIds = [...this.selected];
    await this.run(async () => {
      const count = await assignReviewers({ applicationIds, reviewerId: this.reviewerId });
      this.assignOpen = false;
      this.toast(helpText('Events', 'Events_Applications_Assigned', count), 'success');
    });
  }

  handleMine(event) {
    this.mineOnly = event.target.checked;
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
        criteriaScores: scoresOf(application.myCriteriaScores),
        notes: application.myNotes || ''
      };
    } else if (value === 'presenter') {
      this.presenterForm = { applicationId: application.id, contactId: null, role: ROLES[0] };
    } else if (value === 'edit') {
      this.edit(application);
    } else {
      this.confirmDecision(application, value === 'accept' ? 'Accepted' : 'Declined');
    }
  }

  handleScore(event) {
    this.reviewing = { ...this.reviewing, score: event.detail.value };
  }

  handleCriterionScore(event) {
    const label = event.target.dataset.label;
    this.reviewing = {
      ...this.reviewing,
      criteriaScores: { ...this.reviewing.criteriaScores, [label]: Number(event.detail.value) }
    };
  }

  handleNotes(event) {
    this.reviewing = { ...this.reviewing, notes: event.detail.value };
  }

  handleReviewCancel() {
    this.reviewing = undefined;
  }

  async handleReviewSave() {
    const { applicationId, score, notes, criteriaScores } = this.reviewing;
    const scored = this.hasCriteria ? roundScore(this.weighted) : Number(score);
    await this.run(async () => {
      await saveReview({
        applicationId,
        score: scored,
        notes,
        criteriaScoresJson: this.hasCriteria ? JSON.stringify(criteriaScores) : null
      });
      this.reviewing = undefined;
    });
  }

  handlePresenterPerson(event) {
    this.presenterForm = { ...this.presenterForm, contactId: event.detail.recordId || null };
  }

  handlePresenterRole(event) {
    this.presenterForm = { ...this.presenterForm, role: event.detail.value };
  }

  handlePresenterCancel() {
    this.presenterForm = undefined;
  }

  async handlePresenterSave() {
    const { applicationId, contactId, role } = this.presenterForm;
    await this.run(async () => {
      await addPresenter({ applicationId, contactId, role });
      this.presenterForm = undefined;
    });
  }

  async handleRemovePresenter(event) {
    const presenterId = event.currentTarget.dataset.id;
    await this.run(() => removePresenter({ presenterId }));
  }

  async edit(application) {
    const saved = await EventRecordModal.open({
      label: `${EDIT}: ${application.name}`,
      size: 'small',
      objectApiName: APPLICATION.objectApiName,
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
      this.toast(
        [done, noticeText(result.notice)].filter(Boolean).join(' '),
        result.notice === 'Sent' || result.notice === 'None' ? 'success' : 'warning'
      );
    });
  }

  /** Runs a change, then reloads; a refusal shows in a toast in plain words. */
  async run(change) {
    this.busy = true;
    try {
      await change();
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')), 'error');
    } finally {
      this.busy = false;
    }
    await this.load();
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
