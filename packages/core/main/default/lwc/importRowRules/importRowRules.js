import { LightningElement, api } from 'lwc';

import heading from '@salesforce/label/c.Core_Import_RowRulesHeading';
import help from '@salesforce/label/c.Core_Import_RowRulesHelp';
import skipHeading from '@salesforce/label/c.Core_Import_RowRulesSkipHeading';
import addRule from '@salesforce/label/c.Core_Import_RowRulesAddRule';
import removeRule from '@salesforce/label/c.Core_Import_RowRulesRemoveRule';
import columnLabel from '@salesforce/label/c.Core_Import_RowRulesColumn';
import testLabel from '@salesforce/label/c.Core_Import_RowRulesTest';
import textLabel from '@salesforce/label/c.Core_Import_RowRulesText';
import testEquals from '@salesforce/label/c.Core_Import_RowRulesTestEquals';
import testContains from '@salesforce/label/c.Core_Import_RowRulesTestContains';
import testBlank from '@salesforce/label/c.Core_Import_RowRulesTestBlank';
import uniqueLabel from '@salesforce/label/c.Core_Import_RowRulesUniqueBy';
import uniqueHelp from '@salesforce/label/c.Core_Import_RowRulesUniqueHelp';

/** The most rules and key columns, as ImportRowFilter.MAX_RULES says. */
const MAX_RULES = 5;

/**
 * Which rows of the file load (canonical model R-IT17): Skip rows where rules and One row per
 * key columns, edited here and saved with the mapping by the wizard. The server decides each
 * row as the file is staged. See docs/admin-guide/importing.md, section 11.
 */
export default class ImportRowRules extends LightningElement {
  /** Every column of the file. */
  @api columnNames = [];

  rules = [];
  keys = [];
  counter = 0;

  labels = {
    heading,
    help,
    skipHeading,
    addRule,
    removeRule,
    columnLabel,
    testLabel,
    textLabel,
    uniqueLabel,
    uniqueHelp
  };

  /** The Skip rows rules, as the mapping document holds them. */
  @api
  get skipRows() {
    return this.rules.map(({ column, test, text }) => {
      return test === 'blank' ? { column, test } : { column, test, text: text || '' };
    });
  }

  set skipRows(value) {
    if (JSON.stringify(value || []) === JSON.stringify(this.skipRows)) {
      return;
    }
    this.rules = (value || []).map((rule) => this.keyed({ ...rule }));
  }

  /** The One row per columns, as the mapping document holds them. */
  @api
  get uniqueBy() {
    return this.keys;
  }

  set uniqueBy(value) {
    this.keys = [...(value || [])];
  }

  get columnOptions() {
    return (this.columnNames || []).map((name) => ({ label: name, value: name }));
  }

  get testOptions() {
    return [
      { label: testEquals, value: 'equals' },
      { label: testContains, value: 'contains' },
      { label: testBlank, value: 'blank' }
    ];
  }

  get rows() {
    return this.rules.map((rule) => ({ ...rule, needsText: rule.test !== 'blank' }));
  }

  get cannotAdd() {
    return this.rules.length >= MAX_RULES;
  }

  handleAdd() {
    const first = (this.columnNames || [])[0] || '';
    this.rules = this.rules.concat(this.keyed({ column: first, test: 'equals', text: '' }));
    this.changed();
  }

  handleRemove(event) {
    const key = event.target.dataset.key;
    this.rules = this.rules.filter((rule) => rule.key !== key);
    this.changed();
  }

  handleRuleInput(event) {
    const { key, name } = event.target.dataset;
    const value = event.detail.value;
    this.rules = this.rules.map((rule) => (rule.key === key ? { ...rule, [name]: value } : rule));
    this.changed();
  }

  handleKeys(event) {
    this.keys = (event.detail.value || []).slice(0, MAX_RULES);
    this.changed();
  }

  changed() {
    this.dispatchEvent(
      new CustomEvent('change', { detail: { skipRows: this.skipRows, uniqueBy: this.uniqueBy } })
    );
  }

  keyed(rule) {
    this.counter += 1;
    return { ...rule, key: `rule-${this.counter}` };
  }
}
