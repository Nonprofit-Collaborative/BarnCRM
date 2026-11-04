import { LightningElement, api } from 'lwc';

const ILLUSTRATIONS = ['no-data', 'setup', 'all-clear'];

/**
 * An empty state with something to look at: a small SLDS-style illustration, a title-style
 * heading, one line of text and, in the default slot, the action that fills it.
 *
 * <c-barn-empty-state illustration="all-clear" heading={labels.allClear} message={labels.noErrors}>
 *     <lightning-button label={labels.refresh} onclick={refresh}></lightning-button>
 * </c-barn-empty-state>
 *
 * Illustrations: "no-data" (default; nothing created yet), "setup" (something to set up first)
 * and "all-clear" (a good empty: no errors, nothing to review). The art is inline SVG drawn with
 * the SLDS illustration fill and stroke classes, so it follows the org's theme and dark mode.
 */
export default class BarnEmptyState extends LightningElement {
  /** "no-data", "setup" or "all-clear". Anything else draws "no-data". */
  @api illustration;
  /** Heading with each main word capitalized, for example "No Data Jobs Yet". */
  @api heading;
  /** One line under the heading. Optional. */
  @api message;
  /**
   * "small" (default, inside a card), "large" (a whole page) or "compact" (no art and a small
   * heading, for a card in a record page sidebar or a section inside a panel).
   */
  @api size;
  /** The heading's level for screen readers; 3 by default, under a card title. */
  @api headingLevel = 3;

  get kind() {
    return ILLUSTRATIONS.includes(this.illustration) ? this.illustration : 'no-data';
  }

  get isCompact() {
    return this.size === 'compact';
  }

  get isAllClear() {
    return !this.isCompact && this.kind === 'all-clear';
  }

  get isSetup() {
    return !this.isCompact && this.kind === 'setup';
  }

  get isNoData() {
    return !this.isCompact && this.kind === 'no-data';
  }

  get containerClass() {
    if (this.isCompact) {
      return 'slds-text-align_center slds-var-p-vertical_small';
    }
    const size = this.size === 'large' ? 'slds-illustration_large' : 'slds-illustration_small';
    return `slds-illustration ${size}`;
  }

  get textClass() {
    return this.isCompact ? 'slds-text-longform' : 'slds-text-longform slds-var-m-top_small';
  }

  get headingClass() {
    return this.isCompact ? 'slds-text-heading_small' : 'slds-text-heading_medium';
  }

  get messageClass() {
    return this.isCompact ? 'slds-text-body_small slds-text-color_weak' : 'slds-text-body_regular';
  }

  get actionClass() {
    return this.isCompact ? 'slds-var-m-top_x-small' : 'slds-var-m-top_small';
  }
}
