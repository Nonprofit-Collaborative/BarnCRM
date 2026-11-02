import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getSchedule from '@salesforce/apex/GrantScheduleController.getSchedule';
import saveSchedule from '@salesforce/apex/GrantScheduleController.saveSchedule';
import markReceived from '@salesforce/apex/GrantScheduleController.markReceived';
import { buildPayments } from 'c/grantScheduleModel';

import TITLE from '@salesforce/label/c.Funders_Schedule_Title';
import CANNOT_BUILD from '@salesforce/label/c.Funders_Schedule_CannotBuild';
import BUILD from '@salesforce/label/c.Funders_Schedule_Build';
import SAVED from '@salesforce/label/c.Funders_Schedule_Saved';
import MARK_RECEIVED from '@salesforce/label/c.Funders_Schedule_MarkReceived';
import ERROR_ACTION from '@salesforce/label/c.Funders_Pipeline_ErrorUnexpected';

const EXPECTED = 'Expected';
const DEFAULT_FREQUENCY = 'Annual';

const messageOf = (error) =>
  (error && error.body && error.body.message) || (error && error.message) || ERROR_ACTION;

/**
 * The Award Schedule card on a grant's page (F-05, canonical model 29ZM): the payments with the
 * amounts awarded, scheduled and received, Build Schedule (split in the browser by
 * `grantScheduleModel`, previewed, then saved) when the award has no schedule yet, and Mark
 * Received on an expected payment. Headings and frequency choices are the org's field labels,
 * sent by the server.
 */
export default class GrantSchedule extends LightningElement {
  @api recordId;

  labels = {
    title: TITLE,
    cannotBuild: CANNOT_BUILD,
    build: BUILD,
    markReceived: MARK_RECEIVED
  };

  schedule;
  frequency = DEFAULT_FREQUENCY;
  errorMessage;
  isLoading = true;
  isSaving = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.schedule = await getSchedule({ grantId: this.recordId });
      this.frequency = (this.schedule && this.schedule.frequency) || DEFAULT_FREQUENCY;
      this.errorMessage = undefined;
    } catch (error) {
      this.schedule = undefined;
      this.errorMessage = messageOf(error);
    } finally {
      this.isLoading = false;
    }
  }

  get hasSchedule() {
    return Boolean(this.schedule);
  }

  get heading() {
    return (this.schedule && this.schedule.fieldLabels) || {};
  }

  get payments() {
    const canMark = Boolean(this.schedule && this.schedule.canMarkReceived);
    return ((this.schedule && this.schedule.payments) || []).map((payment) => ({
      ...payment,
      canMarkReceived: canMark && payment.status === EXPECTED
    }));
  }

  get hasPayments() {
    return this.payments.length > 0;
  }

  get canBuild() {
    return Boolean(this.schedule && this.schedule.canBuild);
  }

  get showCannotBuild() {
    return Boolean(this.schedule) && !this.canBuild && !this.hasPayments;
  }

  get frequencyOptions() {
    return (this.schedule && this.schedule.frequencies) || [];
  }

  get preview() {
    if (!this.canBuild) {
      return [];
    }
    return buildPayments({
      amount: this.schedule.amountAwarded,
      start: this.schedule.startDate,
      end: this.schedule.endDate,
      frequency: this.frequency
    });
  }

  get hasPreview() {
    return this.preview.length > 0;
  }

  get buildDisabled() {
    return this.isSaving || !this.hasPreview;
  }

  handleFrequency(event) {
    this.frequency = event.detail.value;
  }

  async handleBuild() {
    this.isSaving = true;
    try {
      const rows = this.preview.map(({ dueDate, amount }) => ({ dueDate, amount }));
      await saveSchedule({
        grantId: this.recordId,
        frequency: this.frequency,
        paymentsJson: JSON.stringify(rows)
      });
      this.toast(SAVED, 'success');
      await this.refresh();
    } catch (error) {
      this.toast(messageOf(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  async handleMarkReceived(event) {
    const paymentId = event.currentTarget.dataset.paymentId;
    this.isSaving = true;
    try {
      await markReceived({ paymentId });
      this.toast(SAVED, 'success');
      await this.refresh();
    } catch (error) {
      this.toast(messageOf(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  async refresh() {
    await this.load();
    await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
