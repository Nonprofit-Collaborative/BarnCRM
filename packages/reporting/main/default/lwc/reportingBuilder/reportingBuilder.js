import { LightningElement, api } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import listChildren from '@salesforce/apex/ReportingQueryService.listChildren';
import load from '@salesforce/apex/ReportingLibrary.load';
import save from '@salesforce/apex/ReportingLibrary.save';
import share from '@salesforce/apex/ReportingLibrary.share';
import remove from '@salesforce/apex/ReportingLibrary.remove';
import { helpText } from 'c/barnHelpText';
import { format } from 'c/barnFormat';
import { messageFrom } from 'c/findCsv';
import {
  DATE_TYPES,
  MAX_COLUMNS,
  MAX_GROUPS,
  MAX_MEASURES,
  MAX_RELATED,
  MAX_ROWS,
  MAX_SUMMARIES,
  isTotals,
  moved,
  newReport,
  normalizeReport,
  replaceAt,
  reportProblems
} from 'c/reportingModel';

export const REPORT_KIND = 'barnreport';

const PICKER_KINDS = {
  sum: 'sum',
  avg: 'sum',
  min: 'minmax',
  max: 'minmax',
  countDistinct: 'distinct'
};

/**
 * The Advanced Reporting report builder: an object, then columns (crossing lookups), filters, a
 * date range, conditions on related records (records that have, or have no, related records),
 * groupings with totals, totals of related records per row, the display (table, bar, column,
 * line, donut or metric), sort and row limit. Run shows the result below; Save, Save As, Share
 * and Delete keep it as a file the person owns (ReportingLibrary). Fires `close` and `saved`.
 */
export default class ReportingBuilder extends LightningElement {
  /** What the person may do: `{ canSave, canExport }` (ReportingLibrary.getContext). */
  @api context = {};

  /** The objects the person may report on: `[{ value, label }]`. */
  @api objects = [];

  /**
   * Editing a dashboard widget's report: Done (fires `done` with `{ report }`) takes the place
   * of Save, Save As, Share and Delete, since the dashboard saves it.
   */
  @api forWidget = false;

  report = newReport('');
  preview;
  saved = null;
  sharing = null;
  children = [];
  error = '';
  notice = '';
  busy = false;
  sharingOpen = false;
  _documentId;
  _startObject;

  /** A saved report to open. */
  @api
  get documentId() {
    return this._documentId;
  }
  set documentId(value) {
    this._documentId = value;
    if (value) {
      this.open(value);
    }
  }

  /** A report to start from, such as a dashboard widget's (a definition, not saved). */
  @api
  get start() {
    return this.report;
  }
  set start(value) {
    if (value) {
      this.report = normalizeReport(value);
      this.loadChildren();
    }
  }

  async open(documentId) {
    this.busy = true;
    this.error = '';
    try {
      const row = await load({ documentId });
      const definition = JSON.parse(row.definition);
      this.saved = row;
      this.sharing = definition.sharing || null;
      this.report = normalizeReport({ ...definition, title: row.title });
      this.preview = this.report;
      this.loadChildren();
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    } finally {
      this.busy = false;
    }
  }

  async loadChildren() {
    this.children = [];
    if (!this.report.object) {
      return;
    }
    try {
      const objectName = this.report.object;
      const children = await listChildren({ objectName });
      if (objectName === this.report.object) {
        this.children = children || [];
      }
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    }
  }

  /** Replaces the report with a changed copy. */
  change(patch) {
    this.report = normalizeReport({ ...this.report, ...patch });
    this.notice = '';
  }

  // ------------------------------------------------------------------------------------------
  // Read-outs for the template
  // ------------------------------------------------------------------------------------------

  get heading() {
    return this.report.title || helpText('Reporting', 'Reporting_Builder_NewReport');
  }

  get hasObject() {
    return !!this.report.object;
  }

  get isTotals() {
    return isTotals(this.report);
  }

