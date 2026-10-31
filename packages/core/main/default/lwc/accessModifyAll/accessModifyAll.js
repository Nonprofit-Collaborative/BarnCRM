import { LightningElement } from 'lwc';
import getModifyAllReport from '@salesforce/apex/AccessExplorerController.getModifyAllReport';
import { format, messageFrom, downloadCsv } from 'c/findCsv';

import INTRO from '@salesforce/label/c.Core_AccessModifyAll_Intro';
import DATA_HEADING from '@salesforce/label/c.Core_AccessModifyAll_DataHeading';
import OBJECTS_HEADING from '@salesforce/label/c.Core_AccessModifyAll_ObjectsHeading';
import COL_VIEW_ALL_DATA from '@salesforce/label/c.Core_AccessModifyAll_ColViewAllData';
import COL_MODIFY_ALL_DATA from '@salesforce/label/c.Core_AccessModifyAll_ColModifyAllData';
import COL_AUTHOR_APEX from '@salesforce/label/c.Core_AccessModifyAll_ColAuthorApex';
import COL_IN_GROUPS from '@salesforce/label/c.Core_AccessModifyAll_ColInGroups';
import COL_SCOPE from '@salesforce/label/c.Core_AccessModifyAll_ColScope';
import SCOPE_STANDARD from '@salesforce/label/c.Core_AccessModifyAll_ScopeStandard';
import SCOPE_CUSTOM from '@salesforce/label/c.Core_AccessModifyAll_ScopeCustom';
import TRUNCATED from '@salesforce/label/c.Core_AccessModifyAll_Truncated';
import KIND_PROFILE from '@salesforce/label/c.Core_AccessExplorer_KindProfile';
import KIND_GROUP from '@salesforce/label/c.Core_AccessExplorer_KindGroup';
import KIND_SET from '@salesforce/label/c.Core_AccessExplorer_KindSet';
import KIND_OF_RECORD from '@salesforce/label/c.Core_AccessExplorer_KindOfRecord';
import COL_NAME from '@salesforce/label/c.Core_AccessExplorer_ColName';
import COL_KIND from '@salesforce/label/c.Core_AccessExplorer_ColKind';
import COL_API_NAME from '@salesforce/label/c.Core_AccessExplorer_ColApiName';
import COL_VIEW_ALL from '@salesforce/label/c.Core_AccessExplorer_ColViewAll';
import COL_MODIFY_ALL from '@salesforce/label/c.Core_AccessExplorer_ColModifyAll';
import COL_ACTIVE_PEOPLE from '@salesforce/label/c.Core_AccessExplorer_ColActivePeople';
import NOTHING_TO_SHOW from '@salesforce/label/c.Core_AccessExplorer_NothingToShow';
import DOWNLOAD from '@salesforce/label/c.Core_AccessExplorer_Download';
import DOWNLOADED from '@salesforce/label/c.Core_AccessExplorer_Downloaded';
import YES from '@salesforce/label/c.Core_AccessExplorer_Yes';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

const FILE_BASE = 'Access_Explorer_Modify_All';
/** The most rows the server lists (AccessExplorerController). */
const MAX_ROWS = '2,000';
const KINDS = { profile: KIND_PROFILE, group: KIND_GROUP, permissionSet: KIND_SET };
const SCOPES = { standard: SCOPE_STANDARD, custom: SCOPE_CUSTOM };

const column = (fieldName, label, extra = {}) => ({ label, fieldName, ...extra });
const yes = (value) => (value ? YES : '');

/**
 * The Modify All Report view of Access Explorer (C-53b, plan 6.0a and 6.1.5, D-156, admin guide
 * access-explorer.md): who holds Modify All Data or View All Data, and Modify All or View All on
 * a kind of record, through which profile, permission set or group. One read when it opens.
 * Read only; shown inside Access Explorer, which only administrators reach.
 */
export default class AccessModifyAll extends LightningElement {
  labels = {
    intro: INTRO,
    dataHeading: DATA_HEADING,
    objectsHeading: OBJECTS_HEADING,
    nothingToShow: NOTHING_TO_SHOW,
    download: DOWNLOAD,
    loading: LOADING
  };

  report;
  loading = true;
  errorMessage;
  noticeMessage;

  async connectedCallback() {
    try {
      this.report = await getModifyAllReport();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  get truncatedMessage() {
    return this.report && this.report.truncated ? format(TRUNCATED, MAX_ROWS) : undefined;
  }

  /** Both tables, by name: columns and rows (the CSV uses the same). */
  get tables() {
    const grants = this.report ? this.report.dataGrants : [];
    const objects = this.report ? this.report.objects : [];
    return {
      data: {
        columns: [
          column('label', COL_NAME),
          column('kindLabel', COL_KIND),
          column('modifyAllDataText', COL_MODIFY_ALL_DATA),
          column('viewAllDataText', COL_VIEW_ALL_DATA),
          column('authorApexText', COL_AUTHOR_APEX),
          column('inGroups', COL_IN_GROUPS, { wrapText: true }),
          column('activePeople', COL_ACTIVE_PEOPLE, { type: 'number' })
        ],
        rows: grants.map((grant) => ({
          ...grant,
          key: grant.id,
          kindLabel: KINDS[grant.kind] || '',
          modifyAllDataText: yes(grant.modifyAllData),
          viewAllDataText: yes(grant.viewAllData || grant.modifyAllData),
          authorApexText: yes(grant.authorApex)
        }))
      },
      objects: {
        columns: [
          column('objectLabel', KIND_OF_RECORD),
          column('objectName', COL_API_NAME),
          column('scopeLabel', COL_SCOPE),
          column('holder', COL_NAME),
          column('kindLabel', COL_KIND),
          column('modifyAllText', COL_MODIFY_ALL),
          column('viewAllText', COL_VIEW_ALL),
          column('inGroups', COL_IN_GROUPS, { wrapText: true }),
          column('activePeople', COL_ACTIVE_PEOPLE, { type: 'number' })
        ],
        rows: objects.map((row) => ({
          ...row,
          key: `${row.objectName}:${row.holderId}`,
          scopeLabel: SCOPES[row.scope] || '',
          kindLabel: KINDS[row.kind] || '',
          modifyAllText: yes(row.modifyAll),
          viewAllText: yes(row.viewAll)
        }))
      }
    };
  }

  get dataTable() {
    return this.tables.data;
  }

  get objectTable() {
    return this.tables.objects;
  }

  get hasData() {
    return this.dataTable.rows.length > 0;
  }

  get hasObjects() {
    return this.objectTable.rows.length > 0;
  }

  handleDownload(event) {
    const table = this.tables[event.currentTarget.dataset.table];
    const columns = table.columns.map((each) => ({ label: each.label, path: each.fieldName }));
    downloadCsv(FILE_BASE, columns, table.rows);
    this.noticeMessage = format(DOWNLOADED, String(table.rows.length));
  }
}
