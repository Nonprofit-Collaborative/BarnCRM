import { LightningElement, api } from 'lwc';
import previewChanges from '@salesforce/apex/ImportController.previewChanges';

import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
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
import opAddFields from '@salesforce/label/c.Core_BulkUpdate_StepAddFields';
import fieldsLabel from '@salesforce/label/c.Core_BulkUpdate_StepFields';
import opMap from '@salesforce/label/c.Core_Import_StepsOpMap';
import opIfThen from '@salesforce/label/c.Core_Import_StepsOpIfThen';
import opPart from '@salesforce/label/c.Core_Import_StepsOpPart';
import opFirst from '@salesforce/label/c.Core_Import_StepsOpFirst';
import opLast from '@salesforce/label/c.Core_Import_StepsOpLast';
import opShiftDate from '@salesforce/label/c.Core_Import_StepsOpShiftDate';
import opToday from '@salesforce/label/c.Core_Import_StepsOpToday';
import mapFromLabel from '@salesforce/label/c.Core_Import_StepsMapFrom';
import mapToLabel from '@salesforce/label/c.Core_Import_StepsMapTo';
import mapAddRowLabel from '@salesforce/label/c.Core_Import_StepsMapAddRow';
import mapRemoveRowLabel from '@salesforce/label/c.Core_Import_StepsMapRemoveRow';
import mapOtherwiseLabel from '@salesforce/label/c.Core_Import_StepsMapOtherwise';
import testLabel from '@salesforce/label/c.Core_Import_StepsTest';
import testEquals from '@salesforce/label/c.Core_Import_StepsTestEquals';
import testContains from '@salesforce/label/c.Core_Import_StepsTestContains';
import testBlank from '@salesforce/label/c.Core_Import_StepsTestBlank';
import testTextLabel from '@salesforce/label/c.Core_Import_StepsTestText';
import thenValueLabel from '@salesforce/label/c.Core_Import_StepsThenValue';
import otherwiseLabel from '@salesforce/label/c.Core_Import_StepsOtherwise';
import splitAtLabel from '@salesforce/label/c.Core_Import_StepsSplitAt';
import positionLabel from '@salesforce/label/c.Core_Import_StepsPosition';
import fromEndLabel from '@salesforce/label/c.Core_Import_StepsFromEnd';
import countLabel from '@salesforce/label/c.Core_Import_StepsCount';
import amountLabel from '@salesforce/label/c.Core_Import_StepsAmount';
import unitLabel from '@salesforce/label/c.Core_Import_StepsUnit';
import unitDays from '@salesforce/label/c.Core_Import_StepsUnitDays';
import unitMonths from '@salesforce/label/c.Core_Import_StepsUnitMonths';
import whenBlankLabel from '@salesforce/label/c.Core_Import_StepsWhenBlank';
import opDigits from '@salesforce/label/c.Core_Import_StepsOpDigits';
import patternLabel from '@salesforce/label/c.Core_Import_StepsPattern';
import countryLabel from '@salesforce/label/c.Core_Import_StepsCountry';

/** The most changes one column may have, as DataTransform.MAX_STEPS says. */
const MAX_STEPS = 10;
/** The most rows a value map may have, as DataTransform.MAX_PAIRS says. */
const MAX_PAIRS = 100;
const SAMPLE_ROWS = 5;
/** Number parameters, kept as whole numbers in the document. */
const NUMBER_PARAMETERS = ['position', 'count', 'amount'];

