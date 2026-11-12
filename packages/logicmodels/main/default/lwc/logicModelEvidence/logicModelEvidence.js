import { LightningElement, api } from 'lwc';
import saveEvidence from '@salesforce/apex/LogicModelBuilderController.saveEvidence';
import remove from '@salesforce/apex/LogicModelBuilderController.remove';
import { LABELS, messageFrom } from 'c/logicModelText';
import BarnConfirmModal from 'c/barnConfirmModal';

/**
 * One arrow's evidence log (L-05): what supports its assumption, each with its source, link,
 * date and strength, newest first, as the model holds it (R-AE1). Staff add, change and remove
 * evidence; a reader only sees it. The object, field and strength names come with the model,
 * from the platform's describe, so they need no labels of their own. Each save hands the whole
 * model back in a `modelchange` event; a refusal goes up as `failure`.
 */
export default class LogicModelEvidence extends LightningElement {
  @api model;
  @api linkId;
  @api canEdit = false;
  @api canDelete = false;

  labels = LABELS;
  busy = false;
  open = false;
  editingId;
  draft = {};

  get link() {
    return ((this.model && this.model.links) || []).find((item) => item.id === this.linkId);
  }

  /** The evidence log's words: title, field labels and strengths (R-AE2). */
  get text() {
    return (this.model && this.model.evidenceText) || { strengths: [] };
  }

  get strengths() {
    return this.text.strengths || [];
  }

  get entries() {
    const link = this.link;
    return ((link && link.evidence) || []).map((item) => ({
      ...item,
      strengthLabel: (this.strengths.find((option) => option.value === item.strength) || {}).label
    }));
  }

  get count() {
    return this.entries.length;
  }

  get toggleLabel() {
    return `${this.text.title} (${this.count})`;
  }

  get toggleIcon() {
    return this.open ? 'utility:chevrondown' : 'utility:chevronright';
  }

  get expanded() {
    return String(this.open);
  }

  get isEmpty() {
    return this.count === 0;
  }

  get editing() {
    return this.editingId !== undefined;
  }

  handleToggle() {
    this.open = !this.open;
  }

  handleAdd() {
    this.editingId = null;
    this.draft = { strength: 'Moderate' };
  }

  handleEdit(event) {
    const entry = this.entries.find((item) => item.id === event.target.dataset.recordId);
    this.editingId = entry.id;
    this.draft = { ...entry };
  }

  handleDraft(event) {
    this.draft = { ...this.draft, [event.target.dataset.field]: event.target.value };
  }

  handleCancel() {
    this.editingId = undefined;
    this.draft = {};
  }

  handleSave() {
    const fields = this.template.querySelectorAll('[data-field]');
    const valid = [...fields].every((field) => field.reportValidity());
    if (!valid) {
      return undefined;
    }
    const evidence = {
      id: this.editingId,
      linkId: this.linkId,
      summary: this.draft.summary,
      source: this.draft.source,
      sourceUrl: this.draft.sourceUrl,
      date: this.draft.date,
      strength: this.draft.strength
    };
    return this.run(saveEvidence({ evidenceJson: JSON.stringify(evidence) }), () =>
      this.handleCancel()
    );
  }

  handleRemove(event) {
    const id = event.target.dataset.recordId;
    return BarnConfirmModal.open({
      size: 'small',
      label: LABELS.remove,
      message: LABELS.removeEvidenceConfirm,
      confirmLabel: LABELS.remove,
      cancelLabel: LABELS.cancel,
      confirmVariant: 'destructive'
    }).then((confirmed) => {
      if (!confirmed) {
        return undefined;
      }
      return this.run(remove({ recordId: id }), null, LABELS.deleted);
    });
  }

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
