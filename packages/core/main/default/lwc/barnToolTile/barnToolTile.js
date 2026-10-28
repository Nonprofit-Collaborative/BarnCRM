import { LightningElement, api } from 'lwc';

const BADGE_THEMES = {
  success: 'slds-theme_success',
  warning: 'slds-theme_warning',
  error: 'slds-theme_error',
  inverse: 'slds-badge_inverse'
};

/**
 * One tool on a hub: an icon, a title-style name, one line (12 words or fewer), and an optional
 * badge for a count or state. The whole tile is one control, so a keyboard or screen reader
 * user meets one stop per tool instead of a box of text and an "Open" button.
 *
 * With `href` the tile is a link; otherwise it is a button that fires `select` with
 * `detail: { name }`, and the caller navigates (NavigationMixin, a tab switch, a modal).
 * A disabled tile stays focusable so its reason is read, but fires nothing.
 */
export default class BarnToolTile extends LightningElement {
  /** The value `select` carries, for example "import". */
  @api name;
  @api label;
  @api description;
  /** An SLDS icon name, for example "standard:data_streams". */
  @api iconName;
  /** A link target, when the tile should be a plain link. */
  @api href;
  /** Text of the badge, for example "3 Need Attention". No badge when empty. */
  @api badgeLabel;
  /** "success", "warning", "error", "inverse", or empty for the neutral badge. */
  @api badgeVariant;
  @api disabled = false;
  /** Shown in place of the description while the tile is disabled. */
  @api disabledReason;

  get isLink() {
    return Boolean(this.href) && !this.disabled;
  }

  get hasBadge() {
    return Boolean(this.badgeLabel);
  }

  get badgeClass() {
    return BADGE_THEMES[this.badgeVariant] || '';
  }

  get lineText() {
    return this.disabled && this.disabledReason ? this.disabledReason : this.description;
  }

  get tileClass() {
    return this.disabled ? 'tile tile_disabled' : 'tile';
  }

  get ariaDisabled() {
    return this.disabled ? 'true' : 'false';
  }

  handleClick(event) {
    if (this.disabled) {
      event.preventDefault();
      return;
    }
    this.dispatchEvent(new CustomEvent('select', { detail: { name: this.name } }));
  }
}
