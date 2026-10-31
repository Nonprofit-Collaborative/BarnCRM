import { LightningElement } from 'lwc';
import searchPeople from '@salesforce/apex/AccessExplorerController.searchPeople';
import searchPermissionSets from '@salesforce/apex/AccessExplorerController.searchPermissionSets';
import getAccess from '@salesforce/apex/AccessExplorerController.getAccess';
import getFieldAccess from '@salesforce/apex/AccessExplorerController.getFieldAccess';
import { toCsv, fileName, format, messageFrom } from 'c/findCsv';
import { withDetails } from 'c/accessExplorerRows';
import {
  OBJECT_FLAGS,
  FIELD_FLAGS,
  diffRows,
  similarity,
  visibleRows,
  countDifferences
} from 'c/accessDiff';

import COMPARE from '@salesforce/label/c.Core_AccessCompare_Compare';
import PEOPLE from '@salesforce/label/c.Core_AccessCompare_People';
import SETS from '@salesforce/label/c.Core_AccessCompare_Sets';
import FIRST from '@salesforce/label/c.Core_AccessCompare_First';
import SECOND from '@salesforce/label/c.Core_AccessCompare_Second';
import CHOOSE from '@salesforce/label/c.Core_AccessCompare_Choose';
import SIMILARITY from '@salesforce/label/c.Core_AccessCompare_Similarity';
import DIFFERENCES_ONLY from '@salesforce/label/c.Core_AccessCompare_DifferencesOnly';
import KINDS_HEADING from '@salesforce/label/c.Core_AccessCompare_KindsHeading';
import FIELDS_FOR from '@salesforce/label/c.Core_AccessCompare_FieldsFor';
import FIELDS_HEADING from '@salesforce/label/c.Core_AccessCompare_FieldsHeading';
import COUNTS from '@salesforce/label/c.Core_AccessCompare_Counts';
import NO_DIFFERENCES from '@salesforce/label/c.Core_AccessCompare_NoDifferences';
import ONLY_IN from '@salesforce/label/c.Core_AccessCompare_OnlyIn';
import NONE from '@salesforce/label/c.Core_AccessCompare_None';
import COL_DIFFERENCE from '@salesforce/label/c.Core_AccessCompare_ColDifference';
import SEARCH_PLACEHOLDER from '@salesforce/label/c.Core_AccessExplorer_SearchPlaceholder';
import NO_MATCHES from '@salesforce/label/c.Core_AccessExplorer_NoMatches';
import INACTIVE from '@salesforce/label/c.Core_AccessExplorer_Inactive';
import KIND_PROFILE from '@salesforce/label/c.Core_AccessExplorer_KindProfile';
import KIND_GROUP from '@salesforce/label/c.Core_AccessExplorer_KindGroup';
import KIND_SET from '@salesforce/label/c.Core_AccessExplorer_KindSet';
import KIND_OF_RECORD from '@salesforce/label/c.Core_AccessExplorer_KindOfRecord';
import FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import COL_API_NAME from '@salesforce/label/c.Core_AccessExplorer_ColApiName';
import COL_READ from '@salesforce/label/c.Core_AccessExplorer_ColRead';
import COL_CREATE from '@salesforce/label/c.Core_AccessExplorer_ColCreate';
import COL_EDIT from '@salesforce/label/c.Core_AccessExplorer_ColEdit';
import COL_DELETE from '@salesforce/label/c.Core_AccessExplorer_ColDelete';
import COL_VIEW_ALL from '@salesforce/label/c.Core_AccessExplorer_ColViewAll';
import COL_MODIFY_ALL from '@salesforce/label/c.Core_AccessExplorer_ColModifyAll';
import DOWNLOAD from '@salesforce/label/c.Core_AccessExplorer_Download';
import DOWNLOADED from '@salesforce/label/c.Core_AccessExplorer_Downloaded';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

const FILE_BASE = 'Access_Explorer_Compare';
const SEARCH_DELAY = 300;
const KINDS = { profile: KIND_PROFILE, group: KIND_GROUP, permissionSet: KIND_SET };
const FLAG_WORDS = {
  read: COL_READ,
  create: COL_CREATE,
  edit: COL_EDIT,
  del: COL_DELETE,
  viewAll: COL_VIEW_ALL,
  modifyAll: COL_MODIFY_ALL
};

const blankSide = (key, label) => ({
  key,
  label,
  term: '',
  results: undefined,
  subject: undefined
});

/**
 * The Compare Two view of Access Explorer (C-53b, plan 6.0a and 6.1.5, D-156, admin guide
 * access-explorer.md): two people, or two profiles, permission sets or groups, side by side,
 * differences only by default, with a similarity score and a field comparison for one kind of
 * record. It reads each side with the same server calls as the single view and compares in
 * c/accessDiff (framework free). Read only; shown inside Access Explorer, which only
 * administrators reach.
 */
export default class AccessCompare extends LightningElement {
  labels = {
    compare: COMPARE,
    choose: CHOOSE,
    differencesOnly: DIFFERENCES_ONLY,
    kindsHeading: KINDS_HEADING,
    fieldsFor: FIELDS_FOR,
    fieldsHeading: FIELDS_HEADING,
    noDifferences: NO_DIFFERENCES,
    searchPlaceholder: SEARCH_PLACEHOLDER,
    noMatches: NO_MATCHES,
    download: DOWNLOAD,
    loading: LOADING
  };

  kindOptions = [
    { label: PEOPLE, value: 'person' },
    { label: SETS, value: 'set' }
  ];

  kind = 'person';
  sides = [blankSide('a', FIRST), blankSide('b', SECOND)];
  differencesOnly = true;
  fieldObject;
  fieldRowsA = [];
  fieldRowsB = [];
  loading = false;
  errorMessage;
  noticeMessage;
  searchTimer;
  searchRun = 0;

