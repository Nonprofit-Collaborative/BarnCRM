import { LightningElement, api } from 'lwc';
import getModel from '@salesforce/apex/LogicModelBuilderController.getModel';
import getPrograms from '@salesforce/apex/LogicModelBuilderController.getPrograms';
import setProgram from '@salesforce/apex/LogicModelBuilderController.setProgram';
import saveElement from '@salesforce/apex/LogicModelBuilderController.saveElement';
import saveOrder from '@salesforce/apex/LogicModelBuilderController.saveOrder';

import { downloadCsv } from 'c/findCsv';
import { createDragController } from 'c/barnDrag';
import { dragInstructions, dragMessages } from 'c/barnDragText';
import {
  RESULTS_SHEET_COLUMNS,
  backwardLinks,
  canMoveTo,
  columns,
  dropOrders,
  findings,
  linkTargets,
  liveLinks,
  nextOrder,
  resultsSheetRows,
  stageByKey
} from 'c/logicModelRules';
import {
  LABELS,
  arrowDragMessages,
  backwardMessage,
  DRAG_TEXT,
  format,
  messageFrom,
  stageLabel
} from 'c/logicModelText';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

const ORGANIZATION = '';
const SELECTED_PART = 'selected-part';
const PART_TILE = 'part-tile';
const HELP = ['LogicModels', 'Core'];

/** The width at which the columns sit side by side (logicModelBuilder.css); below it they stack. */
const SIDE_BY_SIDE = '(min-width: 64em)';

function columnsSideBySide() {
  return typeof window === 'undefined' || typeof window.matchMedia !== 'function'
    ? true
    : window.matchMedia(SIDE_BY_SIDE).matches;
}

/**
 * The Logic Model Builder panel on a logic model (L-01 to L-04): whose model it is, the seven
 * columns of parts drawn left to right, the selected part with its arrows and indicators, what
 * needs attention, and the Logic Model Report.
 * Every save returns the whole model, which the panel redraws.
 *
 * Drag and drop is an addition (DnD-2, DnD-3, c/barnDrag): a part's handle moves it within its
 * column or to another one, and its arrow handle dropped on a later part opens Add Arrow with
 * that part chosen. Edit, Move Up, Move Down and Add Arrow stay. On a phone, where the columns
 * stack, a part reorders within its column only and arrows are drawn with the form.
 */
