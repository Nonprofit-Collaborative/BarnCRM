import { LightningElement, api } from 'lwc';
import LEARN_MORE from '@salesforce/label/c.Core_Kit_LearnMore';
import NEW_TAB from '@salesforce/label/c.Core_Kit_NewTab';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * Help that stays out of the way: an info popover (lightning-helptext) for the short
 * explanation, and an optional Learn More link to the guide page. The link opens in a new tab,
 * says so to screen readers, shows the new-window icon, and carries rel="noopener noreferrer".
 *
 * <c-barn-help help-package="Core" help-key="Core_Example_Help" learn-more-url={helpUrl}></c-barn-help>
 * <c-barn-help content={text}></c-barn-help>
 * The popover text comes from the package's help catalog (ADR-0164 help-text-json) when
 * help-key is set, or from content. Either part may be left out.
 */
export default class BarnHelp extends LightningElement {
  /** The popover text, when it is not from a help catalog. No popover when empty. */
  @api content;
  /** The help catalog key of the popover text (the help text's former label name). */
  @api helpKey;
  /** The package whose catalog holds helpKey: Core, Giving, Rollups, and so on. */
  @api helpPackage = 'Core';
  /** The guide page the Learn More link opens. No link when empty. */
  @api learnMoreUrl;
  /** The link text; defaults to "Learn More". */
  @api learnMoreLabel;
  /** The popover's screen reader name (lightning-helptext's alternative text). */
  @api alternativeText;

  labels = { newTab: NEW_TAB };
  helpReady = false;

  connectedCallback() {
    if (this.helpKey) {
      this.helpReady = isHelpLoaded(this.helpPackage);
      if (!this.helpReady) {
        loadHelp(this.helpPackage).then(() => {
          this.helpReady = true;
        });
      }
    }
  }

  get popoverText() {
    if (this.helpKey) {
      return this.helpReady ? helpText(this.helpPackage, this.helpKey) : '';
    }
    return this.content;
  }

  get hasContent() {
    return Boolean(this.popoverText);
  }

  get hasLink() {
    return Boolean(this.learnMoreUrl);
  }

  get linkText() {
    return this.learnMoreLabel || LEARN_MORE;
  }
}
