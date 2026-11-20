import { LightningElement, wire } from 'lwc';
import Toast from 'lightning/toast';
import BarnConfirmModal from 'c/barnConfirmModal';
import getStatus from '@salesforce/apex/SampleDataController.getStatus';
import loadSampleData from '@salesforce/apex/SampleDataController.loadSampleData';
import removeSampleData from '@salesforce/apex/SampleDataController.removeSampleData';
import canManageSampleData from '@salesforce/apex/SampleDataController.canManageSampleData';
import relationshipsOn from '@salesforce/apex/RelationshipController.isFeatureOn';

import cardTitle from '@salesforce/label/c.Core_SampleData_CardTitle';
import loadButtonLabel from '@salesforce/label/c.Core_SampleData_LoadButton';
import removeButtonLabel from '@salesforce/label/c.Core_SampleData_RemoveButton';
import loadConfirmTitle from '@salesforce/label/c.Core_SampleData_LoadConfirmTitle';
import removeConfirmTitle from '@salesforce/label/c.Core_SampleData_RemoveConfirmTitle';
import statusLoaded from '@salesforce/label/c.Core_SampleData_StatusLoaded';
import statusNotLoaded from '@salesforce/label/c.Core_SampleData_StatusNotLoaded';
import statusRemoving from '@salesforce/label/c.Core_SampleData_StatusRemoving';
import statusLoading from '@salesforce/label/c.Core_AccessExplorer_Loading';
import loadingAltText from '@salesforce/label/c.Core_AccessExplorer_Loading';
import householdsLabel from '@salesforce/label/c.Core_SettingsGroup_Households';
import contactsLabel from '@salesforce/label/c.Core_SampleData_ContactsLabel';
import organizationsLabel from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizations';
import relationshipsLabel from '@salesforce/label/c.Core_Feature_Relationships_Name';
import affiliationsLabel from '@salesforce/label/c.Core_Feature_Affiliations_Name';
import cancelButtonLabel from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import confirmButtonLabel from '@salesforce/label/c.Core_HealthCheck_ConfirmButton';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** How often the status card polls while a load is running (C-10). */
const POLL_INTERVAL_MS = 3000;

/**
 * Status card for the C-10 sample data loader: shows whether the sample set is loaded,
 * with Load and Remove actions (each behind a confirmation that warns against
 * production orgs), and polls the load's progress while it runs.
 * See docs/admin-guide/sample-data.md.
 */
export default class SampleDataManager extends LightningElement {
  helpReady = isHelpLoaded('Core');

  labels = {
    cardTitle,
    loadButtonLabel,
    removeButtonLabel,
    loadConfirmTitle,
    get loadConfirmBody() {
      return helpText('Core', 'Core_SampleData_LoadConfirmBody');
    },
    removeConfirmTitle,
    get removeConfirmBody() {
      return helpText('Core', 'Core_SampleData_RemoveConfirmBody');
    },
    get productionWarning() {
      return helpText('Core', 'Core_SampleData_ProductionWarning');
    },
    statusLoaded,
    statusNotLoaded,
    statusLoading,
    statusRemoving,
    loadingAltText,
    householdsLabel,
    contactsLabel,
    organizationsLabel,
    relationshipsLabel,
    affiliationsLabel,
    get readOnlyMessage() {
      return helpText('Core', 'Core_SampleData_ReadOnlyMessage');
    },
    cancelButtonLabel,
    confirmButtonLabel,
    get junctionModeNote() {
      return helpText('Core', 'Core_SampleData_JunctionModeNote');
    },
    get loadSuccess() {
      return helpText('Core', 'Core_SampleData_LoadSuccess');
    },
    get removeSuccess() {
      return helpText('Core', 'Core_SampleData_RemoveSuccess');
    },
    get loadError() {
      return helpText('Core', 'Core_SampleData_LoadError');
    },
    get removeError() {
      return helpText('Core', 'Core_SampleData_RemoveError');
    },
    get statusError() {
      return helpText('Core', 'Core_SampleData_StatusError');
    }
  };

  householdCount = 0;
  contactCount = 0;
  organizationCount = 0;
  relationshipCount = 0;

  // The Relationships tile hides while the Relationships feature is off (D-185).
  @wire(relationshipsOn) relationshipsFeature;
  affiliationCount = 0;
  // One entry per installed module sample set, each carrying its own label, so a module
  // that ships sample data adds a count here without this component changing (C-10).
  moduleCounts = [];
  loaded = false;
  loading = false;
  // The remove runs in the stage batch too (ADMIN-3), so the card polls it like a load.
  removing = false;
  // Undefined until the first status call answers, so the notice never flashes before the
  // org has been asked. Only an explicit true shows it.
  junctionMembership;
  canManage = false;
  isLoadingStatus = true;
  statusFailed = false;
  isBusy = false;

