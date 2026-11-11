import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getBoard from '@salesforce/apex/HubBoardController.getBoard';
import requestFromBoard from '@salesforce/apex/HubBoardController.requestFromBoard';
import startAssessment from '@salesforce/apex/HubBoardController.startAssessment';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { expiringSeats, percent, skillGaps, todayIso } from 'c/corporateHubModel';

const HELP_PACKAGES = ['CorporateHub'];

/**
 * The Board panel (CH-09, CH-12, CH-13, CH-15, CH-16, CH-17, CH-19; ADR-NEXT
 * `NEXT-corporate-hub-board-governance.md` decision 13): current seats with term ends and the
 * term-limit flag, terms ending soon, the skills matrix and its gaps, giving participation when
 * Giving is installed, open action items, and for a holder of Manage Corporate Hub, Request From
 * Board (a disclosure or policy) and Start Self-Assessment.
 */
export default class HubBoardPanel extends NavigationMixin(LightningElement) {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  view;
  documentId = '';
  isWorking = false;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  get labels() {
    return {
      title: helpText('CorporateHub', 'CorporateHub_Board_Title'),
      seats: helpText('CorporateHub', 'CorporateHub_Board_Seats', this.seats.length),
      noSeats: helpText('CorporateHub', 'CorporateHub_Board_NoSeats'),
      atLimit: helpText('CorporateHub', 'CorporateHub_Board_AtLimit'),
      termEnds: helpText('CorporateHub', 'CorporateHub_Board_TermEnds'),
      expiring: helpText('CorporateHub', 'CorporateHub_Board_Expiring', this.expiring.length),
      skills: helpText('CorporateHub', 'CorporateHub_Board_Skills'),
      gaps: this.gaps.length
        ? helpText('CorporateHub', 'CorporateHub_Board_Gaps', this.gaps.join(', '))
        : helpText('CorporateHub', 'CorporateHub_Board_NoGaps'),
      giving: helpText('CorporateHub', 'CorporateHub_Board_Giving', this.givingPercent),
      items: helpText('CorporateHub', 'CorporateHub_Board_Items'),
      noItems: helpText('CorporateHub', 'CorporateHub_Board_NoItems'),
      document: helpText('CorporateHub', 'CorporateHub_Board_Document'),
      request: helpText('CorporateHub', 'CorporateHub_Board_Request'),
      assess: helpText('CorporateHub', 'CorporateHub_Board_Assess')
    };
  }

  async load() {
    try {
      this.view = await getBoard({ boardId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(
        error,
        helpText('CorporateHub', 'CorporateHub_Error_Generic')
      );
    }
  }

  get seats() {
    return (this.view && this.view.seats) || [];
  }

  get hasSeats() {
    return this.seats.length > 0;
  }

  get expiring() {
    return expiringSeats(this.seats, todayIso(), this.view ? this.view.alertDays : 0);
  }

  get hasExpiring() {
    return this.expiring.length > 0;
  }

  get matrix() {
    return skillGaps((this.view && this.view.neededSkills) || [], this.seats).counts;
  }

  get hasMatrix() {
    return this.matrix.length > 0;
  }

  get gaps() {
    return skillGaps((this.view && this.view.neededSkills) || [], this.seats).gaps;
  }

  get showGiving() {
    return Boolean(this.view) && this.view.givers !== null && this.view.givers !== undefined;
  }

  get givingPercent() {
    return this.view ? percent(this.view.givers, this.seats.length) : 0;
  }

  get items() {
    return (this.view && this.view.actionItems) || [];
  }

  get hasItems() {
    return this.items.length > 0;
  }

  get canManage() {
    return Boolean(this.view && this.view.canManage);
  }

  get documentOptions() {
    return ((this.view && this.view.documents) || []).map((row) => ({
      label: row.name,
      value: row.id
    }));
  }

  get cannotRequest() {
    return this.isWorking || !this.documentId;
  }

  handleDocument(event) {
    this.documentId = event.detail.value;
  }

  handleRequest() {
    return this.run(
      () => requestFromBoard({ boardId: this.recordId, documentId: this.documentId }),
      (asked) => helpText('CorporateHub', 'CorporateHub_Document_Asked', asked || 0)
    );
  }

  async handleAssess() {
    const assessmentId = await this.run(
      () => startAssessment({ boardId: this.recordId }),
      () => helpText('CorporateHub', 'CorporateHub_Board_Assessed')
    );
    if (assessmentId) {
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId: assessmentId, actionName: 'view' }
      });
    }
  }

  /** One server call, then a toast and the panel refreshed; the call's result, or undefined. */
  async run(call, success) {
    this.isWorking = true;
    try {
      const result = await call();
      this.dispatchEvent(new ShowToastEvent({ message: success(result), variant: 'success' }));
      await this.load();
      return result;
    } catch (error) {
      this.errorMessage = messageFrom(
        error,
        helpText('CorporateHub', 'CorporateHub_Error_Generic')
      );
      return undefined;
    } finally {
      this.isWorking = false;
    }
  }
}
