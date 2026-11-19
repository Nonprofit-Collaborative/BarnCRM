import { LightningElement, api } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import runReport from '@salesforce/apex/ReportingQueryService.run';
import load from '@salesforce/apex/ReportingLibrary.load';
import save from '@salesforce/apex/ReportingLibrary.save';
import share from '@salesforce/apex/ReportingLibrary.share';
import remove from '@salesforce/apex/ReportingLibrary.remove';
import { helpText } from 'c/barnHelpText';
import { format } from 'c/barnFormat';
import { messageFrom } from 'c/findCsv';
import {
  MAX_FILTERS,
  MAX_WIDGETS,
  applyFilters,
  moved,
  newDashboard,
  newReport,
  nextWidgetKey,
  normalizeDashboard,
  normalizeReport,
  replaceAt,
  runRequest
} from 'c/reportingModel';

export const DASHBOARD_KIND = 'barndash';
const RECORD_CHOICES = 50;
const SEARCH_DELAY = 300;

/** Grid widths per widget size: phone full width; small a third and medium a half on desktop. */
const SIZE_CLASSES = {
  small: 'slds-col slds-size_1-of-1 slds-medium-size_1-of-2 slds-large-size_1-of-3',
  medium: 'slds-col slds-size_1-of-1 slds-large-size_1-of-2',
  large: 'slds-col slds-size_1-of-1'
};

/**
 * One Advanced Reporting dashboard: report widgets in a grid under one filter bar. A date
 * filter replaces each bound widget's date range; a record filter (a fund, a board, a job)
 * narrows each bound widget, through related records where the binding says so. Each widget
 * runs as the person, so everyone sees only the records they may read. Edit adds, changes,
 * sizes, orders and removes widgets and filters and binds each filter to each widget's field.
 * Save, Save As, Share and Delete keep it as a file the person owns (ReportingLibrary).
 */
export default class ReportingDashboard extends LightningElement {
  /** What the person may do: `{ canSave, canExport }`. */
  @api context = {};

  /** The objects the person may report on: `[{ value, label }]`. */
  @api objects = [];

  /** Saved reports the person can open, for Add Widget: `[{ id, title }]`. */
  @api savedReports = [];

  dashboard = newDashboard();
  saved = null;
  sharing = null;
  values = {};
  cards = [];
  editing = false;
  editIndex = null;
  editReport = null;
  sharingOpen = false;
  busy = false;
  error = '';
  notice = '';
  choices = {};
  searches = {};
  timers = {};
  pickedReport = '';
  newFilterKind = 'date';
  newFilterObject = '';
  newFilterLabel = '';
  _documentId;

  /** A saved dashboard to open. */
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

  /** A shipped template or a new dashboard's starting definition (not saved). */
  @api
  get definition() {
    return this.dashboard;
  }
  set definition(value) {
    if (value) {
      this.saved = null;
      this.sharing = null;
      this.dashboard = normalizeDashboard(value);
      this.editing = this.dashboard.widgets.length === 0;
      this.values = {};
      this.arrange();
      this.loadAllChoices();
    }
  }

  disconnectedCallback() {
    Object.values(this.timers).forEach((timer) => clearTimeout(timer));
  }

  async open(documentId) {
    this.busy = true;
    this.error = '';
    try {
      const row = await load({ documentId });
      const definition = JSON.parse(row.definition);
      this.saved = row;
      this.sharing = definition.sharing || null;
      this.dashboard = normalizeDashboard({ ...definition, title: row.title });
      this.values = {};
      this.arrange();
      this.loadAllChoices();
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    } finally {
      this.busy = false;
    }
  }

  /** Works out each widget's report with the filter values; widgets run when theirs changes. */
  arrange() {
    const previous = new Map(this.cards.map((card) => [card.key, card]));
    const last = this.dashboard.widgets.length - 1;
    this.cards = this.dashboard.widgets.map((widget, index) => {
      const applied = applyFilters(widget, this.dashboard.filters, this.values);
      const before = previous.get(widget.key);
      const same = before && JSON.stringify(before.report) === JSON.stringify(applied.report);
      return {
        key: widget.key,
        index,
        title: widget.title,
        size: widget.size,
        css: SIZE_CLASSES[widget.size],
        report: same ? before.report : applied.report,
        unfiltered: applied.unfiltered,
        first: index === 0,
        last: index === last,
        bindings: this.bindingRows(widget),
        editLabel: format(helpText('Reporting', 'Reporting_Widget_EditNamed'), widget.title),
        upLabel: format(helpText('Reporting', 'Reporting_MoveUp'), widget.title),
        downLabel: format(helpText('Reporting', 'Reporting_MoveDown'), widget.title),
        removeLabel: format(helpText('Reporting', 'Reporting_RemoveNamed'), widget.title)
      };
    });
  }