  reset() {
    this.sides = [blankSide('a', FIRST), blankSide('b', SECOND)];
    this.clearFields();
  }

  disconnectedCallback() {
    clearTimeout(this.searchTimer);
  }

  get sideItems() {
    return this.sides.map((side) => ({
      ...side,
      noResults: Array.isArray(side.results) && side.results.length === 0,
      resultItems: (side.results || []).map((choice) => ({
        ...choice,
        text: [choice.label, KINDS[choice.detail] || choice.detail, choice.isActive ? '' : INACTIVE]
          .filter(Boolean)
          .join(', ')
      })),
      heading: side.subject
        ? withDetails(side.subject.label, [
            KINDS[side.subject.detail] || side.subject.detail,
            side.subject.isActive ? '' : INACTIVE
          ])
        : undefined
    }));
  }

  get bothChosen() {
    return Boolean(this.sides[0].subject && this.sides[1].subject);
  }

  /** Each side's name; two identical names fall back to First and Second. */
  get names() {
    const [a, b] = this.sides.map((side) => (side.subject ? side.subject.label : side.label));
    return a === b ? [FIRST, SECOND] : [a, b];
  }

  get words() {
    return {
      flags: FLAG_WORDS,
      onlyIn: ONLY_IN,
      nameA: this.names[0],
      nameB: this.names[1],
      none: NONE
    };
  }

  get objectDiff() {
    if (!this.bothChosen) {
      return [];
    }
    const [a, b] = this.sides.map((side) => side.subject.objects);
    return diffRows(a, b, OBJECT_FLAGS, this.words);
  }

  get fieldDiff() {
    return this.fieldObject
      ? diffRows(this.fieldRowsA, this.fieldRowsB, FIELD_FLAGS, this.words)
      : [];
  }

  get similarityText() {
    const [a, b] = this.sides.map((side) => side.subject.objects);
    return format(SIMILARITY, String(similarity(a, b, OBJECT_FLAGS)));
  }

  get fieldObjectOptions() {
    const byName = new Map();
    for (const side of this.sides) {
      for (const row of side.subject ? side.subject.objects : []) {
        byName.set(row.name, `${row.label} (${row.name})`);
      }
    }
    return [...byName.entries()]
      .map(([value, label]) => ({ value, label }))
      .sort((x, y) => x.label.localeCompare(y.label));
  }

  /** Both tables, by name: columns, the rows shown and a count line (the CSV uses the same). */
  get tables() {
    const columns = (first) => [
      { label: first, fieldName: 'label' },
      { label: COL_API_NAME, fieldName: 'name' },
      { label: this.names[0], fieldName: 'aText', wrapText: true },
      { label: this.names[1], fieldName: 'bText', wrapText: true },
      { label: COL_DIFFERENCE, fieldName: 'difference', wrapText: true }
    ];
    const shown = (diff) => {
      const rows = visibleRows(diff, this.differencesOnly);
      const count = format(COUNTS, String(countDifferences(diff)), String(diff.length));
      return { rows, count, empty: rows.length === 0 };
    };
    return {
      objects: { columns: columns(KIND_OF_RECORD), ...shown(this.objectDiff) },
      fields: { columns: columns(FIELD), ...shown(this.fieldDiff) }
    };
  }

  get objectTable() {
    return this.tables.objects;
  }

  get fieldTable() {
    return this.tables.fields;
  }

  get showFields() {
    return Boolean(this.fieldObject);
  }

  handleKind(event) {
    this.kind = event.detail.value;
    this.reset();
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
  }

  handleDifferencesOnly(event) {
    this.differencesOnly = event.target.checked;
  }

  handleTerm(event) {
    const key = event.target.dataset.side;
    const term = event.target.value || '';
    this.patchSide(key, { term });
    clearTimeout(this.searchTimer);
    if (term.trim().length < 2) {
      this.patchSide(key, { results: undefined });
      return;
    }
    // A pause between key presses, so typing a name runs one search, not one per letter.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.search(key, term), SEARCH_DELAY);
  }

  async search(key, term) {
    const run = ++this.searchRun;
    try {
      const found =
        this.kind === 'person'
          ? await searchPeople({ term })
          : await searchPermissionSets({ term });
      if (run === this.searchRun) {
        this.patchSide(key, { results: found });
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  patchSide(key, changes) {
    this.sides = this.sides.map((side) => {
      return side.key === key ? { ...side, ...changes } : side;
    });
  }

  handleChoose(event) {
    const key = event.currentTarget.dataset.side;
    const subjectId = event.currentTarget.dataset.value;
    this.patchSide(key, { term: '', results: undefined });
    this.clearFields();
    this.load(async () => {
      this.patchSide(key, { subject: await getAccess({ subjectId }) });
    });
  }

  handleFieldObject(event) {
    this.fieldObject = event.detail.value;
    const objectName = this.fieldObject;
    const [a, b] = this.sides.map((side) => side.subject.id);
    this.load(async () => {
      [this.fieldRowsA, this.fieldRowsB] = await Promise.all([
        getFieldAccess({ subjectId: a, objectName }),
        getFieldAccess({ subjectId: b, objectName })
      ]);
    });
  }

  clearFields() {
    this.fieldObject = undefined;
    this.fieldRowsA = [];
    this.fieldRowsB = [];
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
    const link = document.createElement('a');
    link.href = URL.createObjectURL(
      new Blob([toCsv(columns, table.rows)], { type: 'text/csv;charset=utf-8' })
    );
    link.download = fileName(FILE_BASE);
    link.click();
    URL.revokeObjectURL(link.href);
    this.noticeMessage = format(DOWNLOADED, String(table.rows.length));
  }
}
