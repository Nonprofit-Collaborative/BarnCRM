import { LightningElement, wire } from 'lwc';
import FUND_OBJECT from '@salesforce/schema/Fund__c';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import getPaymentMethods from '@salesforce/apex/AccountingExportController.getPaymentMethods';
import exportGifts from '@salesforce/apex/AccountingExportController.exportGifts';
import markPosted from '@salesforce/apex/AccountingExportController.markPosted';
// Bare, and correctly so: a custom permission defined in Giving resolves without a namespace
// prefix while the namespace is deferred.
import canPostGifts from '@salesforce/customPermission/Post_Gifts';
import title from '@salesforce/label/c.Mirror_AccountingExport_Title';
import from from '@salesforce/label/c.Core_SetupChanges_From';
import to from '@salesforce/label/c.Core_SetupChanges_To';
import fund from '@salesforce/label/c.Giving_GiftBatch_ColumnFund';
import allFunds from '@salesforce/label/c.Mirror_AccountingExport_AllFunds';
import paymentMethod from '@salesforce/label/c.Giving_QuickGiftEntry_TypeLabel';
import allMethods from '@salesforce/label/c.Mirror_AccountingExport_AllMethods';
import download from '@salesforce/label/c.Mirror_AccountingExport_Download';
import onlyUnposted from '@salesforce/label/c.Mirror_AccountingExport_OnlyUnposted';
import markPostedLabel from '@salesforce/label/c.Mirror_AccountingExport_MarkPosted';
import { BYTE_ORDER_MARK, bodyMessage, saveBlob } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

const REVOKE_DELAY_MS = 1000;

/**
 * The Accounting Export page (feature X-04). The service decides what is in the file and
 * refuses a bad range in words; the page only collects the choices, saves the file and says
 * what it held.
 *
 * After a download, someone holding Post Gifts can mark the gifts in that file posted (G-20).
 * The page remembers what it downloaded and forgets it when any choice changes, so the button
 * always marks the file on screen, and the server builds it again and compares its digest.
 */
export default class AccountingExport extends LightningElement {
  helpReady = isHelpLoaded('Mirror');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Mirror').then(() => {
        this.helpReady = true;
      });
    }
  }

  icons = { accountingExport: iconFor('Accounting_Export') };

  labels = {
    title,
    get intro() {
      return helpText('Mirror', 'Mirror_AccountingExport_Intro');
    },
    get visibility() {
      return helpText('Mirror', 'Mirror_AccountingExport_Visibility');
    },
    from,
    to,
    fund,
    allFunds,
    paymentMethod,
    allMethods,
    download,
    onlyUnposted,
    markPosted: markPostedLabel,
    get markPostedHelp() {
      return helpText('Mirror', 'Mirror_AccountingExport_MarkPostedHelp');
    },
    get markNeedsAllFunds() {
      return helpText('Mirror', 'Mirror_AccountingExport_MarkNeedsAllFunds');
    }
  };

  fromDate;
  toDate;
  fundId;
  paymentMethod = '';
  onlyUnposted = false;
  downloaded;
  methods = [];
  working = false;
  error;
  message;

  get fundObjectApiName() {
    return FUND_OBJECT.objectApiName;
  }

  get methodOptions() {
    return [{ label: allMethods, value: '' }].concat(this.methods);
  }

  @wire(getPaymentMethods)
  wiredMethods({ data, error }) {
    if (data) {
      this.methods = data.map((option) => ({ label: option.label, value: option.value }));
    } else if (error) {
      this.error = helpText('Mirror', 'Mirror_AccountingExport_ErrorFailed');
    }
  }

  get canPost() {
    return canPostGifts === true;
  }

  get showMarkPosted() {
    return this.canPost && !!this.downloaded && !this.downloaded.choices.fundId;
  }

  get showNeedsAllFunds() {
    return this.canPost && !!this.downloaded && !!this.downloaded.choices.fundId;
  }

  handleFromChange(event) {
    this.fromDate = event.detail.value;
    this.downloaded = undefined;
  }

  handleToChange(event) {
    this.toDate = event.detail.value;
    this.downloaded = undefined;
  }

  handleFundChange(event) {
    this.fundId = event.detail.recordId || undefined;
    this.downloaded = undefined;
  }

  handleMethodChange(event) {
    this.paymentMethod = event.detail.value;
    this.downloaded = undefined;
  }

  handleOnlyUnpostedChange(event) {
    this.onlyUnposted = event.detail.checked;
    this.downloaded = undefined;
  }

  get choices() {
    return {
      fromDate: this.fromDate,
      toDate: this.toDate,
      fundId: this.fundId || null,
      paymentMethod: this.paymentMethod || null,
      onlyUnposted: this.onlyUnposted
    };
  }

  async handleDownload() {
    this.error = undefined;
    this.message = undefined;
    this.downloaded = undefined;
    if (!this.fromDate || !this.toDate) {
      this.error = helpText('Mirror', 'Mirror_AccountingExport_ErrorDatesRequired');
      return;
    }
    this.working = true;
    try {
      const choices = this.choices;
      const view = await exportGifts(choices);
      if (!view || !view.rowCount) {
        this.message = helpText('Mirror', 'Mirror_AccountingExport_NoGifts');
        return;
      }
      this.save(view.fileName, view.csv);
      this.downloaded = { choices, digest: view.digest };
      this.message = helpText('Mirror', 'Mirror_AccountingExport_Summary')
        .replace('{0}', view.rowCount)
        .replace('{1}', view.giftCount)
        .replace('{2}', this.money(view.total));
    } catch (failure) {
      this.error = bodyMessage(failure, helpText('Mirror', 'Mirror_AccountingExport_ErrorFailed'));
    } finally {
      this.working = false;
    }
  }

  async handleMarkPosted() {
    this.error = undefined;
    this.message = undefined;
    this.working = true;
    try {
      const count = await markPosted({
        ...this.downloaded.choices,
        digest: this.downloaded.digest
      });
      this.downloaded = undefined;
      this.message = helpText('Mirror', 'Mirror_AccountingExport_Marked').replace('{0}', count);
    } catch (failure) {
      this.error = bodyMessage(failure, helpText('Mirror', 'Mirror_AccountingExport_ErrorFailed'));
    } finally {
      this.working = false;
    }
  }

  money(amount) {
    return new Intl.NumberFormat(LOCALE, { style: 'currency', currency: CURRENCY }).format(
      amount || 0
    );
  }

  /**
   * A Blob, not a data URI: 10,000 rows is over a megabyte, past what browsers take in a URL.
   * The byte-order mark tells a spreadsheet the file is UTF-8, so a name like Muñoz arrives
   * intact. The address is released a moment after the click, because some browsers start the
   * download only after the click handler returns.
   */
  save(fileName, csv) {
    saveBlob(
      new Blob([BYTE_ORDER_MARK, csv], { type: 'text/csv;charset=utf-8' }),
      fileName,
      REVOKE_DELAY_MS
    );
  }
}
