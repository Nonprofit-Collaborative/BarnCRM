import { LightningElement, wire } from 'lwc';
import canFind from '@salesforce/customPermission/Find_And_Export_Records';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import describeObject from '@salesforce/apex/DataDictionaryController.describeObject';
import getFindPage from '@salesforce/apex/FindController.getPage';
import exportPage from '@salesforce/apex/FindController.exportPage';
import getChecks from '@salesforce/apex/DataHygieneController.getChecks';
import { readFillRates, toRow, dictionaryCsv } from 'c/dictionaryKit';
import { toCsv, fileName, format, messageFrom, saveBlob } from 'c/findCsv';
import { writeZip } from 'c/xlsxWriter';
import {
  HANDLING,
  REASONS,
  sensitiveFields,
  recordFields,
  queryChunks,
  createMasker,
  browserSigner,
  buildSchema,
  buildReadme
} from 'c/aiReadinessPack';

import CHOOSE_LABEL from '@salesforce/label/c.Core_DataDictionary_ChooseLabel';
import SOURCE_LABEL from '@salesforce/label/c.Core_DataDictionary_SourceLabel';
import SELECTED_LABEL from '@salesforce/label/c.Core_DataDictionary_SelectedLabel';
import INCLUDE_FILL_RATES from '@salesforce/label/c.Core_DataDictionary_IncludeFillRates';
import INCLUDE_FILL_RATES_HELP from '@salesforce/label/c.Core_DataDictionary_IncludeFillRatesHelp';
import DESCRIBE_PROGRESS from '@salesforce/label/c.Core_DataDictionary_Progress';
import FILL_PROGRESS from '@salesforce/label/c.Core_DataDictionary_FillProgress';
import NOT_COUNTED from '@salesforce/label/c.Core_DataDictionary_NotCounted';
import COL_OBJECT from '@salesforce/label/c.Core_DataDictionary_ColObject';
import COL_FIELD from '@salesforce/label/c.Core_DataDictionary_ColField';
import COL_API_NAME from '@salesforce/label/c.Core_DataDictionary_ColApiName';
import TITLE from '@salesforce/label/c.Core_AiExport_Title';
import INTRO from '@salesforce/label/c.Core_AiExport_Intro';
import INCLUDE_RECORDS from '@salesforce/label/c.Core_AiExport_IncludeRecords';
import INCLUDE_RECORDS_HELP from '@salesforce/label/c.Core_AiExport_IncludeRecordsHelp';
import INCLUDE_CHECKS from '@salesforce/label/c.Core_AiExport_IncludeChecks';
import INCLUDE_CHECKS_HELP from '@salesforce/label/c.Core_AiExport_IncludeChecksHelp';
import NEEDS_FIND from '@salesforce/label/c.Core_AiExport_NeedsFind';
import REVIEW from '@salesforce/label/c.Core_AiExport_Review';
import REVIEW_FIRST from '@salesforce/label/c.Core_AiExport_ReviewFirst';
import SENSITIVE_HEADING from '@salesforce/label/c.Core_AiExport_SensitiveHeading';
import SENSITIVE_INTRO from '@salesforce/label/c.Core_AiExport_SensitiveIntro';
import NO_SENSITIVE from '@salesforce/label/c.Core_AiExport_NoSensitive';
import COL_WHY from '@salesforce/label/c.Core_AiExport_ColWhy';
import COL_HANDLING from '@salesforce/label/c.Core_AiExport_ColHandling';
import LEAVE_OUT from '@salesforce/label/c.Core_AiExport_LeaveOut';
import MASK from '@salesforce/label/c.Core_AiExport_Mask';
import KEEP from '@salesforce/label/c.Core_AiExport_Keep';
import REASON_EMAIL from '@salesforce/label/c.Core_AiExport_ReasonEmail';
import REASON_PHONE from '@salesforce/label/c.Core_AiExport_ReasonPhone';
import REASON_ENCRYPTED from '@salesforce/label/c.Core_AiExport_ReasonEncrypted';
import REASON_NAME from '@salesforce/label/c.Core_AiExport_ReasonName';
import REASON_BIRTH_DATE from '@salesforce/label/c.Core_AiExport_ReasonBirthDate';
import REASON_ADDRESS from '@salesforce/label/c.Core_AiExport_ReasonAddress';
import REASON_IDENTITY from '@salesforce/label/c.Core_AiExport_ReasonIdentity';
import REASON_PRIVATE from '@salesforce/label/c.Core_AiExport_ReasonPrivate';
import REASON_FREE_TEXT from '@salesforce/label/c.Core_AiExport_ReasonFreeText';
import DOWNLOAD from '@salesforce/label/c.Core_AiExport_Download';
import RECORDS_PROGRESS from '@salesforce/label/c.Core_AiExport_RecordsProgress';
import WRITING from '@salesforce/label/c.Core_AiExport_Writing';
import DONE from '@salesforce/label/c.Core_AiExport_Done';
import STOPPED from '@salesforce/label/c.Core_AiExport_Stopped';
import RECORDS_FAILED from '@salesforce/label/c.Core_AiExport_RecordsFailed';
import CHECKS_FAILED from '@salesforce/label/c.Core_AiExport_ChecksFailed';
import README_TITLE from '@salesforce/label/c.Core_AiExport_ReadmeTitle';
import README_INTRO from '@salesforce/label/c.Core_AiExport_ReadmeIntro';
import README_FILES from '@salesforce/label/c.Core_AiExport_ReadmeFiles';
import README_FILE_SCHEMA from '@salesforce/label/c.Core_AiExport_ReadmeFileSchema';
import README_FILE_DICTIONARY from '@salesforce/label/c.Core_AiExport_ReadmeFileDictionary';
import README_FILE_DATA from '@salesforce/label/c.Core_AiExport_ReadmeFileData';
import README_OBJECTS from '@salesforce/label/c.Core_AiExport_ReadmeObjects';
import README_OBJECT_LINE from '@salesforce/label/c.Core_AiExport_ReadmeObjectLine';
import README_OBJECT_RECORDS from '@salesforce/label/c.Core_AiExport_ReadmeObjectRecords';
import README_OBJECT_STOPPED from '@salesforce/label/c.Core_AiExport_ReadmeObjectStopped';
import README_RELATIONSHIPS from '@salesforce/label/c.Core_AiExport_ReadmeRelationships';
import README_RELATIONSHIP_LINE from '@salesforce/label/c.Core_AiExport_ReadmeRelationshipLine';
import README_PRIVACY from '@salesforce/label/c.Core_AiExport_ReadmePrivacy';
import README_PRIVACY_NONE from '@salesforce/label/c.Core_AiExport_ReadmePrivacyNone';
import README_PRIVACY_LEFT_OUT from '@salesforce/label/c.Core_AiExport_ReadmePrivacyLeftOut';
import README_PRIVACY_MASKED from '@salesforce/label/c.Core_AiExport_ReadmePrivacyMasked';
import README_PRIVACY_KEPT from '@salesforce/label/c.Core_AiExport_ReadmePrivacyKept';
import README_PRIVACY_ADVICE from '@salesforce/label/c.Core_AiExport_ReadmePrivacyAdvice';
import README_QUALITY from '@salesforce/label/c.Core_AiExport_ReadmeQuality';
import README_QUALITY_LOW_FILL from '@salesforce/label/c.Core_AiExport_ReadmeQualityLowFill';
import README_QUALITY_CHECK from '@salesforce/label/c.Core_AiExport_ReadmeQualityCheck';
import README_QUALITY_NONE from '@salesforce/label/c.Core_AiExport_ReadmeQualityNone';
import README_USE from '@salesforce/label/c.Core_AiExport_ReadmeUse';
import README_USE_STEP_1 from '@salesforce/label/c.Core_AiExport_ReadmeUseStep1';
import README_USE_STEP_2 from '@salesforce/label/c.Core_AiExport_ReadmeUseStep2';
import README_USE_STEP_3 from '@salesforce/label/c.Core_AiExport_ReadmeUseStep3';
import README_USE_STEP_4 from '@salesforce/label/c.Core_AiExport_ReadmeUseStep4';

