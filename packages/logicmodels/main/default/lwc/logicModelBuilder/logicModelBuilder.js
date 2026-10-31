import { LightningElement, api } from 'lwc';
import getModel from '@salesforce/apex/LogicModelBuilderController.getModel';
import getPrograms from '@salesforce/apex/LogicModelBuilderController.getPrograms';
import setProgram from '@salesforce/apex/LogicModelBuilderController.setProgram';
import saveElement from '@salesforce/apex/LogicModelBuilderController.saveElement';

import { columns, findings, nextOrder, stageByKey } from 'c/logicModelRules';
import { LABELS, format, messageFrom, stageLabel } from 'c/logicModelText';

const ORGANIZATION = '';

/**
 * The Logic Model Builder panel on a logic model (L-01, L-02): whose model it is, the seven
 * columns of parts, the selected part with its arrows and indicators, and what needs attention.
 * Every save returns the whole model, which the panel redraws.
 */
export default class LogicModelBuilder extends LightningElement {
  @api recordId;

  labels = LABELS;
  model;
  loading = true;
  busy = false;
  errorMessage;
  resultMessage;
  selectedId;
  addingStage;
  draftName = '';
  changingScope = false;
  programOptions = [];
  draftProgramId = ORGANIZATION;
  focusTarget;

  connectedCallback() {
    this.load();
  }

  renderedCallback() {
    if (this.focusTarget) {
      const target = this.template.querySelector(`[data-id="${this.focusTarget}"]`);
      if (target) {
        this.focusTarget = undefined;
        target.focus();
      }
    }
  }

  load() {
    return getModel({ modelId: this.recordId })
      .then((model) => {
        this.model = model;
      })
      .catch((error) => {
        this.errorMessage = messageFrom(error);
      })
      .finally(() => {
        this.loading = false;
      });
  }

  get loaded() {
    return !!this.model;
  }

  get showSpinner() {
    return this.loading || this.busy;
  }

  get canEdit() {
    return !!(this.model && this.model.canEdit);
  }

  get canDelete() {
    return !!(this.model && this.model.canDelete);
  }

  get hasError() {
    return !!this.errorMessage;
  }

  // ------------------------------------------------------------------------------ scope

  get scopeName() {
    if (!this.model || !this.model.programId) {
      return LABELS.wholeOrganization;
    }
    return this.model.programMissing ? LABELS.programMissing : this.model.programName;
  }

  get canChangeScope() {
    return this.canEdit && !!this.model.programsAvailable && !this.changingScope;
  }

  get scopeOptions() {
    return [{ value: ORGANIZATION, label: LABELS.wholeOrganization }, ...this.programOptions];
  }

  handleChangeScope() {
    this.busy = true;
    this.errorMessage = undefined;
    return getPrograms()
      .then((options) => {
        this.programOptions = options || [];
        this.draftProgramId = this.model.programId || ORGANIZATION;
        this.changingScope = true;
        this.focusTarget = 'scope-picker';
      })
      .catch((error) => {
        this.errorMessage = messageFrom(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleScopePick(event) {
    this.draftProgramId = event.detail.value;
  }

  handleScopeCancel() {
    this.changingScope = false;
  }

  handleScopeSave() {
    return this.run(
      setProgram({ modelId: this.recordId, programId: this.draftProgramId || null }),
      () => {
        this.changingScope = false;
      }
    );
  }

  // ---------------------------------------------------------------------------- columns

  get columns() {
    return columns(this.model).map((column) => {
      const name = stageLabel(column.key);
      return {
        key: column.key,
        name,
        addLabel: format(LABELS.addTo, name),
        adding: this.addingStage === column.key,
        empty: column.elements.length === 0,
        elements: column.elements.map((element) => ({
          id: element.id,
          name: element.name,
          pressed: element.id === this.selectedId ? 'true' : 'false',
          className:
            'slds-button slds-button_stretch slds-var-m-bottom_xx-small ' +
            (element.id === this.selectedId ? 'slds-button_brand' : 'slds-button_neutral')
        }))
      };
    });
  }

  handleSelect(event) {
    const id = event.currentTarget.dataset.recordId;
    this.selectedId = this.selectedId === id ? undefined : id;
  }

  handleAdd(event) {
    this.addingStage = event.currentTarget.dataset.stage;
    this.draftName = '';
    this.focusTarget = 'draft-name';
  }

  handleDraftName(event) {
    this.draftName = event.target.value;
  }

  handleAddCancel() {
    this.addingStage = undefined;
  }

  get addDisabled() {
    return this.busy || !this.draftName || !this.draftName.trim();
  }

  handleAddSave() {
    const stage = stageByKey(this.addingStage);
    const element = {
      modelId: this.recordId,
      name: this.draftName,
      type: stage.type,
      term: stage.term,
      sortOrder: nextOrder(this.model, stage.key)
    };
    return this.run(saveElement({ elementJson: JSON.stringify(element) }), () => {
      this.addingStage = undefined;
    });
  }

  // --------------------------------------------------------------------- selected part

  get hasSelection() {
    return !!(
      this.selectedId &&
      this.model &&
      this.model.elements.some((element) => element.id === this.selectedId)
    );
  }

  /** A child panel saved or deleted something and hands back the whole model. */
  handleModelChange(event) {
    this.model = event.detail.model;
    this.errorMessage = undefined;
    this.resultMessage = event.detail.message || LABELS.saved;
    this.focusTarget = 'result';
  }

  handleChildError(event) {
    this.errorMessage = event.detail.message;
    this.focusTarget = 'error-message';
  }

  // ------------------------------------------------------------------------- findings

  get findings() {
    return findings(this.model).map((finding, index) => {
      let text;
      if (finding.code === 'emptyStage') {
        const name = finding.stage === 'Outcome' ? LABELS.outcomes : stageLabel(finding.stage);
        text = format(LABELS.findingEmpty, name);
      } else if (finding.code === 'noArrowIn') {
        text = format(LABELS.findingNoIn, finding.name);
      } else if (finding.code === 'noArrowOut') {
        text = format(LABELS.findingNoOut, finding.name);
      } else {
        text = format(LABELS.findingNoIndicator, finding.name);
      }
      return { key: `${finding.code}-${finding.stage || finding.elementId}-${index}`, text };
    });
  }

  get hasFindings() {
    return this.findings.length > 0;
  }

  // ---------------------------------------------------------------------------- saving

  /** Runs one save, shows the model it returns and announces it once. */
  run(call, after) {
    this.busy = true;
    this.errorMessage = undefined;
    return call
      .then((model) => {
        this.model = model;
        if (after) {
          after();
        }
        this.resultMessage = LABELS.saved;
        this.focusTarget = 'result';
      })
      .catch((error) => {
        this.errorMessage = messageFrom(error);
        this.focusTarget = 'error-message';
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
