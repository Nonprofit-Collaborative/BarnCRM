import { LightningElement } from 'lwc';
import TEMPLATES_URL from '@salesforce/resourceUrl/BarnReporting_Templates';
import getContext from '@salesforce/apex/ReportingLibrary.getContext';
import listSaved from '@salesforce/apex/ReportingLibrary.listSaved';
import listObjects from '@salesforce/apex/ReportingQueryService.listObjects';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { format, formatDate } from 'c/barnFormat';
import { messageFrom } from 'c/findCsv';
import LOCALE from '@salesforce/i18n/locale';
import { availableTemplates, newDashboard } from 'c/reportingModel';

const REPORT = 'barnreport';
const DASHBOARD = 'barndash';
const MAX_SAVED = 1000;

/**
 * The Advanced Reporting tab: dashboards and reports the person can open (their own and those
 * shared with them), the shipped dashboard templates whose modules are installed, and New
 * Report and New Dashboard. Opens c/reportingBuilder or c/reportingDashboard in place.
 */
export default class ReportingHome extends LightningElement {
  helpReady = isHelpLoaded(['Reporting', 'Core']);
  loading = true;
  error = '';
  context = {};
  objects = [];
  saved = [];
  templates = [];
  mode = 'home';
  openId = null;
  openDefinition = null;
  activeTab = 'dashboards';

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(['Reporting', 'Core']).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.loading = true;
    this.error = '';
    try {
      const [context, objects, saved] = await Promise.all([
        getContext(),
        listObjects(),
        listSaved()
      ]);
      this.context = context || {};
      this.objects = objects || [];
      this.saved = saved || [];
      this.templates = await this.loadTemplates();
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    } finally {
      this.loading = false;
    }
  }

  /** The shipped templates whose objects the person can report on (their modules are in). */
  async loadTemplates() {
    try {
      const response = await fetch(TEMPLATES_URL, { credentials: 'same-origin' });
      const body = response.ok ? await response.json() : null;
      const offered = new Set();
      for (const option of this.objects) {
        offered.add(option.value);
        // A namespaced org names objects with a prefix; the templates name them without one.
        offered.add(option.value.replace(/^[A-Za-z0-9]+__(?=.+__c$)/, ''));
      }
      return availableTemplates(body && body.templates, offered);
    } catch {
      return [];
    }
  }

  async reloadSaved() {
    try {
      this.saved = (await listSaved()) || [];
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    }
  }

  // ------------------------------------------------------------------------------------------
  // Read-outs
  // ------------------------------------------------------------------------------------------

  get isHome() {
    return this.mode === 'home';
  }

  get isReport() {
    return this.mode === 'report';
  }

  get isDashboard() {
    return this.mode === 'dashboard';
  }

  rows(kind) {
    return this.saved
      .filter((row) => row.kind === kind)
      .map((row) => ({
        ...row,
        key: row.id,
        ownerText: row.mine ? helpText('Reporting', 'Reporting_Home_You') : row.ownerName,
        accessText: row.mine
          ? helpText('Reporting', 'Reporting_Home_Owner')
          : row.canEdit
            ? helpText('Reporting', 'Reporting_Share_Edit')
            : helpText('Reporting', 'Reporting_Share_View'),
        modifiedText: row.modified ? formatDate(String(row.modified).slice(0, 10), LOCALE) : '',
        openLabel: format(helpText('Reporting', 'Reporting_Home_OpenNamed'), row.title)
      }));
  }

  get dashboards() {
    return this.rows(DASHBOARD);
  }

  /** Said when the list reached its cap (ReportingLibrary.listSaved lists the first 1,000). */
  get savedCapText() {
    return this.saved.length >= MAX_SAVED
      ? format(helpText('Reporting', 'Reporting_Home_SavedCap'), MAX_SAVED.toLocaleString(LOCALE))
      : '';
  }

  get reports() {
    return this.rows(REPORT);
  }

  get hasDashboards() {
    return this.dashboards.length > 0;
  }

  get hasReports() {
    return this.reports.length > 0;
  }

  get savedReports() {
    return this.saved
      .filter((row) => row.kind === REPORT)
      .map((row) => ({ id: row.id, title: row.title }));
  }

  get templateCards() {
    return this.templates.map((template) => ({
      key: template.key,
      title: template.dashboard.title,
      description: template.dashboard.description,
      count: format(
        helpText('Reporting', 'Reporting_Home_WidgetCount'),
        template.dashboard.widgets.length
      ),
      openLabel: format(helpText('Reporting', 'Reporting_Home_OpenNamed'), template.dashboard.title)
    }));
  }

  get hasTemplates() {
    return this.templates.length > 0;
  }

  get canCreate() {
    return this.objects.length > 0;
  }

  get showLists() {
    return !this.loading && this.canCreate;
  }

  get showNoObjects() {
    return !this.loading && !this.error && !this.canCreate;
  }

  get labels() {
    return {
      title: helpText('Reporting', 'Reporting_Home_Title'),
      purpose: helpText('Reporting', 'Reporting_Home_Purpose'),
      help: helpText('Reporting', 'Reporting_Home_Help'),
      loading: helpText('Reporting', 'Reporting_Loading'),
      dashboards: helpText('Reporting', 'Reporting_Home_Dashboards'),
      reports: helpText('Reporting', 'Reporting_Home_Reports'),
      newReport: helpText('Reporting', 'Reporting_Home_NewReport'),
      newDashboard: helpText('Reporting', 'Reporting_Home_NewDashboard'),
      templates: helpText('Reporting', 'Reporting_Home_Templates'),
      templatesHelp: helpText('Reporting', 'Reporting_Home_TemplatesHelp'),
      saved: helpText('Reporting', 'Reporting_Home_SavedDashboards'),
      savedReports: helpText('Reporting', 'Reporting_Home_SavedReports'),
      name: helpText('Reporting', 'Reporting_Home_Name'),
      owner: helpText('Reporting', 'Reporting_Home_Owner'),
      access: helpText('Reporting', 'Reporting_Share_Access'),
      modified: helpText('Reporting', 'Reporting_Home_Modified'),
      open: helpText('Reporting', 'Reporting_Home_Open'),
      noDashboards: helpText('Reporting', 'Reporting_Home_NoDashboards'),
      noDashboardsHelp: this.hasTemplates
        ? helpText('Reporting', 'Reporting_Home_NoDashboardsHelp')
        : helpText('Reporting', 'Reporting_Home_NoDashboardsHelpNoTemplates'),
      noReports: helpText('Reporting', 'Reporting_Home_NoReports'),
      noReportsHelp: helpText('Reporting', 'Reporting_Home_NoReportsHelp'),
      noObjects: helpText('Reporting', 'Reporting_Home_NoObjects')
    };
  }

  // ------------------------------------------------------------------------------------------
  // Navigation within the tab
  // ------------------------------------------------------------------------------------------

  handleTab(event) {
    this.activeTab = event.target.value;
  }

  handleNewReport() {
    this.openId = null;
    this.openDefinition = null;
    this.mode = 'report';
  }

  handleNewDashboard() {
    this.openId = null;
    this.openDefinition = newDashboard();
    this.mode = 'dashboard';
  }

  handleOpen(event) {
    const id = event.currentTarget.dataset.entry;
    const row = this.saved.find((entry) => entry.id === id);
    this.openDefinition = null;
    this.openId = id;
    this.mode = row && row.kind === DASHBOARD ? 'dashboard' : 'report';
  }

  handleTemplate(event) {
    const key = event.currentTarget.dataset.entry;
    const template = this.templates.find((entry) => entry.key === key);
    this.openId = null;
    this.openDefinition = template.dashboard;
    this.mode = 'dashboard';
  }

  handleClose() {
    this.mode = 'home';
    this.openId = null;
    this.openDefinition = null;
  }

  handleSaved() {
    this.reloadSaved();
  }
}
