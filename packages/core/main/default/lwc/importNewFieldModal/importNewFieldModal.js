import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import getConnection from '@salesforce/apex/ImportNewFieldController.getConnection';
import getPermissionSets from '@salesforce/apex/ImportNewFieldController.getPermissionSets';
import createField from '@salesforce/apex/ImportNewFieldController.createField';
import checkField from '@salesforce/apex/ImportNewFieldController.checkField';
import findField from '@salesforce/apex/ImportNewFieldController.findField';
import { apiNameFrom, distinctValues, suggestField } from './fieldSuggestions';

import OBJECT from '@salesforce/label/c.Core_ImportNewField_ObjectField';
import LABEL from '@salesforce/label/c.Core_ImportNewField_LabelField';
import API_NAME from '@salesforce/label/c.Core_ImportNewField_ApiNameField';
import API_NAME_HELP from '@salesforce/label/c.Core_ImportNewField_ApiNameHelp';
import TYPE from '@salesforce/label/c.Core_ImportNewField_TypeField';
import LENGTH from '@salesforce/label/c.Core_ImportNewField_LengthField';
import DECIMALS from '@salesforce/label/c.Core_ImportNewField_DecimalsField';
import VALUES from '@salesforce/label/c.Core_ImportNewField_ValuesField';
import PERMISSION_SET from '@salesforce/label/c.Core_ImportNewField_PermissionSetField';
import NO_PERMISSION_SET from '@salesforce/label/c.Core_ImportNewField_NoPermissionSet';
import ACCESS_NOTE from '@salesforce/label/c.Core_ImportNewField_AccessNote';
import CREATE from '@salesforce/label/c.Core_ImportNewField_CreateButton';
import CANCEL from '@salesforce/label/c.Core_ImportNewField_CancelButton';
import REFRESH from '@salesforce/label/c.Core_ImportNewField_RefreshButton';
import CREATING from '@salesforce/label/c.Core_ImportNewField_Creating';
import STILL_WAITING from '@salesforce/label/c.Core_ImportNewField_StillWaiting';
import NO_CONNECTION from '@salesforce/label/c.Core_ImportNewField_NoConnection';
import SETUP_STEPS from '@salesforce/label/c.Core_ImportNewField_SetupSteps';
import DETAILS from '@salesforce/label/c.Core_ImportNewField_DetailsField';
import NOT_FOUND from '@salesforce/label/c.Core_ImportNewField_NotFound';
import UNEXPECTED from '@salesforce/label/c.Core_UnexpectedError';
import TYPE_TEXT from '@salesforce/label/c.Core_ImportNewField_TypeText';
import TYPE_LONG_TEXT from '@salesforce/label/c.Core_ImportNewField_TypeLongTextArea';
import TYPE_NUMBER from '@salesforce/label/c.Core_ImportNewField_TypeNumber';
import TYPE_CURRENCY from '@salesforce/label/c.Core_ImportNewField_TypeCurrency';
import TYPE_PERCENT from '@salesforce/label/c.Core_ImportNewField_TypePercent';
import TYPE_DATE from '@salesforce/label/c.Core_ImportNewField_TypeDate';
import TYPE_DATE_TIME from '@salesforce/label/c.Core_ImportNewField_TypeDateTime';
import TYPE_CHECKBOX from '@salesforce/label/c.Core_ImportNewField_TypeCheckbox';
import TYPE_EMAIL from '@salesforce/label/c.Core_ImportNewField_TypeEmail';
import TYPE_PHONE from '@salesforce/label/c.Core_ImportNewField_TypePhone';
import TYPE_URL from '@salesforce/label/c.Core_ImportNewField_TypeUrl';
import TYPE_PICKLIST from '@salesforce/label/c.Core_ImportNewField_TypePicklist';

const TYPE_OPTIONS = [
  { value: 'Text', label: TYPE_TEXT },
  { value: 'LongTextArea', label: TYPE_LONG_TEXT },
  { value: 'Number', label: TYPE_NUMBER },
  { value: 'Currency', label: TYPE_CURRENCY },
  { value: 'Percent', label: TYPE_PERCENT },
  { value: 'Date', label: TYPE_DATE },
  { value: 'DateTime', label: TYPE_DATE_TIME },
  { value: 'Checkbox', label: TYPE_CHECKBOX },
  { value: 'Email', label: TYPE_EMAIL },
  { value: 'Phone', label: TYPE_PHONE },
  { value: 'Url', label: TYPE_URL },
  { value: 'Picklist', label: TYPE_PICKLIST }
];
const DECIMAL_TYPES = ['Number', 'Currency', 'Percent'];
const NONE = '';
const CREATED = 'Created';
const FAILED = 'Failed';
const POLL_MS = 3000;
const MAX_POLLS = 40;

/**
 * Create New Field (C-49d), opened from the import's field picker:
 * ImportNewFieldModal.open({ size: 'small', label, objects, heading, values }).
 * `objects` is [{ label, value, prefix }]: the objects the column can load into, and the prefix
 * its target takes (blank for a one-object template). Closes with
 * { objectApiName, prefix, fieldValue, fieldLabel } once the field is in describe, or undefined.
 * Without the connection it shows the field's details to create it in Setup.
 */
export default class ImportNewFieldModal extends LightningModal {
  @api objects = [];
  @api heading;
  @api values = [];

