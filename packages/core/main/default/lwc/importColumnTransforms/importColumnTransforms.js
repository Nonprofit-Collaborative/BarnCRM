import { LightningElement, api } from 'lwc';
import previewChanges from '@salesforce/apex/ImportController.previewChanges';

import heading from '@salesforce/label/c.Core_Import_ChangesHeading';
import help from '@salesforce/label/c.Core_Import_ChangesHelp';
import addLabel from '@salesforce/label/c.Core_Import_ChangesAdd';
import kindLabel from '@salesforce/label/c.Core_Import_ChangesKind';
import removeLabel from '@salesforce/label/c.Core_Import_ChangesRemove';
import doneLabel from '@salesforce/label/c.Core_Import_ChangesDone';
import opTrim from '@salesforce/label/c.Core_Import_ChangesOpTrim';
import opUpper from '@salesforce/label/c.Core_Import_ChangesOpUpper';
import opLower from '@salesforce/label/c.Core_Import_ChangesOpLower';
import opProper from '@salesforce/label/c.Core_Import_ChangesOpProper';
import opReplace from '@salesforce/label/c.Core_Import_ChangesOpReplace';
import opIfBlank from '@salesforce/label/c.Core_Import_ChangesOpIfBlank';
import opAppend from '@salesforce/label/c.Core_Import_ChangesOpAppend';
import opDate from '@salesforce/label/c.Core_Import_ChangesOpDate';
import findLabel from '@salesforce/label/c.Core_Import_ChangesFind';
import replaceWithLabel from '@salesforce/label/c.Core_Import_ChangesReplaceWith';
import matchCaseLabel from '@salesforce/label/c.Core_Import_ChangesMatchCapitals';
import wholeValueLabel from '@salesforce/label/c.Core_Import_ChangesWholeValue';
import valueLabel from '@salesforce/label/c.Core_Import_ChangesValue';
import columnsLabel from '@salesforce/label/c.Core_Import_ChangesColumns';
import separatorLabel from '@salesforce/label/c.Core_Import_ChangesSeparator';
import dateOrderLabel from '@salesforce/label/c.Core_Import_ChangesDateOrder';
import orderMdy from '@salesforce/label/c.Core_Import_ChangesOrderMDY';
import orderDmy from '@salesforce/label/c.Core_Import_ChangesOrderDMY';
import orderYmd from '@salesforce/label/c.Core_Import_ChangesOrderYMD';
import previewHeading from '@salesforce/label/c.Core_Import_ChangesPreviewHeading';
import beforeHeader from '@salesforce/label/c.Core_Import_ChangesBefore';
import afterHeader from '@salesforce/label/c.Core_Import_ChangesAfter';
import rowNumberHeader from '@salesforce/label/c.Core_Import_RowNumberHeader';

/** The most changes one column may have, as DataTransform.MAX_STEPS says. */
const MAX_STEPS = 10;
const SAMPLE_ROWS = 5;

/**
 * The changes to one column's values as they load (canonical model R-IT15): an ordered list
 * of named steps, edited here and saved with the mapping by the wizard. Nothing here changes a
 * value itself: the preview asks the server, so what is shown is what the import will do.
 * See docs/admin-guide/importing.md, section 10.
 */
export default class ImportColumnTransforms extends LightningElement {
  /** The column whose values are changed; another column is previewed afresh. */
  @api
  get source() {
    return this.sourceName;
  }

  set source(value) {
    const switched = this.sourceName !== undefined && this.sourceName !== value;
    this.sourceName = value;
    if (switched) {
      this.refreshPreview();
    }
  }

  sourceName;
  /** Every column of the file, for Add other columns. */
  @api columnNames = [];
  /** The file's first rows, each a map of column to value. */
  @api sampleRows = [];

  steps = [];
  counter = 0;
  samples = [];
  problems = [];

  labels = {
    help,
    addLabel,
    kindLabel,
    removeLabel,
    doneLabel,
    findLabel,
    replaceWithLabel,
    matchCaseLabel,
    wholeValueLabel,
    valueLabel,
    columnsLabel,
    separatorLabel,
    dateOrderLabel,
    previewHeading,
    beforeHeader,
    afterHeader,
    rowNumberHeader
  };

  /** The column's steps, as the mapping document holds them. */
  @api
  get transforms() {
    return this.steps.map((step) => this.stored(step));
  }

