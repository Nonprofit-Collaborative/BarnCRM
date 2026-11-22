import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { gql, graphql } from 'lightning/graphql';
import getHome from '@salesforce/apex/VolunteersHomeController.getHome';
import VOLUNTEER_JOB from '@salesforce/schema/Volunteer_Job__c';
import IMPORT_BATCH from '@salesforce/schema/Import_Batch__c';
import { iconFor } from 'c/barnIcons';
import { tabPageReference } from 'c/barnTabs';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { pageReferenceFor, toTiles } from './volunteersHomeModel';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

/** Core's Import tab, opened by name: the first-run panel's second action. */
const IMPORT_TAB = 'Import';

// The name comes from a schema import (ADR-0093 A1), so the query works with any namespace.
const JOB_OBJECT = VOLUNTEER_JOB.objectApiName;

/** Whether any volunteer job exists yet, read as the person (ADR-0093). */
const FIRST_JOB = gql`
  query firstVolunteerJob {
    uiapi {
      query {
        ${JOB_OBJECT}(first: 1) {
          edges {
            node {
              Id
            }
          }
        }
      }
    }
  }
`;

/**
 * Volunteers Home (vis-modules-19): the app's first tab. Three figures that open their lists
 * (approved hours this month, hours to approve, shifts needing people), with the Volunteers
 * report charts beside them on the same page, and New Volunteer Job in the header for whoever
 * may create one. Before the first volunteer job, a first-run panel offers New Volunteer Job and
 * Import a File instead of empty figures (D-200 R4).
 */
export default class VolunteersHome extends NavigationMixin(LightningElement) {
  labels = { loading: LOADING };
  helpReady = isHelpLoaded('Volunteers');
  loading = true;
  failed = false;
  home = [];
  /** True once the read finds no volunteer job; undefined until then or when it fails. */
  noJobYet;
  canCreateJob = false;
  canCreateImport = false;
  refreshFirstJob;

  @wire(getObjectInfo, { objectApiName: VOLUNTEER_JOB })
  receiveJobInfo({ data }) {
    this.canCreateJob = Boolean(data && data.createable);
  }

  @wire(getObjectInfo, { objectApiName: IMPORT_BATCH })
  receiveImportInfo({ data }) {
    this.canCreateImport = Boolean(data && data.createable);
  }

  // The first-run panel is a nicety: if the read fails, the figures still show.
  @wire(graphql, { query: FIRST_JOB })
  receiveFirstJob(result) {
    const { data } = result;
    this.refreshFirstJob = result.refresh;
    this.noJobYet = data ? data.uiapi.query[JOB_OBJECT].edges.length === 0 : undefined;
  }

  /** New Volunteer Job in the header, once the help text is in and not beside the first-run one. */
  get showNewJob() {
    return this.helpReady && this.canCreateJob && !this.firstRun;
  }

  connectedCallback() {
    // A card opened again shows the cached read at once; read it again for new jobs.
    if (this.refreshFirstJob) {
      this.refreshFirstJob();
    }
    if (!this.helpReady) {
      loadHelp('Volunteers').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const home = await getHome();
      this.home = home || [];
      this.failed = false;
    } catch {
      this.home = [];
      this.failed = true;
    } finally {
      this.loading = false;
    }
  }

  get showError() {
    return this.failed && this.helpReady;
  }

  get errorMessage() {
    return helpText('Volunteers', 'Volunteers_Home_LoadError');
  }

  get tiles() {
    return toTiles(this.home, iconFor);
  }

  /** No volunteer job exists yet and the person may create one (D-200 R4). */
  get firstRun() {
    return Boolean(this.helpReady && this.canCreateJob && this.noJobYet === true);
  }

  get canImport() {
    return this.firstRun && this.canCreateImport;
  }

  get firstRunText() {
    return {
      heading: helpText('Volunteers', 'Volunteers_Home_FirstRunHeading'),
      message: helpText('Volunteers', 'Volunteers_Home_FirstRunMessage'),
      newJob: helpText('Volunteers', 'Volunteers_Home_FirstRunNewJob'),
      importFile: helpText('Volunteers', 'Volunteers_Home_FirstRunImport')
    };
  }

  get title() {
    return this.helpReady ? helpText('Volunteers', 'Volunteers_Home_Title') : '';
  }

  get purpose() {
    return this.helpReady ? helpText('Volunteers', 'Volunteers_Home_Purpose') : '';
  }

  get iconName() {
    return iconFor('Volunteers_Home');
  }

  /** With nothing to count yet, the report charts below are empty: say why and what to do. */
  get showChartsNote() {
    return Boolean(
      this.helpReady &&
      this.hasTiles &&
      !this.loading &&
      this.tiles.every((tile) => tile.value === 0)
    );
  }

  get chartsNote() {
    return helpText('Volunteers', 'Volunteers_Home_ChartsEmpty');
  }

  get hasTiles() {
    return !this.firstRun && this.tiles.length > 0;
  }

  handleNewJob() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: VOLUNTEER_JOB.objectApiName, actionName: 'new' }
    });
  }

  async handleImport() {
    this[NavigationMixin.Navigate](await tabPageReference(IMPORT_TAB));
  }

  handleTileSelect(event) {
    const name = event.detail && event.detail.name;
    const reference = pageReferenceFor(this.home.find((tile) => tile.name === name));
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }
}
