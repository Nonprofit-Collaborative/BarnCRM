import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import getDashboard from '@salesforce/apex/ProgramDashboardController.getDashboard';

import TITLE from '@salesforce/label/c.Programs_Dashboard_Title';
import PERIOD from '@salesforce/label/c.Core_Shared_Period';
import THIS_MONTH from '@salesforce/label/c.Programs_Dashboard_ThisMonth';
import LAST_MONTH from '@salesforce/label/c.Programs_Dashboard_LastMonth';
import THIS_YEAR from '@salesforce/label/c.Programs_Dashboard_ThisYear';
import LAST_YEAR from '@salesforce/label/c.Programs_Dashboard_LastYear';
import LAST_12_MONTHS from '@salesforce/label/c.Programs_Dashboard_Last12Months';
import ACTIVE_PROGRAMS from '@salesforce/label/c.Programs_Dashboard_ActivePrograms';
import OPEN_ENROLLMENTS from '@salesforce/label/c.Programs_Dashboard_OpenEnrollments';
import NEW_ENROLLMENTS from '@salesforce/label/c.Programs_Dashboard_NewEnrollments';
import COMPLETED from '@salesforce/label/c.Core_Shared_Completed';
import PEOPLE_SERVED from '@salesforce/label/c.Programs_Dashboard_PeopleServed';
import PEOPLE_COUNTED from '@salesforce/label/c.Programs_Dashboard_PeopleCounted';
import DELIVERED from '@salesforce/label/c.Programs_Dashboard_Delivered';
import ATTENDANCE_RATE from '@salesforce/label/c.Programs_Dashboard_AttendanceRate';
import PROGRAM from '@salesforce/label/c.Core_Shared_Program';
import BY_PROGRAM from '@salesforce/label/c.Programs_Dashboard_ByProgram';
import NO_RATE from '@salesforce/label/c.Programs_Dashboard_NoRate';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import TOOLS from '@salesforce/label/c.Core_SettingsGroup_Tools';

import { DEFAULT_PERIOD, periodRange, programRows, tiles, toolTiles } from './dashboardRows';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/** The Programs app's object tabs, in the app's order, as tiles on the module home. */
const TOOL_OBJECTS = [
  'Program__c',
  'Cohort__c',
  'Session__c',
  'Enrollment__c',
  'Service_Delivery__c',
  'Case_Note__c',
  'Referral__c',
  'Service_Count__c',
  'Goal__c'
];

/** The line under each tile, from the help catalog (keys are literals for the CI check). */
function toolLine(apiName) {
  switch (apiName) {
    case 'Program__c':
      return helpText('Programs', 'Programs_Home_ProgramTile');
    case 'Cohort__c':
      return helpText('Programs', 'Programs_Home_CohortTile');
    case 'Session__c':
      return helpText('Programs', 'Programs_Home_SessionTile');
    case 'Enrollment__c':
      return helpText('Programs', 'Programs_Home_EnrollmentTile');
    case 'Service_Delivery__c':
      return helpText('Programs', 'Programs_Home_DeliveryTile');
    case 'Case_Note__c':
      return helpText('Programs', 'Programs_Home_CaseNoteTile');
    case 'Referral__c':
      return helpText('Programs', 'Programs_Home_ReferralTile');
    case 'Service_Count__c':
      return helpText('Programs', 'Programs_Home_CountTile');
    default:
      return helpText('Programs', 'Programs_Home_GoalTile');
  }
}

/**
 * The Programs Dashboard (P-05): for the period picked, tiles for the whole organization and a
 * table per program. The figures are the server's, counted in user mode; the periods and rates
 * are worked out in `dashboardRows`.
 */
export default class ProgramDashboard extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Programs');

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Programs', 'Programs_Dashboard_Intro');
    },
    period: PERIOD,
    program: PROGRAM,
    openEnrollments: OPEN_ENROLLMENTS,
    newEnrollments: NEW_ENROLLMENTS,
    completed: COMPLETED,
    peopleServed: PEOPLE_SERVED,
    peopleCounted: PEOPLE_COUNTED,
    delivered: DELIVERED,
    attendanceRate: ATTENDANCE_RATE,
    byProgram: BY_PROGRAM,
    get noPrograms() {
      return helpText('Programs', 'Programs_Dashboard_NoPrograms');
    },
    get moreThanShown() {
      return helpText('Programs', 'Programs_Dashboard_MoreThanShown');
    },
    get noAccess() {
      return helpText('Programs', 'Programs_Dashboard_NoAccess');
    },
    loading: LOADING
  };

  periodOptions = [
    { label: THIS_MONTH, value: 'thisMonth' },
    { label: LAST_MONTH, value: 'lastMonth' },
    { label: THIS_YEAR, value: 'thisYear' },
    { label: LAST_YEAR, value: 'lastYear' },
    { label: LAST_12_MONTHS, value: 'last12Months' }
  ];

  icons = { dashboard: iconFor('Programs_Dashboard') };

  period = DEFAULT_PERIOD;
  dashboard;
  objectInfos;
  loading = true;
  errorMessage;

  /** The Programs objects the person can read; the rest get no tile. */
  @wire(getObjectInfos, { objectApiNames: TOOL_OBJECTS })
  wiredObjectInfos({ data }) {
    if (data) {
      this.objectInfos = data;
    }
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Programs').then(() => {
        this.helpReady = true;
      });
    }
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
          error && error.body && error.body.message
            ? error.body.message
            : helpText('Programs', 'Programs_Fail_Dashboard');
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
      peopleCounted: PEOPLE_COUNTED,
      delivered: DELIVERED,
      attendanceRate: ATTENDANCE_RATE,
      noRate: NO_RATE
    });
  }

  get rows() {
    return programRows(this.dashboard, NO_RATE);
  }

  get toolGroups() {
    return [
      {
        name: 'tabs',
        label: TOOLS,
        tiles: toolTiles(this.objectInfos, TOOL_OBJECTS, toolLine, (apiName) => iconFor(apiName))
      }
    ];
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