  bindingRows(widget) {
    return this.dashboard.filters.map((filter) => {
      const binding = widget.bindings[filter.key];
      return {
        key: `${widget.key}-${filter.key}`,
        filterKey: filter.key,
        widgetKey: widget.key,
        object: widget.report.object,
        kind: filter.kind === 'date' ? 'date' : 'reference',
        label: format(helpText('Reporting', 'Reporting_Widget_BindTo'), filter.label),
        value: binding && !binding.related ? binding.field : '',
        throughText:
          binding && binding.related
            ? format(
                helpText('Reporting', 'Reporting_Widget_Through'),
                binding.related.object,
                binding.field
              )
            : '',
        bound: !!binding,
        clearLabel: format(helpText('Reporting', 'Reporting_Widget_Unbind'), filter.label)
      };
    });
  }

  // ------------------------------------------------------------------------------------------
  // Read-outs
  // ------------------------------------------------------------------------------------------

  get heading() {
    return this.dashboard.title || helpText('Reporting', 'Reporting_Dash_New');
  }

  get readOnly() {
    return !!this.saved && !this.saved.canEdit;
  }

  get canEditLayout() {
    return !this.readOnly;
  }

  get canSave() {
    return !!(this.context && this.context.canSave) && !this.readOnly;
  }

  get canSaveAs() {
    return !!(this.context && this.context.canSave) && !!this.saved;
  }

  get isOwner() {
    return !!this.saved && this.saved.mine;
  }

  get canExport() {
    return !!(this.context && this.context.canExport);
  }

  get ownerText() {
    return this.saved && !this.saved.mine
      ? format(helpText('Reporting', 'Reporting_Builder_Owner'), this.saved.ownerName)
      : '';
  }

  get hasWidgets() {
    return this.cards.length > 0;
  }

  get isWidgetEditor() {
    return this.editIndex !== null;
  }

  get editToggleLabel() {
    return this.editing
      ? helpText('Reporting', 'Reporting_Dash_DoneEditing')
      : helpText('Reporting', 'Reporting_Dash_Edit');
  }

  get filterRows() {
    return this.dashboard.filters.map((filter) => {
      const value = this.values[filter.key];
      const search = this.searches[filter.key] || '';
      return {
        ...filter,
        isDate: filter.kind === 'date',
        dateValue: filter.kind === 'date' ? value || null : null,
        recordValue: filter.kind === 'record' ? value || '' : '',
        search,
        searchLabel: format(helpText('Reporting', 'Reporting_Dash_FindRecord'), filter.label),
        options: [
          { value: '', label: helpText('Reporting', 'Reporting_Dash_All') },
          ...(this.choices[filter.key] || [])
        ],
        removeLabel: format(helpText('Reporting', 'Reporting_RemoveNamed'), filter.label)
      };
    });
  }

  get hasFilters() {
    return this.dashboard.filters.length > 0;
  }

  get canAddFilter() {
    return this.dashboard.filters.length < MAX_FILTERS;
  }

  get canAddWidget() {
    return this.dashboard.widgets.length < MAX_WIDGETS;
  }

  get sizeOptions() {
    return [
      { value: 'small', label: helpText('Reporting', 'Reporting_Size_Small') },
      { value: 'medium', label: helpText('Reporting', 'Reporting_Size_Medium') },
      { value: 'large', label: helpText('Reporting', 'Reporting_Size_Large') }
    ];
  }

  get filterKindOptions() {
    return [
      { value: 'date', label: helpText('Reporting', 'Reporting_Dash_DateFilter') },
      { value: 'record', label: helpText('Reporting', 'Reporting_Dash_RecordFilter') }
    ];
  }

  get isRecordFilter() {
    return this.newFilterKind === 'record';
  }

  get addFilterDisabled() {
    return (
      !this.newFilterLabel.trim() || (this.newFilterKind === 'record' && !this.newFilterObject)
    );
  }

  get reportOptions() {
    return (this.savedReports || []).map((row) => ({ value: row.id, label: row.title }));
  }

  get hasSavedReports() {
    return this.reportOptions.length > 0;
  }

