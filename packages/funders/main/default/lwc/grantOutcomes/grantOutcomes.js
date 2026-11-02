import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOutcomes from '@salesforce/apex/GrantOutcomeController.getOutcomes';
import setOutcome from '@salesforce/apex/GrantOutcomeController.setOutcome';
import { indicatorLines } from 'c/grantReportModel';

import TITLE from '@salesforce/label/c.Funders_Outcomes_Title';
import NOT_INSTALLED from '@salesforce/label/c.Funders_Outcomes_NotInstalled';
import NO_REQUIREMENTS from '@salesforce/label/c.Funders_Outcomes_NoRequirements';
import NONE from '@salesforce/label/c.Core_Shared_NoOutcome';
import MISSING from '@salesforce/label/c.Funders_Outcomes_Missing';
import SAVED from '@salesforce/label/c.Funders_Outcomes_Saved';
import NO_INDICATORS from '@salesforce/label/c.Funders_Outcomes_NoIndicators';
import PERIOD_LINE from '@salesforce/label/c.Funders_Outcomes_PeriodLine';
import NOT_SET from '@salesforce/label/c.Funders_Outcomes_NotSet';
import ERROR_LOAD from '@salesforce/label/c.Funders_Outcomes_ErrorLoad';
import SAVE from '@salesforce/label/c.Core_Kit_Save';

const NONE_VALUE = '';

const messageOf = (error, fallback) =>
  (error && error.body && error.body.message) || (error && error.message) || fallback;

/**
 * The Logic Model Outcomes card on a grant's page (L-06, canonical model 29ZI R-GQ6): each
 * requirement with the Logic Models outcome or output it reports on, chosen here and saved by
 * record identifier, and that outcome's indicator results for the award period. Without Logic
 * Models it says so.
 */
export default class GrantOutcomes extends LightningElement {
  @api recordId;

  labels = { title: TITLE, notInstalled: NOT_INSTALLED, noRequirements: NO_REQUIREMENTS };

  card;
  choices = {};
  savingId;
  errorMessage;
  isLoading = true;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.card = await getOutcomes({ grantId: this.recordId });
      this.choices = {};
      this.errorMessage = undefined;
    } catch (error) {
      this.card = undefined;
      this.errorMessage = messageOf(error, ERROR_LOAD);
    } finally {
      this.isLoading = false;
    }
  }

  get notInstalled() {
    return Boolean(this.card) && !this.card.available;
  }

  get noRequirements() {
    return Boolean(this.card && this.card.available) && this.card.rows.length === 0;
  }

  get hasRows() {
    return Boolean(this.card && this.card.available) && this.card.rows.length > 0;
  }

  get rows() {
    const card = this.card || { rows: [], options: [] };
    const options = [{ label: NONE, value: NONE_VALUE }, ...(card.options || [])];
    const words = { periodLine: PERIOD_LINE, notSet: NOT_SET };
    return card.rows.map((row) => {
      const saved = row.outcomeId || NONE_VALUE;
      const value = Object.prototype.hasOwnProperty.call(this.choices, row.requirementId)
        ? this.choices[row.requirementId]
        : saved;
      const indicators = indicatorLines(row.outcome, words);
      return {
        id: row.requirementId,
        heading: `${row.name} (${row.type})`,
        options,
        value,
        canEdit: card.canEdit,
        readOnlyName: row.outcome ? `${row.outcome.model}: ${row.outcome.name}` : NONE,
        saveLabel: SAVE,
        saveDisabled: value === saved || this.savingId === row.requirementId,
        missing: row.missing,
        missingText: MISSING,
        indicators,
        noIndicators: Boolean(row.outcome) && indicators.length === 0,
        noIndicatorsText: NO_INDICATORS
      };
    });
  }

  handleChange(event) {
    this.choices = { ...this.choices, [event.target.dataset.id]: event.detail.value };
  }

  async handleSave(event) {
    const requirementId = event.currentTarget.dataset.id;
    this.savingId = requirementId;
    try {
      await setOutcome({ requirementId, outcomeId: this.choices[requirementId] || null });
      this.dispatchEvent(new ShowToastEvent({ message: SAVED, variant: 'success' }));
      await this.load();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({ message: messageOf(error, ERROR_LOAD), variant: 'error' })
      );
    } finally {
      this.savingId = undefined;
    }
  }
}
