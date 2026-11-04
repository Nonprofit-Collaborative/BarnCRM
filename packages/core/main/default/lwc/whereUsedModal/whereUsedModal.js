import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import findReferences from '@salesforce/apex/WhereUsedController.findReferences';
import { fieldSetupPath, setupPath } from 'c/setupLinks';
import { bodyMessage, format } from 'c/findCsv';
import { groupReferences, retireSteps, doneCount } from './whereUsedModel';

import TITLE from '@salesforce/label/c.Core_WhereUsed_Title';
import LOADING from '@salesforce/label/c.Core_WhereUsed_Loading';
import NOT_CHECKED from '@salesforce/label/c.Core_WhereUsed_NotChecked';
import OPEN_SETUP from '@salesforce/label/c.Core_SetupNote_OpenInSetup';
import INCOMPLETE from '@salesforce/label/c.Core_WhereUsed_Incomplete';
import NONE from '@salesforce/label/c.Core_WhereUsed_None';
import NONE_OBJECT from '@salesforce/label/c.Core_WhereUsed_NoneObject';
import COUNT from '@salesforce/label/c.Core_WhereUsed_Count';
import COUNT_ONE from '@salesforce/label/c.Core_WhereUsed_CountOne';
import NAMED_IN from '@salesforce/label/c.Core_WhereUsed_NamedIn';
import BREAKS from '@salesforce/label/c.Core_WhereUsed_Breaks';
import SHOW_OBJECT from '@salesforce/label/c.Core_WhereUsed_ShowObject';
import SHOW_FIELD from '@salesforce/label/c.Core_WhereUsed_ShowField';
import RETIRE_TITLE from '@salesforce/label/c.Core_WhereUsed_RetireTitle';
import STEP_NO_REFERENCES from '@salesforce/label/c.Core_WhereUsed_StepNoReferences';
import STEP_CANNOT_DELETE from '@salesforce/label/c.Core_WhereUsed_StepCannotDelete';
import OPEN_FIND from '@salesforce/label/c.Core_DataHygiene_OpenInFind';
import PROGRESS from '@salesforce/label/c.Core_SetupAssistant_ProgressFormat';
import CLOSE from '@salesforce/label/c.Core_BulkUpdate_Close';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const STEP_TEXT = {
  get references() {
    return helpText('Core', 'Core_WhereUsed_StepReferences');
  },
  noReferences: STEP_NO_REFERENCES,
  get salesforce() {
    return helpText('Core', 'Core_WhereUsed_StepSalesforce');
  },
  get backup() {
    return helpText('Core', 'Core_WhereUsed_StepBackup');
  },
  get hide() {
    return helpText('Core', 'Core_WhereUsed_StepHide');
  },
  get delete() {
    return helpText('Core', 'Core_WhereUsed_StepDelete');
  },
  cannotDelete: STEP_CANNOT_DELETE
};

/**
 * Where Used and Retire a Field (C-59, admin guide where-used.md): which BarnCRM setup records
 * name a field or a whole object, with a link to edit each, then a checklist for retiring the
 * field safely. BarnCRM never deletes the field; the last step links its Setup page. Open it
 * with WhereUsedModal.open({ objectName, objectLabel, fieldName, fieldLabel, size: 'medium' })
 * from any field list a BarnCRM Admin sees (Data Dictionary, Field Utilization, Record Inspector).
 */
export default class WhereUsedModal extends LightningModal {
  helpReady = isHelpLoaded('Core');

  @api objectName;
  @api objectLabel;
  @api fieldName;
  @api fieldLabel;

  labels = {
    loading: LOADING,
    notChecked: NOT_CHECKED,
    openSetup: OPEN_SETUP,
    incomplete: INCOMPLETE,
    retireTitle: RETIRE_TITLE,
    get retireIntro() {
      return helpText('Core', 'Core_WhereUsed_RetireIntro');
    },
    openFind: OPEN_FIND,
    close: CLOSE
  };

  /** True while the whole object is shown instead of the one field. */
  wholeObject = false;
  result;
  loading = false;
  errorMessage;
  ticked = new Set();
  run = 0;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.wholeObject = !this.fieldName;
    this.load();
  }

  async load() {
    const run = ++this.run;
    this.loading = true;
    this.errorMessage = undefined;
    this.result = undefined;
    try {
      const result = await findReferences({
        objectName: this.objectName,
        fieldName: this.wholeObject ? null : this.fieldName
      });
      if (run === this.run) {
        this.result = result;
      }
    } catch (error) {
      if (run === this.run) {
        this.errorMessage = bodyMessage(error);
      }
    } finally {
      if (run === this.run) {
        this.loading = false;
      }
    }
  }

  get heading() {
    const subject = this.wholeObject
      ? this.objectLabel || this.objectName
      : `${this.fieldLabel || this.fieldName} (${this.objectLabel || this.objectName})`;
    return format(TITLE, subject);
  }

  get groups() {
    return groupReferences(this.result && this.result.references).map((group) => ({
      ...group,
      items: group.items.map((item) => ({
        ...item,
        partsText: item.parts ? format(NAMED_IN, item.parts) : '',
        breaksText: item.breaks ? format(BREAKS, item.breaks) : ''
      }))
    }));
  }

  get hasReferences() {
    return !!(this.result && this.result.references && this.result.references.length);
  }

  get countText() {
    const count = this.hasReferences ? this.result.references.length : 0;
    return count === 1 ? COUNT_ONE : format(COUNT, String(count));
  }

  get noneText() {
    return this.wholeObject ? NONE_OBJECT : NONE;
  }

  get showEmpty() {
    return !!this.result && !this.hasReferences;
  }

  get incomplete() {
    return !!(this.result && this.result.incomplete);
  }

  /** Object Manager for the object, or the field's own page when one field is shown. */
  get setupUrl() {
    if (this.wholeObject || !this.fieldName) {
      return `${setupPath('objectManager').replace(/\/home$/, '')}/${encodeURIComponent(this.objectName)}/view`;
    }
    return fieldSetupPath(
      this.objectName,
      (this.result && this.result.fieldName) || this.fieldName
    );
  }

  get canSwitch() {
    return !!this.fieldName;
  }

  get switchLabel() {
    return this.wholeObject ? SHOW_FIELD : SHOW_OBJECT;
  }

  get showRetire() {
    return !this.wholeObject && !!this.result;
  }

  get steps() {
    const findUrl = this.result && this.result.findUrl;
    return retireSteps(this.result).map((step) => ({
      ...step,
      text: STEP_TEXT[step.key],
      checked: this.ticked.has(step.key),
      linkUrl: step.link === 'setup' ? this.setupUrl : step.link === 'find' ? findUrl : null,
      linkLabel: step.link === 'find' ? OPEN_FIND : OPEN_SETUP
    }));
  }

  get progressText() {
    const steps = retireSteps(this.result);
    return format(PROGRESS, String(doneCount(steps, this.ticked)), String(steps.length));
  }

  handleSwitch() {
    this.wholeObject = !this.wholeObject;
    this.load();
  }

  handleTick(event) {
    const key = event.target.dataset.step;
    const ticked = new Set(this.ticked);
    if (event.target.checked) {
      ticked.add(key);
    } else {
      ticked.delete(key);
    }
    this.ticked = ticked;
  }

  handleClose() {
    this.close();
  }
}