  get labels() {
    return {
      back: helpText('Reporting', 'Reporting_Back'),
      title: helpText('Reporting', 'Reporting_Dash_Title'),
      description: helpText('Reporting', 'Reporting_Dash_Description'),
      filters: helpText('Reporting', 'Reporting_Dash_Filters'),
      refresh: helpText('Reporting', 'Reporting_Dash_Refresh'),
      save: helpText('Reporting', 'Reporting_Save'),
      saveAs: helpText('Reporting', 'Reporting_SaveAs'),
      share: helpText('Reporting', 'Reporting_Share'),
      delete: helpText('Reporting', 'Reporting_Delete'),
      empty: helpText('Reporting', 'Reporting_Dash_Empty'),
      emptyHelp: helpText('Reporting', 'Reporting_Dash_EmptyHelp'),
      size: helpText('Reporting', 'Reporting_Widget_Size'),
      widgetTitle: helpText('Reporting', 'Reporting_Widget_Title'),
      addWidget: helpText('Reporting', 'Reporting_Dash_AddWidget'),
      fromSaved: helpText('Reporting', 'Reporting_Dash_FromSaved'),
      addSaved: helpText('Reporting', 'Reporting_Dash_AddSaved'),
      newReport: helpText('Reporting', 'Reporting_Dash_NewReport'),
      addFilter: helpText('Reporting', 'Reporting_Dash_AddFilter'),
      filterKind: helpText('Reporting', 'Reporting_Dash_FilterKind'),
      filterObject: helpText('Reporting', 'Reporting_Dash_FilterObject'),
      filterLabel: helpText('Reporting', 'Reporting_Dash_FilterLabel'),
      bindings: helpText('Reporting', 'Reporting_Widget_Bindings'),
      readOnly: helpText('Reporting', 'Reporting_Dash_ReadOnly'),
      layout: helpText('Reporting', 'Reporting_Dash_Layout')
    };
  }

  // ------------------------------------------------------------------------------------------
  // Filter bar
  // ------------------------------------------------------------------------------------------

  handleDateValue(event) {
    const key = event.target.dataset.key;
    this.values = { ...this.values, [key]: event.detail.value };
    this.arrange();
  }

  handleRecordValue(event) {
    const key = event.target.dataset.key;
    this.values = { ...this.values, [key]: event.detail.value || null };
    this.arrange();
  }

  handleRecordSearch(event) {
    const key = event.target.dataset.key;
    const term = event.detail.value || '';
    this.searches = { ...this.searches, [key]: term };
    clearTimeout(this.timers[key]);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timers[key] = setTimeout(() => this.loadChoices(key), SEARCH_DELAY);
  }

  loadAllChoices() {
    this.choices = {};
    this.searches = {};
    this.dashboard.filters
      .filter((filter) => filter.kind === 'record')
      .forEach((filter) => this.loadChoices(filter.key));
  }

  /** The records a record filter offers: by name, holding the search text, as the person sees them. */
  async loadChoices(key) {
    const filter = this.dashboard.filters.find((entry) => entry.key === key);
    if (!filter || filter.kind !== 'record') {
      return;
    }
    const term = (this.searches[key] || '').trim();
    const report = normalizeReport({
      object: filter.object,
      columns: [{ path: 'Name', label: 'Name' }],
      filter: term
        ? { version: 1, conditions: [{ id: 1, field: 'Name', operator: 'contains', value: term }] }
        : '',
      sort: { by: 'Name', direction: 'asc' },
      limit: RECORD_CHOICES
    });
    try {
      const result = await runReport({ requestJson: JSON.stringify(runRequest(report)) });
      const chosen = this.values[key];
      const options = (result.rows || []).map((row) => ({
        value: row.Id,
        label: row.Name || row.Id
      }));
      const current = (this.choices[key] || []).find((option) => option.value === chosen);
      if (current && !options.some((option) => option.value === chosen)) {
        options.unshift(current);
      }
      this.choices = { ...this.choices, [key]: options };
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    }
  }

  handleRefresh() {
    this.template.querySelectorAll('c-reporting-view').forEach((view) => view.refresh());
  }

  // ------------------------------------------------------------------------------------------
  // Editing
  // ------------------------------------------------------------------------------------------

  change(patch) {
    this.dashboard = normalizeDashboard({ ...this.dashboard, ...patch });
    this.notice = '';
    this.arrange();
  }

  handleToggleEdit() {
    this.editing = !this.editing;
  }

  handleTitle(event) {
    this.change({ title: event.detail.value || '' });
  }

  handleDescription(event) {
    this.change({ description: event.detail.value || '' });
  }

  handleNewFilterKind(event) {
    this.newFilterKind = event.detail.value;
  }

  handleNewFilterObject(event) {
    this.newFilterObject = event.detail.value;
    if (!this.newFilterLabel) {
      const option = (this.objects || []).find((entry) => entry.value === this.newFilterObject);
      this.newFilterLabel = option ? option.label : '';
    }
  }

  handleNewFilterLabel(event) {
    this.newFilterLabel = event.detail.value || '';
  }

  handleAddFilter() {
    const used = new Set(this.dashboard.filters.map((filter) => filter.key));
    let index = used.size + 1;
    while (used.has(`f${index}`)) {
      index++;
    }
    const filter = {
      key: `f${index}`,
      kind: this.newFilterKind,
      label: this.newFilterLabel.trim(),
      ...(this.newFilterKind === 'record' ? { object: this.newFilterObject } : {})
    };
    this.change({ filters: [...this.dashboard.filters, filter] });
    this.newFilterLabel = '';
    this.newFilterObject = '';
    if (filter.kind === 'record') {
      this.loadChoices(filter.key);
    }
  }

