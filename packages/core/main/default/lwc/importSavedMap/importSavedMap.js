import { LightningElement, api } from 'lwc';
import listMaps from '@salesforce/apex/MapController.listMaps';
import loadMap from '@salesforce/apex/MapController.loadMap';
import saveMap from '@salesforce/apex/MapController.saveMap';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { applyToColumns, format, fromImportMapping, parseMap, serialize } from 'c/mapDocument';

function errorText(error) {
  return (error && error.body && error.body.message) || UNEXPECTED_ERROR;
}

/**
 * Saved Maps on Super Importer's Check Columns step (MAP-04; admin guide importing.md section 3
 * and mapper.md section 5). Use a Saved Map copies a map onto the file's columns by heading
 * (c/mapDocument applyToColumns) and fires `apply` with `{ columns }`; the wizard keeps those
 * columns as its own, so a map changed later never changes the template. Save as Map saves the
 * columns shown as a new map. Nothing else of the wizard changes.
 */
export default class ImportSavedMap extends LightningElement {
  helpReady = isHelpLoaded('Core');

  /** The wizard's columns: { source, target, transforms, lookupField, ... }. */
  @api columns = [];
  /** The wizard's mapping document (R-IT1), for Save as Map. */
  @api mappingDocument;
  /** The object a one-object template fills; empty for a people template. */
  @api objectName;
  /** The targets the template may load. */
  @api allowedTargets = [];
  /** For each lookup target, the fields it may name its parent by. */
  @api lookupChoices = {};
  /** Targets that mean "not loaded", left out of a saved map. */
  @api ignoredValues = [];

  maps = [];
  chosen;
  name = '';
  busy = false;
  message;
  errorMessage;

  get labels() {
    return {
      heading: helpText('Core', 'Core_ImportSavedMap_Heading'),
      useLabel: helpText('Core', 'Core_ImportSavedMap_UseLabel'),
      use: helpText('Core', 'Core_ImportSavedMap_Use'),
      nameLabel: helpText('Core', 'Core_ImportSavedMap_NameLabel'),
      save: helpText('Core', 'Core_ImportSavedMap_Save'),
      choose: helpText('Core', 'Core_ImportSavedMap_Choose')
    };
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.refresh();
  }

  async refresh() {
    try {
      this.maps = (await listMaps()) || [];
    } catch (error) {
      this.errorMessage = errorText(error);
    }
  }

  get mapOptions() {
    return this.maps.map((entry) => ({ label: entry.name, value: entry.recordId }));
  }

  get hasMaps() {
    return this.maps.length > 0;
  }

  get useDisabled() {
    return this.busy || !this.chosen;
  }

  get saveDisabled() {
    return this.busy || !this.name.trim();
  }

  handleChoose(event) {
    this.chosen = event.detail.value;
  }

  handleName(event) {
    this.name = event.detail.value || '';
  }

  async handleUse() {
    this.busy = true;
    this.message = undefined;
    try {
      const saved = await loadMap({ recordId: this.chosen });
      const { document } = parseMap(saved.definitionJson);
      const result = applyToColumns(
        this.columns,
        document,
        this.allowedTargets,
        this.lookupChoices
      );
      this.dispatchEvent(new CustomEvent('apply', { detail: { columns: result.columns } }));
      const unused = result.missing + result.unusable;
      this.message =
        unused > 0
          ? format(
              helpText('Core', 'Core_ImportSavedMap_UsedSome'),
              result.applied,
              saved.name,
              unused
            )
          : format(helpText('Core', 'Core_ImportSavedMap_Used'), result.applied, saved.name);
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = errorText(error);
    } finally {
      this.busy = false;
    }
  }

  async handleSave() {
    this.busy = true;
    this.message = undefined;
    try {
      const document = fromImportMapping(this.mappingDocument, this.objectName, this.ignoredValues);
      const saved = await saveMap({
        recordId: null,
        name: this.name,
        definitionJson: serialize(document)
      });
      this.message = format(
        helpText('Core', 'Core_ImportSavedMap_Saved'),
        saved.name,
        document.columns.length
      );
      this.errorMessage = undefined;
      this.name = '';
      await this.refresh();
    } catch (error) {
      this.errorMessage = errorText(error);
    } finally {
      this.busy = false;
    }
  }
}
