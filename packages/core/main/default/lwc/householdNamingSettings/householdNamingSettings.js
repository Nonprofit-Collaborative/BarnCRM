import { LightningElement, track } from 'lwc';
import Toast from 'lightning/toast';
import BarnConfirmModal from 'c/barnConfirmModal';
import hasManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import preview from '@salesforce/apex/HouseholdController.preview';
import getNamingSettings from '@salesforce/apex/HouseholdController.getNamingSettings';
import recomputeAll from '@salesforce/apex/HouseholdController.recomputeAll';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';

import TITLE from '@salesforce/label/c.Core_SettingsGroup_HouseholdNames';
import NAME_LABEL from '@salesforce/label/c.Core_HouseholdNamingSettings_NameLabel';
import FORMAL_LABEL from '@salesforce/label/c.Core_HouseholdNamingSettings_FormalLabel';
import INFORMAL_LABEL from '@salesforce/label/c.Core_HouseholdNamingSettings_InformalLabel';
import PREVIEW_HEADING from '@salesforce/label/c.Core_HouseholdNamingSettings_PreviewHeading';
import COLUMN_MEMBERS from '@salesforce/label/c.Core_SettingsGroup_People';
import COLUMN_NAME from '@salesforce/label/c.Core_HouseholdNamingSettings_ColumnName';
import COLUMN_FORMAL from '@salesforce/label/c.Core_HouseholdNamingSettings_ColumnFormal';
import COLUMN_INFORMAL from '@salesforce/label/c.Core_HouseholdNamingSettings_ColumnInformal';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import SAVED from '@salesforce/label/c.Core_HouseholdNamingSettings_Saved';
import RECOMPUTE from '@salesforce/label/c.Core_HouseholdNamingSettings_Recompute';
import RECOMPUTE_CONFIRM from '@salesforce/label/c.Core_HouseholdNamingSettings_RecomputeConfirm';
import RECOMPUTE_STARTED from '@salesforce/label/c.Core_HouseholdNamingSettings_RecomputeStarted';
import READ_ONLY from '@salesforce/label/c.Core_HouseholdNamingSettings_ReadOnly';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import CONFIRM from '@salesforce/label/c.Core_HouseholdNamingSettings_Confirm';
import SAVING from '@salesforce/label/c.Core_HouseholdScreens_Saving';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { PARTS, insertPart, positionAtOffset } from './patternParts';

const DEBOUNCE_MILLISECONDS = 300;
// What the package ships. Used only until this org's own saved patterns arrive, and where
// the org has never saved one of the three.
const SHIPPED_NAME_PATTERN = 'The {LastName} Family';
const SHIPPED_FORMAL_PATTERN = '{Salutation} {FirstName} {LastName}';
const SHIPPED_INFORMAL_PATTERN = '{FirstName}';
const NAME_KEY = 'Household_Name_Pattern__c';
const FORMAL_KEY = 'Formal_Greeting_Pattern__c';
const INFORMAL_KEY = 'Informal_Greeting_Pattern__c';
/** How far a pointer moves before a press on a part becomes a drag, in pixels. */
const DRAG_THRESHOLD = 5;
const INPUT_CLASS = 'slds-input';
const DROP_TARGET_CLASS = 'slds-input pattern_drop-target';

/** The three patterns, in the order they show, by the property that holds each. */
const PATTERN_FIELDS = [
  { key: 'name', property: 'namePattern', label: NAME_LABEL },
  { key: 'formal', property: 'formalPattern', label: FORMAL_LABEL },
  { key: 'informal', property: 'informalPattern', label: INFORMAL_LABEL }
];

/** A context that measures text in the font a pattern box uses, or undefined. */
function textMeasure(input) {
  try {
    const canvas = document.createElement('canvas');
    const context = typeof canvas.getContext === 'function' ? canvas.getContext('2d') : null;
    if (!context || typeof context.measureText !== 'function') {
      return undefined;
    }
    const style = window.getComputedStyle(input);
    context.font = style.font || `${style.fontSize} ${style.fontFamily}`;
    return (text) => context.measureText(text).width;
  } catch {
    return undefined;
  }
}

export default class HouseholdNamingSettings extends LightningElement {
  helpReady = isHelpLoaded('Core');

