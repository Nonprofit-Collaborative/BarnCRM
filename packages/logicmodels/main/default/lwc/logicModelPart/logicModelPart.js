import { LightningElement, api } from 'lwc';
import saveElement from '@salesforce/apex/LogicModelBuilderController.saveElement';
import saveOrder from '@salesforce/apex/LogicModelBuilderController.saveOrder';
import saveLink from '@salesforce/apex/LogicModelBuilderController.saveLink';
import remove from '@salesforce/apex/LogicModelBuilderController.remove';

import {
  STAGES,
  liveLinks,
  linkTargets,
  moveOrders,
  stageByKey,
  stageOf,
  takesIndicators
} from 'c/logicModelRules';
import { LABELS, messageFrom, stageLabel } from 'c/logicModelText';

/**
 * The selected part of a logic model (L-01): its name, description and column, its place in the
 * column, deleting it, and the arrows out of it and into it with their assumptions. Outputs and
 * outcomes also show their indicators (L-02). Each save hands the whole model back to the
 * builder in a `modelchange` event; a refusal goes up as `failure`.
 */
export default class LogicModelPart extends LightningElement {
  @api model;
  @api elementId;
  @api canEdit = false;
  @api canDelete = false;

  labels = LABELS;
  busy = false;
  editing = false;
  draftName = '';
  draftDescription = '';
  draftStage;
  confirmingDelete = false;
  addingArrow = false;
  draftTargetId;
  draftAssumption = '';
  editingLinkId;
  draftLinkAssumption = '';

  get element() {
    return ((this.model && this.model.elements) || []).find((item) => item.id === this.elementId);
  }

  get name() {
    return this.element ? this.element.name : '';
  }

  get description() {
    return this.element ? this.element.description : '';
  }

  get columnName() {
    const stage = stageOf(this.element);
    return stage ? stageLabel(stage.key) : '';
  }

  get showActions() {
    return this.canEdit && !this.editing && !this.confirmingDelete;
  }

  get measured() {
    return takesIndicators(this.element);
  }

  // ------------------------------------------------------------------------------ edit

  get stageOptions() {
    const hasIndicators = ((this.model && this.model.indicators) || []).some(
      (indicator) => indicator.elementId === this.elementId
    );
    return STAGES.filter((stage) => !hasIndicators || stage.measured).map((stage) => ({
      value: stage.key,
      label: stageLabel(stage.key)
    }));
  }

  handleEdit() {
    this.editing = true;
    this.draftName = this.element.name;
    this.draftDescription = this.element.description || '';
    this.draftStage = stageOf(this.element).key;
  }

  handleDraftName(event) {
    this.draftName = event.target.value;
  }

  handleDraftDescription(event) {
    this.draftDescription = event.target.value;
  }

  handleDraftStage(event) {
    this.draftStage = event.detail.value;
  }

  handleEditCancel() {
    this.editing = false;
  }

  get editSaveDisabled() {
    return this.busy || !this.draftName || !this.draftName.trim();
  }

  handleEditSave() {
    const stage = stageByKey(this.draftStage);
    const element = {
      id: this.elementId,
      name: this.draftName,
      description: this.draftDescription,
      type: stage.type,
      term: stage.term
    };
    return this.run(saveElement({ elementJson: JSON.stringify(element) }), () => {
      this.editing = false;
    });
  }

  // ------------------------------------------------------------------------------ move

  get moveUpDisabled() {
    return this.busy || moveOrders(this.model, this.elementId, -1).length === 0;
  }

  get moveDownDisabled() {
    return this.busy || moveOrders(this.model, this.elementId, 1).length === 0;
  }

  handleMoveUp() {
    return this.move(-1);
  }

  handleMoveDown() {
    return this.move(1);
  }

  move(direction) {
    const orders = moveOrders(this.model, this.elementId, direction);
    return this.run(saveOrder({ modelId: this.model.id, ordersJson: JSON.stringify(orders) }));
  }

  // ---------------------------------------------------------------------------- delete

  handleDelete() {
    this.confirmingDelete = true;
  }

  handleDeleteCancel() {
    this.confirmingDelete = false;
  }

