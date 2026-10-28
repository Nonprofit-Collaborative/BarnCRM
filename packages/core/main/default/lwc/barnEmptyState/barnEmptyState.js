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
  /** "small" (default, inside a card) or "large" (a whole page). */
  @api size;
  /** The heading's level for screen readers; 3 by default, under a card title. */
  @api headingLevel = 3;

  get kind() {
    return ILLUSTRATIONS.includes(this.illustration) ? this.illustration : 'no-data';
  }

  get isAllClear() {
    return this.kind === 'all-clear';
  }

  get isSetup() {
    return this.kind === 'setup';
  }

  get containerClass() {
    const size = this.size === 'large' ? 'slds-illustration_large' : 'slds-illustration_small';
    return `slds-illustration ${size}`;
  }
}