  get isList() {
    return !this.isTotals;
  }

  get readOnly() {
    return !!this.saved && !this.saved.canEdit;
  }

  get canSave() {
    return (
      !this.forWidget &&
      !!(this.context && this.context.canSave) &&
      !this.readOnly &&
      this.hasObject
    );
  }

  get canSaveAs() {
    return !this.forWidget && !!(this.context && this.context.canSave) && this.hasObject;
  }

  get isOwner() {
    return !this.forWidget && !!this.saved && this.saved.mine;
  }

  get doneDisabled() {
    return this.runDisabled;
  }

  get canExport() {
    return !!(this.context && this.context.canExport);
  }

  get objectOptions() {
    return this.objects || [];
  }

  get columns() {
    const last = this.report.columns.length - 1;
    return this.report.columns.map((column, index) => ({
      ...column,
      key: `c${index}-${column.path}`,
      index,
      isDate: DATE_TYPES.has(column.type),
      asAge: column.show === 'age',
      first: index === 0,
      last: index === last,
      upLabel: format(helpText('Reporting', 'Reporting_MoveUp'), column.label),
      downLabel: format(helpText('Reporting', 'Reporting_MoveDown'), column.label),
      removeLabel: format(helpText('Reporting', 'Reporting_RemoveNamed'), column.label)
    }));
  }

  get canAddColumn() {
    return this.report.columns.length < MAX_COLUMNS;
  }

  get filterJson() {
    const filter = this.report.filter;
    return typeof filter === 'string' ? filter : JSON.stringify(filter);
  }

  get dateField() {
    return this.report.dateRange ? this.report.dateRange.field || '' : '';
  }

  get dateRange() {
    return this.report.dateRange;
  }

  get childOptions() {
    return this.children.map((child) => ({
      value: `${child.object}.${child.field}`,
      label: format(
        helpText('Reporting', 'Reporting_ChildOption'),
        child.objectLabel,
        child.fieldLabel
      )
    }));
  }

  get hasChildren() {
    return this.children.length > 0;
  }

  get hasOptions() {
    return [
      { value: 'has', label: helpText('Reporting', 'Reporting_Related_Has') },
      { value: 'hasNo', label: helpText('Reporting', 'Reporting_Related_HasNo') }
    ];
  }

  get related() {
    return this.report.related.map((entry, index) => ({
      ...entry,
      key: `r${index}`,
      index,
      choice: `${entry.object}.${entry.field}`,
      hasValue: entry.has ? 'has' : 'hasNo',
      filterJson: entry.filter
        ? typeof entry.filter === 'string'
          ? entry.filter
          : JSON.stringify(entry.filter)
        : '',
      removeLabel: format(helpText('Reporting', 'Reporting_RemoveNamed'), entry.label)
    }));
  }

  get canAddRelated() {
    return this.hasChildren && this.report.related.length < MAX_RELATED;
  }

  get bucketOptions() {
    return ['day', 'week', 'month', 'quarter', 'year'].map((bucket) => ({
      value: bucket,
      label: {
        day: helpText('Reporting', 'Reporting_Bucket_Day'),
        week: helpText('Reporting', 'Reporting_Bucket_Week'),
        month: helpText('Reporting', 'Reporting_Bucket_Month'),
        quarter: helpText('Reporting', 'Reporting_Bucket_Quarter'),
        year: helpText('Reporting', 'Reporting_Bucket_Year')
      }[bucket]
    }));
  }

  get groups() {
    return this.report.groups.map((group, index) => ({
      ...group,
      key: `g${index}-${group.field}`,
      index,
      isDate: DATE_TYPES.has(group.type),
      bucketValue: group.bucket || 'day',
      label: group.label,
      fieldLabel:
        index === 0
          ? helpText('Reporting', 'Reporting_Builder_GroupBy')
          : helpText('Reporting', 'Reporting_Builder_ThenBy'),
      removeLabel: format(helpText('Reporting', 'Reporting_RemoveNamed'), group.label)
    }));
  }

