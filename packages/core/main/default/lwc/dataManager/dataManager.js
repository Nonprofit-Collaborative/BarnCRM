import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import canFind from '@salesforce/customPermission/Find_And_Export_Records';
import canBulkUpdate from '@salesforce/customPermission/Bulk_Update_Records';
import canBulkDelete from '@salesforce/customPermission/Bulk_Delete_Records';
import getMappings from '@salesforce/apex/DataManagerController.getMappings';
import findToolStateKey from '@salesforce/apex/DataManagerController.findToolStateKey';
import BarnConfirmModal from 'c/barnConfirmModal';

import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import TITLE from '@salesforce/label/c.Core_DataManager_Title';
import INTRO from '@salesforce/label/c.Core_DataManager_Intro';
import HELP_CHANGE from '@salesforce/label/c.Core_DataManager_HelpChange';
import HELP_DELETE from '@salesforce/label/c.Core_DataManager_HelpDelete';
import GROUP_BRING_IN from '@salesforce/label/c.Core_DataManager_GroupBringIn';
import GROUP_FIND_CHANGE from '@salesforce/label/c.Core_DataManager_GroupFindChange';
import GROUP_CHECK from '@salesforce/label/c.Core_DataManager_GroupCheck';
import GROUP_CAREFUL from '@salesforce/label/c.Core_DataManager_GroupCareful';
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
import OPTIMIZER_TITLE from '@salesforce/label/c.Core_DataManager_OptimizerTitle';
import OPTIMIZER_TEXT from '@salesforce/label/c.Core_DataManager_OptimizerText';
import MAPPINGS_HEADING from '@salesforce/label/c.Core_DataManager_MappingsHeading';
import MAPPINGS_INTRO from '@salesforce/label/c.Core_DataManager_MappingsIntro';
import MAPPINGS_EMPTY from '@salesforce/label/c.Core_DataManager_MappingsEmpty';
import MAPPINGS_EMPTY_HINT from '@salesforce/label/c.Core_DataManager_MappingsEmptyHint';
import CREATE_TEMPLATE from '@salesforce/label/c.Core_DataManager_CreateTemplate';
import COLUMN_NAME from '@salesforce/label/c.Core_DataManager_ColumnName';
import COLUMN_LOADS from '@salesforce/label/c.Core_DataManager_ColumnLoads';
import COLUMN_SOURCE from '@salesforce/label/c.Core_DataManager_ColumnSource';
import COLUMN_LAST_LOADED from '@salesforce/label/c.Core_DataManager_ColumnLastLoaded';
import LOADS_PEOPLE from '@salesforce/label/c.Core_DataManager_LoadsPeople';
import SALESFORCE_HEADING from '@salesforce/label/c.Core_DataManager_SalesforceHeading';
import WEEKLY_EXPORT from '@salesforce/label/c.Core_DataManager_WeeklyExport';
import WEEKLY_EXPORT_TEXT from '@salesforce/label/c.Core_DataManager_WeeklyExportText';
import RECYCLE_BIN from '@salesforce/label/c.Core_DataManager_RecycleBin';
import RECYCLE_BIN_TEXT from '@salesforce/label/c.Core_DataManager_RecycleBinText';
import DATA_IMPORT_WIZARD from '@salesforce/label/c.Core_DataManager_DataImportWizard';
import DATA_IMPORT_WIZARD_TEXT from '@salesforce/label/c.Core_DataManager_DataImportWizardText';

/** The tabs the tiles open, by API name (ADR-0103 org-optimizer-and-data-manager-pages). */
const TABS = {
  import: 'Import',
  find: 'Find',
  // Super Transform (C-50) on the tab that kept the Bulk Update API name.
  update: 'Bulk_Update',
  optimizer: 'Data_Hygiene',
  delete: 'Find'
};
/** The tiles that open Find for a bulk tool, and the tool Find's note names. */
const BULK_TOOLS = { delete: 'delete' };

const LEARN_MORE_URL =
  'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/docs/admin-guide/data-manager.md';

/** Salesforce's own pages, for administrators; each opens in a new browser tab. */
const SALESFORCE_TILES = [
  {
    name: 'export',
    label: WEEKLY_EXPORT,
    description: WEEKLY_EXPORT_TEXT,
    iconName: 'standard:dataset',
    href: '/lightning/setup/DataManagementExport/home',
    newTab: true
  },
  {
    name: 'recycle',
    label: RECYCLE_BIN,
    description: RECYCLE_BIN_TEXT,
    iconName: 'standard:recycle_bin',
    href: '/lightning/o/DeleteEvent/home',
    newTab: true
  },
  {
    name: 'wizard',
    label: DATA_IMPORT_WIZARD,
    description: DATA_IMPORT_WIZARD_TEXT,
    iconName: 'standard:data_mapping',
    href: '/lightning/setup/DataManagementDataImporter/home',
    newTab: true
  }
];

