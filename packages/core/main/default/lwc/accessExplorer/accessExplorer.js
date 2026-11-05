import { LightningElement, wire } from 'lwc';
import searchPeople from '@salesforce/apex/AccessExplorerController.searchPeople';
import searchPermissionSets from '@salesforce/apex/AccessExplorerController.searchPermissionSets';
import getAccess from '@salesforce/apex/AccessExplorerController.getAccess';
import getFieldAccess from '@salesforce/apex/AccessExplorerController.getFieldAccess';
import getObjectAccess from '@salesforce/apex/AccessExplorerController.getObjectAccess';
import getPeopleWithAccess from '@salesforce/apex/AccessExplorerController.getPeopleWithAccess';
import getOverview from '@salesforce/apex/AccessExplorerController.getOverview';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import describeObject from '@salesforce/apex/DataDictionaryController.describeObject';
import { format, messageFrom, downloadCsv } from 'c/findCsv';
import {
  withFlags as toFlagRow,
  withDetails,
  barnName,
  shownColumns,
  nameOptions
} from 'c/accessExplorerRows';

import TITLE from '@salesforce/label/c.Core_AccessExplorer_Title';
import SHOW from '@salesforce/label/c.Core_DataJobs_Show';
import VIEW_SUBJECT from '@salesforce/label/c.Core_AccessExplorer_ViewSubject';
import VIEW_OBJECT from '@salesforce/label/c.Core_AccessExplorer_ViewObject';
import VIEW_BARNCRM from '@salesforce/label/c.Core_AccessExplorer_ViewBarnCrm';
import VIEW_COMPARE from '@salesforce/label/c.Core_AccessCompare_ViewCompare';
import VIEW_MODIFY_ALL from '@salesforce/label/c.Core_AccessCompare_ViewModifyAll';
import VIEW_CHANGE from '@salesforce/label/c.Core_FieldAccess_ViewChange';
import LOOK_UP from '@salesforce/label/c.Core_AccessExplorer_LookUp';
import LOOK_UP_PERSON from '@salesforce/label/c.Core_Section_Person';
import LOOK_UP_SET from '@salesforce/label/c.Core_AccessExplorer_KindSet';
import SEARCH_PLACEHOLDER from '@salesforce/label/c.Core_AccessExplorer_SearchPlaceholder';
import INACTIVE from '@salesforce/label/c.Core_MatchLogic_Inactive';
import KIND_PROFILE from '@salesforce/label/c.Core_AccessExplorer_KindProfile';
import KIND_GROUP from '@salesforce/label/c.Core_AccessExplorer_KindGroup';
import KIND_SET from '@salesforce/label/c.Core_AccessExplorer_KindSet';
import SOURCES_HEADING from '@salesforce/label/c.Core_AccessExplorer_SourcesHeading';
import OBJECTS_HEADING from '@salesforce/label/c.Core_AccessCompare_KindsHeading';
import FIELD_ACCESS_FOR from '@salesforce/label/c.Core_AccessExplorer_FieldAccessFor';
import FIELDS_HEADING from '@salesforce/label/c.Core_AccessCompare_FieldsHeading';
import KIND_OF_RECORD from '@salesforce/label/c.Core_AccessExplorer_KindOfRecord';
import FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import FIELD_NONE from '@salesforce/label/c.Core_AccessExplorer_FieldNone';
import GRANTS_HEADING from '@salesforce/label/c.Core_AccessExplorer_GrantsHeading';
import PEOPLE_HEADING from '@salesforce/label/c.Core_AccessExplorer_PeopleHeading';
import SHOW_MORE from '@salesforce/label/c.Core_AccessExplorer_ShowMore';
import DOWNLOAD from '@salesforce/label/c.Core_AccessExplorer_Download';
import YES from '@salesforce/label/c.Core_AccessExplorer_Yes';
import ALWAYS from '@salesforce/label/c.Core_AccessExplorer_Always';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import COL_NAME from '@salesforce/label/c.Core_CmdtManager_NameField';
import COL_KIND from '@salesforce/label/c.Core_AccessExplorer_ColKind';
import COL_INCLUDES from '@salesforce/label/c.Core_AccessExplorer_ColIncludes';
import COL_API_NAME from '@salesforce/label/c.Core_AccessExplorer_ColApiName';
import COL_READ from '@salesforce/label/c.Core_AccessExplorer_ColRead';
import COL_CREATE from '@salesforce/label/c.Core_AccessExplorer_ColCreate';
import COL_EDIT from '@salesforce/label/c.Core_AccessExplorer_ColEdit';
import COL_DELETE from '@salesforce/label/c.Core_AccessExplorer_ColDelete';
import COL_VIEW_ALL from '@salesforce/label/c.Core_AccessExplorer_ColViewAll';
import COL_MODIFY_ALL from '@salesforce/label/c.Core_AccessExplorer_ColModifyAll';
import COL_GRANTED_BY from '@salesforce/label/c.Core_AccessExplorer_ColGrantedBy';
import COL_ACTIVE_PEOPLE from '@salesforce/label/c.Core_AccessExplorer_ColActivePeople';
import COL_PERSON from '@salesforce/label/c.Core_Section_Person';
import SHOW_TECHNICAL_NAMES from '@salesforce/label/c.Core_Shared_ShowTechnicalNames';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const FILE_BASE = 'Access_Explorer';
const SEARCH_DELAY = 300;
/** The most grants the server lists for one kind of record (AccessExplorerController). */
const MAX_GRANTS = '2,000';
const KINDS = { profile: KIND_PROFILE, group: KIND_GROUP, permissionSet: KIND_SET };