  get canAddGroup() {
    return this.report.groups.length < MAX_GROUPS;
  }

  get functionOptions() {
    return [
      { value: 'count', label: helpText('Reporting', 'Reporting_Fn_Count') },
      { value: 'sum', label: helpText('Reporting', 'Reporting_Fn_Sum') },
      { value: 'avg', label: helpText('Reporting', 'Reporting_Fn_Avg') },
      { value: 'min', label: helpText('Reporting', 'Reporting_Fn_Min') },
      { value: 'max', label: helpText('Reporting', 'Reporting_Fn_Max') },
      { value: 'countDistinct', label: helpText('Reporting', 'Reporting_Fn_CountDistinct') }
    ];
  }

  get measures() {
    return this.report.measures.map((measure, index) => ({
      ...measure,
      key: `m${index}`,
      index,
      needsField: measure.fn !== 'count',
      pickerKind: PICKER_KINDS[measure.fn] || 'sum',
      removeLabel: format(helpText('Reporting', 'Reporting_RemoveNamed'), measure.label)
    }));
  }

  get canAddMeasure() {
    return this.report.measures.length < MAX_MEASURES;
  }

  get summaries() {
    return this.report.summaries.map((entry, index) => ({
      ...entry,
      key: `s${index}`,
      index,
      choice: `${entry.object}.${entry.field}`,
      needsField: entry.fn !== 'count',
      pickerKind: PICKER_KINDS[entry.fn] || 'sum',
      filterJson: entry.filter
        ? typeof entry.filter === 'string'
          ? entry.filter
          : JSON.stringify(entry.filter)
        : '',
      removeLabel: format(helpText('Reporting', 'Reporting_RemoveNamed'), entry.label)
    }));
  }

  get canAddSummary() {
    return this.hasChildren && this.report.summaries.length < MAX_SUMMARIES;
  }

  get viewOptions() {
    const options = [{ value: 'table', label: helpText('Reporting', 'Reporting_View_Table') }];
    if (this.isTotals) {
      options.push(
        { value: 'bar', label: helpText('Reporting', 'Reporting_View_Bar') },
        { value: 'column', label: helpText('Reporting', 'Reporting_View_Column') },
        { value: 'line', label: helpText('Reporting', 'Reporting_View_Line') },
        { value: 'donut', label: helpText('Reporting', 'Reporting_View_Donut') },
        { value: 'metric', label: helpText('Reporting', 'Reporting_View_Metric') }
      );
    }
    return options;
  }

  get canStack() {
    return (
      this.isTotals &&
      this.report.groups.length === 2 &&
      ['bar', 'column'].includes(this.report.view.type)
    );
  }

  get sortOptions() {
    const options = [{ value: '', label: helpText('Reporting', 'Reporting_Sort_Default') }];
    if (this.isTotals) {
      this.report.groups.forEach((group, index) =>
        options.push({ value: `g${index}`, label: group.label })
      );
      this.report.measures.forEach((measure, index) =>
        options.push({ value: `m${index}`, label: measure.label })
      );
    } else {
      this.report.columns.forEach((column) =>
        options.push({ value: column.path, label: column.label })
      );
    }
    return options;
  }

  get sortBy() {
    return this.report.sort ? this.report.sort.by : '';
  }

  get sortDirection() {
    return this.report.sort ? this.report.sort.direction : 'asc';
  }

  get directionOptions() {
    return [
      { value: 'asc', label: helpText('Reporting', 'Reporting_Sort_Asc') },
      { value: 'desc', label: helpText('Reporting', 'Reporting_Sort_Desc') }
    ];
  }

  get limitLabel() {
    return this.isTotals
      ? helpText('Reporting', 'Reporting_Builder_TopGroups')
      : helpText('Reporting', 'Reporting_Builder_RowLimit');
  }

