import { LightningElement } from 'lwc';
import check from '@salesforce/apex/FilesImportController.check';
import start from '@salesforce/apex/FilesImportController.start';
import addFiles from '@salesforce/apex/FilesImportController.addFiles';
import finish from '@salesforce/apex/FilesImportController.finish';
import undo from '@salesforce/apex/FilesImportController.undo';
import getJobs from '@salesforce/apex/FilesImportController.getJobs';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { downloadCsv, format, messageFrom } from 'c/findCsv';
import { openZip, ZIP_ERRORS } from 'c/zipReader';
import {
  MAX_FILE_BYTES,
  MAX_FILES,
  REASONS,
  checkRows,
  countRows,
  groupRows,
  idsToCheck,
  markUnseen,
  readManifest,
  toBase64
} from 'c/filesImportModel';

/** Refused rows shown on the page; Download Rows has them all. */
const ROWS_SHOWN = 100;

/**
 * The Import Files panel on Data Manager (C-70, canonical model 29FI, admin guide
 * files-import.md): choose a zip, Dry Run checks every manifest row in the browser and the
 * records on the server, Load Files sends the ready files in groups to a Files data job, and
 * Recent Loads lists the loads with Undo. The rules are in `filesImportModel` and
 * `FilesImportService`; this only reads the zip and asks.
 */
export default class FilesImport extends LightningElement {
  helpReady = isHelpLoaded('Core');
  zip;
  zipName;
  rows;
  checked = false;
  busy = false;
  progress;
  errorMessage;
  noticeMessage;
  jobs = [];
  undoTarget;
  undoText = '';

  get labels() {
    return {
      title: helpText('Core', 'Core_DataManager_FilesTitle'),
      intro: helpText('Core', 'Core_FilesImport_Intro'),
      choose: helpText('Core', 'Core_FilesImport_Choose'),
      dryRun: helpText('Core', 'Core_FilesImport_DryRun'),
      load: helpText('Core', 'Core_FilesImport_Load'),
      download: helpText('Core', 'Core_FilesImport_Download'),
      refusedHeading: helpText('Core', 'Core_FilesImport_RefusedHeading'),
      row: helpText('Core', 'Core_FilesImport_ColumnRow'),
      file: helpText('Core', 'Core_FilesImport_ColumnFile'),
      recordId: helpText('Core', 'Core_FilesImport_ColumnRecordId'),
      result: helpText('Core', 'Core_FilesImport_ColumnResult'),
      recentHeading: helpText('Core', 'Core_FilesImport_RecentHeading'),
      recentNone: helpText('Core', 'Core_FilesImport_RecentNone'),
      undo: helpText('Core', 'Core_FilesImport_Undo'),
      undoButton: helpText('Core', 'Core_FilesImport_UndoButton'),
      cancel: helpText('Core', 'Core_FilesImport_Cancel')
    };
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.loadJobs();
  }

  get hasRows() {
    return Boolean(this.rows && this.rows.length);
  }

  get manifestLine() {
    return this.hasRows ? format(helpText('Core', 'Core_FilesImport_Read'), this.rows.length) : '';
  }

  get counts() {
    return countRows(this.rows || []);
  }

  get summaryLine() {
    return format(
      helpText('Core', 'Core_FilesImport_Ready'),
      this.counts.ready,
      this.counts.refused
    );
  }

  get refusedRows() {
    return (this.rows || [])
      .filter((row) => row.reason)
      .slice(0, ROWS_SHOWN)
      .map((row) => ({ ...row, key: `row-${row.row}`, result: this.reasonText(row.reason) }));
  }

  get hasRefused() {
    return this.checked && this.counts.refused > 0;
  }

  get dryRunDisabled() {
    return this.busy || !this.hasRows;
  }

  get loadDisabled() {
    return this.busy || !this.checked || this.counts.ready === 0;
  }

  get progressLine() {
    return this.progress
      ? format(
          helpText('Core', 'Core_FilesImport_Progress'),
          this.progress.done,
          this.progress.total
        )
      : '';
  }

  get progressValue() {
    return this.progress && this.progress.total
      ? Math.round((this.progress.done * 100) / this.progress.total)
      : 0;
  }

  get hasJobs() {
    return this.jobs.length > 0;
  }

  get jobRows() {
    return this.jobs.map((job) => ({
      ...job,
      summary: format(helpText('Core', 'Core_FilesImport_JobSummary'), job.saved, job.refused)
    }));
  }

  get undoLine() {
    return this.undoTarget
      ? format(helpText('Core', 'Core_FilesImport_UndoConfirm'), this.undoTarget.saved)
      : '';
  }

  get undoDisabled() {
    return (
      this.busy ||
      !this.undoTarget ||
      String(this.undoText).trim() !== String(this.undoTarget.saved)
    );
  }

