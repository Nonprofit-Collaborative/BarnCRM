import { LightningElement, api } from 'lwc';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import DISCARD from '@salesforce/label/c.Core_Kit_Discard';
import UNSAVED_ONE from '@salesforce/label/c.Core_Kit_UnsavedOne';
import UNSAVED_MANY from '@salesforce/label/c.Core_Kit_UnsavedMany';

/**
 * The save footer of a settings form, docked to the bottom of the screen while anything is
 * unsaved: how many changes are waiting, Discard and Save. With nothing unsaved it shows
 * nothing, but its live region stays so the count is announced when the first change is made.
 *
 * The caller counts its own changes into `dirty-count` and handles `save` and `discard`. While
 * anything is unsaved, closing or reloading the browser tab asks the person first.
 */
export default class BarnSaveBar extends LightningElement {
  /** How many settings have changed since the last save. */
  @api dirtyCount = 0;
  /** True while the caller saves; both buttons wait. */
  @api saving = false;

  labels = { save: SAVE, discard: DISCARD };

  connectedCallback() {
    this.beforeUnload = (event) => {
      if (this.isDirty) {
        event.preventDefault();
        event.returnValue = '';
      }
    };
    window.addEventListener('beforeunload', this.beforeUnload);
  }

  disconnectedCallback() {
    window.removeEventListener('beforeunload', this.beforeUnload);
  }

  get isDirty() {
    return Number(this.dirtyCount) > 0;
  }

  get barClass() {
    return this.isDirty ? 'savebar' : 'slds-assistive-text';
  }

  get countText() {
    if (!this.isDirty) {
      return '';
    }
    const count = Number(this.dirtyCount);
    return count === 1 ? UNSAVED_ONE : UNSAVED_MANY.replace('{0}', count);
  }

  handleSave() {
    this.dispatchEvent(new CustomEvent('save'));
  }

  handleDiscard() {
    this.dispatchEvent(new CustomEvent('discard'));
  }
}
