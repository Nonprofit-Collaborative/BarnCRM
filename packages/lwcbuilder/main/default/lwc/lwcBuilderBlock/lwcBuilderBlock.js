import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import loadRecords from '@salesforce/apex/LwcBuilderController.loadRecords';
import loadChart from '@salesforce/apex/LwcBuilderController.loadChart';
import { messageFrom } from 'c/findCsv';
import { helpText } from 'c/barnHelpText';
import { chartView, isSafeImageUrl } from 'c/lwcBuilderModel';

// lightning-datatable column types for the field types Apex reports; anything else is text.
const COLUMN_TYPES = {
  currency: 'currency',
  percent: 'percent',
  double: 'number',
  integer: 'number',
  long: 'number',
  date: 'date-local',
  datetime: 'date',
  boolean: 'boolean',
  email: 'email',
  phone: 'phone',
  url: 'url'
};

/**
 * One block of a built component (LB-03, LB-04, LB-07): the page record's fields through
 * Lightning Data Service, a related or record list and a report chart through
 * LwcBuilderController (user mode; the chart laid out by c/lwcBuilderModel), rich text, an image, or a button that opens a quick action or runs a flow. What the
 * viewer may not read or run, the platform refuses; this block only draws.
 */
export default class LwcBuilderBlock extends NavigationMixin(LightningElement) {
  @api recordId;
  @api objectApiName;

  current = {};
  signature;
  columns = [];
  rows = [];
  chart;
  errorMessage;
  isLoading = false;
  showFlow = false;
  showTable = false;

  @api
  get block() {
    return this.current;
  }
  set block(value) {
    this.current = value || {};
    const signature = JSON.stringify(this.current);
    if (signature !== this.signature) {
      this.signature = signature;
      this.load();
    }
  }

  get isFields() {
    return this.current.type === 'fields';
  }
  get isList() {
    return this.current.type === 'relatedList' || this.current.type === 'recordList';
  }
  get isChart() {
    return this.current.type === 'chart';
  }
  get isText() {
    return this.current.type === 'text';
  }
  get isImage() {
    return this.current.type === 'image' && isSafeImageUrl(this.current.url);
  }
  get isAction() {
    return this.current.type === 'action';
  }

  get fieldNames() {
    return (this.current.fields || []).map((name) => ({ name, key: name }));
  }
  get hasRecord() {
    return Boolean(this.recordId && this.objectApiName);
  }
  get fieldCss() {
    return this.current.columns === 2
      ? 'slds-col slds-size_1-of-1 slds-medium-size_1-of-2'
      : 'slds-col slds-size_1-of-1';
  }
  get hasRows() {
    return this.rows.length > 0;
  }
  get showNoRows() {
    return !this.errorMessage && !this.isLoading;
  }
  get noRowsText() {
    return helpText('LwcBuilder', 'LwcBuilder_Block_NoRows');
  }
  get noRecordText() {
    return helpText('LwcBuilder', 'LwcBuilder_Block_NeedsRecord');
  }
  get tableToggleLabel() {
    return this.showTable
      ? helpText('LwcBuilder', 'LwcBuilder_Chart_ShowChart')
      : helpText('LwcBuilder', 'LwcBuilder_Chart_ShowTable');
  }
  // The table is always there for screen readers; Show Table makes it visible too.
  get tableCss() {
    return this.showTable
      ? 'slds-table slds-table_bordered slds-table_cell-buffer'
      : 'slds-assistive-text';
  }

  get showChart() {
    return !this.showTable;
  }

  toggleTable() {
    this.showTable = !this.showTable;
  }

  async load() {
    this.errorMessage = undefined;
    this.showFlow = false;
    if (this.isList) {
      await this.loadList();
    } else if (this.isChart) {
      await this.loadBars();
    }
  }

  async loadList() {
    const block = this.current;
    if (block.type === 'relatedList' && !this.recordId) {
      this.rows = [];
      return;
    }
    this.isLoading = true;
    try {
      const result = await loadRecords({
        requestJson: JSON.stringify({
          object: block.object,
          fields: block.fields,
          parentField: block.type === 'relatedList' ? block.parentField : '',
          recordId: this.recordId,
          filterField: block.filterField,
          filterOperator: block.filterOperator,
          filterValue: block.filterValue,
          orderBy: block.orderBy,
          direction: block.direction
        })
      });
      this.columns = (result.columns || []).map((column) => {
        if (column.isName) {
          return {
            label: column.label,
            fieldName: 'recordUrl',
            type: 'url',
            typeAttributes: { label: { fieldName: column.fieldName } }
          };
        }
        return {
          label: column.label,
          fieldName: column.fieldName,
          type: COLUMN_TYPES[column.type] || 'text'
        };
      });
      this.rows = (result.rows || []).map((row) => ({ ...row, recordUrl: `/${row.Id}` }));
    } catch (error) {
      this.rows = [];
      this.errorMessage = messageFrom(error, helpText('LwcBuilder', 'LwcBuilder_Error_Generic'));
    } finally {
      this.isLoading = false;
    }
  }

  async loadBars() {
    this.isLoading = true;
    try {
      const result = await loadChart({ reportName: this.current.report });
      this.chart = chartView(result, this.current.display);
    } catch (error) {
      this.chart = undefined;
      this.errorMessage = messageFrom(error, helpText('LwcBuilder', 'LwcBuilder_Error_Generic'));
    } finally {
      this.isLoading = false;
    }
  }

  get flowInputs() {
    return this.current.passRecordId && this.recordId
      ? [{ name: 'recordId', type: 'String', value: this.recordId }]
      : [];
  }

  handleAction() {
    const block = this.current;
    if (block.kind === 'quickAction') {
      const state = this.recordId
        ? { recordId: this.recordId, objectApiName: this.objectApiName, context: 'RECORD_DETAIL' }
        : {};
      this[NavigationMixin.Navigate]({
        type: 'standard__quickAction',
        attributes: { apiName: block.actionName },
        state
      });
      return;
    }
    this.showFlow = !this.showFlow;
  }

  handleFlowStatus(event) {
    if (
      event.detail &&
      (event.detail.status === 'FINISHED' || event.detail.status === 'FINISHED_SCREEN')
    ) {
      this.showFlow = false;
    }
  }
}
