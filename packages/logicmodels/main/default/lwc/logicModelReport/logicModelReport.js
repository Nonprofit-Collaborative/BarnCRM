import { LightningElement, api } from 'lwc';
import { downloadCsv, fileName, saveBlob } from 'c/findCsv';
import {
  defaultReportKeys,
  progressWords,
  report,
  reportCsv,
  reportHtml,
  reportPeriods
} from 'c/logicModelRules';
import { LABELS, format, stageLabel } from 'c/logicModelText';

const FILE_BASE = 'Logic_Model_Report';

/**
 * The Logic Model Report (L-04, R-IN7) under the builder: per indicator the baseline and, for the
 * chosen periods, the target, result and progress, downloadable as CSV or a printable page. It
 * reads the builder's model, so it changes as the model is saved, and stores nothing.
 */
export default class LogicModelReport extends LightningElement {
  @api scopeName;

  labels = LABELS;
  chosenKeys;
  resultMessage;
  _model;

  @api
  get model() {
    return this._model;
  }

  set model(value) {
    this._model = value;
    const known = reportPeriods(value).map((period) => period.key);
    this.chosenKeys = this.chosenKeys
      ? this.chosenKeys.filter((key) => known.includes(key))
      : defaultReportKeys(value);
  }

  get built() {
    return report(this._model, this.chosenKeys);
  }

  get periodOptions() {
    return reportPeriods(this._model).map((period) => ({
      value: period.key,
      label: `${period.name} (${format(LABELS.reportPeriodDates, period.startDate, period.endDate)})`
    }));
  }

  get hasPeriods() {
    return this.periodOptions.length > 0;
  }

  get hasIndicators() {
    return ((this._model && this._model.indicators) || []).length > 0;
  }

  get nothingChosen() {
    return this.hasPeriods && this.chosenKeys.length === 0;
  }

  get cannotDownload() {
    return !this.hasIndicators || this.built.periods.length === 0;
  }

  get headPeriods() {
    return this.built.periods.map((period) => ({
      key: period.key,
      name: period.name,
      dates: format(LABELS.reportPeriodDates, period.startDate, period.endDate)
    }));
  }

  get subHeads() {
    return this.built.periods.flatMap((period) => [
      { key: `${period.key}-t`, label: LABELS.target },
      { key: `${period.key}-r`, label: LABELS.result },
      { key: `${period.key}-p`, label: LABELS.progress }
    ]);
  }

  get rows() {
    const words = this.words;
    return this.built.rows.map((row) => ({
      id: row.id,
      column: stageLabel(row.stage),
      part: row.part,
      indicator: row.indicator,
      unit: row.unit,
      baseline: row.baseline,
      cells: row.cells.flatMap((cell) => [
        { key: `${cell.key}-t`, value: cell.target, number: true },
        { key: `${cell.key}-r`, value: cell.result, number: true },
        { key: `${cell.key}-p`, value: progressWords(cell.progress, words), number: false }
      ])
    }));
  }

  get words() {
    const name = this._model ? this._model.name : '';
    return {
      title: `${name}: ${LABELS.reportTitle}`,
      meta: format(LABELS.reportMeta, name, this.scopeName, new Date().toLocaleDateString()),
      column: LABELS.column,
      part: LABELS.reportPart,
      indicator: LABELS.reportIndicator,
      unit: LABELS.unit,
      betterWhen: LABELS.betterWhen,
      higher: LABELS.higher,
      lower: LABELS.lower,
      baseline: LABELS.baseline,
      baselineDate: LABELS.baselineDate,
      target: LABELS.target,
      result: LABELS.result,
      progress: LABELS.progress,
      met: LABELS.met,
      stage: stageLabel
    };
  }

  handlePeriods(event) {
    this.chosenKeys = [...event.detail.value];
  }

  handleCsv() {
    const csv = reportCsv(this.built, this.words);
    downloadCsv(FILE_BASE, csv.columns, csv.rows);
    this.resultMessage = LABELS.reportDownloaded;
  }

  handlePrintable() {
    const html = reportHtml(this.built, this.words);
    saveBlob(
      new Blob([html], { type: 'text/html;charset=utf-8' }),
      fileName(FILE_BASE, new Date(), 'html')
    );
    this.resultMessage = LABELS.reportDownloaded;
  }
}
