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
    this.close(true);
  }
}