  pollTimer;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.checkPermission();
    this.refreshStatus();
  }

  disconnectedCallback() {
    this.clearPollTimer();
  }

  async checkPermission() {
    try {
      this.canManage = await canManageSampleData();
    } catch {
      // No permission check available (unauthenticated or unpackaged context):
      // fail closed to the read-only view.
      this.canManage = false;
    }
  }

  async refreshStatus() {
    try {
      const result = await getStatus();
      this.applyStatus(result);
      this.statusFailed = false;
    } catch {
      // Only the status read failed, not a load, so no toast: an inline note says so, and the
      // server has already logged the failure.
      this.statusFailed = true;
    } finally {
      this.isLoadingStatus = false;
    }
  }

  applyStatus(result) {
    const wasLoading = this.loading;
    const wasRemoving = this.removing;
    this.householdCount = result.householdCount;
    this.contactCount = result.contactCount;
    this.organizationCount = result.organizationCount;
    this.relationshipCount = result.relationshipCount || 0;
    this.affiliationCount = result.affiliationCount || 0;
    this.moduleCounts = result.moduleCounts || [];
    this.loaded = result.loaded;
    this.loading = result.loading;
    this.removing = result.removing === true;
    this.junctionMembership = result.junctionMembership;

    if (this.loading || this.removing) {
      this.startPolling();
    } else {
      this.clearPollTimer();
      if (wasLoading && this.loaded) {
        this.showToast(this.labels.loadSuccess, '', 'success');
      }
      if (wasRemoving) {
        this.showToast(this.labels.removeSuccess, '', 'success');
      }
    }
  }

  startPolling() {
    if (this.pollTimer) {
      return;
    }
    this.pollTimer = setInterval(() => {
      this.refreshStatus();
    }, POLL_INTERVAL_MS);
  }

  clearPollTimer() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  /**
   * The numbers the card shows, in reading order: Core's own records first, then one tile
   * per installed module sample set, labelled by the module itself.
   */
  get tiles() {
    const tiles = [
      { key: 'households', label: this.labels.householdsLabel, value: this.householdCount },
      { key: 'contacts', label: this.labels.contactsLabel, value: this.contactCount },
      {
        key: 'organizations',
        label: this.labels.organizationsLabel,
        value: this.organizationCount
      }
    ];
    if (this.relationshipsFeature && this.relationshipsFeature.data) {
      tiles.push({
        key: 'relationships',
        label: this.labels.relationshipsLabel,
        value: this.relationshipCount
      });
    }
    tiles.push({
      key: 'affiliations',
      label: this.labels.affiliationsLabel,
      value: this.affiliationCount
    });
    this.moduleCounts.forEach((module) => {
      tiles.push({
        key: `module-${module.name}`,
        label: module.label,
        value: module.recordCount
      });
    });
    return tiles;
  }

  get statusLabel() {
    if (this.loading) {
      return this.labels.statusLoading;
    }
    if (this.removing) {
      return this.labels.statusRemoving;
    }
    return this.loaded ? this.labels.statusLoaded : this.labels.statusNotLoaded;
  }

  /** The status badge's tone (c/barnStatus): running, success or neutral. */
  get statusTone() {
    if (this.loading || this.removing) {
      return 'running';
    }
    return this.loaded ? 'success' : 'neutral';
  }

  get loadDisabled() {
    return !this.canManage || this.loaded || this.loading || this.removing || this.isBusy;
  }

  get removeDisabled() {
    // Remove stays disabled while a load runs: deleting the households mid-chain would
    // leave the next contact chunk inserting against records that no longer exist.
    return !this.canManage || this.loading || this.removing || !this.loaded || this.isBusy;
  }

  handleLoadClick() {
    return this.confirmAndRun('load');
  }

  handleRemoveClick() {
    return this.confirmAndRun('remove');
  }

  /**
   * Asks the person to confirm in a modal, then loads or removes the sample data.
   * Cancel, Escape and the close button change nothing.
   *
   * @param {string} action 'load' or 'remove'
   */
  async confirmAndRun(action) {
    const isLoad = action === 'load';
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: isLoad ? this.labels.loadConfirmTitle : this.labels.removeConfirmTitle,
      message: isLoad ? this.labels.loadConfirmBody : this.labels.removeConfirmBody,
      confirmLabel: this.labels.confirmButtonLabel,
      cancelLabel: this.labels.cancelButtonLabel
    });
    if (!confirmed) {
      return;
    }
    this.isBusy = true;
    try {
      if (action === 'load') {
        await loadSampleData();
      } else {
        // The remove only starts here; the success toast waits for the batch to finish.
        this.applyStatus(await removeSampleData());
      }
    } catch (error) {
      const message = action === 'load' ? this.labels.loadError : this.labels.removeError;
      this.showToast(message, this.reduceError(error), 'error');
    } finally {
      this.isBusy = false;
      await this.refreshStatus();
    }
  }

  showToast(title, message, variant) {
    Toast.show({ label: title, message, variant }, this);
  }

  reduceError(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return error && error.message ? error.message : '';
  }
}