  label = {
    title: TITLE,
    get tokenHelp() {
      return helpText('Core', 'Core_HouseholdNamingSettings_TokenHelp');
    },
    previewHeading: PREVIEW_HEADING,
    columnMembers: COLUMN_MEMBERS,
    columnName: COLUMN_NAME,
    columnFormal: COLUMN_FORMAL,
    columnInformal: COLUMN_INFORMAL,
    save: SAVE,
    recompute: RECOMPUTE,
    readOnly: READ_ONLY,
    saving: SAVING
  };

  parts = PARTS;

  namePattern = SHIPPED_NAME_PATTERN;
  formalPattern = SHIPPED_FORMAL_PATTERN;
  informalPattern = SHIPPED_INFORMAL_PATTERN;

  @track samples = [];
  errorMessage;
  isSaving = false;
  /** The last part added, said by the aria-live region. */
  announcement = '';
  /** The pattern a dragged part is over, outlined while it is. */
  dropTarget;

  debounceTimer;
  /** Counts previews, so a slow answer for earlier patterns cannot replace a newer one. */
  previewSequence = 0;
  /** A press on a part: `{ part, pointerId, x, y, dragging }` until it is released. */
  press;
  /** Set when a drag ended, so the click the browser fires after it adds nothing. */
  suppressClick = false;

  get canEdit() {
    return hasManageSettings === true;
  }

  get isReadOnly() {
    return !this.canEdit;
  }

  get hasSamples() {
    return this.samples.length > 0;
  }

  get isSaveDisabled() {
    return this.isReadOnly || this.isSaving;
  }

  /** The three pattern boxes, each with its parts row. */
  get patterns() {
    return PATTERN_FIELDS.map((field) => ({
      key: field.key,
      label: field.label,
      value: this[field.property],
      inputId: `pattern-${field.key}`,
      inputClass: this.dropTarget === field.key ? DROP_TARGET_CLASS : INPUT_CLASS,
      partsLabel: helpText('Core', 'Core_HouseholdNamingSettings_PartsHelp')
    }));
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    // The page opens on this org's own wording, not on what the package ships, so that
    // saving again never writes the shipped patterns over what an admin chose before.
    return getNamingSettings()
      .then((saved) => {
        if (saved) {
          this.namePattern = saved.namePattern || SHIPPED_NAME_PATTERN;
          this.formalPattern = saved.formalPattern || SHIPPED_FORMAL_PATTERN;
          this.informalPattern = saved.informalPattern || SHIPPED_INFORMAL_PATTERN;
        }
        return this.refreshPreview();
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
        return this.refreshPreview();
      });
  }

  disconnectedCallback() {
    clearTimeout(this.debounceTimer);
  }

  fieldFor(key) {
    return PATTERN_FIELDS.find((field) => field.key === key);
  }

  inputFor(key) {
    return Array.from(this.template.querySelectorAll('input[data-pattern]')).find(
      (input) => input.dataset.pattern === key
    );
  }

  handlePatternInput(event) {
    const field = this.fieldFor(event.target.dataset.pattern);
    if (field) {
      this[field.property] = event.target.value;
      this.schedulePreview();
    }
  }

  /** A part clicked, or chosen with Enter or Space: it goes where the cursor is in that box. */
  handlePartClick(event) {
    if (this.suppressClick) {
      this.suppressClick = false;
      return;
    }
    const { part, pattern } = event.currentTarget.dataset;
    const input = this.inputFor(pattern);
    const start = input ? input.selectionStart : undefined;
    const end = input ? input.selectionEnd : undefined;
    this.addPart(pattern, part, start, end);
  }

  /** Puts a part into a pattern, moves the cursor after it, and says so. */
  addPart(patternKey, part, start, end) {
    const field = this.fieldFor(patternKey);
    if (!field || this.isReadOnly) {
      return;
    }
    const result = insertPart(this[field.property], part, start, end);
    this[field.property] = result.value;
    const input = this.inputFor(patternKey);
    if (input) {
      input.value = result.value;
      if (typeof input.focus === 'function') {
        input.focus();
      }
      if (typeof input.setSelectionRange === 'function') {
        input.setSelectionRange(result.caret, result.caret);
      }
    }
    this.announcement = helpText(
      'Core',
      'Core_HouseholdNamingSettings_PartAdded',
      part,
      field.label
    );
    this.schedulePreview();
  }

  // Dragging uses pointer events, so a mouse, a pen and a finger all work. Clicking stays the
  // keyboard and phone path; a press that moves less than a few pixels is a click.
  handlePartPointerDown(event) {
    if (this.isReadOnly || (event.button !== undefined && event.button !== 0)) {
      return;
    }
    this.press = {
      part: event.currentTarget.dataset.part,
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      dragging: false
    };
  }