  get maxRows() {
    return MAX_ROWS;
  }

  get runDisabled() {
    return !this.hasObject || reportProblems(this.report).length > 0;
  }

  get ownerText() {
    return this.saved && !this.saved.mine
      ? format(helpText('Reporting', 'Reporting_Builder_Owner'), this.saved.ownerName)
      : '';
  }

  get labels() {
    return {
      back: helpText('Reporting', 'Reporting_Back'),
      title: helpText('Reporting', 'Reporting_Builder_Title'),
      object: helpText('Reporting', 'Reporting_Builder_Object'),
      columns: helpText('Reporting', 'Reporting_Builder_Columns'),
      columnsHelp: helpText('Reporting', 'Reporting_Builder_ColumnsHelp'),
      addColumn: helpText('Reporting', 'Reporting_Builder_AddColumn'),
      showAge: helpText('Reporting', 'Reporting_Builder_ShowAge'),
      filters: helpText('Reporting', 'Reporting_Builder_Filters'),
      dateRange: helpText('Reporting', 'Reporting_Builder_DateRange'),
      dateField: helpText('Reporting', 'Reporting_Builder_DateField'),
      range: helpText('Reporting', 'Reporting_Builder_Range'),
      related: helpText('Reporting', 'Reporting_Builder_Related'),
      relatedHelp: helpText('Reporting', 'Reporting_Builder_RelatedHelp'),
      relatedKind: helpText('Reporting', 'Reporting_Builder_RelatedKind'),
      relatedHas: helpText('Reporting', 'Reporting_Builder_RelatedHas'),
      addRelated: helpText('Reporting', 'Reporting_Builder_AddRelated'),
      totals: helpText('Reporting', 'Reporting_Builder_Totals'),
      totalsHelp: helpText('Reporting', 'Reporting_Builder_TotalsHelp'),
      addGroup: helpText('Reporting', 'Reporting_Builder_AddGroup'),
      bucket: helpText('Reporting', 'Reporting_Builder_Bucket'),
      addMeasure: helpText('Reporting', 'Reporting_Builder_AddMeasure'),
      fn: helpText('Reporting', 'Reporting_Builder_Function'),
      field: helpText('Reporting', 'Reporting_Builder_Field'),
      measureLabel: helpText('Reporting', 'Reporting_Builder_MeasureLabel'),
      summaries: helpText('Reporting', 'Reporting_Builder_Summaries'),
      summariesHelp: helpText('Reporting', 'Reporting_Builder_SummariesHelp'),
      addSummary: helpText('Reporting', 'Reporting_Builder_AddSummary'),
      display: helpText('Reporting', 'Reporting_Builder_Display'),
      view: helpText('Reporting', 'Reporting_Builder_View'),
      stacked: helpText('Reporting', 'Reporting_Builder_Stacked'),
      sortBy: helpText('Reporting', 'Reporting_Builder_SortBy'),
      direction: helpText('Reporting', 'Reporting_Builder_Direction'),
      run: helpText('Reporting', 'Reporting_Run'),
      save: helpText('Reporting', 'Reporting_Save'),
      saveAs: helpText('Reporting', 'Reporting_SaveAs'),
      share: helpText('Reporting', 'Reporting_Share'),
      delete: helpText('Reporting', 'Reporting_Delete'),
      result: helpText('Reporting', 'Reporting_Builder_Result'),
      runFirst: helpText('Reporting', 'Reporting_Builder_RunFirst'),
      readOnly: helpText('Reporting', 'Reporting_Builder_ReadOnly'),
      done: helpText('Reporting', 'Reporting_Done')
    };
  }

  // ------------------------------------------------------------------------------------------
  // Changes
  // ------------------------------------------------------------------------------------------

  handleTitle(event) {
    this.change({ title: event.detail.value || '' });
  }

