import { LightningElement, api } from 'lwc';

const VARIANTS = {
  info: {
    container: 'slds-scoped-notification_light',
    icon: 'utility:info',
    iconVariant: undefined
  },
  success: {
    container: 'slds-scoped-notification_light',
    icon: 'utility:success',
    iconVariant: 'success'
  },
  warning: { container: 'slds-theme_warning', icon: 'utility:warning', iconVariant: undefined },
  error: { container: 'slds-theme_error', icon: 'utility:error', iconVariant: 'inverse' }
};

/**
 * An inline message in a panel: an SLDS scoped notification with an icon per variant, an
 * optional title, the message, and an optional action. It replaces solid `slds-box
 * slds-theme_*` blocks and inline `slds-notify_alert` banners (keep those only for an org-wide
 * state at the top of a page, such as paused automation).
 *
 * <c-barn-notice variant="success" message={saved} action-label={openGift} action-href={url}>
 * </c-barn-notice>
 *
 * Info and success sit on a light background; warning and error use the SLDS warning and error
 * themes. The action link takes the notice's own text color and an underline, so it passes
 * contrast on every variant. Without `action-href` the action is a button that fires `action`.
 * Anything richer (a list, a button group) goes in the default slot.
 */
export default class BarnNotice extends LightningElement {
  /** "info" (default), "success", "warning" or "error". */
  @api variant;
  /** Optional bold first line. */
  @api title;
  @api message;
  @api actionLabel;
  @api actionHref;
  /** Read for the icon by screen readers; leave empty when the text already says it. */
  @api alternativeText;

  get look() {
    return VARIANTS[this.variant] || VARIANTS.info;
  }

  get containerClass() {
    return `notice slds-scoped-notification slds-media slds-media_center ${this.look.container}`;
  }

  get role() {
    return this.variant === 'error' ? 'alert' : 'status';
  }

  get iconName() {
    return this.look.icon;
  }

  get iconVariant() {
    return this.look.iconVariant;
  }

  get hasAction() {
    return Boolean(this.actionLabel);
  }

  get hasActionHref() {
    return Boolean(this.actionHref);
  }

  handleAction() {
    this.dispatchEvent(new CustomEvent('action'));
  }
}
