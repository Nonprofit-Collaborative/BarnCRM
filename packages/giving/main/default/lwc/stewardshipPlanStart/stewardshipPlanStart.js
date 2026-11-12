import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { CloseActionScreenEvent } from 'lightning/actions';
import getStartable from '@salesforce/apex/StewardshipStartController.getStartable';
import startPlan from '@salesforce/apex/StewardshipStartController.startPlan';

import HEADING from '@salesforce/label/c.Giving_Stewardship_StartHeading';
import PLAN from '@salesforce/label/c.Giving_Stewardship_ColumnPlan';
import CHOOSE from '@salesforce/label/c.Giving_Stewardship_StartChoose';
import START from '@salesforce/label/c.Giving_Stewardship_StartButton';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * Starts a stewardship plan by hand on the person, household or organization the action was
 * opened from: pick a plan that is turned on, read what it is for, and start it.
 */
export default class StewardshipPlanStart extends LightningElement {
  @api recordId;

  labels = {
    heading: HEADING,
    plan: PLAN,
    choose: CHOOSE,
    start: START,
    cancel: CANCEL,
    get none() {
      return helpText('Giving', 'Giving_Stewardship_StartNone');
    },
    get noAccess() {
      return helpText('Giving', 'Giving_Stewardship_StartNoPermission');
    }
  };

  plans = [];
  canStart;
  loaded = false;
  loadError;
  templateId;
  working = false;
  helpReady = isHelpLoaded('Giving');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
  }

  @wire(getStartable)
  loadPlans({ data, error }) {
    if (data) {
      this.plans = data.plans || [];
      this.canStart = data.canStart === true;
      this.loaded = true;
      this.loadError = undefined;
    } else if (error) {
      this.loadError = this.messageOf(error);
    }
  }

  get noAccess() {
    return this.loaded && !this.canStart;
  }

  get noPlans() {
    return this.loaded && this.plans.length === 0;
  }

  /** Start is offered only when there is something the person may start. */
  get canChoose() {
    return this.loaded && !this.loadError && !this.noAccess && !this.noPlans;
  }

  get planOptions() {
    return this.plans.map((plan) => ({ label: plan.label, value: plan.value }));
  }

  get description() {
    const chosen = this.plans.find((plan) => plan.value === this.templateId);
    return chosen ? chosen.description : undefined;
  }

  handlePlanChange(event) {
    this.templateId = event.detail.value;
  }

  handleCancel() {
    this.close();
  }

  async handleStart() {
    if (!this.templateId) {
      this.toast(helpText('Giving', 'Giving_Stewardship_StartChooseFirst'), 'error');
      return;
    }
    this.working = true;
    try {
      await startPlan({ templateId: this.templateId, donorId: this.recordId });
      this.toast(helpText('Giving', 'Giving_Stewardship_StartSuccess'), 'success');
      this.close();
    } catch (error) {
      this.toast(this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  messageOf(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return error && error.message ? error.message : String(error);
  }

  toast(message, variant) {
    Toast.show({ label: message, variant }, this);
  }

  close() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