const text = (fieldName, label, extra = {}) => ({ label, fieldName, ...extra });
const FLAG_COLUMNS = [
  text('readText', COL_READ, { initialWidth: 80 }),
  text('createText', COL_CREATE, { initialWidth: 80 }),
  text('editText', COL_EDIT, { initialWidth: 80 }),
  text('delText', COL_DELETE, { initialWidth: 80 }),
  text('viewAllText', COL_VIEW_ALL, { initialWidth: 90 }),
  text('modifyAllText', COL_MODIFY_ALL, { initialWidth: 100 })
];
const READ_EDIT_COLUMNS = FLAG_COLUMNS.filter((column) =>
  ['readText', 'editText'].includes(column.fieldName)
);
const GRANTED_BY = text('grantedBy', COL_GRANTED_BY, { wrapText: true });
const ACTIVE_PEOPLE = text('activePeople', COL_ACTIVE_PEOPLE, { type: 'number' });

/** An API name column: shown only while Show technical names is on (admin-24). */
const API_NAME = text('name', COL_API_NAME, { technical: true });

/** How a BarnCRM role or extra permission is named, as on the Access page (admin-9). */
const barnNames = () => ({
  role: helpText('Core', 'Core_AccessExplorer_RoleName'),
  extraPermission: helpText('Core', 'Core_AccessExplorer_ExtraPermissionName')
});
/** A row as the table and CSV show it (c/accessExplorerRows, framework free). */
const withFlags = (row) =>
  toFlagRow(row, { yes: YES, always: ALWAYS, kinds: KINDS, barnNames: barnNames() });

/**
 * The Access Explorer section of Org Optimizer (C-53, plan Section 6.1.1 item 7, D-154, admin
 * guide access-explorer.md): who can see or change what, and why. Three views: one person or
 * permission set (sources, object access, field access for one kind of record), one kind of
 * record or field (grants with active holders, people 50 at a time), and BarnCRM's own sets with
 * the Tab Access Check. Read only; every table downloads as CSV. The server checks Manage
 * BarnCRM Settings, and Org Optimizer shows the section only to people who hold it.
 */
