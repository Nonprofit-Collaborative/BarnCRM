import { LightningElement, api } from 'lwc';
import getAward from '@salesforce/apex/ScholarshipsController.getAward';
import makeLetter from '@salesforce/apex/ScholarshipsController.makeLetter';
import respond from '@salesforce/apex/ScholarshipsController.respond';
import buildSchedule from '@salesforce/apex/ScholarshipsController.buildSchedule';
import markPaid from '@salesforce/apex/ScholarshipsController.markPaid';
import setRequirement from '@salesforce/apex/ScholarshipsController.setRequirement';
import startRenewal from '@salesforce/apex/ScholarshipsController.startRenewal';
import { localIsoDate, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PKG = 'Scholarships';
const METHODS = ['Check', 'Bank Transfer', 'Card', 'Other'];

// What each action says when it has worked.
function notices() {
  return {
    Scholarships_Award_LetterMade: helpText('Scholarships', 'Scholarships_Award_LetterMade'),
    Scholarships_Award_Saved: helpText('Scholarships', 'Scholarships_Award_Saved'),
    Scholarships_Award_Scheduled: helpText('Scholarships', 'Scholarships_Award_Scheduled'),
    Scholarships_Payment_Paid: helpText('Scholarships', 'Scholarships_Payment_Paid'),
    Scholarships_Award_Renewed: helpText('Scholarships', 'Scholarships_Award_Renewed')
  };
}

/**
 * The award panel (SG-04 to SG-06, SG-09): Make Letter, Accepted and Declined, Build Schedule,
 * the disbursements with any held back by an open condition and Mark Paid, the conditions and
 * reports with Met and Waive, and Start Renewal. Records only: BarnCRM moves no money.
 */
export default class AwardPanel extends LightningElement {
  @api recordId;
  helpReady = isHelpLoaded([PKG]);
  panel;
  isWorking = false;
  errorMessage;
  notice;
  scheduling = false;
  count = 2;
  firstDate;
  monthsApart = 6;
  payingId;
  paidOn;
  method = 'Check';
  reference;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    this.firstDate = localIsoDate();
    this.load();
  }

  get labels() {
    return {
      title: helpText('Scholarships', 'Scholarships_Award_Title'),
      letter: helpText('Scholarships', 'Scholarships_Award_Letter'),
      accepted: helpText('Scholarships', 'Scholarships_Award_Accepted'),
      declined: helpText('Scholarships', 'Scholarships_Award_Declined'),
      schedule: helpText('Scholarships', 'Scholarships_Award_Schedule'),
      renewal: helpText('Scholarships', 'Scholarships_Award_Renewal'),
      count: helpText('Scholarships', 'Scholarships_Schedule_Count'),
      firstDate: helpText('Scholarships', 'Scholarships_Schedule_First'),
      monthsApart: helpText('Scholarships', 'Scholarships_Schedule_Months'),
      payments: helpText('Scholarships', 'Scholarships_Award_Payments'),
      noPayments: helpText('Scholarships', 'Scholarships_Award_NoPayments'),
      requirements: helpText('Scholarships', 'Scholarships_Award_Requirements'),
      noRequirements: helpText('Scholarships', 'Scholarships_Award_NoRequirements'),
      held: helpText('Scholarships', 'Scholarships_Payment_Held'),
      markPaid: helpText('Scholarships', 'Scholarships_Payment_MarkPaid'),
      paidOn: helpText('Scholarships', 'Scholarships_Payment_PaidOn'),
      method: helpText('Scholarships', 'Scholarships_Payment_Method'),
      reference: helpText('Scholarships', 'Scholarships_Payment_Reference'),
      met: helpText('Scholarships', 'Scholarships_Requirement_Met'),
      waive: helpText('Scholarships', 'Scholarships_Requirement_Waive'),
      reportLink: helpText('Scholarships', 'Scholarships_Requirement_Link'),
      save: helpText('Scholarships', 'Scholarships_Save'),
      cancel: helpText('Scholarships', 'Scholarships_Cancel')
    };
  }

  get methodOptions() {
    return METHODS.map((value) => ({ label: value, value }));
  }

  get canManage() {
    return this.panel?.canManage === true;
  }

  get payments() {
    return (this.panel?.payments || []).map((p) => ({
      ...p,
      href: `/lightning/r/${p.id}/view`,
      payable: p.status === 'Scheduled' && !p.held && this.canManage,
      isPaying: p.id === this.payingId
    }));
  }

  get requirements() {
    return (this.panel?.requirements || []).map((r) => ({
      ...r,
      href: `/lightning/r/${r.Id}/view`,
      blocks: r.Disbursement__r ? r.Disbursement__r.Name : '',
      isOpen: r.Status__c === 'Open' || r.Status__c === 'Submitted'
    }));
  }

  get hasPayments() {
    return this.payments.length > 0;
  }

  get hasRequirements() {
    return this.requirements.length > 0;
  }

  async load() {
    try {
      this.panel = await getAward({ awardId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  async run(work, noticeKey) {
    this.isWorking = true;
    try {
      await work();
      this.notice = notices()[noticeKey];
      this.errorMessage = undefined;
      this.scheduling = false;
      this.payingId = undefined;
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }

  handleField(event) {
    this[event.target.dataset.field] = event.target.value;
  }

  handleLetter() {
    this.run(() => makeLetter({ awardId: this.recordId }), 'Scholarships_Award_LetterMade');
  }

  handleAccepted() {
    this.run(() => respond({ awardId: this.recordId, accepted: true }), 'Scholarships_Award_Saved');
  }

  handleDeclined() {
    this.run(
      () => respond({ awardId: this.recordId, accepted: false }),
      'Scholarships_Award_Saved'
    );
  }

  handleStartSchedule() {
    this.scheduling = true;
  }

  handleCancel() {
    this.scheduling = false;
    this.payingId = undefined;
  }

  handleSchedule() {
    this.run(
      () =>
        buildSchedule({
          awardId: this.recordId,
          count: Number(this.count),
          firstDate: this.firstDate,
          monthsApart: Number(this.monthsApart)
        }),
      'Scholarships_Award_Scheduled'
    );
  }

  handleStartPaid(event) {
    this.payingId = event.target.dataset.rowId;
    this.paidOn = localIsoDate();
  }

  handlePaid() {
    const paymentId = this.payingId;
    this.run(
      () =>
        markPaid({
          paymentId,
          paidOn: this.paidOn,
          method: this.method,
          reference: this.reference
        }),
      'Scholarships_Payment_Paid'
    );
  }

  handleRequirement(event) {
    const { rowId, status } = event.target.dataset;
    this.run(() => setRequirement({ requirementId: rowId, status }), 'Scholarships_Award_Saved');
  }

  handleRenewal() {
    this.run(() => startRenewal({ awardId: this.recordId }), 'Scholarships_Award_Renewed');
  }
}
