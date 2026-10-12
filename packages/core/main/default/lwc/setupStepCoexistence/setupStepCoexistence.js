import { LightningElement, api } from 'lwc';
import SHAPE_PERSON_ACCOUNTS from '@salesforce/label/c.Core_SetupAssistant_ShapePersonAccounts';
import SHAPE_NPSP from '@salesforce/label/c.Core_SetupAssistant_ShapeNpsp';
import SHAPE_FRESH from '@salesforce/label/c.Core_SetupAssistant_ShapeFresh';
import RECOMMENDED from '@salesforce/label/c.Core_SetupAssistant_RecommendedLabel';
import MODE_LABEL from '@salesforce/label/c.Core_SetupAssistant_ModeLabel';
import MODE_STANDALONE from '@salesforce/label/c.Core_SetupAssistant_ModeStandalone';
import MODE_NPSP from '@salesforce/label/c.Core_SetupAssistant_ModeNpsp';
import MODE_AGENTFORCE from '@salesforce/label/c.Core_SetupAssistant_ModeAgentforce';
import CONFIRM from '@salesforce/label/c.Core_SetupAssistant_ConfirmButton';

const SHAPE_TEXT = {
  PersonAccounts: SHAPE_PERSON_ACCOUNTS,
  Npsp: SHAPE_NPSP,
  Fresh: SHAPE_FRESH
};

const MODE_TEXT = {
  Standalone: MODE_STANDALONE,
  NPSP: MODE_NPSP,
  AgentforceNonprofit: MODE_AGENTFORCE
};

/**
 * Step one: what BarnCRM found in this org, in plain words, leading with the
 * Nonprofit Cloud case, and the mode it recommends because of it.
 */
export default class SetupStepCoexistence extends LightningElement {
  @api canEdit = false;

  chosen;

  labels = {
    recommended: RECOMMENDED,
    mode: MODE_LABEL,
    confirm: CONFIRM
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
    return SHAPE_TEXT[this._coexistence.detectedShape] || SHAPE_FRESH;
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
