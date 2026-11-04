import { LightningElement, api } from 'lwc';
import RECOMMENDED from '@salesforce/label/c.Core_SetupAssistant_RecommendedLabel';
import MODE_LABEL from '@salesforce/label/c.Core_SetupAssistant_ModeLabel';
import MODE_STANDALONE from '@salesforce/label/c.Core_CoexistenceMode_Standalone';
import MODE_NPSP from '@salesforce/label/c.Core_CoexistenceMode_Npsp';
import MODE_NONPROFIT_CLOUD from '@salesforce/label/c.Core_CoexistenceMode_NonprofitCloud';
import CONFIRM from '@salesforce/label/c.Core_SetupAssistant_ConfirmButton';
import OTHER_ROLLUP_TOOLS from '@salesforce/label/c.Core_OtherRollupTools_Title';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const SHAPE_TEXT = {
  get PersonAccounts() {
    return helpText('Core', 'Core_SetupAssistant_ShapePersonAccounts');
  },
  get Npsp() {
    return helpText('Core', 'Core_SetupAssistant_ShapeNpsp');
  },
  get Fresh() {
    return helpText('Core', 'Core_SetupAssistant_ShapeFresh');
  }
};

const MODE_TEXT = {
  Standalone: MODE_STANDALONE,
  NPSP: MODE_NPSP,
  NonprofitCloud: MODE_NONPROFIT_CLOUD
};

/**
 * Step one: what BarnCRM found in this org, in plain words, leading with the
 * Nonprofit Cloud case, and the mode it recommends because of it.
 */
export default class SetupStepCoexistence extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  @api canEdit = false;

  chosen;

  labels = {
    recommended: RECOMMENDED,
    mode: MODE_LABEL,
    confirm: CONFIRM,
    otherRollupTools: OTHER_ROLLUP_TOOLS
  };

  _coexistence = {};

  @api
  get coexistence() {
    return this._coexistence;
  }

  set coexistence(value) {
    this._coexistence = value || {};
    this.chosen = this._coexistence.currentMode || this._coexistence.recommendedMode;
  }

  get isReadOnly() {
    return !this.canEdit;
  }

  get shapeText() {
    return (
      SHAPE_TEXT[this._coexistence.detectedShape] ||
      helpText('Core', 'Core_SetupAssistant_ShapeFresh')
    );
  }

  /** DLRS or Rollup Helper found in the org: separate tools BarnCRM does not manage (R-R16). */
  get otherRollupTools() {
    return this._coexistence.otherRollupTools || [];
  }

  get hasOtherRollupTools() {
    return this.otherRollupTools.length > 0;
  }

  get recommendedText() {
    return MODE_TEXT[this._coexistence.recommendedMode] || this._coexistence.recommendedMode;
  }

  get options() {
    return (this._coexistence.modes || []).map((mode) => ({
      label: MODE_TEXT[mode] || mode,
      value: mode
    }));
  }

  handleModeChange(event) {
    this.chosen = event.detail.value;
  }

  handleConfirm() {
    this.dispatchEvent(new CustomEvent('confirm', { detail: { mode: this.chosen } }));
  }
}