/**
 * The changes to one column's values as they load (canonical model R-IT15): an ordered list
 * of named steps, edited here and saved with the mapping by the wizard. Nothing here changes a
 * value itself: the preview asks the server, so what is shown is what the import will do.
 * See docs/admin-guide/importing.md, section 10.
 *
 * Bulk update (C-37, R-BU7) uses it `embedded`, for a field's change with steps: the steps
 * only, with the record's fields to add (`columnOptions`), and no heading, preview or Done,
 * because the bulk update preview shows each record before and after.
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
  /** Steps only, inside another tool's form: no heading, preview or Done. */
  @api embedded = false;
  /** In place of columnNames, the values to add as label and value (a record's fields). */
  @api columnOptions;

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
    rowNumberHeader,
    mapFromLabel,
    mapToLabel,
    mapAddRowLabel,
    mapRemoveRowLabel,
    mapOtherwiseLabel,
    testLabel,
    testTextLabel,
    thenValueLabel,
    otherwiseLabel,
    splitAtLabel,
    positionLabel,
    fromEndLabel,
    countLabel,
    amountLabel,
    unitLabel,
    whenBlankLabel,
    patternLabel,
    countryLabel
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

  get standalone() {
    return !this.embedded;
  }

  /** What the values to add are called: a file's columns, or a record's fields. */
  get columnsText() {
    return this.embedded ? fieldsLabel : columnsLabel;
  }

  get operationOptions() {
    return [
      { label: opTrim, value: 'trim' },
      { label: opUpper, value: 'upper' },
      { label: opLower, value: 'lower' },
      { label: opProper, value: 'proper' },
      { label: opReplace, value: 'replace' },
      { label: opIfBlank, value: 'ifBlank' },
      { label: this.embedded ? opAddFields : opAppend, value: 'append' },
      { label: opDate, value: 'date' },
      { label: opMap, value: 'map' },
      { label: opIfThen, value: 'ifThen' },
      { label: opPart, value: 'part' },
      { label: opFirst, value: 'first' },
      { label: opLast, value: 'last' },
      { label: opShiftDate, value: 'shiftDate' },
      { label: opToday, value: 'today' },
      { label: opDigits, value: 'digits' }
    ];
  }

  get testOptions() {
    return [
      { label: testEquals, value: 'equals' },
      { label: testContains, value: 'contains' },
      { label: testBlank, value: 'blank' }
    ];
  }

  get unitOptions() {
    return [
      { label: unitDays, value: 'days' },
      { label: unitMonths, value: 'months' }
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
    if (this.columnOptions) {
      return this.columnOptions.filter((option) => option.value !== this.source);
    }
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
      isMap: step.op === 'map',
      isIfThen: step.op === 'ifThen',
      needsTestText: step.op === 'ifThen' && step.test !== 'blank',
      isPart: step.op === 'part',
      isCount: step.op === 'first' || step.op === 'last',
      isShiftDate: step.op === 'shiftDate',
      isToday: step.op === 'today',
      isDigits: step.op === 'digits',
      columns: step.columns || [],
      pairRows: (step.pairs || []).map((pair, index) => ({
        ...pair,
        index,
        key: `${step.key}-pair-${index}`
      })),
      cannotAddPair: (step.pairs || []).length >= MAX_PAIRS
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
        // A new kind starts from its stored defaults, so the inputs show what will be saved.
        return this.keyed({ ...this.stored({ op: value }), key });
      }
      if (NUMBER_PARAMETERS.includes(name)) {
        const number = parseInt(value, 10);
        return { ...step, [name]: Number.isNaN(number) ? null : number };
      }
      return { ...step, [name]: value };
    });
    this.changed();
  }

  /** One cell of a value map's table: the input names the step, the row and the side. */
  handlePair(event) {
    const { key, index, name } = event.target.dataset;
    const value = event.detail && event.detail.value !== undefined ? event.detail.value : '';
    this.updatePairs(key, (pairs) =>
      pairs.map((pair, at) => (at === Number(index) ? { ...pair, [name]: value } : pair))
    );
  }

  handleAddPair(event) {
    this.updatePairs(event.target.dataset.key, (pairs) => pairs.concat({ text: '', value: '' }));
  }

  handleRemovePair(event) {
    const { key, index } = event.target.dataset;
    this.updatePairs(key, (pairs) => pairs.filter((pair, at) => at !== Number(index)));
  }

  updatePairs(key, change) {
    this.steps = this.steps.map((step) => {
      if (step.key !== key) {
        return step;
      }
      return { ...step, pairs: change(step.pairs || []) };
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
    if (this.embedded) {
      // The tool it sits in previews (bulk update checks the steps when it previews).
      return;
    }
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
        error && error.body && error.body.message ? error.body.message : UNEXPECTED_ERROR
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
    } else {
      Object.assign(result, this.storedNewer(step));
    }
    return result;
  }

  /** The parameters of the steps ADR-0112 (more transform steps) added. */
  storedNewer(step) {
    switch (step.op) {
      case 'map':
        return {
          pairs: (step.pairs || [{ text: '', value: '' }]).map((pair) => ({
            text: pair.text || '',
            value: pair.value || ''
          })),
          otherwise: step.otherwise || '',
          matchCase: Boolean(step.matchCase)
        };
      case 'ifThen':
        return {
          test: step.test || 'equals',
          text: step.text || '',
          value: step.value || '',
          otherwise: step.otherwise || '',
          matchCase: Boolean(step.matchCase)
        };
      case 'part':
        return {
          separator: step.separator || '',
          position: step.position === undefined ? 1 : step.position,
          fromEnd: Boolean(step.fromEnd)
        };
      case 'first':
      case 'last':
        return { count: step.count === undefined ? 1 : step.count };
      case 'shiftDate':
        return {
          amount: step.amount === undefined ? 0 : step.amount,
          unit: step.unit || 'days'
        };
      case 'today':
        return { whenBlank: Boolean(step.whenBlank) };
      case 'digits':
        // A new step starts as the US and Canada phone pattern, so its inputs show what is saved.
        return {
          pattern: step.pattern === undefined ? '(###) ###-####' : step.pattern,
          country: step.country === undefined ? '1' : step.country
        };
      default:
        return {};
    }
  }
}