  handleObject(event) {
    const object = event.detail.value;
    this.report = normalizeReport({ title: this.report.title, object, view: { type: 'table' } });
    this.preview = undefined;
    this.loadChildren();
  }

  handleAddColumn(event) {
    const field = event.detail;
    if (!this.report.columns.some((column) => column.path === field.path)) {
      this.change({
        columns: [
          ...this.report.columns,
          { path: field.path, label: field.label, type: field.type }
        ]
      });
    }
    event.target.clear();
  }

  handleColumnMove(event) {
    const index = Number(event.currentTarget.dataset.index);
    const step = event.currentTarget.dataset.step === 'up' ? -1 : 1;
    this.change({ columns: moved(this.report.columns, index, index + step) });
  }

  handleColumnRemove(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.change({ columns: this.report.columns.filter((unused, position) => position !== index) });
  }

  handleColumnAge(event) {
    const index = Number(event.target.dataset.index);
    const checked = event.target.checked;
    this.change({
      columns: this.report.columns.map((column, position) => {
        if (position !== index) {
          return column;
        }
        const copy = { ...column };
        delete copy.show;
        return checked ? { ...copy, show: 'age' } : copy;
      })
    });
  }

  handleFilter(event) {
    this.change({ filter: event.detail.value || '' });
  }

  handleDateField(event) {
    const field = event.detail;
    const current = this.report.dateRange || { range: 'THIS_YEAR' };
    this.change({
      dateRange: { ...current, field: field.path, type: field.type, label: field.label }
    });
  }

  handleDateRange(event) {
    const value = event.detail.value;
    const current = this.report.dateRange;
    if (!value) {
      this.change({ dateRange: null });
      return;
    }
    const field =
      current && current.field
        ? { field: current.field, type: current.type, label: current.label }
        : {};
    this.change({ dateRange: { ...value, ...field } });
  }

  handleAddRelated() {
    const child = this.children[0];
    this.change({
      related: [
        ...this.report.related,
        { object: child.object, field: child.field, label: child.objectLabel, has: true }
      ]
    });
  }

  handleRelatedChild(event) {
    const index = Number(event.target.dataset.index);
    const [object, field] = event.detail.value.split('.');
    const child = this.children.find((entry) => entry.object === object && entry.field === field);
    this.change({
      related: replaceAt(this.report.related, index, (entry) => ({
        object,
        field,
        label: child ? child.objectLabel : object,
        has: entry.has
      }))
    });
  }

  handleRelatedHas(event) {
    const index = Number(event.target.dataset.index);
    const has = event.detail.value === 'has';
    this.change({
      related: replaceAt(this.report.related, index, (entry) => ({ ...entry, has }))
    });
  }

  handleRelatedFilter(event) {
    const index = Number(event.target.dataset.index);
    const filter = event.detail.value || '';
    this.change({
      related: this.report.related.map((entry, position) => {
        if (position !== index) {
          return entry;
        }
        const copy = { ...entry };
        delete copy.filter;
        return filter ? { ...copy, filter } : copy;
      })
    });
  }

  handleRelatedRemove(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.change({ related: this.report.related.filter((unused, position) => position !== index) });
  }

  handleAddGroup(event) {
    const field = event.detail;
    const group = {
      field: field.path,
      label: field.label,
      type: field.type,
      ...(DATE_TYPES.has(field.type) ? { bucket: 'month' } : {}),
      ...(field.labelPath ? { labelPath: field.labelPath } : {}),
      ...(field.picklist && Object.keys(field.picklist).length ? { picklist: field.picklist } : {})
    };
    const measures = this.report.measures.length
      ? this.report.measures
      : [{ fn: 'count', label: helpText('Reporting', 'Reporting_Fn_RecordCount') }];
    const view =
      this.report.view.type === 'table' || this.report.view.type === 'metric'
        ? { type: 'bar' }
        : this.report.view;
    this.change({ groups: [...this.report.groups, group], measures, view, sort: null });
    event.target.clear();
  }

