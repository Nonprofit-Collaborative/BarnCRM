import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LANGUAGE from '@salesforce/i18n/lang';
import getSchedule from '@salesforce/apex/GrantScheduleController.getSchedule';
import saveSchedule from '@salesforce/apex/GrantScheduleController.saveSchedule';
import markReceived from '@salesforce/apex/GrantScheduleController.markReceived';
import undoReceived from '@salesforce/apex/GrantScheduleController.undoReceived';
import { buildNeeds, buildPayments, percentOf } from 'c/grantScheduleModel';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

import TITLE from '@salesforce/label/c.Funders_Schedule_Title';
import CANNOT_BUILD from '@salesforce/label/c.Funders_Schedule_CannotBuild';
import BUILD from '@salesforce/label/c.Funders_Schedule_Build';
import SAVED from '@salesforce/label/c.Core_Shared_Saved';
import MARK_RECEIVED from '@salesforce/label/c.Funders_Schedule_MarkReceived';
import UNDO from '@salesforce/label/c.Core_AutoMerge_Undo';
import ERROR_ACTION from '@salesforce/label/c.Funders_Pipeline_ErrorUnexpected';

const EXPECTED = 'Expected';
const DEFAULT_FREQUENCY = 'Annual';

const messageOf = (error) => messageFrom(error, ERROR_ACTION);

/** "A, B and C" in the person's language; plain commas where the browser cannot. */
function listOf(words) {
  try {
    return new Intl.ListFormat(LANGUAGE, { type: 'conjunction' }).format(words);
  } catch {
    return words.join(', ');
  }
}

/**
 * The Award Schedule card on a grant's page (F-05, canonical model 29ZM): the amounts awarded,
 * scheduled and received as tiles with a received meter, the payments, Build Schedule (split in
 * the browser by `grantScheduleModel`, previewed, then saved) when the award has no schedule yet,
 * and Mark Received on an expected payment with its Undo (modules-17). When a schedule cannot be
 * built yet, it names only what is missing (modules-16). Headings and frequency choices are the
 * org's field labels, sent by the server.
 */
export default class GrantSchedule extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded('Funders');

  labels = {
    title: TITLE,
    build: BUILD,
    markReceived: MARK_RECEIVED,
    saved: SAVED,
    undo: UNDO
  };

  schedule;
  frequency = DEFAULT_FREQUENCY;
  errorMessage;
  isLoading = true;
  isSaving = false;
  /** What the last Mark Received replaced, while its Undo is offered. */
  lastReceived;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Funders').then(() => {
        this.helpReady = true;
      });
    }
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

  /** The share of the award received, as a bar with its number (vis-modules-5). */
  get showReceivedMeter() {
    return Boolean(this.schedule) && Number(this.schedule.amountAwarded) > 0;
  }

  get receivedPercent() {
    return this.schedule ? percentOf(this.schedule.amountReceived, this.schedule.amountAwarded) : 0;
  }

  get receivedPercentText() {
    return `${this.receivedPercent}%`;
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

  /** Only what this grant still lacks (modules-16); the full rule when nothing is missing. */
  get cannotBuildText() {
    if (!this.helpReady) {
      return CANNOT_BUILD;
    }
    const needs = buildNeeds(this.schedule);
    const names = this.heading;
    if (needs.notAwarded) {
      return helpText('Funders', 'Funders_Schedule_NeedsAwarded');
    }
    if (needs.missing.length) {
      return helpText(
        'Funders',
        'Funders_Schedule_NeedsFields',
        listOf(needs.missing.map((key) => names[key] || key))
      );
    }
    if (needs.reversed) {
      return helpText('Funders', 'Funders_Schedule_DatesReversed', names.endDate, names.startDate);
    }
    return CANNOT_BUILD;
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

  get showUndo() {
    return Boolean(this.lastReceived);
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

  /** Mark Received, then "Saved. Undo" for the life of the card (modules-17). */
  async handleMarkReceived(event) {
    const paymentId = event.currentTarget.dataset.paymentId;
    this.isSaving = true;
    try {
      const previous = await markReceived({ paymentId });
      this.lastReceived = previous && previous.id ? previous : undefined;
      await this.refresh();
    } catch (error) {
      this.toast(messageOf(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  /** Puts the payment back as it was and removes the ledger entry Mark Received wrote. */
  async handleUndoReceived() {
    const previous = this.lastReceived;
    if (!previous) {
      return;
    }
    this.lastReceived = undefined;
    this.isSaving = true;
    try {
      await undoReceived({
        paymentId: previous.id,
        status: previous.status,
        receivedDate: previous.dateValue || null
      });
      this.toast(helpText('Funders', 'Funders_Undo_Done'), 'success');
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
