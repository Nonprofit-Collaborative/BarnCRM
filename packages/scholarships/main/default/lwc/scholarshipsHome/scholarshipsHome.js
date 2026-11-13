import { LightningElement } from 'lwc';
import getHome from '@salesforce/apex/ScholarshipsController.getHome';
import exportDisbursements from '@salesforce/apex/ScholarshipsController.exportDisbursements';
import { localIsoDate, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { toCsv } from 'c/scholarshipsModel';
import { recordHref } from 'c/recordRows';

const PKG = 'Scholarships';

/**
 * The Scholarships and Grants page (SG-03, SG-05, SG-10): my reviews to do, cycles open or in
 * review, disbursements due in 30 days with any held back, and, for a holder of Manage
 * Scholarships, Export Disbursements as a CSV built here (`c/scholarshipsModel`).
 */
export default class ScholarshipsHome extends LightningElement {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Scholarships');
  home;
  isLoading = true;
  isWorking = false;
  errorMessage;
  exportFrom;
  exportTo;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    const today = new Date();
    this.exportFrom = localIsoDate(new Date(today.getFullYear(), today.getMonth(), 1));
    this.exportTo = localIsoDate(today);
    this.load();
  }

  get labels() {
    return {
      title: helpText('Scholarships', 'Scholarships_Home_Title'),
      intro: helpText('Scholarships', 'Scholarships_Home_Intro'),
      reviews: helpText('Scholarships', 'Scholarships_Home_Reviews'),
      noReviews: helpText('Scholarships', 'Scholarships_Home_NoReviews'),
      cycles: helpText('Scholarships', 'Scholarships_Home_Cycles'),
      noCycles: helpText('Scholarships', 'Scholarships_Home_NoCycles'),
      due: helpText('Scholarships', 'Scholarships_Home_Due'),
      noDue: helpText('Scholarships', 'Scholarships_Home_NoDue'),
      held: helpText('Scholarships', 'Scholarships_Payment_Held'),
      exportTitle: helpText('Scholarships', 'Scholarships_Export_Title'),
      from: helpText('Scholarships', 'Scholarships_Export_From'),
      to: helpText('Scholarships', 'Scholarships_Export_To'),
      exportButton: helpText('Scholarships', 'Scholarships_Export_Button')
    };
  }

  get canManage() {
    return this.home?.canManage === true;
  }

  get reviews() {
    return (this.home?.reviews || []).map((row) => ({ ...row, href: recordHref(row.id) }));
  }

  get cycles() {
    return (this.home?.cycles || []).map((row) => ({
      ...row,
      href: recordHref(row.id),
      detailText: helpText(
        'Scholarships',
        'Scholarships_Home_CycleDetail',
        row.detail,
        row.count ?? 0,
        row.due ?? ''
      )
    }));
  }

  get due() {
    return (this.home?.due || []).map((row) => ({ ...row, href: recordHref(row.id) }));
  }

  get hasReviews() {
    return this.reviews.length > 0;
  }

  get hasCycles() {
    return this.cycles.length > 0;
  }

  get hasDue() {
    return this.due.length > 0;
  }

  async load() {
    this.isLoading = true;
    try {
      this.home = await getHome();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleRange(event) {
    this[event.target.dataset.field] = event.target.value;
  }

  async handleExport() {
    this.isWorking = true;
    try {
      const rows = await exportDisbursements({ fromDate: this.exportFrom, toDate: this.exportTo });
      const link = document.createElement('a');
      link.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(toCsv(rows));
      link.download = `disbursements-${this.exportFrom}-${this.exportTo}.csv`;
      link.click();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }
}
