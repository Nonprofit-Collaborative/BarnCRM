import { LightningElement, api } from 'lwc';
import { statusFor } from 'c/barnStatus';

/**
 * A status as a badge whose color and icon come from the suite vocabulary (c/barnStatus), so
 * every list shows "Active", "Overdue" or "Off" the same way and never by color alone.
 *
 * <c-barn-status-badge status="overdue" label={labels.overdue}></c-barn-status-badge>
 *
 * `status` picks the look (success, warning, error, running, info, neutral or any recorded
 * word such as active, due, failed, off, new); `label` is the caller's text.
 */
export default class BarnStatusBadge extends LightningElement {
  /** A status word from the vocabulary; unknown words draw the neutral badge. */
  @api status;
  /** The badge text, from the caller's custom label or data. */
  @api label;
  /** Replaces the tone's icon, for example "utility:favorite" for Primary. */
  @api iconName;
  /** Draws the badge with no icon. */
  @api hideIcon = false;

  get look() {
    return statusFor(this.status);
  }

  get tone() {
    return this.look.tone;
  }

  get badgeClass() {
    return this.look.themeClass;
  }

  get badgeIcon() {
    if (this.hideIcon) {
      return undefined;
    }
    return this.iconName || this.look.iconName || undefined;
  }
}