  handleBucket(event) {
    const index = Number(event.target.dataset.index);
    const bucket = event.detail.value;
    this.change({
      groups: replaceAt(this.report.groups, index, (group) => ({ ...group, bucket }))
    });
  }

  handleGroupRemove(event) {
    const index = Number(event.currentTarget.dataset.index);
    const groups = this.report.groups.filter((unused, position) => position !== index);
    const view =
      groups.length === 0 && this.report.view.type !== 'table'
        ? { type: 'metric' }
        : this.report.view;
    this.change({ groups, view, sort: null });
  }

  handleAddMeasure() {
    const view = this.isTotals ? this.report.view : { type: 'metric' };
    this.change({
      measures: [
        ...this.report.measures,
        { fn: 'count', label: helpText('Reporting', 'Reporting_Fn_RecordCount') }
      ],
      view,
      sort: null
    });
  }

  handleMeasureFn(event) {
    const index = Number(event.target.dataset.index);
    const fn = event.detail.value;
    const label = this.functionOptions.find((option) => option.value === fn).label;
    this.change({
      measures: replaceAt(this.report.measures, index, () => ({
        fn,
        label: fn === 'count' ? helpText('Reporting', 'Reporting_Fn_RecordCount') : label
      }))
    });
  }

  handleMeasureField(event) {
    const index = Number(event.target.dataset.index);
    const field = event.detail;
    this.change({
      measures: this.report.measures.map((measure, position) => {
        if (position !== index) {
          return measure;
        }
        const fnLabel = this.functionOptions.find((option) => option.value === measure.fn).label;
        return {
          ...measure,
          path: field.path,
          type: field.type,
          label: format(helpText('Reporting', 'Reporting_MeasureName'), fnLabel, field.label)
        };
      })
    });
  }

  handleMeasureLabel(event) {
    const index = Number(event.target.dataset.index);
    const label = event.detail.value || '';
    this.change({
      measures: replaceAt(this.report.measures, index, (measure) => ({ ...measure, label }))
    });
  }

  handleMeasureRemove(event) {
    const index = Number(event.currentTarget.dataset.index);
    const measures = this.report.measures.filter((unused, position) => position !== index);
    const patch = { measures, sort: null };
    if (measures.length === 0) {
      patch.groups = [];
      patch.view = { type: 'table' };
    }
    this.change(patch);
  }

  handleAddSummary() {
    const child = this.children[0];
    this.change({
      summaries: [
        ...this.report.summaries,
        {
          object: child.object,
          field: child.field,
          fn: 'count',
          label: format(helpText('Reporting', 'Reporting_SummaryCount'), child.objectLabel)
        }
      ]
    });
  }

  handleSummaryChild(event) {
    const index = Number(event.target.dataset.index);
    const [object, field] = event.detail.value.split('.');
    const child = this.children.find((entry) => entry.object === object && entry.field === field);
    this.change({
      summaries: replaceAt(this.report.summaries, index, () => ({
        object,
        field,
        fn: 'count',
        label: format(
          helpText('Reporting', 'Reporting_SummaryCount'),
          child ? child.objectLabel : object
        )
      }))
    });
  }

  handleSummaryFn(event) {
    const index = Number(event.target.dataset.index);
    const fn = event.detail.value;
    this.change({
      summaries: this.report.summaries.map((entry, position) => {
        if (position !== index) {
          return entry;
        }
        const copy = { ...entry, fn };
        delete copy.path;
        return copy;
      })
    });
  }

  handleSummaryField(event) {
    const index = Number(event.target.dataset.index);
    const field = event.detail;
    this.change({
      summaries: this.report.summaries.map((entry, position) => {
        if (position !== index) {
          return entry;
        }
        const fnLabel = this.functionOptions.find((option) => option.value === entry.fn).label;
        return {
          ...entry,
          path: field.path,
          type: field.type,
          label: format(helpText('Reporting', 'Reporting_MeasureName'), fnLabel, field.label)
        };
      })
    });
  }

