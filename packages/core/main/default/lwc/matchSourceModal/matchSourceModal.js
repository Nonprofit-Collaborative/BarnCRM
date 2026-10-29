import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import describeObject from '@salesforce/apex/MatchSourceController.describeObject';
import saveRow from '@salesforce/apex/CustomMetadataManagerController.saveRow';

import OBJECT from '@salesforce/label/c.Core_MatchLogic_Object';
import VALUE_FIELD from '@salesforce/label/c.Core_MatchLogic_ValueField';
import POSTAL_FIELD from '@salesforce/label/c.Core_MatchLogic_PostalField';
import PARENT_FIELD from '@salesforce/label/c.Core_MatchLogic_ParentField';
import COMPARE from '@salesforce/label/c.Core_MatchLogic_Compare';
import FIND_FIELDS from '@salesforce/label/c.Core_MatchLogic_FindFields';
import SAVE from '@salesforce/label/c.Core_CmdtManager_SaveButton';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import NAME from '@salesforce/label/c.Core_CmdtManager_NameField';
import LOAD_ERROR from '@salesforce/label/c.Core_CmdtManager_LoadError';

const TYPE_NAME = 'Match_Source__mdt';
const ADDRESS = 'Address';
const FIELDS = [
  'Object_Name__c',
  'Value_Field__c',
  'Postal_Code_Field__c',
  'Parent_Field__c',
  'Normalization__c'
];

/**
 * The add and edit form of a match source, in a platform modal (Matching Logic, UX 9b). Save
 * sends the source to the custom metadata manager, which checks it against the org; a refusal
 * shows here and the form stays open. Once the deployment has started the modal closes with
 * { jobId, label }, and the Matching Logic area waits on it. Open it with
 * MatchSourceModal.open({ label, source, normalizations, size: 'small' }); source is the card's
 * source when editing, or empty when adding.
 */
export default class MatchSourceModal extends LightningModal {
  /** The source being edited ({ developerName, label, values }), or empty for a new one. */
  @api source;
  /** The comparison choices ({ label, value }) from the Matching Logic view. */
  @api normalizations;

  labels = {
    name: NAME,
    object: OBJECT,
    valueField: VALUE_FIELD,
    postalField: POSTAL_FIELD,
    parentField: PARENT_FIELD,
    compare: COMPARE,
    findFields: FIND_FIELDS,
    save: SAVE,
    cancel: CANCEL
  };

  form;
  /** The fields of the form's object, from describeObject. */
  objectFields;
  errorMessage;
  busy = false;

  connectedCallback() {
    const values = {};
    FIELDS.forEach((name) => {
      values[name] = '';
    });
    const source = this.source || {};
    this.form = {
      developerName: source.developerName || null,
      label: source.label || '',
      values: { ...values, ...(source.values || {}) }
    };
    if (this.form.developerName) {
      this.findFields();
    }
  }

  get isAddress() {
    return this.form.values.Normalization__c === ADDRESS;
  }

  /** A field's choices: the object's fields once found, else the value already there. */
  choicesFor(list, current) {
    const found = (this.objectFields && this.objectFields[list]) || [];
    if (current && !found.some((choice) => choice.value === current)) {
      return [{ label: current, value: current }, ...found];
    }
    return found;
  }

  get valueFieldOptions() {
    return this.choicesFor('valueFields', this.form.values.Value_Field__c);
  }

  get postalFieldOptions() {
    return this.choicesFor('valueFields', this.form.values.Postal_Code_Field__c);
  }

  get parentFieldOptions() {
    return this.choicesFor('parentFields', this.form.values.Parent_Field__c);
  }

  handleNameChange(event) {
    this.form = { ...this.form, label: event.detail.value };
  }

  handleFieldChange(event) {
    const values = { ...this.form.values, [event.target.dataset.field]: event.detail.value };
    this.form = { ...this.form, values };
  }

  handleFindFields() {
    this.findFields();
  }

  async findFields() {
    const objectName = this.form.values.Object_Name__c;
    if (!objectName) {
      return;
    }
    try {
      this.objectFields = await describeObject({ objectName });
      this.errorMessage = undefined;
    } catch (error) {
      this.objectFields = undefined;
      this.errorMessage = this.messageFrom(error);
    }
  }

  handleCancel() {
    this.close(undefined);
  }

  async handleSave() {
    const form = this.form;
    this.busy = true;
    this.errorMessage = undefined;
    try {
      const jobId = await saveRow({
        typeName: TYPE_NAME,
        input: { developerName: form.developerName, label: form.label, values: form.values }
      });
      this.close({ jobId, label: form.label });
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  messageFrom(error) {
    return error && error.body && error.body.message ? error.body.message : LOAD_ERROR;
  }
}