export default class AccessExplorer extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Core', 'Core_AccessExplorer_Intro');
    },
    show: SHOW,
    lookUp: LOOK_UP,
    searchPlaceholder: SEARCH_PLACEHOLDER,
    get noMatches() {
      return helpText('Core', 'Core_AccessExplorer_NoMatches');
    },
    get chooseSubject() {
      return helpText('Core', 'Core_AccessExplorer_ChooseSubject');
    },
    inactive: INACTIVE,
    sourcesHeading: SOURCES_HEADING,
    objectsHeading: OBJECTS_HEADING,
    fieldAccessFor: FIELD_ACCESS_FOR,
    fieldsHeading: FIELDS_HEADING,
    kindOfRecord: KIND_OF_RECORD,
    field: FIELD,
    get chooseObject() {
      return helpText('Core', 'Core_AccessExplorer_ChooseObject');
    },
    grantsHeading: GRANTS_HEADING,
    peopleHeading: PEOPLE_HEADING,
    get mayMissPeople() {
      return helpText('Core', 'Core_AccessExplorer_MayMissPeople');
    },
    showMore: SHOW_MORE,
    get alwaysField() {
      return helpText('Core', 'Core_AccessExplorer_AlwaysField');
    },
    get tabCheckScheduled() {
      return helpText('Core', 'Core_AccessExplorer_TabCheckScheduled');
    },
    get tabCheckNotScheduled() {
      return helpText('Core', 'Core_AccessExplorer_TabCheckNotScheduled');
    },
    download: DOWNLOAD,
    get nothingToShow() {
      return helpText('Core', 'Core_AccessExplorer_NothingToShow');
    },
    loading: LOADING,
    showTechnicalNames: SHOW_TECHNICAL_NAMES
  };

  viewOptions = [
    { label: VIEW_SUBJECT, value: 'subject' },
    { label: VIEW_OBJECT, value: 'object' },
    { label: VIEW_BARNCRM, value: 'barncrm' },
    { label: VIEW_COMPARE, value: 'compare' },
    { label: VIEW_MODIFY_ALL, value: 'modifyAll' },
    { label: VIEW_CHANGE, value: 'change' }
  ];
  lookUpOptions = [
    { label: LOOK_UP_PERSON, value: 'person' },
    { label: LOOK_UP_SET, value: 'set' }
  ];

  view = 'subject';
  lookUp = 'person';
  term = '';
  results;
  subject;
  fieldObject;
  fieldRows = [];
  objectChoices = [];
  objectName;
  fieldChoices = [];
  fieldName = '';
  showTechnicalNames = false;
  objectAccess;
  people = [];
  nextPage;
  overview;
  loading = false;
  errorMessage;
  noticeMessage;
  searchTimer;
  searchRun = 0;

  @wire(listObjects)
  wiredObjects({ data, error }) {
    if (data) {
      this.objectChoices = data;
    } else if (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get objectOptions() {
    return nameOptions(this.objectChoices, this.showTechnicalNames);
  }

  get fieldOptions() {
    return nameOptions(this.fieldChoices, this.showTechnicalNames);
  }

  handleTechnicalNames(event) {
    this.showTechnicalNames = event.target.checked;
  }

  get isSubjectView() {
    return this.view === 'subject';
  }

  get isObjectView() {
    return this.view === 'object';
  }

  get isBarnCrmView() {
    return this.view === 'barncrm';
  }

  get isCompareView() {
    return this.view === 'compare';
  }

  get isModifyAllView() {
    return this.view === 'modifyAll';
  }

  get isChangeView() {
    return this.view === 'change';
  }

  get noResults() {
    return Array.isArray(this.results) && this.results.length === 0;
  }

  get resultItems() {
    const patterns = barnNames();
    return (this.results || []).map((choice) => ({
      ...choice,
      text: [
        barnName(choice.label, choice.barnKind, patterns),
        KINDS[choice.detail] || choice.detail,
        choice.isActive ? '' : INACTIVE
      ]
        .filter(Boolean)
        .join(', ')
    }));
  }

  get subjectHeading() {
    if (!this.subject) {
      return undefined;
    }
    return withDetails(barnName(this.subject.label, this.subject.barnKind, barnNames()), [
      KINDS[this.subject.detail] || this.subject.detail,
      this.subject.isActive ? '' : INACTIVE
    ]);
  }

  get allDataNotes() {
    const notes = [];
    for (const source of this.subject ? this.subject.sources : []) {
      if (source.modifyAllData) {
        notes.push({
          key: source.id,
          text: format(helpText('Core', 'Core_AccessExplorer_ModifyAllDataNote'), source.label)
        });
      } else if (source.viewAllData) {
        notes.push({
          key: source.id,
          text: format(helpText('Core', 'Core_AccessExplorer_ViewAllDataNote'), source.label)
        });
      }
    }
    return notes;
  }

  get fieldObjectOptions() {
    return nameOptions(
      (this.subject ? this.subject.objects : []).map((row) => ({
        value: row.name,
        label: row.label
      })),
      this.showTechnicalNames
    );
  }

  get truncatedMessage() {
    return this.objectAccess && this.objectAccess.truncated
      ? format(helpText('Core', 'Core_AccessExplorer_Truncated'), MAX_GRANTS)
      : undefined;
  }

  get showGrants() {
    return Boolean(this.objectAccess) && !this.objectAccess.always;
  }

  get hasMorePeople() {
    return Boolean(this.nextPage && this.nextPage.hasMore);
  }

  get tabCheckNextRun() {
    return this.overview && this.overview.tabAccessCheckNextRun;
  }

  /** Every table the section shows, by name: its columns and rows (the CSV uses the same). */
  get tables() {
    const all = this.allTables;
    const shown = {};
    for (const name of Object.keys(all)) {
      shown[name] = {
        rows: all[name].rows,
        columns: shownColumns(all[name].columns, this.showTechnicalNames)
      };
    }
    return shown;
  }

  /** Every table with every column, API name columns marked technical. */
  get allTables() {
    const fieldMode = Boolean(this.fieldName);
    return {
      sources: {
        columns: [
          text('label', COL_NAME),
          text('kindLabel', COL_KIND),
          text('through', COL_INCLUDES, { wrapText: true })
        ],
        rows: (this.subject ? this.subject.sources : []).map(withFlags)
      },
      objects: {
        columns: [text('label', KIND_OF_RECORD), API_NAME, ...FLAG_COLUMNS, GRANTED_BY],
        rows: (this.subject ? this.subject.objects : []).map(withFlags)
      },
      fields: {
        columns: [text('label', FIELD), API_NAME, ...READ_EDIT_COLUMNS, GRANTED_BY],
        rows: this.fieldRows.map(withFlags)
      },
      grants: {
        columns: [
          text('label', COL_NAME),
          text('kindLabel', COL_KIND),
          ...(fieldMode ? READ_EDIT_COLUMNS : FLAG_COLUMNS),
          ACTIVE_PEOPLE
        ],
        rows: (this.objectAccess ? this.objectAccess.grants : []).map(withFlags)
      },
      people: {
        columns: [
          text('label', COL_PERSON),
          ...(fieldMode ? READ_EDIT_COLUMNS : FLAG_COLUMNS),
          GRANTED_BY
        ],
        rows: this.people.map(withFlags)
      },
      barncrm: {
        columns: [text('label', COL_NAME), API_NAME, text('kindLabel', COL_KIND), ACTIVE_PEOPLE],
        rows: (this.overview ? this.overview.sets : []).map(withFlags)
      }
    };
  }

  get sourceTable() {
    return this.tables.sources;
  }

  get objectTable() {
    return this.tables.objects;
  }

  get fieldTable() {
    return this.tables.fields;
  }

  get grantTable() {
    return this.tables.grants;
  }

  get peopleTable() {
    return this.tables.people;
  }

  get barnCrmTable() {
    return this.tables.barncrm;
  }

  handleView(event) {
    this.view = event.detail.value;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    if (this.view === 'barncrm' && !this.overview) {
      this.load(async () => {
        this.overview = await getOverview();
      });
    }
  }

  handleLookUp(event) {
    this.lookUp = event.detail.value;
    this.term = '';
    this.results = undefined;
  }

  handleTerm(event) {
    this.term = event.target.value || '';
    clearTimeout(this.searchTimer);
    if (this.term.trim().length < 2) {
      this.results = undefined;
      return;
    }
    // A pause between key presses, so typing a name runs one search, not one per letter.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.search(), SEARCH_DELAY);
  }

  async search() {
    const run = ++this.searchRun;
    const term = this.term;
    try {
      const found =
        this.lookUp === 'person'
          ? await searchPeople({ term })
          : await searchPermissionSets({ term });
      if (run === this.searchRun) {
        this.results = found;
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  handleChoose(event) {
    const subjectId = event.currentTarget.dataset.value;
    this.results = undefined;
    this.term = '';
    this.fieldObject = undefined;
    this.fieldRows = [];
    this.load(async () => {
      this.subject = await getAccess({ subjectId });
    });
  }

  handleFieldObject(event) {
    this.fieldObject = event.detail.value;
    const subjectId = this.subject.id;
    const objectName = this.fieldObject;
    this.load(async () => {
      this.fieldRows = await getFieldAccess({ subjectId, objectName });
    });
  }

  handleObject(event) {
    this.objectName = event.detail.value;
    this.fieldName = '';
    this.fieldChoices = [];
    this.load(async () => {
      const described = await describeObject({ objectName: this.objectName });
      this.fieldChoices = [
        { value: '', label: FIELD_NONE },
        ...described.fields.map((field) => ({
          value: field.fieldName,
          label: field.fieldLabel
        }))
      ];
      await this.loadObjectAccess();
    });
  }

  handleField(event) {
    this.fieldName = event.detail.value;
    this.load(() => this.loadObjectAccess());
  }

  async loadObjectAccess() {
    const objectName = this.objectName;
    const fieldName = this.fieldName || null;
    this.objectAccess = await getObjectAccess({ objectName, fieldName });
    this.people = [];
    this.nextPage = undefined;
    if (!this.objectAccess.always) {
      await this.loadPeople();
    }
  }

  async loadPeople() {
    const page = await getPeopleWithAccess({
      objectName: this.objectName,
      fieldName: this.fieldName || null,
      afterName: this.nextPage ? this.nextPage.afterName : null,
      afterId: this.nextPage ? this.nextPage.afterId : null
    });
    this.people = [...this.people, ...page.rows];
    this.nextPage = page;
  }

  handleShowMore() {
    this.load(() => this.loadPeople());
  }

  /** Runs one server read with the spinner on, and shows what went wrong, if anything. */
  async load(read) {
    this.loading = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      await read();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  handleDownload(event) {
    const table = this.tables[event.currentTarget.dataset.table];
    const columns = table.columns.map((column) => ({
      label: column.label,
      path: column.fieldName
    }));
    downloadCsv(FILE_BASE, columns, table.rows);
    this.noticeMessage = format(
      helpText('Core', 'Core_AccessExplorer_Downloaded'),
      String(table.rows.length)
    );
  }
}
