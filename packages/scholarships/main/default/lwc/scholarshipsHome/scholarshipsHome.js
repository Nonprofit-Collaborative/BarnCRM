import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import getHome from '@salesforce/apex/ScholarshipsController.getHome';
import AWARD_PROGRAM from '@salesforce/schema/Award_Program__c';
import AWARD_APPLICATION from '@salesforce/schema/Award_Application__c';
import AWARD from '@salesforce/schema/Award__c';
import APPLICATION_REVIEW from '@salesforce/schema/Application_Review__c';
import exportDisbursements from '@salesforce/apex/ScholarshipsController.exportDisbursements';
import { localIsoDate, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { toCsv } from 'c/scholarshipsModel';
import { recordHref } from 'c/barnFormat';

const PKG = 'Scholarships';

/** An object's list, from its schema import so the name carries any namespace. */
function listHref(schema) {
  return `/lightning/o/${schema.objectApiName}/list`;
}

/**
 * Scholarships Home (SG-03, SG-05, SG-10): New Award Program for whoever may create one, the
 * figures row (active award programs, my reviews to do, applications in review, awards this
 * year), my reviews to do, cycles open or in review, disbursements due in 30 days with any held
 * back, and, for a holder of Manage Scholarships, Export Disbursements as a CSV built here
 * (`c/scholarshipsModel`). Before the first award program, a first-run panel offers New Award
 * Program (D-200 R4).
 */
export default class ScholarshipsHome extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Scholarships');
  canCreate = false;
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
      exportButton: helpText('Scholarships', 'Scholarships_Export_Button'),
      firstRunHeading: helpText('Scholarships', 'Scholarships_Home_FirstRunHeading'),
      firstRunMessage: helpText('Scholarships', 'Scholarships_Home_FirstRunMessage'),
      firstRunNew: helpText('Scholarships', 'Scholarships_Home_FirstRunNew')
    };
  }

  get canManage() {
    return this.home?.canManage === true;
  }

  /** New Award Program shows only to someone who may create award programs. */
  @wire(getObjectInfo, { objectApiName: AWARD_PROGRAM })
  receiveProgramInfo({ data }) {
    this.canCreate = Boolean(data && data.createable);
  }

  /** True before the org's first award program, for someone who may create one. */
  get firstRun() {
    return this.home?.firstRun === true;
  }

  get showTiles() {
    return Boolean(this.home) && !this.firstRun;
  }

  /** The figures row (Module Home pattern), each a link to the list behind it. */
  get tiles() {
    const figures = this.home?.figures || {};
    return [
      {
        key: 'programs',
        label: helpText('Scholarships', 'Scholarships_Home_FigurePrograms'),
        value: figures.programs || 0,
        href: listHref(AWARD_PROGRAM)
      },
      {
        key: 'my-reviews',
        label: helpText('Scholarships', 'Scholarships_Home_FigureMyReviews'),
        value: this.reviews.length,
        href: listHref(APPLICATION_REVIEW)
      },
      {
        key: 'review',
        label: helpText('Scholarships', 'Scholarships_Home_FigureInReview'),
        value: figures.review || 0,
        href: listHref(AWARD_APPLICATION)
      },
      {
        key: 'awards',
        label: helpText('Scholarships', 'Scholarships_Home_FigureAwards'),
        value: figures.awards || 0,
        href: listHref(AWARD)
      }
    ];
  }

  handleNewProgram() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: AWARD_PROGRAM.objectApiName, actionName: 'new' }
    });
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
