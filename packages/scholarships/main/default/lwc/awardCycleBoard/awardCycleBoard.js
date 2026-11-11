import { LightningElement, api } from 'lwc';
import getBoard from '@salesforce/apex/ScholarshipsController.getBoard';
import assignReviewers from '@salesforce/apex/ScholarshipsController.assignReviewers';
import decide from '@salesforce/apex/ScholarshipsController.decide';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PKG = 'Scholarships';

// What each action says when it has worked, with what it returned.
function notices(result) {
  return {
    Scholarships_Board_Assigned: helpText('Scholarships', 'Scholarships_Board_Assigned', result),
    Scholarships_Board_Awarded: helpText('Scholarships', 'Scholarships_Board_Awarded', result),
    Scholarships_Board_Declined: helpText('Scholarships', 'Scholarships_Board_Declined', result)
  };
}

/**
 * The cycle's Review Board (SG-03, SG-04, SG-10): applications ranked by average score, the
 * budget left, the public application link, and, for a holder of Manage Scholarships, Assign
 * Reviewers and Award or Decline on each row. Blind review hides applicants from reviewers.
 */
export default class AwardCycleBoard extends LightningElement {
  @api recordId;
  helpReady = isHelpLoaded([PKG]);
  board;
  isWorking = false;
  errorMessage;
  notice;
  awardingId;
  awardAmount;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  get labels() {
    return {
      title: helpText('Scholarships', 'Scholarships_Board_Title'),
      assign: helpText('Scholarships', 'Scholarships_Board_Assign'),
      award: helpText('Scholarships', 'Scholarships_Board_Award'),
      decline: helpText('Scholarships', 'Scholarships_Board_Decline'),
      amount: helpText('Scholarships', 'Scholarships_Board_Amount'),
      save: helpText('Scholarships', 'Scholarships_Save'),
      cancel: helpText('Scholarships', 'Scholarships_Cancel'),
      empty: helpText('Scholarships', 'Scholarships_Board_Empty'),
      formLink: helpText('Scholarships', 'Scholarships_Board_FormLink'),
      blind: helpText('Scholarships', 'Scholarships_Board_Blind'),
      remaining: helpText('Scholarships', 'Scholarships_Board_Remaining')
    };
  }

  get rows() {
    return (this.board?.rows || []).map((row) => ({
      ...row,
      href: `/lightning/r/${row.id}/view`,
      shownApplicant: row.applicant ?? this.labels.blind,
      decidable: this.canManage && ['Submitted', 'Eligible', 'In Review'].includes(row.status),
      isAwarding: row.id === this.awardingId
    }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get canManage() {
    return this.board?.canManage === true;
  }

  get remaining() {
    return this.board?.remaining;
  }

  get formLink() {
    return this.board?.formLink;
  }

  get hasBudget() {
    return this.board?.budget !== null && this.board?.budget !== undefined;
  }

  async load() {
    try {
      this.board = await getBoard({ cycleId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  async run(work, noticeKey) {
    this.isWorking = true;
    try {
      const result = await work();
      this.notice = notices(result ?? '')[noticeKey];
      this.errorMessage = undefined;
      this.awardingId = undefined;
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }

  handleAssign() {
    this.run(() => assignReviewers({ cycleId: this.recordId }), 'Scholarships_Board_Assigned');
  }

  handleStartAward(event) {
    const row = this.rows.find((r) => r.id === event.target.dataset.rowId);
    this.awardingId = row.id;
    this.awardAmount = row.requested;
  }

  handleAmount(event) {
    this.awardAmount = event.target.value;
  }

  handleCancel() {
    this.awardingId = undefined;
  }

  handleSaveAward() {
    const applicationId = this.awardingId;
    this.run(
      () => decide({ applicationId, award: true, amount: this.awardAmount }),
      'Scholarships_Board_Awarded'
    );
  }

  handleDecline(event) {
    const applicationId = event.target.dataset.rowId;
    this.run(
      () => decide({ applicationId, award: false, amount: null }),
      'Scholarships_Board_Declined'
    );
  }
}
