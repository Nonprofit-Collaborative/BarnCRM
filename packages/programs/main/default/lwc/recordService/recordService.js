import { LightningElement, api } from 'lwc';
import Toast from 'lightning/toast';
import { CloseActionScreenEvent } from 'lightning/actions';
import getForm from '@salesforce/apex/RecordServiceController.getForm';
import record from '@salesforce/apex/RecordServiceController.record';

import TITLE from '@salesforce/label/c.Programs_RecordService_Title';
import PERSON from '@salesforce/label/c.Core_Section_Person';
import SERVICE from '@salesforce/label/c.Programs_Log_Service';
import ATTENDANCE from '@salesforce/label/c.Core_Shared_Attendance';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PRESENT = 'Present';
const ABSENCES = ['Excused Absence', 'Unexcused Absence'];

function today() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/**
 * The Record Service quick action (modules-14) on a person and on an enrollment: one service
 * delivery by hand with a single Person picker, filled in from the record it was opened from
 * (an enrollment also fills in the program's services and links the delivery to it). The
 * standard New form stays for anyone who prefers it.
 */
export default class RecordService extends LightningElement {
  helpReady = isHelpLoaded('Programs');

  @api recordId;

  labels = {
    title: TITLE,
    person: PERSON,
    service: SERVICE,
    attendance: ATTENDANCE,
    save: SAVE,
    cancel: CANCEL,
    loading: LOADING,
    get noAccess() {
      return helpText('Programs', 'Programs_RecordService_NoAccess');
    },
    get noServices() {
      return helpText('Programs', 'Programs_RecordService_NoServices');
    }
  };

  form;
  personId;
  serviceId;
  deliveryDate = today();
  attendance = PRESENT;
  quantity = 1;
  loadError;
  working = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Programs').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  load() {
    return getForm({ recordId: this.recordId })
      .then((form) => {
        this.form = form;
        this.personId = form.personId;
        this.serviceId = form.serviceId;
      })
      .catch((error) => {
        this.loadError = bodyMessage(error, helpText('Programs', 'Programs_Fail_RecordService'));
      });
  }

  get loaded() {
    return !!this.form;
  }

  get noAccess() {
    return this.loaded && !this.form.canCreate;
  }

  get noServices() {
    return this.loaded && this.form.canCreate && this.form.services.length === 0;
  }

  get canRecord() {
    return this.loaded && this.form.canCreate && this.form.services.length > 0;
  }

  get personFilter() {
    if (!this.form || !this.form.personFilterField) {
      return undefined;
    }
    return { criteria: [{ fieldPath: this.form.personFilterField, operator: 'eq', value: true }] };
  }

  get isAbsence() {
    return ABSENCES.includes(this.attendance);
  }

  get saveDisabled() {
    return this.working || !this.personId || !this.serviceId || !this.deliveryDate;
  }

  handlePersonChange(event) {
    this.personId = event.detail ? event.detail.recordId : undefined;
  }

  handleServiceChange(event) {
    this.serviceId = event.detail.value;
  }

  handleDateChange(event) {
    this.deliveryDate = event.target.value;
  }

  handleAttendanceChange(event) {
    this.attendance = event.detail.value;
  }

  handleQuantityChange(event) {
    this.quantity = event.target.value;
  }

  handleCancel() {
    this.close();
  }

  handleSave() {
    if (this.saveDisabled) {
      return Promise.resolve();
    }
    this.working = true;
    // The enrollment it was opened from belongs to its own person only.
    const enrollmentId =
      this.form.enrollmentId && this.personId === this.form.personId
        ? this.form.enrollmentId
        : null;
    return record({
      personId: this.personId,
      serviceId: this.serviceId,
      deliveryDate: this.deliveryDate,
      attendance: this.attendance,
      quantity: this.isAbsence || this.quantity === '' ? null : Number(this.quantity),
      enrollmentId
    })
      .then(() => {
        Toast.show(
          { label: helpText('Programs', 'Programs_RecordService_Saved'), variant: 'success' },
          this
        );
        this.close();
      })
      .catch((error) => {
        Toast.show(
          {
            label: bodyMessage(error, helpText('Programs', 'Programs_Fail_RecordService')),
            variant: 'error'
          },
          this
        );
      })
      .finally(() => {
        this.working = false;
      });
  }

  close() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
