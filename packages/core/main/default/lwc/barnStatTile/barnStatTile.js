import { LightningElement, api } from 'lwc';

const BADGE_THEMES = {
  success: 'slds-theme_success',
  warning: 'slds-theme_warning',
  error: 'slds-theme_error',
  inverse: 'slds-badge_inverse'
};

/**
 * One count as a big number over a short label, with an optional badge for its state, for
 * example "12" over "Would Add" or "3" over "Rejected" with an error badge. A number is
 * formatted for the person's locale; text (such as "More than 2,000") is shown as given.
 */
export default class BarnStatTile extends LightningElement {
  @api label;
  /** A number, or text when the count is not exact. */
  @api value;
  @api badgeLabel;
  /** "success", "warning", "error", "inverse", or empty for the neutral badge. */
  @api badgeVariant;

  get isNumber() {
    return typeof this.value === 'number';
  }

  get hasBadge() {
    return Boolean(this.badgeLabel);
  }

  get badgeClass() {
    return BADGE_THEMES[this.badgeVariant] || '';
  }
}
