import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import USER_ID from '@salesforce/user/Id';
import UPLOAD_HELP from '@salesforce/label/c.Core_SetupAssistant_UploadHelp';
import SAVE from '@salesforce/label/c.Core_SetupAssistant_SaveButton';

const FILE_URL = '/sfc/servlet.shepherd/document/download/';
const TEXT = 'Text';
const RECORD = 'Record';
const FILE = 'File';
const NAVIGATE = 'Navigate';
const ADDRESS = 'Address';

/**
 * The fields of one Setup Assistant step, whichever package declared them (C-29, ADR-0059):
 * text boxes, record pickers, file uploads and buttons that open another tab. The step's
 * fields come from Apex with their labels, limits and current values, so a module adds a field
 * to a step without Core knowing what it is.
 *
 * Salesforce attaches every uploaded file to a record, and a logo belongs to no record in
 * particular, so an upload goes on the current user's own record and only the file's
 * identifier is kept in settings. The admin guide records that limitation.
 */
export default class SetupStepFields extends NavigationMixin(LightningElement) {
  @api canEdit = false;

  userId = USER_ID;
  draft = {};
  declared = [];

  labels = { uploadHelp: UPLOAD_HELP, save: SAVE };

  @api
  get fields() {
    return this.declared;
  }

  set fields(value) {
    this.declared = value || [];
    const draft = {};
    this.declared.forEach((field) => {
      if (field.key) {
        draft[field.key] = field.value;
      }
    });
    this.draft = draft;
  }

  get isReadOnly() {
    return !this.canEdit;
  }

  get acceptedFormats() {
    return ['.png', '.jpg', '.jpeg'];
  }

  // Maria never sees a file's record identifier, only the picture it points at
  // (plan Section 2.3: no setting requires knowing an API name).
  get view() {
    const firstAddress = this.declared.find((field) => field.fieldType === ADDRESS);
    return this.declared.map((field) => ({
      ...field,
      value: this.draft[field.key],
      isText: field.fieldType === TEXT,
      isRecord: field.fieldType === RECORD,
      isFile: field.fieldType === FILE,
      isNavigate: field.fieldType === NAVIGATE,
      // The address parts are shown as one grouped block, where the first part sits.
      isAddress: field === firstAddress,
      columnClass:
        field.fullWidth || field === firstAddress
          ? 'slds-col slds-size_1-of-1'
          : 'slds-col slds-size_1-of-1 slds-medium-size_1-of-2',
      previewUrl: this.draft[field.key] ? `${FILE_URL}${this.draft[field.key]}` : undefined
    }));
  }

  get inputs() {
    return this.view.filter((field) => field.isText || field.isRecord || field.isAddress);
  }

  /** What the address block shows: every address part's current draft, keyed by setting. */
  get addressValues() {
    const values = {};
    this.declared
      .filter((field) => field.fieldType === ADDRESS)
      .forEach((field) => {
        values[field.key] = this.draft[field.key];
      });
    return values;
  }

  get files() {
    return this.view.filter((field) => field.isFile);
  }

  get buttons() {
    return this.view.filter((field) => field.isNavigate);
  }

  get hasInputs() {
    return this.inputs.length > 0;
  }

  get hasFiles() {
    return this.canEdit && this.files.length > 0;
  }

  get showSave() {
    return this.canEdit && this.hasInputs;
  }

  handleFieldChange(event) {
    const key = event.target.dataset.key;
    this.draft = { ...this.draft, [key]: event.target.value };
  }

  handleAddressPartChange(event) {
    this.draft = { ...this.draft, [event.detail.key]: event.detail.value };
  }

  handleRecordChange(event) {
    const key = event.target.dataset.key;
    this.draft = { ...this.draft, [key]: event.detail.recordId };
  }

  handleUploaded(event) {
    const key = event.target.dataset.key;
    const files = (event.detail && event.detail.files) || [];
    if (files.length === 0) {
      return;
    }
    this.draft = { ...this.draft, [key]: files[0].documentId };
    this.handleSave();
  }

  handleNavigate(event) {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: event.target.dataset.target }
    });
  }

  handleSave() {
    // The address boxes mark what is still required and nothing is sent; the server refuses
    // an incomplete address too, for anyone who saves another way.
    const address = this.template.querySelector('c-organization-address');
    if (address && address.reportValidity() === false) {
      return;
    }
    const values = {};
    this.declared.forEach((field) => {
      if (field.key && field.fieldType !== NAVIGATE) {
        values[field.key] = this.draft[field.key] === undefined ? null : this.draft[field.key];
      }
    });
    this.dispatchEvent(new CustomEvent('save', { detail: { values } }));
  }
}