export default class LogicModelBuilder extends LightningElement {
  helpReady = isHelpLoaded(HELP);

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
  /** c/barnDrag's state while a part is moved, and while an arrow is drawn. */
  moveState = {};
  arrowState = {};
  dragAnnouncement = '';
  /** The part an arrow was dropped on: the Add Arrow form opens with it once drawn. */
  pendingArrowTarget;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    const announce = (text) => {
      this.dragAnnouncement = text;
    };
    this.moveDrag = createDragController({
      root: this.template,
      layout: 'columns',
      // A column is a move zone and each part row an arrow zone; both carry data-drop-zone.
      zoneSelector: '[data-move-zone]',
      itemSelector: '[data-move-handle]',
      messages: dragMessages(),
      announce,
      onChange: (state) => {
        this.moveState = state;
      },
      canDrop: (itemId, fromZone, toZone) =>
        fromZone === toZone || (columnsSideBySide() && canMoveTo(this.model, itemId, toZone)),
      onDrop: (drop) => this.dropPart(drop)
    });
    this.arrowDrag = createDragController({
      root: this.template,
      layout: 'columns',
      zoneSelector: '[data-arrow-zone]',
      itemSelector: '[data-arrow-handle]',
      messages: arrowDragMessages(),
      announce,
      onChange: (state) => {
        this.arrowState = state;
      },
      canDrop: (itemId, fromZone, toZone) =>
        columnsSideBySide() &&
        linkTargets(this.model, itemId).some((element) => element.id === toZone),
      onDrop: (drop) => this.dropArrow(drop)
    });
    this.load();
  }

  disconnectedCallback() {
    if (this.moveDrag) {
      this.moveDrag.destroy();
    }
    if (this.arrowDrag) {
      this.arrowDrag.destroy();
    }
  }

  renderedCallback() {
    this.openPendingArrow();
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
    const move = this.moveState || {};
    const arrow = this.arrowState || {};
    const canEdit = this.canEdit;
    return columns(this.model).map((column, index) => {
      const name = stageLabel(column.key);
      const over = !!move.active && move.overZone === column.key;
      const others = column.elements.filter((element) => element.id !== move.itemId);
      return {
        key: column.key,
        name,
        count: String(column.elements.length),
        showSeparator: index > 0,
        addLabel: format(LABELS.addTo, name),
        adding: this.addingStage === column.key,
        empty: column.elements.length === 0,
        columnClass: [
          'diagram__column',
          over ? 'diagram__column_over' : '',
          over && move.overIndex === others.length ? 'diagram__column_drop-end' : ''
        ]
          .filter(Boolean)
          .join(' '),
        elements: column.elements.map((element) => {
          const moving = !!move.active && move.itemId === element.id;
          const before = over && !moving && others.indexOf(element) === move.overIndex;
          const arrowSource = !!arrow.active && arrow.itemId === element.id;
          const arrowTarget = !!arrow.active && arrow.overZone === element.id;
          return {
            id: element.id,
            name: element.name,
            pressed: element.id === this.selectedId ? 'true' : 'false',
            className: this.partClass(element.id, linked),
            rowClass: [
              'part-row',
              moving ? 'part-row_moving' : '',
              before ? 'part-row_drop-before' : '',
              arrowSource ? 'part-row_arrow-source' : '',
              arrowTarget ? 'part-row_arrow-target' : ''
            ]
              .filter(Boolean)
              .join(' '),
            moveLabel: DRAG_TEXT.moveHandle(element.name),
            arrowLabel: DRAG_TEXT.arrowHandle(element.name),
            canDrawArrow: canEdit && linkTargets(this.model, element.id).length > 0
          };
        })
      };
    });
  }

  get dragInstructions() {
    return dragInstructions();
  }

  get arrowInstructions() {
    return DRAG_TEXT.arrowInstructions();
  }

  get dragHint() {
    return DRAG_TEXT.hint();
  }

  // -------------------------------------------------------------------- drag and drop

  handleMovePointerDown(event) {
    if (this.canEdit && !this.busy) {
      this.moveDrag.pointerDown(event);
    }
  }

  handleMoveKey(event) {
    if (this.canEdit && !this.busy) {
      this.moveDrag.keyDown(event);
    }
  }

  handleArrowPointerDown(event) {
    if (this.canEdit && !this.busy) {
      this.arrowDrag.pointerDown(event);
    }
  }

  handleArrowKey(event) {
    if (this.canEdit && !this.busy) {
      this.arrowDrag.keyDown(event);
    }
  }

  /**
   * A part dropped in a column (DnD-2): within its own column the column is renumbered, as Move
   * Up and Move Down do; in another column it changes column first, then takes its place. A
   * change the arrow rules refuse snaps back with the Edit form's message naming the arrows.
   */
  dropPart({ itemId, fromZone, toZone, toIndex }) {
    const element = this.model.elements.find((item) => item.id === itemId);
    if (!element) {
      return false;
    }
    if (fromZone === toZone) {
      const orders = dropOrders(this.model, itemId, toZone, toIndex);
      return this.run(saveOrder({ modelId: this.model.id, ordersJson: JSON.stringify(orders) }));
    }
    const backward = backwardLinks(this.model, itemId, toZone);
    if (backward.length) {
      this.errorMessage = backwardMessage(backward);
      return false;
    }
    const stage = stageByKey(toZone);
    const changed = {
      id: itemId,
      name: element.name,
      description: element.description,
      type: stage.type,
      term: stage.term
    };
    return this.run(
      saveElement({ elementJson: JSON.stringify(changed) }).then((model) =>
        saveOrder({
          modelId: model.id,
          ordersJson: JSON.stringify(dropOrders(model, itemId, toZone, toIndex))
        })
      )
    );
  }

  /** An arrow dropped on a later part (DnD-3): Add Arrow opens on the first part with it chosen. */
  dropArrow({ itemId, toZone }) {
    this.addingStage = undefined;
    this.selectedId = itemId;
    this.pendingArrowTarget = toZone;
    return true;
  }

  openPendingArrow() {
    if (!this.pendingArrowTarget) {
      return;
    }
    const part = this.template.querySelector('[data-id="selected-part"]');
    if (part) {
      const target = this.pendingArrowTarget;
      this.pendingArrowTarget = undefined;
      part.startArrow(target);
    }
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

  /** Runs one save, shows the model it returns and announces it once; true when it saved. */
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
        return true;
      })
      .catch((error) => {
        this.errorMessage = messageFrom(error);
        this.focusTarget = 'error-message';
        // A drop that failed snaps back (c/barnDrag reads false as refused).
        return false;
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
