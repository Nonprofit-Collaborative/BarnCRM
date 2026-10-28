import { LightningElement, api } from 'lwc';
import ABOUT_THIS_TOOL from '@salesforce/label/c.Core_Kit_AboutThisTool';

const STORAGE_PREFIX = 'barnPageShell.help.';

/**
 * The standard page for an admin tool: one header (icon, title-style title, a purpose line of 15
 * words or fewer, the primary action on the right), a collapsible "About This Tool" help region,
 * the body, and a footer for Back, Cancel and the primary action. One card level, so a tool
 * never puts a card inside a card.
 *
 * Slots: default (body), "actions" (header buttons), "help" (the long explanation), "footer".
 * The help region and the footer show only when their slot has content.
 *
 * On a Lightning App Page the platform already prints the page name above the component, so
 * pass `title-hidden`: the h1 stays for screen readers and the header leads with the purpose.
 *
 * The help region opens on a person's first visit and is closed after that; with
 * `help-storage-key` set, their own open or closed choice is remembered in this browser. That is
 * a convenience, not a setting, so it uses browser storage and fails quietly without it.
 *
 * `status-message` is read out by screen readers (one polite live region per page).
 */
export default class BarnPageShell extends LightningElement {
  @api iconName;
  @api title;
  @api purpose;
  @api titleHidden = false;
  /** Defaults to "About This Tool". */
  @api helpLabel;
  /** Names this tool's remembered help state, for example "dataManager". */
  @api helpStorageKey;
  @api statusMessage;

  hasHelp = false;
  hasFooter = false;
  helpOpen = true;

  connectedCallback() {
    const stored = this.readStored();
    if (stored === 'open' || stored === 'closed') {
      this.helpOpen = stored === 'open';
    } else {
      // First visit: open now, closed next time unless the person opens it again.
      this.helpOpen = true;
      this.writeStored('closed');
    }
  }

  get showIcon() {
    return Boolean(this.iconName);
  }

  get titleClass() {
    return this.titleHidden ? 'slds-assistive-text' : 'slds-page-header__title slds-truncate';
  }

  get helpHeading() {
    return this.helpLabel || ABOUT_THIS_TOOL;
  }

  get helpSectionClass() {
    const state = this.helpOpen ? ' slds-is-open' : '';
    const hidden = this.hasHelp ? '' : ' slds-hide';
    return `slds-section slds-var-m-horizontal_medium${state}${hidden}`;
  }

  get helpExpanded() {
    return this.helpOpen ? 'true' : 'false';
  }

  get helpCollapsed() {
    return !this.helpOpen;
  }

  get helpIcon() {
    return this.helpOpen ? 'utility:chevrondown' : 'utility:chevronright';
  }

  get footerClass() {
    return this.hasFooter ? 'slds-card__footer slds-text-align_left' : 'slds-hide';
  }

  handleToggleHelp() {
    this.helpOpen = !this.helpOpen;
    this.writeStored(this.helpOpen ? 'open' : 'closed');
  }

  handleHelpSlotChange(event) {
    this.hasHelp = event.target.assignedNodes().length > 0;
  }

  handleFooterSlotChange(event) {
    this.hasFooter = event.target.assignedNodes().length > 0;
  }

  readStored() {
    if (!this.helpStorageKey) {
      return null;
    }
    try {
      return window.localStorage.getItem(STORAGE_PREFIX + this.helpStorageKey);
    } catch {
      return null;
    }
  }

  writeStored(value) {
    if (!this.helpStorageKey) {
      return;
    }
    try {
      window.localStorage.setItem(STORAGE_PREFIX + this.helpStorageKey, value);
    } catch {
      // Storage blocked or full: the help simply opens as on a first visit.
    }
  }
}