  reasonText(reason) {
    const texts = {
      [REASONS.notInZip]: helpText('Core', 'Core_FilesImport_ReasonNotInZip'),
      [REASONS.empty]: helpText('Core', 'Core_FilesImport_ErrorNoData'),
      [REASONS.tooLarge]: helpText('Core', 'Core_FilesImport_ErrorFileTooLarge'),
      [REASONS.recordId]: helpText('Core', 'Core_FilesImport_ErrorRecordId'),
      [REASONS.repeated]: helpText('Core', 'Core_FilesImport_ReasonRepeated'),
      [REASONS.unseen]: helpText('Core', 'Core_FilesImport_ReasonUnseen')
    };
    // A reason the server gave is already a sentence.
    return texts[reason] || reason;
  }

  zipErrorText(reason) {
    const texts = {
      [REASONS.noManifest]: helpText('Core', 'Core_FilesImport_ErrorNoManifest'),
      [REASONS.noHeadings]: helpText('Core', 'Core_FilesImport_ErrorNoHeadings'),
      [REASONS.noRows]: helpText('Core', 'Core_FilesImport_ErrorNoRows'),
      [REASONS.tooMany]: format(helpText('Core', 'Core_FilesImport_ErrorTooMany'), MAX_FILES),
      [ZIP_ERRORS.notAZip]: helpText('Core', 'Core_FilesImport_ErrorNotAZip'),
      [ZIP_ERRORS.tooLarge]: format(helpText('Core', 'Core_FilesImport_ErrorTooMany'), MAX_FILES),
      [ZIP_ERRORS.unsupportedBrowser]: helpText('Core', 'Core_FilesImport_ErrorBrowser')
    };
    return texts[reason];
  }

  async handleFile(event) {
    const chosen = event.target.files && event.target.files[0];
    this.reset();
    if (!chosen) {
      return;
    }
    await this.work(async () => {
      try {
        const zip = openZip(await chosen.arrayBuffer());
        this.rows = await readManifest(zip);
        this.zip = zip;
        this.zipName = chosen.name;
      } catch (error) {
        const text = error && this.zipErrorText(error.reason);
        if (!text) {
          throw error;
        }
        this.errorMessage = text;
      }
    });
  }

  async handleDryRun() {
    await this.work(async () => {
      const rows = checkRows(this.rows, this.zip);
      const ids = idsToCheck(rows);
      const unseen = ids.length ? await check({ recordIds: ids }) : [];
      this.rows = markUnseen(rows, unseen);
      this.checked = true;
    });
  }

  handleDownload() {
    downloadCsv(
      'files-import',
      [
        { label: this.labels.row, path: 'row' },
        { label: this.labels.file, path: 'file' },
        { label: this.labels.recordId, path: 'recordId' },
        { label: this.labels.result, path: 'result' }
      ],
      this.rows.map((row) => ({
        ...row,
        result: row.reason
          ? this.reasonText(row.reason)
          : helpText('Core', 'Core_FilesImport_ResultReady')
      }))
    );
  }

  async handleLoad() {
    const groups = groupRows(this.rows, (file) => this.zip.sizeOf(file));
    const total = groups.reduce((sum, group) => sum + group.length, 0);
    await this.work(async () => {
      const jobId = await start({ fileName: this.zipName, rowCount: total });
      const refusedOnServer = new Map();
      this.progress = { done: 0, total };
      for (const group of groups) {
        const files = [];
        for (const row of group) {
          // eslint-disable-next-line no-await-in-loop
          const bytes = await this.zip.read(row.file, MAX_FILE_BYTES);
          files.push({
            row: row.row,
            recordId: row.recordId,
            fileName: row.file,
            title: row.title,
            description: row.description,
            data: toBase64(bytes)
          });
        }
        // Groups go one at a time: each is up to 2 MB, and the server saves them in order.
        // eslint-disable-next-line no-await-in-loop
        const result = await addFiles({ jobId, files });
        (result.refusals || []).forEach((refusal) =>
          refusedOnServer.set(refusal.row, refusal.reason)
        );
        this.progress = { done: this.progress.done + group.length, total };
      }
      const job = await finish({ jobId });
      this.rows = this.rows.map((row) => {
        return refusedOnServer.has(row.row)
          ? { ...row, reason: refusedOnServer.get(row.row) }
          : row;
      });
      this.noticeMessage = format(
        helpText('Core', 'Core_FilesImport_Done'),
        job.saved,
        job.refused
      );
      await this.loadJobs();
    });
    this.progress = undefined;
  }

  handleUndo(event) {
    const id = event.currentTarget.dataset.id;
    this.undoTarget = this.jobs.find((job) => job.id === id);
    this.undoText = '';
  }

  handleUndoText(event) {
    this.undoText = event.detail.value;
  }

  handleUndoCancel() {
    this.undoTarget = undefined;
    this.undoText = '';
  }

  async handleUndoConfirm() {
    await this.work(async () => {
      await undo({ jobId: this.undoTarget.id, confirmedFiles: this.undoTarget.saved });
      this.undoTarget = undefined;
      this.undoText = '';
      this.noticeMessage = helpText('Core', 'Core_FilesImport_Undone');
      await this.loadJobs();
    });
  }

  async loadJobs() {
    try {
      this.jobs = (await getJobs()) || [];
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  reset() {
    this.zip = undefined;
    this.zipName = undefined;
    this.rows = undefined;
    this.checked = false;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
  }

  async work(action) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }
}
