import { LightningElement, api } from 'lwc';

let pickerCount = 0;

/**
 * One choice from a few, shown as cards with an icon, a title-style name and one line. It is a
 * native radio group inside a fieldset, so the keyboard and screen readers treat it as one:
 * Tab reaches the group, the arrow keys move the choice, and each card's line is read as its
 * description.
 *
 * Because the arrow keys change the choice, a caller keeps the picker on screen after a choice
 * and shows what follows from it below, rather than moving on as soon as `change` fires.
 */
export default class BarnVisualPicker extends LightningElement {
  /** The question the picker answers, shown as the legend, for example "What Are You Importing?". */
  @api label;
  /** Each `{ value, label, description, iconName, warning }`; `warning` colors the icon. */
  @api options = [];
  /** The chosen `value`, or empty for none. */
  @api value;

  groupName = `barn-visual-picker-${++pickerCount}`;

  get choices() {
    return (this.options || []).map((option, index) => ({
      ...option,
      id: `choice-${index}`,
      lineId: `line-${index}`,
      checked: option.value === this.value,
      iconVariant: option.warning ? 'warning' : undefined
    }));
  }

  handleChange(event) {
    // The caller sets `value` from the event, as with lightning-radio-group.
    const value = event.target.value;
    this.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  }
}