/**
 * The Data Manager tab (admin guide data-manager.md), built on the UX kit: a hub of tool tiles
 * in groups, the import templates, every data job with its undo (c-data-job-history), and tiles
 * for Salesforce's own export, Recycle Bin and Data Import Wizard. Each tool keeps its own
 * permission check; the tiles only hide what the tool would refuse. Delete Many Records is last,
 * alone in the Careful group, and first shows in a confirmation box that the records go to the
 * Recycle Bin and can be undone; only Continue opens the tool (D-135). Find, Import and Bulk
 * Update are in no app's navigation, so these tiles are how they are reached.
 */
export default class DataManager extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    intro: INTRO,
    helpChange: HELP_CHANGE,
    helpDelete: HELP_DELETE,
    mappingsHeading: MAPPINGS_HEADING,
    mappingsIntro: MAPPINGS_INTRO,
    mappingsEmpty: MAPPINGS_EMPTY,
    mappingsEmptyHint: MAPPINGS_EMPTY_HINT,
    createTemplate: CREATE_TEMPLATE
  };

  learnMoreUrl = LEARN_MORE_URL;

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

  /** Find's tool state key, with the namespace's prefix (never a literal `c__`). */
  toolStateKey;

  get isAdmin() {
    return Boolean(canManageSettings);
  }

  @wire(getMappings)
  wiredMappings({ data, error }) {
    if (data) {
      this.mappings = data.map((mapping) => ({
        ...mapping,
        // The server names what each mapping loads (an object label, Gifts, or people and
        // organizations), never an API name.
        loads: mapping.loads || LOADS_PEOPLE
      }));
      this.mappingsError = undefined;
    } else if (error) {
      this.mappings = [];
      this.mappingsError = (error && error.body && error.body.message) || UNEXPECTED_ERROR;
    }
  }

  @wire(findToolStateKey)
  wiredToolStateKey({ data }) {
    if (data) {
      this.toolStateKey = data;
    }
  }

  /** The tool tiles, grouped, for the tools the person may use. Empty groups are left out. */
  get toolGroups() {
    const bringIn = [];
    if (canManageSettings) {
      bringIn.push(tile('import', IMPORT_TITLE, IMPORT_TEXT, 'standard:data_streams'));
    }
    const findChange = [];
    if (canFind) {
      findChange.push(tile('find', FIND_TITLE, FIND_TEXT, 'standard:search'));
    }
    if (canBulkUpdate) {
      findChange.push(tile('update', UPDATE_TITLE, UPDATE_TEXT, 'standard:record_update'));
    }
    const check = [];
    if (canFind || canManageSettings) {
      check.push(
        tile('optimizer', OPTIMIZER_TITLE, OPTIMIZER_TEXT, 'standard:data_integration_hub')
      );
    }
    // Always last: the one destructive tool.
    const careful = [];
    if (canBulkDelete) {
      careful.push(tile('delete', DELETE_TITLE, DELETE_TEXT, 'standard:record_delete'));
    }
    return [
      { name: 'bringIn', label: GROUP_BRING_IN, tiles: bringIn },
      { name: 'findChange', label: GROUP_FIND_CHANGE, tiles: findChange },
      { name: 'check', label: GROUP_CHECK, tiles: check },
      { name: 'careful', label: GROUP_CAREFUL, tiles: careful }
    ];
  }

  get salesforceGroups() {
    return [{ name: 'salesforce', label: SALESFORCE_HEADING, tiles: SALESFORCE_TILES }];
  }

  get hasMappings() {
    return this.mappings.length > 0;
  }

  async handleSelect(event) {
    const name = event.detail && event.detail.name;
    if (!TABS[name]) {
      return;
    }
    if (name === 'delete') {
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
    const pageReference = { type: 'standard__navItemPage', attributes: { apiName: TABS[name] } };
    // The bulk tiles open Find with a note saying where the bulk tool is (D-135).
    if (BULK_TOOLS[name] && this.toolStateKey) {
      pageReference.state = { [this.toolStateKey]: BULK_TOOLS[name] };
    }
    this[NavigationMixin.Navigate](pageReference);
  }

  /** A template is made in Import's One Kind of Record step, so the empty state opens Import. */
  handleCreateTemplate() {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: TABS.import }
    });
  }
}

function tile(name, label, description, iconName) {
  return { name, label, description, iconName };
}