  handleRemoveFilter(event) {
    const key = event.currentTarget.dataset.key;
    const values = { ...this.values };
    delete values[key];
    this.values = values;
    this.change({
      filters: this.dashboard.filters.filter((filter) => filter.key !== key),
      widgets: this.dashboard.widgets.map((widget) => {
        const bindings = { ...widget.bindings };
        delete bindings[key];
        return { ...widget, bindings };
      })
    });
  }

  updateWidget(index, patch) {
    this.change({
      widgets: replaceAt(this.dashboard.widgets, index, (widget) => ({ ...widget, ...patch }))
    });
  }

  handleWidgetTitle(event) {
    this.updateWidget(Number(event.target.dataset.index), { title: event.detail.value || '' });
  }

  handleWidgetSize(event) {
    this.updateWidget(Number(event.target.dataset.index), { size: event.detail.value });
  }

  handleWidgetMove(event) {
    const index = Number(event.currentTarget.dataset.index);
    const step = event.currentTarget.dataset.step === 'up' ? -1 : 1;
    this.change({ widgets: moved(this.dashboard.widgets, index, index + step) });
  }

  handleWidgetRemove(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.change({
      widgets: this.dashboard.widgets.filter((unused, position) => position !== index)
    });
  }

  handleBinding(event) {
    const widgetKey = event.target.dataset.widget;
    const filterKey = event.target.dataset.filter;
    const field = event.detail;
    const index = this.dashboard.widgets.findIndex((widget) => widget.key === widgetKey);
    this.change({
      widgets: replaceAt(this.dashboard.widgets, index, (widget) => ({
        ...widget,
        bindings: {
          ...widget.bindings,
          [filterKey]: {
            field: field.path,
            ...(field.type === 'datetime' || field.type === 'date' ? { type: field.type } : {})
          }
        }
      }))
    });
  }

  handleUnbind(event) {
    const widgetKey = event.currentTarget.dataset.widget;
    const filterKey = event.currentTarget.dataset.filter;
    this.change({
      widgets: this.dashboard.widgets.map((widget) => {
        if (widget.key !== widgetKey) {
          return widget;
        }
        const bindings = { ...widget.bindings };
        delete bindings[filterKey];
        return { ...widget, bindings };
      })
    });
  }

  handlePickReport(event) {
    this.pickedReport = event.detail.value;
  }

  async handleAddSaved() {
    if (!this.pickedReport) {
      return;
    }
    this.busy = true;
    try {
      const row = await load({ documentId: this.pickedReport });
      const report = normalizeReport({ ...JSON.parse(row.definition), title: row.title });
      this.addWidget(report);
      this.pickedReport = '';
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    } finally {
      this.busy = false;
    }
  }

  addWidget(report) {
    const widget = {
      key: nextWidgetKey(this.dashboard),
      title: report.title,
      size: 'medium',
      report,
      bindings: {}
    };
    this.change({ widgets: [...this.dashboard.widgets, widget] });
  }

  handleNewWidget() {
    this.editIndex = -1;
    this.editReport = newReport('');
  }

  handleEditWidget(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.editIndex = index;
    this.editReport = this.dashboard.widgets[index].report;
  }

  handleWidgetDone(event) {
    const report = event.detail.report;
    if (this.editIndex === -1) {
      this.addWidget(report);
    } else {
      this.updateWidget(this.editIndex, {
        report,
        ...(report.title ? { title: report.title } : {})
      });
    }
    this.editIndex = null;
    this.editReport = null;
  }

  handleWidgetCancel() {
    this.editIndex = null;
    this.editReport = null;
  }

  // ------------------------------------------------------------------------------------------
  // Save, share, delete
  // ------------------------------------------------------------------------------------------

  handleBack() {
    this.dispatchEvent(new CustomEvent('close'));
  }

  handleSave() {
    return this.write(this.saved && this.saved.canEdit ? this.saved.id : null);
  }

  handleSaveAs() {
    return this.write(null);
  }

  async write(documentId) {
    const title = (this.dashboard.title || '').trim();
    if (!title) {
      this.error = helpText('Reporting', 'Reporting_Error_Title');
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const definition = {
        ...this.dashboard,
        ...(documentId && this.sharing ? { sharing: this.sharing } : {})
      };
      const row = await save({
        kind: DASHBOARD_KIND,
        documentId,
        title,
        definitionJson: JSON.stringify(definition)
      });
      this.saved = row;
      this.sharing = documentId ? this.sharing : null;
      this.editing = false;
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
