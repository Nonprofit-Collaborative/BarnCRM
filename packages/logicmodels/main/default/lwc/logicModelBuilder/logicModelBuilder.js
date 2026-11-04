import { LightningElement, api } from 'lwc';
import getModel from '@salesforce/apex/LogicModelBuilderController.getModel';
import getPrograms from '@salesforce/apex/LogicModelBuilderController.getPrograms';
import setProgram from '@salesforce/apex/LogicModelBuilderController.setProgram';
import saveElement from '@salesforce/apex/LogicModelBuilderController.saveElement';

import { downloadCsv } from 'c/findCsv';
import {
  RESULTS_SHEET_COLUMNS,
  columns,
  findings,
  liveLinks,
  nextOrder,
  resultsSheetRows,
  stageByKey
} from 'c/logicModelRules';
import { LABELS, format, messageFrom, stageLabel } from 'c/logicModelText';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

const ORGANIZATION = '';
const SELECTED_PART = 'selected-part';
const PART_TILE = 'part-tile';

/**
 * The Logic Model Builder panel on a logic model (L-01 to L-04): whose model it is, the seven
 * columns of parts drawn left to right, the selected part with its arrows and indicators, what
 * needs attention, and the Logic Model Report.
 * Every save returns the whole model, which the panel redraws.
 */
export default class LogicModelBuilder extends LightningElement {
  helpReady = isHelpLoaded('LogicModels');

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
    if (!this.helpReady) {
      loadHelp('LogicModels').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  renderedCallback() {
    this.applyFocus();
  }

  /** Moves focus to what the last action asked for, once it is on screen. */
  applyFocus() {
    if (!this.focusTarget) {
      return;
    }
    if (this.focusTarget === SELECTED_PART) {
      // The details sit below the columns, a screen away on a phone: take the person there.
      const part = this.template.querySelector('[data-id="selected-part"]');
      if (part) {
        this.focusTarget = undefined;
        part.focusHeading();
      }
      return;
    }
    if (this.focusTarget === PART_TILE) {
      const tile = this.template.querySelector(
        `[data-id="part"][data-record-id="${this.selectedId}"]`
      );
      if (tile) {
        this.focusTarget = undefined;
        if (tile.scrollIntoView) {
          tile.scrollIntoView({ block: 'center' });
        }
        tile.focus();
      }
      return;
    }
    const target = this.template.querySelector(`[data-id="${this.focusTarget}"]`);
    if (target) {
      this.focusTarget = undefined;
      target.focus();
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

  /**
   * Saves the results sheet (L-03, R-IN3): one row per period of every indicator that is not
   * computed, with the columns the Indicator Results import template reads.
   */
  handleDownloadResults() {
    const rows = resultsSheetRows(this.model);
    if (!rows.length) {
      this.errorMessage = LABELS.noResultRows;
      return;
    }
    this.errorMessage = undefined;
    downloadCsv('Indicator_Results', RESULTS_SHEET_COLUMNS, rows);
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

  /** The parts an arrow joins to the selected one, either way: drawn with a brand border. */
  get linkedIds() {
    const linked = new Set();
    if (!this.selectedId) {
      return linked;
    }
    for (const link of liveLinks(this.model)) {
      if (link.fromId === this.selectedId) {
        linked.add(link.toId);
      } else if (link.toId === this.selectedId) {
        linked.add(link.fromId);
      }
    }
    return linked;
  }

  partClass(id, linked) {
    if (id === this.selectedId) {
      return 'part part_selected';
    }
    if (!this.selectedId) {
      return 'part';
    }
    return linked.has(id) ? 'part part_linked' : 'part part_dimmed';
  }

  get columns() {
    const linked = this.linkedIds;
    return columns(this.model).map((column, index) => {
      const name = stageLabel(column.key);
      return {
        key: column.key,
        name,
        count: String(column.elements.length),
        showSeparator: index > 0,
        addLabel: format(LABELS.addTo, name),
        adding: this.addingStage === column.key,
        empty: column.elements.length === 0,
        elements: column.elements.map((element) => ({
          id: element.id,
          name: element.name,
          pressed: element.id === this.selectedId ? 'true' : 'false',
          className: this.partClass(element.id, linked)
        }))
      };
    });
  }

  handleSelect(event) {
    const id = event.currentTarget.dataset.recordId;
    this.selectedId = this.selectedId === id ? undefined : id;
    if (this.selectedId) {
      this.focusTarget = SELECTED_PART;
    }
  }

  /** Back to the Model: from the part's details to its tile in the columns. */
  handleBack() {
    // Nothing on screen changes, so the tile is focused now rather than after a render.
    this.focusTarget = PART_TILE;
    this.applyFocus();
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