  handleDeleteConfirm() {
    return this.run(
      remove({ recordId: this.elementId }),
      () => {
        this.confirmingDelete = false;
      },
      LABELS.deleted
    );
  }

  // ---------------------------------------------------------------------------- arrows

  nameOf(id) {
    const element = ((this.model && this.model.elements) || []).find((item) => item.id === id);
    return element ? element.name : '';
  }

  arrows(direction) {
    return liveLinks(this.model)
      .filter((link) => (direction === 'out' ? link.fromId : link.toId) === this.elementId)
      .map((link) => ({
        id: link.id,
        other: this.nameOf(direction === 'out' ? link.toId : link.fromId),
        assumption: link.assumption || LABELS.noAssumption,
        editing: link.id === this.editingLinkId
      }));
  }

  /** Leads To (the arrows out, with Add Arrow) and Comes From (the arrows in). */
  get arrowGroups() {
    return [
      { key: 'arrows-out', heading: LABELS.leadsTo, out: true, arrows: this.arrows('out') },
      { key: 'arrows-in', heading: LABELS.comesFrom, out: false, arrows: this.arrows('in') }
    ].map((group) => ({ ...group, empty: group.arrows.length === 0 }));
  }

  get targetOptions() {
    return linkTargets(this.model, this.elementId).map((element) => ({
      value: element.id,
      label: `${element.name} (${stageLabel(stageOf(element).key)})`
    }));
  }

  get hasTargets() {
    return this.targetOptions.length > 0;
  }

  get canAddArrow() {
    return this.canEdit && !this.addingArrow && this.hasTargets;
  }

  get showNoTargets() {
    return this.canEdit && !this.hasTargets;
  }

  handleAddArrow() {
    this.addingArrow = true;
    this.draftTargetId = undefined;
    this.draftAssumption = '';
  }

  handleDraftTarget(event) {
    this.draftTargetId = event.detail.value;
  }

  handleDraftAssumption(event) {
    this.draftAssumption = event.target.value;
  }

  handleArrowCancel() {
    this.addingArrow = false;
  }

  get arrowSaveDisabled() {
    return this.busy || !this.draftTargetId;
  }

  handleArrowSave() {
    const link = {
      modelId: this.model.id,
      fromId: this.elementId,
      toId: this.draftTargetId,
      assumption: this.draftAssumption
    };
    return this.run(saveLink({ linkJson: JSON.stringify(link) }), () => {
      this.addingArrow = false;
    });
  }

  handleEditAssumption(event) {
    const id = event.currentTarget.dataset.recordId;
    const link = liveLinks(this.model).find((item) => item.id === id);
    this.editingLinkId = id;
    this.draftLinkAssumption = (link && link.assumption) || '';
  }

  handleDraftLinkAssumption(event) {
    this.draftLinkAssumption = event.target.value;
  }

  handleLinkCancel() {
    this.editingLinkId = undefined;
  }

  handleLinkSave() {
    const link = { id: this.editingLinkId, assumption: this.draftLinkAssumption };
    return this.run(saveLink({ linkJson: JSON.stringify(link) }), () => {
      this.editingLinkId = undefined;
    });
  }

  handleRemoveArrow(event) {
    return this.run(
      remove({ recordId: event.currentTarget.dataset.recordId }),
      null,
      LABELS.deleted
    );
  }

  // ----------------------------------------------------------------------- indicators

  handleChildChange(event) {
    this.dispatchEvent(new CustomEvent('modelchange', { detail: event.detail }));
  }

  handleChildFailure(event) {
    this.dispatchEvent(new CustomEvent('failure', { detail: event.detail }));
  }

  // ---------------------------------------------------------------------------- saving

  run(call, after, message) {
    this.busy = true;
    return call
      .then((model) => {
        if (after) {
          after();
        }
        this.dispatchEvent(
          new CustomEvent('modelchange', { detail: { model, message: message || LABELS.saved } })
        );
      })
      .catch((error) => {
        this.dispatchEvent(new CustomEvent('failure', { detail: { message: messageFrom(error) } }));
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
