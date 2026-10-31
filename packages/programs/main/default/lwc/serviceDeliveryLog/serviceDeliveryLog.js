import { LightningElement, api } from 'lwc';
import getLog from '@salesforce/apex/ServiceDeliveryLogController.getLog';
import save from '@salesforce/apex/ServiceDeliveryLogController.save';

import TITLE from '@salesforce/label/c.Programs_Log_Title';
import SERVICE from '@salesforce/label/c.Programs_Log_Service';
import DATE from '@salesforce/label/c.Programs_Log_Date';
import ATTENDANCE from '@salesforce/label/c.Programs_Log_Attendance';
import QUANTITY from '@salesforce/label/c.Programs_Log_Quantity';
import NOT_RECORDED from '@salesforce/label/c.Programs_Log_NotRecorded';
import MARK_ALL_PRESENT from '@salesforce/label/c.Programs_Log_MarkAllPresent';
import SAVE from '@salesforce/label/c.Programs_Log_Save';
import SAVED from '@salesforce/label/c.Programs_Log_Saved';
import SAVED_ONE from '@salesforce/label/c.Programs_Log_SavedOne';
import NOTHING_TO_SAVE from '@salesforce/label/c.Programs_Log_NothingToSave';
import NO_SERVICES from '@salesforce/label/c.Programs_Log_NoServices';
import EMPTY from '@salesforce/label/c.Programs_Log_Empty';
import ATTENDANCE_FOR from '@salesforce/label/c.Programs_Log_AttendanceFor';
import QUANTITY_FOR from '@salesforce/label/c.Programs_Log_QuantityFor';
import MORE_THAN_SHOWN from '@salesforce/label/c.Programs_Log_MoreThanShown';
import ACTION_FAILED from '@salesforce/label/c.Programs_Log_ActionFailed';
import LOADING from '@salesforce/label/c.Programs_Loading';

import {
  entriesToSave,
  format,
  logRows,
  markAllPresent,
  withAttendance,
  withQuantity
} from './logRows';
import { bodyMessage } from 'c/findCsv';

/**
 * The Service Delivery Log panel on a program (P-02): for one active service and one day, the
 * attendance and quantity of everyone with an open enrollment, saved in one go. One person per
 * row on a desktop, one per card on a phone. Saves go through the delivery rules (R-SD2, R-SD3).
 */
export default class ServiceDeliveryLog extends LightningElement {
  @api recordId;

  labels = {
    title: TITLE,
    service: SERVICE,
    date: DATE,
    attendance: ATTENDANCE,
    markAllPresent: MARK_ALL_PRESENT,
    save: SAVE,
    noServices: NO_SERVICES,
    empty: EMPTY,
    moreThanShown: MORE_THAN_SHOWN,
    loading: LOADING
  };

  log;
  drafts = {};
  busy = false;
  loading = true;
  errorMessage;
  resultMessage;

  connectedCallback() {
    this.load();
  }

  load(serviceId, deliveryDate) {
    this.loading = true;
    return getLog({ programId: this.recordId, serviceId, deliveryDate })
      .then((log) => {
        this.log = log;
        this.drafts = {};
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.loading = false;
      });
  }

  get showSpinner() {
    return this.loading || this.busy;
  }

  get loaded() {
    return !!this.log;
  }

  get hasServices() {
    return this.loaded && this.log.services && this.log.services.length > 0;
  }

  get noServices() {
    return this.loaded && !this.hasServices;
  }

  get serviceOptions() {
    return (this.log && this.log.services ? this.log.services : []).map(({ label, value }) => ({
      label,
      value
    }));
  }

  get quantityLabel() {
    const service = (this.log.services || []).find((option) => option.value === this.log.serviceId);
    return format(QUANTITY, service && service.unit ? service.unit : '');
  }

  get rows() {
    return logRows(this.log, this.drafts, {
      notRecorded: NOT_RECORDED,
      attendanceFor: ATTENDANCE_FOR,
      quantityFor: QUANTITY_FOR
    });
  }

  get isEmpty() {
    return this.hasServices && this.rows.length === 0;
  }

  get canEdit() {
    return !!(this.log && this.log.canEdit);
  }

  get showHeader() {
    return this.canEdit && this.rows.length > 0;
  }

  get controlsDisabled() {
    return this.busy || this.loading;
  }

  get moreThanShown() {
    return !!(this.log && this.log.moreThanShown);
  }

  // ------------------------------------------------------------------------- choosing

  handleServiceChange(event) {
    this.resultMessage = undefined;
    this.errorMessage = undefined;
    return this.load(event.detail.value, this.log.deliveryDate);
  }

  handleDateChange(event) {
    const value = event.target.value;
    if (!value) {
      return undefined;
    }
    this.resultMessage = undefined;
    this.errorMessage = undefined;
    return this.load(this.log.serviceId, value);
  }

  // ------------------------------------------------------------------------- recording

  handleAttendanceChange(event) {
    this.resultMessage = undefined;
    this.drafts = withAttendance(
      this.log,
      this.drafts,
      event.target.dataset.key,
      event.detail.value
    );
  }

  handleQuantityChange(event) {
    this.resultMessage = undefined;
    this.drafts = withQuantity(this.log, this.drafts, event.target.dataset.key, event.target.value);
  }

  handleMarkAllPresent() {
    this.resultMessage = undefined;
    this.drafts = markAllPresent(this.log, this.drafts);
  }

  handleSave() {
    const entries = entriesToSave(this.log, this.drafts);
    this.errorMessage = undefined;
    if (entries.length === 0) {
      this.resultMessage = NOTHING_TO_SAVE;
      return Promise.resolve();
    }
    this.busy = true;
    return save({
      programId: this.recordId,
      serviceId: this.log.serviceId,
      deliveryDate: this.log.deliveryDate,
      entries
    })
      .then((log) => {
        this.log = log;
        this.drafts = {};
        this.resultMessage = log.saved === 1 ? SAVED_ONE : format(SAVED, log.saved);
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
