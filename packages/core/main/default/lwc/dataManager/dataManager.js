import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import canFind from '@salesforce/customPermission/Find_And_Export_Records';
import canBulkUpdate from '@salesforce/customPermission/Bulk_Update_Records';
import canBulkDelete from '@salesforce/customPermission/Bulk_Delete_Records';
import getMappings from '@salesforce/apex/DataManagerController.getMappings';
import findToolStateKey from '@salesforce/apex/DataManagerController.findToolStateKey';

import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import TITLE from '@salesforce/label/c.Core_DataManager_Title';
import INTRO from '@salesforce/label/c.Core_DataManager_Intro';
import TOOLS_HEADING from '@salesforce/label/c.Core_DataManager_ToolsHeading';
import IMPORT_TITLE from '@salesforce/label/c.Core_DataManager_ImportTitle';
import IMPORT_TEXT from '@salesforce/label/c.Core_DataManager_ImportText';
import FIND_TITLE from '@salesforce/label/c.Core_DataManager_FindTitle';
import FIND_TEXT from '@salesforce/label/c.Core_DataManager_FindText';
import UPDATE_TITLE from '@salesforce/label/c.Core_DataManager_UpdateTitle';
import UPDATE_TEXT from '@salesforce/label/c.Core_DataManager_UpdateText';
import DELETE_TITLE from '@salesforce/label/c.Core_DataManager_DeleteTitle';
import DELETE_TEXT from '@salesforce/label/c.Core_DataManager_DeleteText';
import DELETE_WARNING from '@salesforce/label/c.Core_DataManager_DeleteWarning';
import DELETE_CONTINUE from '@salesforce/label/c.Core_DataManager_DeleteContinue';
import DELETE_CANCEL from '@salesforce/label/c.Core_DataManager_DeleteCancel';
import BarnConfirmModal from 'c/barnConfirmModal';
import OPTIMIZER_TITLE from '@salesforce/label/c.Core_DataManager_OptimizerTitle';
import OPTIMIZER_TEXT from '@salesforce/label/c.Core_DataManager_OptimizerText';
import OPEN from '@salesforce/label/c.Core_DataManager_Open';
import OPEN_ARIA from '@salesforce/label/c.Core_DataManager_OpenAria';
import MAPPINGS_HEADING from '@salesforce/label/c.Core_DataManager_MappingsHeading';
import MAPPINGS_INTRO from '@salesforce/label/c.Core_DataManager_MappingsIntro';
import MAPPINGS_EMPTY from '@salesforce/label/c.Core_DataManager_MappingsEmpty';
import COLUMN_NAME from '@salesforce/label/c.Core_DataManager_ColumnName';
import COLUMN_LOADS from '@salesforce/label/c.Core_DataManager_ColumnLoads';
import COLUMN_SOURCE from '@salesforce/label/c.Core_DataManager_ColumnSource';
import COLUMN_LAST_LOADED from '@salesforce/label/c.Core_DataManager_ColumnLastLoaded';
import LOADS_PEOPLE from '@salesforce/label/c.Core_DataManager_LoadsPeople';
import SALESFORCE_HEADING from '@salesforce/label/c.Core_DataManager_SalesforceHeading';
import WEEKLY_EXPORT from '@salesforce/label/c.Core_DataManager_WeeklyExport';
import RECYCLE_BIN from '@salesforce/label/c.Core_DataManager_RecycleBin';
import DATA_IMPORT_WIZARD from '@salesforce/label/c.Core_DataManager_DataImportWizard';

/** The tabs the cards open, by API name (ADR-0103 org-optimizer-and-data-manager-pages). */
const TABS = {
  import: 'Import',
  find: 'Find',
  optimizer: 'Data_Hygiene'
};
/** The cards that open Find for a bulk tool, and the tool Find's note names. */
const BULK_TOOLS = { update: 'update', delete: 'delete' };

/** Salesforce's own pages, linked for administrators. */
const SALESFORCE_LINKS = [
  { key: 'export', label: WEEKLY_EXPORT, url: '/lightning/setup/DataManagementExport/home' },
  { key: 'recycle', label: RECYCLE_BIN, url: '/lightning/o/DeleteEvent/home' },
  {
    key: 'wizard',
    label: DATA_IMPORT_WIZARD,
    url: '/lightning/setup/DataManagementDataImporter/home'
  }
];

