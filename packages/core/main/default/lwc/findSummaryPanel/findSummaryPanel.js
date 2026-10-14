import { LightningElement, api } from 'lwc';
import summarize from '@salesforce/apex/FindController.summarize';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import { messageFrom } from 'c/findCsv';
import TIME_ZONE from '@salesforce/i18n/timeZone';

import SUMMARIZE from '@salesforce/label/c.Core_Find_Summarize';
import SUMMARY_FUNCTION from '@salesforce/label/c.Core_Find_SummaryFunction';
import COUNT from '@salesforce/label/c.Core_Find_Count';
import SUM from '@salesforce/label/c.Core_Find_Sum';
import MIN from '@salesforce/label/c.Core_Find_Min';
import MAX from '@salesforce/label/c.Core_Find_Max';
import SUMMARY_FIELD from '@salesforce/label/c.Core_Find_SummaryField';
import GROUP_BY from '@salesforce/label/c.Core_Find_GroupBy';
import NO_GROUP from '@salesforce/label/c.Core_Find_NoGroup';
import GROUP from '@salesforce/label/c.Core_Find_Group';
import RESULT from '@salesforce/label/c.Core_Find_Result';
import BLANK from '@salesforce/label/c.Core_Find_Blank';
import CAPPED from '@salesforce/label/c.Core_Find_SummaryCapped';
import LOADING from '@salesforce/label/c.Core_Find_Loading';

const NUMBER_TYPES = new Set(['double', 'currency', 'percent', 'integer', 'long']);
const DATE_TYPES = new Set(['date', 'datetime']);
const NOT_GROUPABLE = new Set(['textarea', 'datetime', 'multipicklist', 'address', 'location']);

/**
 * Find's summary (C-36, admin guide find.md section 7.3, canonical model R-SQ9): count, total,
 * lowest or highest of the query's records, grouped by a field. The server builds and checks
 * the aggregate query from the document; this panel only chooses the function and fields.
 * The choice is reported in a `change` event so a saved query keeps it.
 */
export default class FindSummaryPanel extends LightningElement {
  @api objectApiName;
  /** The query document as Find has it now, without the summary. */
  @api queryJson;

  labels = {
    summarize: SUMMARIZE,
    summaryFunction: SUMMARY_FUNCTION,
    summaryField: SUMMARY_FIELD,
    groupBy: GROUP_BY,
    loading: LOADING
  };

  fn = 'count';
  field = '';
  groupBy = '';
  fields = [];
  lines;
  capped = false;
  busy = false;
  errorMessage;
  loadedFor;

  /** A summary the query already holds (a saved query, or typed text). */
  @api
  get aggregate() {
    return this.currentAggregate();
  }
  set aggregate(value) {
    if (value) {
      this.fn = String(value.function || 'count').toLowerCase();
      this.field = value.field || '';
      this.groupBy = value.groupBy || '';
    }
  }

  connectedCallback() {
    this.loadFields();
  }

  renderedCallback() {
    if (this.objectApiName !== this.loadedFor) {
      this.loadFields();
    }
  }

  async loadFields() {
    if (!this.objectApiName || this.loadedFor === this.objectApiName) {
      return;
    }
    this.loadedFor = this.objectApiName;
    try {
      const info = await getObjectInfo({ objectApiName: this.objectApiName });
      this.fields = info.fields;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get functionOptions() {
    return [
      { label: COUNT, value: 'count' },
      { label: SUM, value: 'sum' },
      { label: MIN, value: 'min' },
      { label: MAX, value: 'max' }
    ];
  }

  get needsField() {
    return this.fn !== 'count';
  }

  get fieldOptions() {
    return this.fields
      .filter(
        (field) =>
          field.aggregatable !== false &&
          (NUMBER_TYPES.has(field.dataType) ||
            (this.fn !== 'sum' && DATE_TYPES.has(field.dataType)))
      )
      .map((field) => ({ label: field.label, value: field.apiName }));
  }

  get groupOptions() {
    return [
      { label: NO_GROUP, value: '' },
      ...this.fields
        // The describe says which fields SOQL groups by (not currency, number or long text);
        // the type list stays for a field described without that answer.
        .filter(
          (field) =>
            field.groupable !== false && field.filterable && !NOT_GROUPABLE.has(field.dataType)
        )
        .map((field) => ({ label: field.label, value: field.apiName }))
    ];
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasLines() {
    return !!this.lines;
  }

  get cappedNote() {
    return CAPPED.split('{0}').join('2,000');
  }

  get summarizeDisabled() {
    return this.busy || !this.queryJson || (this.needsField && !this.field);
  }

  get columns() {
    const measured = this.fields.find((field) => field.apiName === this.field);
    const type = this.fn === 'count' || !measured ? 'number' : measured.dataType;
    const result = { label: RESULT, fieldName: 'value', type: 'text' };
    if (NUMBER_TYPES.has(type) || this.fn === 'count') {
      result.type = 'number';
    } else if (type === 'date') {
      // The lowest or highest date, shown as a date like the grid shows it.
      result.type = 'date-local';
    } else if (type === 'datetime') {
      result.type = 'date';
      result.typeAttributes = {
        year: 'numeric',
        month: 'short',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        timeZone: TIME_ZONE
      };
    }
    return [{ label: GROUP, fieldName: 'group', type: 'text' }, result];
  }

  get rows() {
    return (this.lines || []).map((line, index) => ({
      key: String(index),
      group: line.groupValue === null || line.groupValue === undefined ? BLANK : line.groupLabel,
      value: line.value
    }));
  }

  currentAggregate() {
    const aggregate = { function: this.fn };
    if (this.needsField && this.field) {
      aggregate.field = this.field;
    }
    if (this.groupBy) {
      aggregate.groupBy = this.groupBy;
    }
    return aggregate;
  }

  handleFunctionChange(event) {
    this.fn = event.detail.value;
    if (!this.fieldOptions.some((option) => option.value === this.field)) {
      this.field = '';
    }
    this.announce();
  }

  handleFieldChange(event) {
    this.field = event.detail.value;
    this.announce();
  }

  handleGroupChange(event) {
    this.groupBy = event.detail.value;
    this.announce();
  }

  announce() {
    this.lines = undefined;
    this.dispatchEvent(
      new CustomEvent('change', { detail: { aggregate: this.currentAggregate() } })
    );
  }

  async handleSummarize() {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      const document = JSON.parse(this.queryJson);
      document.aggregate = this.currentAggregate();
      const result = await summarize({ queryJson: JSON.stringify(document) });
      this.lines = result.lines;
      this.capped = result.capped === true;
    } catch (error) {
      this.lines = undefined;
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }
}