  labels = {
    object: OBJECT,
    label: LABEL,
    apiName: API_NAME,
    apiNameHelp: API_NAME_HELP,
    type: TYPE,
    length: LENGTH,
    decimals: DECIMALS,
    values: VALUES,
    permissionSet: PERMISSION_SET,
    accessNote: ACCESS_NOTE,
    create: CREATE,
    cancel: CANCEL,
    refresh: REFRESH,
    noConnection: NO_CONNECTION,
    setupSteps: SETUP_STEPS,
    details: DETAILS
  };
  typeOptions = TYPE_OPTIONS;
  form = {};
  permissionSetOptions = [{ label: NO_PERMISSION_SET, value: NONE }];
  connected = false;
  loading = true;
  busy = false;
  status;
  errorMessage;

  async connectedCallback() {
    const suggested = suggestField(this.values);
    const objects = this.objects || [];
    this.form = {
      objectApiName: objects.length ? objects[0].value : '',
      label: String(this.heading || '').slice(0, 40),
      apiName: apiNameFrom(this.heading),
      type: suggested.type,
      length: suggested.length,
      scale: suggested.scale,
      valuesText: (suggested.type === 'Picklist'
        ? suggested.values
        : distinctValues(this.values)
      ).join('\n'),
      permissionSetId: NONE
    };
    try {
      const connection = await getConnection();
      this.connected = Boolean(connection && connection.canCreate && connection.connected);
      if (this.connected) {
        const sets = await getPermissionSets();
        this.permissionSetOptions = this.permissionSetOptions.concat(sets || []);
      }
    } catch (error) {
      this.errorMessage = this.errorText(error);
    } finally {
      this.loading = false;
    }
  }

  get objectOptions() {
    return (this.objects || []).map((each) => ({ label: each.label, value: each.value }));
  }

  get choosesObject() {
    return this.objectOptions.length > 1;
  }

  get isText() {
    return this.form.type === 'Text';
  }

  get hasDecimals() {
    return DECIMAL_TYPES.includes(this.form.type);
  }

  get isPicklist() {
    return this.form.type === 'Picklist';
  }

  get showsGuidance() {
    return !this.loading && !this.connected;
  }

  get cannotCreate() {
    return this.busy || this.loading || !this.connected;
  }

  get picklistValues() {
    return distinctValues(String(this.form.valuesText || '').split('\n'));
  }

  /** The field as text to copy into Setup, one detail per line. */
  get setupDetails() {
    const type = TYPE_OPTIONS.find((option) => option.value === this.form.type);
    const lines = [
      `${OBJECT}: ${this.form.objectApiName}`,
      `${LABEL}: ${this.form.label}`,
      `${API_NAME}: ${this.form.apiName}__c`,
      `${TYPE}: ${type ? type.label : this.form.type}`
    ];
    if (this.isText) {
      lines.push(`${LENGTH}: ${this.form.length}`);
    }
    if (this.hasDecimals) {
      lines.push(`${DECIMALS}: ${this.form.scale}`);
    }
    if (this.isPicklist) {
      lines.push(`${VALUES}:`, ...this.picklistValues);
    }
    return lines.join('\n');
  }

  handleChange(event) {
    const name = event.target.dataset.field;
    let value = event.detail.value;
    if (name === 'length' || name === 'scale') {
      value = value === '' ? null : Number(value);
    }
    this.form = { ...this.form, [name]: value };
  }

  handleCancel() {
    this.close();
  }

  async handleCreate() {
    this.errorMessage = undefined;
    this.busy = true;
    this.status = CREATING;
    let jobId;
    try {
      jobId = await createField({
        requestJson: JSON.stringify({
          objectApiName: this.form.objectApiName,
          label: this.form.label,
          apiName: this.form.apiName,
          type: this.form.type,
          length: this.form.length,
          scale: this.form.scale,
          values: this.isPicklist ? this.picklistValues : [],
          permissionSetId: this.form.permissionSetId || null
        })
      });
    } catch (error) {
      // A refused request (a name in use, a missing permission): fix it and try again.
      this.fail(this.errorText(error), false);
      return;
    }
    try {
      await this.poll(jobId, 0);
    } catch (error) {
      this.fail(this.errorText(error));
    }
  }

  async poll(jobId, attempt) {
    const outcome = await checkField({
      jobId,
      objectApiName: this.form.objectApiName,
      apiName: this.form.apiName
    });
    if (outcome.state === CREATED) {
      this.finish(outcome);
    } else if (outcome.state === FAILED) {
      this.fail(outcome.message);
    } else if (attempt >= MAX_POLLS) {
      this.fail(STILL_WAITING);
    } else {
      await new Promise((resolve) => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(resolve, POLL_MS);
      });
      await this.poll(jobId, attempt + 1);
    }
  }

  /** Refresh Fields: the field created in Setup is picked up and mapped. */
  async handleRefresh() {
    this.errorMessage = undefined;
    this.busy = true;
    try {
      const outcome = await findField({
        objectApiName: this.form.objectApiName,
        apiName: this.form.apiName
      });
      if (outcome.state === CREATED) {
        this.finish(outcome);
      } else {
        this.fail(NOT_FOUND);
      }
    } catch (error) {
      this.fail(this.errorText(error));
    }
  }

  finish(outcome) {
    const chosen = (this.objects || []).find((each) => each.value === this.form.objectApiName);
    this.close({
      objectApiName: this.form.objectApiName,
      prefix: chosen ? chosen.prefix : '',
      fieldValue: outcome.fieldValue,
      fieldLabel: outcome.fieldLabel
    });
  }

  /**
   * A failure keeps the dialog open. Once the call to Salesforce has failed, the Setup details
   * become the way forward.
   */
  fail(message, toSetup = true) {
    this.busy = false;
    this.status = undefined;
    this.errorMessage = message || UNEXPECTED;
    if (toSetup) {
      this.connected = false;
    }
  }

  errorText(error) {
    return (error && error.body && error.body.message) || UNEXPECTED;
  }
}