/**
 * The Data Manager tab (admin guide data-manager.md): a card for each data tool the person may
 * use, the import templates, every data job with its undo (c-data-job-history), and links to
 * Salesforce's own export and Recycle Bin. Each tool keeps its own permission check; the cards
 * only hide what the tool would refuse. The bulk delete card is last and marked destructive: a
 * red Open button that first shows, in a confirmation box, that the records go to the Recycle
 * Bin and can be undone; only Continue opens the tool (D-135). Find, Import and Bulk Update are
 * in no app's navigation, so these cards are how they are reached.
 */
export default class DataManager extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    intro: INTRO,
    toolsHeading: TOOLS_HEADING,
    open: OPEN,
    mappingsHeading: MAPPINGS_HEADING,
    mappingsIntro: MAPPINGS_INTRO,
    mappingsEmpty: MAPPINGS_EMPTY,
    salesforceHeading: SALESFORCE_HEADING
  };

  mappingColumns = [
    { label: COLUMN_NAME, fieldName: 'name' },
    { label: COLUMN_LOADS, fieldName: 'loads' },
    { label: COLUMN_SOURCE, fieldName: 'sourceName' },
    {
      label: COLUMN_LAST_LOADED,
      fieldName: 'lastImportDate',
      type: 'date-local',
      typeAttributes: { year: 'numeric', month: 'short', day: 'numeric' }
    }
  ];

  mappings = [];
  mappingsError;

  get isAdmin() {
    return Boolean(canManageSettings);
  }

  @wire(getMappings)
  wiredMappings({ data, error }) {
    if (data) {
      this.mappings = data.map((mapping) => ({
        ...mapping,
        loads: mapping.targetObject || LOADS_PEOPLE
      }));
      this.mappingsError = undefined;
    } else if (error) {
      this.mappings = [];
      this.mappingsError = (error && error.body && error.body.message) || UNEXPECTED_ERROR;
    }
  }

  get tools() {
    const tools = [];
    if (canManageSettings) {
      tools.push({ key: 'import', title: IMPORT_TITLE, text: IMPORT_TEXT, tab: TABS.import });
    }
    if (canFind) {
      tools.push({ key: 'find', title: FIND_TITLE, text: FIND_TEXT, tab: TABS.find });
    }
    if (canBulkUpdate) {
      tools.push({ key: 'update', title: UPDATE_TITLE, text: UPDATE_TEXT, tab: TABS.find });
    }
    if (canFind || canManageSettings) {
      tools.push({
        key: 'optimizer',
        title: OPTIMIZER_TITLE,
        text: OPTIMIZER_TEXT,
        tab: TABS.optimizer
      });
    }
    // Always last: the one destructive tool.
    if (canBulkDelete) {
      tools.push({
        key: 'delete',
        title: DELETE_TITLE,
        text: DELETE_TEXT,
        tab: TABS.find,
        destructive: true
      });
    }
    return tools.map((tool) => ({
      ...tool,
      openLabel: OPEN_ARIA.replace('{0}', tool.title),
      // A destructive tool reads as one: a red Open button that confirms first.
      buttonVariant: tool.destructive ? 'destructive-text' : 'neutral'
    }));
  }

  get hasMappings() {
    return this.mappings.length > 0;
  }

  /** Find's tool state key, with the namespace's prefix (never a literal `c__`). */
  toolStateKey;

  @wire(findToolStateKey)
  wiredToolStateKey({ data }) {
    if (data) {
      this.toolStateKey = data;
    }
  }

  get salesforceLinks() {
    return SALESFORCE_LINKS;
  }

  async handleOpen(event) {
    const { tab, id } = event.currentTarget.dataset;
    if (id === 'delete') {
      const confirmed = await BarnConfirmModal.open({
        size: 'small',
        label: DELETE_TITLE,
        message: DELETE_WARNING,
        confirmLabel: DELETE_CONTINUE,
        cancelLabel: DELETE_CANCEL,
        confirmVariant: 'destructive'
      });
      if (!confirmed) {
        return;
      }
    }
    const pageReference = { type: 'standard__navItemPage', attributes: { apiName: tab } };
    // The bulk cards open Find with a note saying where the bulk tool is (D-135).
    if (BULK_TOOLS[id] && this.toolStateKey) {
      pageReference.state = { [this.toolStateKey]: BULK_TOOLS[id] };
    }
    this[NavigationMixin.Navigate](pageReference);
  }
}
