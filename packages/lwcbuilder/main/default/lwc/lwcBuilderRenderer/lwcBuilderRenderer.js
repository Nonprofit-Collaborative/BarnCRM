import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import loadComponent from '@salesforce/apex/LwcBuilderController.loadComponent';
import checkPermissions from '@salesforce/apex/LwcBuilderController.checkPermissions';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { isVisible, normalize, ruleFields, rulePermissions } from 'c/lwcBuilderModel';

const HELP_PACKAGES = ['LwcBuilder'];

/**
 * BarnCRM Built Component (LB-02; ADR-NEXT `NEXT-lwc-builder-module.md`, decision 4): the one
 * packaged component that shows a component built in the LWC Builder, placed on record, app and
 * home pages. It reads the definition by key as the viewing user and lays it out on the SLDS
 * grid; each block reads its own data (c/lwcBuilderBlock). Nothing is generated or deployed.
 * The builder's preview sets `definition` directly instead of a key.
 */
export default class LwcBuilderRenderer extends LightningElement {
  @api componentKey;
  @api recordId;
  @api objectApiName;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  document;
  record = {};
  permissions = {};
  errorMessage;
  previewing = false;

  /** A definition (object or JSON) shown as it is: the builder's preview. */
  @api
  get definition() {
    return this.document;
  }
  set definition(value) {
    this.previewing = true;
    this.useDefinition(value);
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    if (!this.previewing) {
      this.load();
    }
  }

  async load() {
    if (!this.componentKey) {
      return;
    }
    try {
      const result = await loadComponent({ componentKey: this.componentKey });
      this.errorMessage = undefined;
      if (result && result.enabled !== false && result.found) {
        this.useDefinition(result.definition);
      }
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('LwcBuilder', 'LwcBuilder_Error_Generic'));
    }
  }

  useDefinition(value) {
    this.document = normalize(value);
    const names = rulePermissions(this.document);
    if (names.length) {
      checkPermissions({ names })
        .then((held) => {
          this.permissions = held || {};
        })
        .catch(() => {
          this.permissions = {};
        });
    }
  }

  /** The page record fields the visibility rules read, as optional fields: unreadable is blank. */
  get optionalFields() {
    if (!this.document || !this.objectApiName) {
      return undefined;
    }
    const names = ruleFields(this.document).map((field) => `${this.objectApiName}.${field}`);
    return names.length ? names : undefined;
  }

  get ruleRecordId() {
    return this.optionalFields ? this.recordId : undefined;
  }

  @wire(getRecord, { recordId: '$ruleRecordId', optionalFields: '$optionalFields' })
  wiredRecord({ data }) {
    const values = {};
    if (data && data.fields) {
      for (const name of Object.keys(data.fields)) {
        values[name] = data.fields[name].value;
      }
    }
    this.record = values;
  }

  /** Sections, rows and columns to draw, with each block's rule already applied. */
  get sections() {
    if (!this.document) {
      return [];
    }
    return this.document.sections.map((section) => ({
      id: section.id,
      title: section.title,
      rows: section.rows.map((row) => ({
        id: row.id,
        columns: row.columns.map((column) => ({
          id: column.id,
          css: `slds-col slds-size_1-of-1 slds-medium-size_${column.width}-of-12`,
          blocks: column.blocks.filter((block) =>
            isVisible(block.visibility, this.record, this.permissions)
          )
        }))
      }))
    }));
  }

  get hasSections() {
    return this.sections.length > 0;
  }

  get emptyPreview() {
    return this.previewing && !this.hasSections;
  }

  get labels() {
    return { empty: helpText('LwcBuilder', 'LwcBuilder_Preview_Empty') };
  }
}
