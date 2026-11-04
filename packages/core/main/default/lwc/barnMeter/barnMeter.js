import { LightningElement, api } from 'lwc';

/**
 * A share or progress as a bar with its label on one side and its value on the other, so the
 * number is always there in text and color is never the only signal. Wraps
 * `lightning-progress-bar`; on a phone the row wraps with the bar under the label.
 *
 * <c-barn-meter label={labels.stepsDone} value={done} max={total} value-text="3 of 5">
 * </c-barn-meter>
 *
 * Without `value-text` the value shows as a percent of `max`.
 */
export default class BarnMeter extends LightningElement {
  @api label;
  /** The amount so far, in the same unit as `max`. */
  @api value = 0;
  /** The whole; 100 by default, so a percent can be passed as `value` directly. */
  @api max = 100;
  /** Text shown beside the bar in place of the percent, for example "3 of 5 Steps". */
  @api valueText;
  /** "x-small", "small", "medium" (default) or "large", as on lightning-progress-bar. */
  @api size = 'medium';

  get fraction() {
    const max = Number(this.max);
    const value = Number(this.value);
    if (!(max > 0) || !(value > 0)) {
      return 0;
    }
    return Math.min(value / max, 1);
  }

  /** lightning-progress-bar takes 0 to 100. */
  get percent() {
    return Math.round(this.fraction * 100);
  }

  get hasValueText() {
    return this.valueText !== undefined && this.valueText !== null && this.valueText !== '';
  }
}