const FILE_BASE = 'AI_Readiness_Export';
/** Find's own export limit when its page cannot be read (FindController.DEFAULT_EXPORT_LIMIT). */
const DEFAULT_EXPORT_LIMIT = 50000;

const REASON_LABELS = {
  [REASONS.EMAIL]: REASON_EMAIL,
  [REASONS.PHONE]: REASON_PHONE,
  [REASONS.ENCRYPTED]: REASON_ENCRYPTED,
  [REASONS.NAME]: REASON_NAME,
  [REASONS.BIRTH_DATE]: REASON_BIRTH_DATE,
  [REASONS.ADDRESS]: REASON_ADDRESS,
  [REASONS.IDENTITY_NUMBER]: REASON_IDENTITY,
  [REASONS.PRIVATE_DETAIL]: REASON_PRIVATE,
  [REASONS.FREE_TEXT]: REASON_FREE_TEXT
};

const README_TEXT = {
  title: README_TITLE,
  intro: README_INTRO,
  filesHeading: README_FILES,
  fileSchema: README_FILE_SCHEMA,
  fileDictionary: README_FILE_DICTIONARY,
  fileData: README_FILE_DATA,
  objectsHeading: README_OBJECTS,
  objectLine: README_OBJECT_LINE,
  objectWithRecords: README_OBJECT_RECORDS,
  objectStopped: README_OBJECT_STOPPED,
  relationshipsHeading: README_RELATIONSHIPS,
  relationshipLine: README_RELATIONSHIP_LINE,
  privacyHeading: README_PRIVACY,
  privacyNone: README_PRIVACY_NONE,
  privacyLeftOut: README_PRIVACY_LEFT_OUT,
  privacyMasked: README_PRIVACY_MASKED,
  privacyKept: README_PRIVACY_KEPT,
  privacyAdvice: README_PRIVACY_ADVICE,
  qualityHeading: README_QUALITY,
  qualityLowFill: README_QUALITY_LOW_FILL,
  qualityCheck: README_QUALITY_CHECK,
  qualityNone: README_QUALITY_NONE,
  useHeading: README_USE,
  useStep1: README_USE_STEP_1,
  useStep2: README_USE_STEP_2,
  useStep3: README_USE_STEP_3,
  useStep4: README_USE_STEP_4
};

