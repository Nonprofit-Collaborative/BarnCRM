/**
 * Jest stub for lightning/modal, which sfdx-lwc-jest does not ship. A subclass renders like any
 * component; close() records its result and fires a "close" event a test can listen for. open()
 * is a jest mock so a caller's test can choose what the person answers.
 */
import { LightningElement, api } from 'lwc';

export default class LightningModal extends LightningElement {
  static open = jest.fn(() => Promise.resolve());

  @api label;
  @api size;
  @api description;
  @api disableClose;

  close(result) {
    this.dispatchEvent(new CustomEvent('close', { detail: result }));
  }
}