  set transforms(value) {
    // The wizard hands back what this component last sent; keeping the steps then keeps their
    // keys, so an input being typed in is not drawn again under the cursor.
    if (JSON.stringify(value || []) === JSON.stringify(this.transforms)) {
      return;
    }
    this.steps = (value || []).map((step) => this.keyed({ ...step }));
  }

  connectedCallback() {
    this.refreshPreview();
  }

  get heading() {
    return heading.replace('{0}', this.source || '');
  }

  get operationOptions() {
    return [
      { label: opTrim, value: 'trim' },
      { label: opUpper, value: 'upper' },
      { label: opLower, value: 'lower' },
      { label: opProper, value: 'proper' },
      { label: opReplace, value: 'replace' },
      { label: opIfBlank, value: 'ifBlank' },
      { label: opAppend, value: 'append' },
      { label: opDate, value: 'date' }
    ];
  }

  get orderOptions() {
    return [
      { label: orderMdy, value: 'MDY' },
      { label: orderDmy, value: 'DMY' },
      { label: orderYmd, value: 'YMD' }
    ];
  }

  get otherColumnOptions() {
    return (this.columnNames || [])
      .filter((name) => name !== this.source)
      .map((name) => ({ label: name, value: name }));
  }

  /** The steps as the template shows them, each with the inputs its kind needs. */
  get rows() {
    return this.steps.map((step) => ({
      ...step,
      isReplace: step.op === 'replace',
      isIfBlank: step.op === 'ifBlank',
      isAppend: step.op === 'append',
      isDate: step.op === 'date',
      columns: step.columns || []
    }));
  }

  get cannotAdd() {
    return this.steps.length >= MAX_STEPS;
  }

  get hasProblems() {
    return this.problems.length > 0;
  }

  get problemText() {
    return this.problems.join(' ');
  }

  get hasSamples() {
    return this.samples.length > 0;
  }

  handleAdd() {
    this.steps = this.steps.concat(this.keyed({ op: 'trim' }));
    this.changed();
  }

  handleRemove(event) {
    const key = event.target.dataset.key;
    this.steps = this.steps.filter((step) => step.key !== key);
    this.changed();
  }

  /** One input of one step: the input names the step by key and the parameter by name. */
  handleInput(event) {
    const { key, name } = event.target.dataset;
    const value =
      event.target.type === 'checkbox'
        ? event.target.checked
        : event.detail && event.detail.value !== undefined
          ? event.detail.value
          : event.target.value;
    this.steps = this.steps.map((step) => {
      if (step.key !== key) {
        return step;
      }
      if (name === 'op') {
        return this.keyed({ op: value, key });
      }
      return { ...step, [name]: value };
    });
    this.changed();
  }

  handleDone() {
    this.dispatchEvent(new CustomEvent('done'));
  }

  changed() {
    this.dispatchEvent(
      new CustomEvent('change', { detail: { source: this.source, transforms: this.transforms } })
    );
    this.refreshPreview();
  }

  async refreshPreview() {
    try {
      const preview = await previewChanges({
        source: this.source,
        transformsJson: JSON.stringify(this.transforms),
        sampleRowsJson: JSON.stringify((this.sampleRows || []).slice(0, SAMPLE_ROWS))
      });
      this.samples = ((preview && preview.samples) || []).map((sample) => ({
        ...sample,
        key: `sample-${sample.rowNumber}`
      }));
      this.problems = (preview && preview.problems) || [];
    } catch (error) {
      this.samples = [];
      this.problems = [
        error && error.body && error.body.message ? error.body.message : String(error)
      ];
    }
  }

  keyed(step) {
    if (step.key) {
      return step;
    }
    this.counter += 1;
    return { ...step, key: `step-${this.counter}` };
  }

  /** A step as the mapping document stores it: its kind and only the parameters it reads. */
  stored(step) {
    const result = { op: step.op };
    if (step.op === 'replace') {
      Object.assign(result, {
        text: step.text || '',
        replaceWith: step.replaceWith || '',
        matchCase: Boolean(step.matchCase),
        wholeValue: Boolean(step.wholeValue)
      });
    } else if (step.op === 'ifBlank') {
      result.value = step.value || '';
    } else if (step.op === 'append') {
      result.columns = step.columns || [];
      if (step.separator !== undefined && step.separator !== null) {
        result.separator = step.separator;
      }
    } else if (step.op === 'date') {
      result.dateOrder = step.dateOrder || 'MDY';
    }
    return result;
  }
}