/**
 * The AI-Readiness Export section of Org Optimizer (AIR-01, plan Section 6.1 item 7, D-154,
 * ADR-0152, admin guide ai-readiness-export.md): choose kinds of record, review the fields flagged as
 * sensitive, and download one zip of README.md, schema.json, data-dictionary.csv and, when
 * asked, one record file per kind of record. It reuses the Data Dictionary's describe, Field
 * Utilization's fill rates, the Data Quality checks and Find's paged export, each with its own
 * server check, and calls no outside service: the pack is built here and downloaded.
 */
export default class AiReadinessExport extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    chooseLabel: CHOOSE_LABEL,
    sourceLabel: SOURCE_LABEL,
    selectedLabel: SELECTED_LABEL,
    includeRecords: INCLUDE_RECORDS,
    includeRecordsHelp: INCLUDE_RECORDS_HELP,
    includeFillRates: INCLUDE_FILL_RATES,
    includeFillRatesHelp: INCLUDE_FILL_RATES_HELP,
    includeChecks: INCLUDE_CHECKS,
    includeChecksHelp: INCLUDE_CHECKS_HELP,
    needsFind: NEEDS_FIND,
    review: REVIEW,
    reviewFirst: REVIEW_FIRST,
    sensitiveHeading: SENSITIVE_HEADING,
    sensitiveIntro: SENSITIVE_INTRO,
    noSensitive: NO_SENSITIVE,
    colObject: COL_OBJECT,
    colField: COL_FIELD,
    colApiName: COL_API_NAME,
    colWhy: COL_WHY,
    colHandling: COL_HANDLING,
    download: DOWNLOAD
  };

  handlingOptions = [
    { label: LEAVE_OUT, value: HANDLING.LEAVE_OUT },
    { label: MASK, value: HANDLING.MASK },
    { label: KEEP, value: HANDLING.KEEP }
  ];

  canFind = Boolean(canFind);
  objectOptions = [];
  selected = [];
  chosenDefaults = false;
  includeRecords = Boolean(canFind);
  includeFillRates = false;
  includeChecks = Boolean(canFind);
  /** The described objects, once reviewed; cleared when the choice of objects changes. */
  described;
  flagged = [];
  working = false;
  progressText;
  errorMessage;
  noticeMessage;
  run = 0;

  @wire(listObjects)
  wiredObjects({ data, error }) {
    if (data) {
      this.objectOptions = data.map((option) => ({
        value: option.value,
        label: `${option.label} (${option.value})`
      }));
      if (!this.chosenDefaults) {
        this.chosenDefaults = true;
        this.selected = data.filter((option) => option.isDefault).map((option) => option.value);
      }
    } else if (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get needsFind() {
    return !this.canFind;
  }

  get findDisabled() {
    return this.working || !this.canFind;
  }

  get reviewDisabled() {
    return this.working || this.selected.length === 0;
  }

  get reviewed() {
    return Boolean(this.described);
  }

  get downloadDisabled() {
    return this.working || !this.reviewed;
  }

  get hasFlagged() {
    return this.flagged.length > 0;
  }

  handleSelect(event) {
    this.selected = event.detail.value;
    this.described = undefined;
    this.flagged = [];
  }

  handleOption(event) {
    this[event.target.dataset.option] = event.target.checked;
  }

  handleHandling(event) {
    const key = event.target.dataset.key;
    const handling = event.detail.value;
    this.flagged = this.flagged.map((row) => (row.key === key ? { ...row, handling } : row));
  }

  /** Runs one piece of work: one at a time, with its errors shown and progress cleared after. */
  async work(task) {
    const run = ++this.run;
    this.working = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      await task(run);
    } catch (error) {
      if (run === this.run) {
        this.errorMessage = messageFrom(error);
      }
    } finally {
      if (run === this.run) {
        this.working = false;
        this.progressText = undefined;
      }
    }
  }

  /** Describes the chosen objects one at a time and lists the fields flagged as sensitive. */
  handleReview() {
    const names = [...this.selected];
    return this.work(async (run) => {
      const described = [];
      for (const objectName of names) {
        this.progressText = format(
          DESCRIBE_PROGRESS,
          String(described.length),
          String(names.length)
        );
        // eslint-disable-next-line no-await-in-loop
        described.push(await describeObject({ objectName }));
        if (run !== this.run) {
          return;
        }
      }
      this.described = described;
      this.flagged = sensitiveFields(described).map((row) => ({
        ...row,
        reasonLabel: REASON_LABELS[row.reason],
        handlingLabel: `${row.objectLabel}: ${row.fieldLabel}`
      }));
    });
  }

  handleDownload() {
    return this.work(async (run) => {
      const objects = this.described;
      const handlingByKey = {};
      for (const row of this.flagged) {
        handlingByKey[row.key] = row.handling;
      }
      const notes = [];
      const fillRates = this.includeFillRates
        ? await this.readAllFillRates(run, objects, notes)
        : {};
      const checks = this.includeChecks ? await this.readChecks(notes) : [];
      const files = [];
      const records = this.includeRecords
        ? await this.readAllRecords(run, objects, handlingByKey, files, notes)
        : {};
      if (run !== this.run) {
        return;
      }
      this.progressText = WRITING;
      const schema = buildSchema(objects, { handlingByKey, fillRates, records, checks });
      const dictionaryRows = objects.flatMap((object) =>
        object.fields.map((field) => {
          const shares = fillRates[object.objectName];
          return toRow(object, field, shares ? shares.get(field.fieldName) : null);
        })
      );
      const bytes = await writeZip([
        ['README.md', buildReadme(schema, README_TEXT)],
        ['schema.json', `${JSON.stringify(schema, null, 2)}\n`],
        ['data-dictionary.csv', dictionaryCsv(dictionaryRows, this.includeFillRates)],
        ...files
      ]);
      saveBlob(
        new Blob([bytes], { type: 'application/zip' }),
        fileName(FILE_BASE, new Date(), 'zip')
      );
      const total = Object.values(records).reduce((sum, info) => sum + info.count, 0);
      this.noticeMessage = [format(DONE, String(objects.length), String(total)), ...notes].join(
        ' '
      );
    });
  }

  /** Fill rates by object, from Field Utilization's counting; objects it cannot count are noted. */
  async readAllFillRates(run, objects, notes) {
    const fillRates = {};
    const skipped = [];
    for (const object of objects) {
      this.progressText = format(FILL_PROGRESS, object.objectLabel);
      try {
        // eslint-disable-next-line no-await-in-loop
        const shares = await readFillRates(object.objectName, () => run === this.run);
        if (shares) {
          fillRates[object.objectName] = shares;
        } else {
          skipped.push(object.objectLabel);
        }
      } catch {
        // A count that fails leaves that object's fill rates blank and says so; the pack stays.
        skipped.push(object.objectLabel);
      }
    }
    if (skipped.length) {
      notes.push(format(NOT_COUNTED, skipped.join(', ')));
    }
    return fillRates;
  }

  async readChecks(notes) {
    try {
      return await getChecks();
    } catch {
      notes.push(CHECKS_FAILED);
      return [];
    }
  }

  /**
   * Each object's records through Find's paged export, up to its export limit, as a CSV added to
   * `files`; returns { file, count, stopped } by object. An object Find refuses is noted and left
   * without records.
   */
  async readAllRecords(run, objects, handlingByKey, files, notes) {
    let limit = DEFAULT_EXPORT_LIMIT;
    try {
      limit = (await getFindPage()).exportLimit || DEFAULT_EXPORT_LIMIT;
    } catch {
      // Find's page reports its own errors; its default limit applies here.
    }
    const masks = Object.keys(handlingByKey).filter((key) => handlingByKey[key] === HANDLING.MASK);
    const mask = masks.length ? createMasker(await browserSigner()) : null;
    const records = {};
    const stopped = [];
    const failed = [];
    for (const object of objects) {
      if (run !== this.run) {
        return records;
      }
      const fields = recordFields(object, handlingByKey);
      try {
        // eslint-disable-next-line no-await-in-loop
        const read = await this.readRecords(object, fields, limit);
        const masked = fields.filter(
          (name) => handlingByKey[`${object.objectName}.${name}`] === HANDLING.MASK
        );
        for (const row of read.rows) {
          for (const name of masked) {
            // eslint-disable-next-line no-await-in-loop
            row[name] = await mask(row[name]);
          }
        }
        const file = `data/${object.objectName}.csv`;
        files.push([
          file,
          toCsv(
            fields.map((name) => ({ label: name, path: name })),
            read.rows
          )
        ]);
        records[object.objectName] = { file, count: read.rows.length, stopped: read.stopped };
        if (read.stopped) {
          stopped.push(object.objectLabel);
        }
      } catch {
        failed.push(object.objectLabel);
      }
    }
    if (stopped.length) {
      notes.push(format(STOPPED, String(limit), stopped.join(', ')));
    }
    if (failed.length) {
      notes.push(format(RECORDS_FAILED, failed.join(', ')));
    }
    return records;
  }

  /**
   * One object's records: each chunk of fields (Find selects at most 20) is read a page at a
   * time in Id order, and the chunks are joined by Id. The first chunk decides which records.
   */
  async readRecords(object, fields, limit) {
    const byId = new Map();
    let stopped = false;
    const chunks = queryChunks(fields);
    for (let index = 0; index < chunks.length; index++) {
      const queryJson = JSON.stringify({ object: object.objectName, fields: chunks[index] });
      let afterId = null;
      let done = false;
      let seen = 0;
      while (!done && seen < limit) {
        // eslint-disable-next-line no-await-in-loop
        const page = await exportPage({ queryJson, afterId });
        for (const row of page.rows) {
          seen += 1;
          if (index === 0 && byId.size < limit) {
            byId.set(row.Id, { ...row });
          } else if (byId.has(row.Id)) {
            Object.assign(byId.get(row.Id), row);
          }
        }
        afterId = page.lastId;
        done = page.done;
        this.progressText = format(RECORDS_PROGRESS, object.objectLabel, String(byId.size));
      }
      if (index === 0) {
        stopped = !done || seen > limit;
      }
    }
    return { rows: [...byId.values()], stopped };
  }
}
