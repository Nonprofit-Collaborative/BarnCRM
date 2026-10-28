import { LightningElement, api } from 'lwc';
import LEARN_MORE from '@salesforce/label/c.Core_Kit_LearnMore';
import NEW_TAB from '@salesforce/label/c.Core_Kit_NewTab';

/**
 * Help that stays out of the way: an info popover (lightning-helptext) for the short
 * explanation, and an optional Learn More link to the guide page. The link opens in a new tab,
 * says so to screen readers, shows the new-window icon, and carries rel="noopener noreferrer".
 *
 * <c-barn-help content={labels.hint} learn-more-url={labels.helpUrl}></c-barn-help>
 * Either part may be left out. Every string comes from the caller's labels.
 */
export default class BarnHelp extends LightningElement {
  /** The popover text. No popover when empty. */
  @api content;
  /** The guide page the Learn More link opens. No link when empty. */
  @api learnMoreUrl;
  /** The link text; defaults to "Learn More". */
  @api learnMoreLabel;
  /** The popover's screen reader name (lightning-helptext's alternative text). */
  @api alternativeText;

  labels = { newTab: NEW_TAB };

  get hasContent() {
    return Boolean(this.content);
  }

  get hasLink() {
    return Boolean(this.learnMoreUrl);
  }

  get linkText() {
    return this.learnMoreLabel || LEARN_MORE;
  }
}
