import LightningModal from 'lightning/modal';
import { api } from 'lwc';

/**
 * A yes or no question in a platform modal (focus trap, Escape, screen reader dialog semantics).
 * lightning/confirm would do the same but only offers OK and Cancel, and every confirm in Core
 * names its action on the button ("Merge households", "Remove"), so this keeps those labels.
 *
 * Open it with BarnConfirmModal.open({ label, message, details, confirmLabel, cancelLabel,
 * confirmVariant, size: 'small' }). It resolves true when the person confirms, and false or
 * undefined (Escape, the close button) otherwise. Every string comes from the caller's labels.
 */
export default class BarnConfirmModal extends LightningModal {
  /** The question or explanation under the heading. */
  @api message;
  /** Further lines shown after the message, one paragraph each; empty entries are skipped. */
  @api details;
  @api confirmLabel;
  @api cancelLabel;
  /** 'brand' (default) or 'destructive'. */
  @api confirmVariant;
  /**
   * For a large or lasting change: text the person types before the confirm button works,
   * such as the record count ("1250"). Compared after trimming spaces.
   */
  @api typeToConfirm;
  /** The field label for that text, such as "Type 1250 to delete these records". */
  @api typeToConfirmLabel;
  /** Names shown as a bulleted list after the details, such as the people a change moves. */
  @api items;
  /**
   * One choice from a few, as { label, value } entries in a radio group labelled choicesLabel,
   * starting on choice. With choices or checks the modal resolves { choice, checked }.
   */
  @api choices;
  @api choicesLabel;
  @api choice;
  /** Tick boxes, as { label, value } entries labelled checksLabel; none ticked to start. */
  @api checks;
  @api checksLabel;

  typed = '';
  picked;
  ticked = [];

  get itemLines() {
    return (this.items || []).map((text, index) => ({ key: `item-${index}`, text }));
  }

  get hasItems() {
    return this.itemLines.length > 0;
  }

  get hasChoices() {
    return Boolean(this.choices && this.choices.length);
  }

  get hasChecks() {
    return Boolean(this.checks && this.checks.length);
  }

  get chosen() {
    return this.picked === undefined ? this.choice : this.picked;
  }

  handleChoice(event) {
    this.picked = event.detail.value;
  }

  handleChecks(event) {
    this.ticked = event.detail.value || [];
  }

  get asksToType() {
    return Boolean(this.typeToConfirm);
  }

  get confirmDisabled() {
    return this.asksToType && this.typed.trim() !== String(this.typeToConfirm).trim();
  }

  handleTyped(event) {
    this.typed = event.target.value || '';
  }

  get detailLines() {
    return (this.details || [])
      .filter((line) => line)
      .map((line, index) => ({ key: `detail-${index}`, text: line }));
  }

  get buttonVariant() {
    return this.confirmVariant || 'brand';
  }

  handleCancel() {
    this.close(false);
  }

  handleConfirm() {
    if (this.confirmDisabled) {
      return;
    }
    if (this.hasChoices || this.hasChecks) {
      this.close({ choice: this.chosen, checked: this.ticked });
      return;
    }
    this.close(true);
  }
}
