import { LightningElement, api } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import getPage from '@salesforce/apex/FormPublicController.getPage';
import listPages from '@salesforce/apex/FormPublicController.listPages';
import { listView, pageView, sitePageUrl } from 'c/formPublicPageModel';
import { HELP, LABELS, PAGE_TEXT } from 'c/formText';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * A module's public page for one of its records, such as an event, or its public list, on a
 * Salesforce Site (EV-16; ADR-0190 public event pages, decisions 4, 6 and 7), loaded by the
 * `FormsPublic` page through Lightning Out. The module decides what is published; this page
 * draws it, and, while registration is open, the record's form through `c-form-public` with the
 * record as the form's context, so the answers take the public intake and its spam checks.
 */
export default class FormPublicPage extends LightningElement {
  /** The record whose page is shown (the page's `record` parameter). */
  @api recordId;
  /** The kind of list shown when no record is named, such as `events` (the `list` parameter). */
  @api listKind;

  helpReady = isHelpLoaded(HELP);
  labels = LABELS;
  loading = true;
  page;
  list;
  missing = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    this.open();
  }

  async open() {
    this.loading = true;
    try {
      if (this.recordId) {
        const json = await getPage({ recordId: this.recordId });
        this.page = json ? JSON.parse(json) : null;
      } else if (this.listKind) {
        const json = await listPages({ kind: this.listKind });
        this.list = json ? JSON.parse(json) : null;
      }
    } catch {
      this.page = null;
      this.list = null;
    }
    this.missing = !this.page && !this.list;
    this.loading = false;
  }

  joiner = (start, end) => PAGE_TEXT.timeRange(start, end);

  get view() {
    return this.page ? pageView(this.page, LOCALE, this.joiner) : null;
  }

  get listing() {
    return this.list ? listView(this.list, LOCALE, this.joiner, sitePageUrl) : null;
  }

  get listEmpty() {
    return Boolean(this.listing) && this.listing.items.length === 0;
  }

  get missingText() {
    return PAGE_TEXT.missing;
  }

  get registerText() {
    return PAGE_TEXT.register;
  }
}
