import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import completeCycle from '@salesforce/apex/CorporateHubController.completeCycle';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { OUTCOMES, todayIso } from 'c/corporateHubModel';

const HELP_PACKAGES = ['CorporateHub'];

/**
 * The Compliance panel's Complete This Cycle on a compliance obligation (CH-03, R-CO1): the date, outcome and notes go into a new
 * Compliance Cycle and the due date moves on; the cycle then takes the evidence as Salesforce
 * Files.
 */
export default class HubCompleteCycle extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  completedOn = todayIso();
  outcome = OUTCOMES[0];
  notes = '';
  cycleId;
  isWorking = false;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
  }

  get labels() {
    return {
      title: helpText('CorporateHub', 'CorporateHub_Cycle_Title'),
      completedOn: helpText('CorporateHub', 'CorporateHub_Cycle_CompletedOn'),
      outcome: helpText('CorporateHub', 'CorporateHub_Cycle_Outcome'),
      notes: helpText('CorporateHub', 'CorporateHub_Cycle_Notes'),
      complete: helpText('CorporateHub', 'CorporateHub_Cycle_Complete'),
      evidence: helpText('CorporateHub', 'CorporateHub_Cycle_Evidence')
    };
  }

  /** The outcome picklist's values, as stored; the record page shows their labels. */
  get outcomeOptions() {
    return OUTCOMES.map((value) => ({ label: value, value }));
  }

  handleChange(event) {
    this[event.target.dataset.field] = event.target.value;
  }

  async handleComplete() {
    this.isWorking = true;
    try {
      this.cycleId = await completeCycle({
        obligationId: this.recordId,
        completedOn: this.completedOn || null,
        outcome: this.outcome,
        notes: this.notes
      });
      this.errorMessage = undefined;
      this.notes = '';
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      this.dispatchEvent(
        new ShowToastEvent({
          message: helpText('CorporateHub', 'CorporateHub_Cycle_Done'),
          variant: 'success'
        })
      );
    } catch (error) {
      this.errorMessage = messageFrom(
        error,
        helpText('CorporateHub', 'CorporateHub_Error_Generic')
      );
    } finally {
      this.isWorking = false;
    }
  }
}
