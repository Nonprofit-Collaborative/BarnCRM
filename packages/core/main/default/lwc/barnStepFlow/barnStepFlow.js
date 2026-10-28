import { LightningElement, api } from 'lwc';
import BACK from '@salesforce/label/c.Core_Kit_Back';
import STEP_OF from '@salesforce/label/c.Core_Kit_StepOf';

/**
 * A multi-step flow: the SLDS path across the top, the step's body, and one footer with Back
 * on the left and the step's own actions on the right, so every wizard puts its buttons in the
 * same place.
 *
 * The path names each step, so the caller drops its own step heading; the flow keeps one
 * `h2` ("Step 2 of 6: Upload File") for screen readers. The caller owns the step: it passes
 * `current-step`, listens for `back`, and puts Next, Preview or Finish in the `actions` slot.
 */
export default class BarnStepFlow extends LightningElement {
  /** The steps in order, each `{ value, label }` with a short title-style label. */
  @api steps = [];
  /** The `value` of the step on screen. */
  @api currentStep;
  /** Shows Back in the footer, which fires `back`. */
  @api canGoBack = false;

  labels = { back: BACK };

  get headingText() {
    const steps = this.steps || [];
    const index = steps.findIndex((step) => step.value === this.currentStep);
    if (index < 0) {
      return '';
    }
    return STEP_OF.replace('{0}', index + 1)
      .replace('{1}', steps.length)
      .replace('{2}', steps[index].label);
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent('back'));
  }
}