  handlePartPointerMove(event) {
    const press = this.press;
    if (!press || press.pointerId !== event.pointerId) {
      return;
    }
    if (!press.dragging) {
      const moved = Math.hypot(event.clientX - press.x, event.clientY - press.y);
      if (moved < DRAG_THRESHOLD) {
        return;
      }
      press.dragging = true;
      const button = event.currentTarget;
      button.classList.add('part_dragging');
      if (typeof button.setPointerCapture === 'function' && event.pointerId !== undefined) {
        try {
          button.setPointerCapture(event.pointerId);
        } catch {
          // A pointer that cannot be captured still drags while it stays over the page.
        }
      }
    }
    const target = this.inputAt(event.clientX, event.clientY);
    this.dropTarget = target ? target.dataset.pattern : undefined;
  }

  handlePartPointerUp(event) {
    const press = this.press;
    this.press = undefined;
    event.currentTarget.classList.remove('part_dragging');
    this.dropTarget = undefined;
    if (!press || !press.dragging) {
      return;
    }
    this.suppressClick = true;
    const input = this.inputAt(event.clientX, event.clientY);
    if (!input) {
      return;
    }
    const position = this.positionIn(input, event.clientX);
    this.addPart(input.dataset.pattern, press.part, position, position);
  }

  handlePartPointerCancel(event) {
    this.press = undefined;
    this.dropTarget = undefined;
    event.currentTarget.classList.remove('part_dragging');
  }

  /** The pattern box under a point on the screen, if any. */
  inputAt(x, y) {
    return Array.from(this.template.querySelectorAll('input[data-pattern]')).find((input) => {
      const box = input.getBoundingClientRect();
      return x >= box.left && x <= box.right && y >= box.top && y <= box.bottom;
    });
  }

  /** Where in a box's text a drop at this point lands: the nearest gap between characters. */
  positionIn(input, x) {
    const box = input.getBoundingClientRect();
    const style = window.getComputedStyle(input);
    const offset =
      x -
      box.left -
      (parseFloat(style.paddingLeft) || 0) -
      (parseFloat(style.borderLeftWidth) || 0) +
      (input.scrollLeft || 0);
    return positionAtOffset(input.value, offset, textMeasure(input));
  }

  schedulePreview() {
    clearTimeout(this.debounceTimer);
    // The preview waits for a pause in typing rather than asking on every keystroke.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.debounceTimer = setTimeout(() => {
      this.refreshPreview();
    }, DEBOUNCE_MILLISECONDS);
  }

  refreshPreview() {
    const sequence = ++this.previewSequence;
    return preview({
      namePattern: this.namePattern,
      formalPattern: this.formalPattern,
      informalPattern: this.informalPattern
    })
      .then((rows) => {
        if (sequence === this.previewSequence) {
          this.samples = (rows || []).map((row, index) => ({ ...row, key: `sample-${index}` }));
          this.errorMessage = undefined;
        }
      })
      .catch((error) => {
        if (sequence === this.previewSequence) {
          this.samples = [];
          this.errorMessage = this.readError(error);
        }
      });
  }

  handleSave() {
    this.isSaving = true;
    const values = {};
    values[NAME_KEY] = this.namePattern;
    values[FORMAL_KEY] = this.formalPattern;
    values[INFORMAL_KEY] = this.informalPattern;
    // The key must match the Apex parameter name (SettingsController.saveSettings(values)).
    return saveSettings({ values })
      .then(() => {
        this.errorMessage = undefined;
        this.toast(SAVED, 'success');
        // The Setup Assistant embeds this panel and listens for "save" to tick its naming
        // step, the same event name setupStepFields dispatches for the same purpose.
        this.dispatchEvent(new CustomEvent('save', { detail: { values } }));
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.isSaving = false;
      });
  }

  async handleRecomputeClick() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: RECOMPUTE,
      message: RECOMPUTE_CONFIRM,
      confirmLabel: CONFIRM,
      cancelLabel: CANCEL
    });
    if (!confirmed) {
      return undefined;
    }
    return recomputeAll()
      .then(() => {
        this.errorMessage = undefined;
        this.toast(RECOMPUTE_STARTED, 'success');
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      });
  }

  toast(message, variant) {
    Toast.show({ label: message, variant }, this);
  }

  readError(error) {
    if (!error) {
      return undefined;
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message;
  }
}
