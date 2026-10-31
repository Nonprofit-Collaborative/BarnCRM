import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDashboard from '@salesforce/apex/ProgramDashboardController.getDashboard';

import TITLE from '@salesforce/label/c.Programs_Dashboard_Title';
import INTRO from '@salesforce/label/c.Programs_Dashboard_Intro';
import PERIOD from '@salesforce/label/c.Programs_Dashboard_Period';
import THIS_MONTH from '@salesforce/label/c.Programs_Dashboard_ThisMonth';
import LAST_MONTH from '@salesforce/label/c.Programs_Dashboard_LastMonth';
import THIS_YEAR from '@salesforce/label/c.Programs_Dashboard_ThisYear';
import LAST_YEAR from '@salesforce/label/c.Programs_Dashboard_LastYear';
import LAST_12_MONTHS from '@salesforce/label/c.Programs_Dashboard_Last12Months';
import ACTIVE_PROGRAMS from '@salesforce/label/c.Programs_Dashboard_ActivePrograms';
import OPEN_ENROLLMENTS from '@salesforce/label/c.Programs_Dashboard_OpenEnrollments';
import NEW_ENROLLMENTS from '@salesforce/label/c.Programs_Dashboard_NewEnrollments';
import COMPLETED from '@salesforce/label/c.Programs_Dashboard_Completed';
import PEOPLE_SERVED from '@salesforce/label/c.Programs_Dashboard_PeopleServed';
import DELIVERED from '@salesforce/label/c.Programs_Dashboard_Delivered';
import ATTENDANCE_RATE from '@salesforce/label/c.Programs_Dashboard_AttendanceRate';
import PROGRAM from '@salesforce/label/c.Programs_Dashboard_Program';
import BY_PROGRAM from '@salesforce/label/c.Programs_Dashboard_ByProgram';
import NO_RATE from '@salesforce/label/c.Programs_Dashboard_NoRate';
import NO_PROGRAMS from '@salesforce/label/c.Programs_Dashboard_NoPrograms';
import MORE_THAN_SHOWN from '@salesforce/label/c.Programs_Dashboard_MoreThanShown';
import LOAD_FAILED from '@salesforce/label/c.Programs_Dashboard_LoadFailed';
import NO_ACCESS from '@salesforce/label/c.Programs_Dashboard_NoAccess';
import LOADING from '@salesforce/label/c.Programs_Loading';

import { DEFAULT_PERIOD, periodRange, programRows, tiles } from './dashboardRows';

/**
 * The Programs Dashboard (P-05): for the period picked, tiles for the whole organization and a
 * table per program. The figures are the server's, counted in user mode; the periods and rates
 * are worked out in `dashboardRows`.
 */
export default class ProgramDashboard extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    intro: INTRO,
    period: PERIOD,
    program: PROGRAM,
    openEnrollments: OPEN_ENROLLMENTS,
    newEnrollments: NEW_ENROLLMENTS,
    completed: COMPLETED,
    peopleServed: PEOPLE_SERVED,
    delivered: DELIVERED,
    attendanceRate: ATTENDANCE_RATE,
    byProgram: BY_PROGRAM,
    noPrograms: NO_PROGRAMS,
    moreThanShown: MORE_THAN_SHOWN,
    noAccess: NO_ACCESS,
    loading: LOADING
  };

  periodOptions = [
    { label: THIS_MONTH, value: 'thisMonth' },
    { label: LAST_MONTH, value: 'lastMonth' },
    { label: THIS_YEAR, value: 'thisYear' },
    { label: LAST_YEAR, value: 'lastYear' },
    { label: LAST_12_MONTHS, value: 'last12Months' }
  ];

  period = DEFAULT_PERIOD;
  dashboard;
  loading = true;
  errorMessage;

  connectedCallback() {
    this.load();
  }

  load() {
    this.loading = true;
    this.errorMessage = undefined;
    return getDashboard(periodRange(this.period, new Date()))
      .then((dashboard) => {
        this.dashboard = dashboard;
      })
      .catch((error) => {
        this.dashboard = undefined;
        this.errorMessage =
          error && error.body && error.body.message ? error.body.message : LOAD_FAILED;
      })
      .finally(() => {
        this.loading = false;
      });
  }

  get canSee() {
    return !!(this.dashboard && this.dashboard.canSee);
  }

  get noAccess() {
    return !!this.dashboard && !this.dashboard.canSee;
  }

  get tiles() {
    return tiles(this.dashboard, {
      activePrograms: ACTIVE_PROGRAMS,
      openEnrollments: OPEN_ENROLLMENTS,
      newEnrollments: NEW_ENROLLMENTS,
      peopleServed: PEOPLE_SERVED,
      delivered: DELIVERED,
      attendanceRate: ATTENDANCE_RATE,
      noRate: NO_RATE
    });
  }

  get rows() {
    return programRows(this.dashboard, NO_RATE);
  }

  get noRows() {
    return this.rows.length === 0;
  }

  get moreThanShown() {
    return !!(this.dashboard && this.dashboard.moreThanShown);
  }

  handlePeriodChange(event) {
    this.period = event.detail.value;
    return this.load();
  }

  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' }
    });
  }
}