  handleSummaryFilter(event) {
    const index = Number(event.target.dataset.index);
    const filter = event.detail.value || '';
    this.change({
      summaries: this.report.summaries.map((entry, position) => {
        if (position !== index) {
          return entry;
        }
        const copy = { ...entry };
        delete copy.filter;
        return filter ? { ...copy, filter } : copy;
      })
    });
  }

  handleSummaryLabel(event) {
    const index = Number(event.target.dataset.index);
    const label = event.detail.value || '';
    this.change({
      summaries: replaceAt(this.report.summaries, index, (entry) => ({ ...entry, label }))
    });
  }

  handleSummaryRemove(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.change({
      summaries: this.report.summaries.filter((unused, position) => position !== index)
    });
  }

  handleView(event) {
    this.change({ view: { type: event.detail.value, stacked: this.report.view.stacked } });
  }

  handleStacked(event) {
    this.change({ view: { ...this.report.view, stacked: event.target.checked } });
  }

  handleSortBy(event) {
    const by = event.detail.value;
    this.change({ sort: by ? { by, direction: this.sortDirection } : null });
  }

  handleDirection(event) {
    if (this.report.sort) {
      this.change({ sort: { ...this.report.sort, direction: event.detail.value } });
    }
  }

  handleLimit(event) {
    this.change({ limit: event.detail.value });
  }

  // ------------------------------------------------------------------------------------------
  // Run, save, share, delete
  // ------------------------------------------------------------------------------------------

  handleRun() {
    // A new object each time, so the view runs again even when nothing changed.
    this.preview = normalizeReport(this.report);
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent('close'));
  }

  handleDone() {
    this.dispatchEvent(
      new CustomEvent('done', { detail: { report: normalizeReport(this.report) } })
    );
  }

  handleSave() {
    return this.write(this.saved ? this.saved.id : null);
  }

  handleSaveAs() {
    return this.write(null);
  }

  async write(documentId) {
    const title = (this.report.title || '').trim();
    if (!title) {
      this.error = helpText('Reporting', 'Reporting_Error_Title');
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const definition = {
        ...this.report,
        ...(documentId && this.sharing ? { sharing: this.sharing } : {})
      };
      const row = await save({
        kind: REPORT_KIND,
        documentId,
        title,
        definitionJson: JSON.stringify(definition)
      });
      this.saved = row;
      this.sharing = documentId ? this.sharing : null;
      this.notice = format(helpText('Reporting', 'Reporting_Saved'), row.title);
      this.dispatchEvent(new CustomEvent('saved', { detail: { row } }));
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    } finally {
      this.busy = false;
    }
  }

  handleShare() {
    this.sharingOpen = true;
  }

  handleShareCancel() {
    this.sharingOpen = false;
  }

  async handleShareSave(event) {
    this.busy = true;
    this.error = '';
    try {
      const sharing = event.detail.sharing;
      const row = await share({ documentId: this.saved.id, sharingJson: JSON.stringify(sharing) });
      this.saved = row;
      this.sharing = sharing;
      this.sharingOpen = false;
      this.notice = helpText('Reporting', 'Reporting_Shared');
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    } finally {
      this.busy = false;
    }
  }

  async handleDelete() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: helpText('Reporting', 'Reporting_Delete_Heading'),
      message: format(helpText('Reporting', 'Reporting_Delete_Body'), this.saved.title),
      confirmLabel: helpText('Reporting', 'Reporting_Delete'),
      cancelLabel: helpText('Reporting', 'Reporting_Cancel'),
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return;
    }
    this.busy = true;
    try {
      await remove({ documentId: this.saved.id });
      this.dispatchEvent(new CustomEvent('saved', { detail: { removed: this.saved.id } }));
      this.dispatchEvent(new CustomEvent('close'));
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    } finally {
      this.busy = false;
    }
  }
}
