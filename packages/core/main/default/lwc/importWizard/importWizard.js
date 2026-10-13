import { LightningElement } from 'lwc';
import { parseCsv, toRecords, toCsv } from './csv';
import { isXlsx, readXlsx, XLSX_ERRORS } from './xlsx';

import canImport from '@salesforce/apex/ImportController.canImport';
import getTemplates from '@salesforce/apex/ImportController.getTemplates';
import suggestMapping from '@salesforce/apex/ImportController.suggestMapping';
import saveFile from '@salesforce/apex/ImportController.saveFile';
import createBatch from '@salesforce/apex/ImportController.createBatch';
import stageRows from '@salesforce/apex/ImportController.stageRows';
import startDryRun from '@salesforce/apex/ImportController.startDryRun';
import startCommit from '@salesforce/apex/ImportController.startCommit';
import getBatch from '@salesforce/apex/ImportController.getBatch';
import getRows from '@salesforce/apex/ImportController.getRows';
import saveRecurring from '@salesforce/apex/ImportController.saveRecurring';
import getEntityTargets from '@salesforce/apex/ImportController.getEntityTargets';
import getMatchFields from '@salesforce/apex/ImportController.getMatchFields';
import getLoadableObjects from '@salesforce/apex/ImportController.getLoadableObjects';
import createObjectTemplate from '@salesforce/apex/ImportController.createObjectTemplate';
import getObjectFields from '@salesforce/apex/ImportController.getObjectFields';
import getKeyFields from '@salesforce/apex/ImportController.getKeyFields';

import cardTitle from '@salesforce/label/c.Core_Import_CardTitle';
import stepTemplate from '@salesforce/label/c.Core_Import_StepTemplate';
import stepUpload from '@salesforce/label/c.Core_Import_StepUpload';
import stepColumns from '@salesforce/label/c.Core_Import_StepColumns';
import stepMatching from '@salesforce/label/c.Core_Import_StepMatching';
import stepPreview from '@salesforce/label/c.Core_Import_StepPreview';
import stepResults from '@salesforce/label/c.Core_Import_StepResults';
import nextButton from '@salesforce/label/c.Core_Import_NextButton';
import backButton from '@salesforce/label/c.Core_Import_BackButton';
import dryRunButton from '@salesforce/label/c.Core_Import_DryRunButton';
import commitButton from '@salesforce/label/c.Core_Import_CommitButton';
import startOverButton from '@salesforce/label/c.Core_Import_StartOverButton';
import downloadExceptionsButton from '@salesforce/label/c.Core_Import_DownloadExceptionsButton';
import uploadLabel from '@salesforce/label/c.Core_Import_UploadLabel';
import uploadHint from '@salesforce/label/c.Core_Import_UploadHint';
import columnHeader from '@salesforce/label/c.Core_Import_ColumnHeader';
import targetHeader from '@salesforce/label/c.Core_Import_TargetHeader';
import sampleHeader from '@salesforce/label/c.Core_Import_SampleHeader';
import doNotLoad from '@salesforce/label/c.Core_Import_DoNotLoad';
import matchingRuleLabel from '@salesforce/label/c.Core_Import_MatchingRuleLabel';
import matchingEmailHelp from '@salesforce/label/c.Core_Import_MatchingEmailHelp';
import matchingNamePostalHelp from '@salesforce/label/c.Core_Import_MatchingNamePostalHelp';
import matchingExternalIdHelp from '@salesforce/label/c.Core_Import_MatchingExternalIdHelp';
import readOnlyMessage from '@salesforce/label/c.Core_Import_ReadOnlyMessage';
import loadingAltText from '@salesforce/label/c.Core_Import_LoadingAltText';
import parsingMessage from '@salesforce/label/c.Core_Import_ParsingMessage';
import noHeaderRow from '@salesforce/label/c.Core_Import_NoHeaderRow';
import xlsxUnreadable from '@salesforce/label/c.Core_Import_XlsxUnreadable';
import xlsxUnsupportedBrowser from '@salesforce/label/c.Core_Import_XlsxUnsupportedBrowser';
import xlsxTooLarge from '@salesforce/label/c.Core_Import_XlsxTooLarge';
import originalTooLargeToKeep from '@salesforce/label/c.Core_Import_OriginalTooLargeToKeep';
import originalNotKept from '@salesforce/label/c.Core_Import_OriginalNotKept';
import recurringLabel from '@salesforce/label/c.Core_Import_RecurringLabel';
import recurringHelp from '@salesforce/label/c.Core_Import_RecurringHelp';
import sourceNameLabel from '@salesforce/label/c.Core_Import_SourceNameLabel';
import controlTotalsHeading from '@salesforce/label/c.Core_Import_ControlTotalsHeading';
import controlTotalsHelp from '@salesforce/label/c.Core_Import_ControlTotalsHelp';
import expectedCountLabel from '@salesforce/label/c.Core_Import_ExpectedCountLabel';
import expectedAmountLabel from '@salesforce/label/c.Core_Import_ExpectedAmountLabel';
import paymentMatchingHeading from '@salesforce/label/c.Core_Import_PaymentMatchingHeading';
import paymentMatchingHelp from '@salesforce/label/c.Core_Import_PaymentMatchingHelp';
import paymentMatchingLabel from '@salesforce/label/c.Core_Import_PaymentMatchingLabel';
import paymentMatchOrCreate from '@salesforce/label/c.Core_Import_PaymentMatchingMatchOrCreate';
import paymentAlwaysCreate from '@salesforce/label/c.Core_Import_PaymentMatchingAlwaysCreate';
import paymentMatchOnly from '@salesforce/label/c.Core_Import_PaymentMatchingMatchOnly';
import paymentNeverMatch from '@salesforce/label/c.Core_Import_PaymentMatchingNeverMatch';
import matchWindowLabel from '@salesforce/label/c.Core_Import_MatchWindowLabel';
import matchToleranceLabel from '@salesforce/label/c.Core_Import_MatchToleranceLabel';
import personMatchFieldLabel from '@salesforce/label/c.Core_Import_PersonMatchFieldLabel';
import organizationRuleLabel from '@salesforce/label/c.Core_Import_OrganizationRuleLabel';
import organizationNameHelp from '@salesforce/label/c.Core_Import_OrganizationNameHelp';
import organizationExternalIdHelp from '@salesforce/label/c.Core_Import_OrganizationExternalIdHelp';
import organizationMatchFieldLabel from '@salesforce/label/c.Core_Import_OrganizationMatchFieldLabel';
import noMatchFields from '@salesforce/label/c.Core_Import_NoMatchFields';
import matchFieldNotMapped from '@salesforce/label/c.Core_Import_MatchFieldNotMapped';
import severalMatchesLabel from '@salesforce/label/c.Core_Import_SeveralMatchesLabel';
import severalRejectOption from '@salesforce/label/c.Core_Import_SeveralRejectOption';
import severalRecentOption from '@salesforce/label/c.Core_Import_SeveralRecentOption';
import severalRejectHelp from '@salesforce/label/c.Core_Import_SeveralRejectHelp';
import severalRecentHelp from '@salesforce/label/c.Core_Import_SeveralRecentHelp';
import fileValuesHeading from '@salesforce/label/c.Core_Import_FileValuesHeading';
import fileValuesHelp from '@salesforce/label/c.Core_Import_FileValuesHelp';
import addFileValueButton from '@salesforce/label/c.Core_Import_AddFileValueButton';
import removeFileValueLabel from '@salesforce/label/c.Core_Import_RemoveFileValueLabel';
import fileValueTargetLabel from '@salesforce/label/c.Core_Import_FileValueTargetLabel';
import fileValueLabel from '@salesforce/label/c.Core_Import_FileValueLabel';
import targetFirstPersonField from '@salesforce/label/c.Core_Import_TargetFirstPersonField';
import targetSecondPersonField from '@salesforce/label/c.Core_Import_TargetSecondPersonField';
import targetOrganizationField from '@salesforce/label/c.Core_Import_TargetOrganizationField';
import recordIdFieldName from '@salesforce/label/c.Core_Import_RecordIdFieldName';
import matchOnlyLabel from '@salesforce/label/c.Core_Import_MatchOnlyLabel';
import matchOnlyHelp from '@salesforce/label/c.Core_Import_MatchOnlyHelp';
import loadObjectHeading from '@salesforce/label/c.Core_Import_LoadObjectHeading';
import loadObjectHelp from '@salesforce/label/c.Core_Import_LoadObjectHelp';
import loadObjectLabel from '@salesforce/label/c.Core_Import_LoadObjectLabel';
import loadObjectNameLabel from '@salesforce/label/c.Core_Import_LoadObjectNameLabel';
import loadObjectCreateButton from '@salesforce/label/c.Core_Import_LoadObjectCreateButton';
import lookupFieldLabel from '@salesforce/label/c.Core_Import_LookupFieldLabel';
import changesButton from '@salesforce/label/c.Core_Import_ChangesButton';
import changesButtonCount from '@salesforce/label/c.Core_Import_ChangesButtonCount';
import duplicateRulesLabel from '@salesforce/label/c.Core_Import_DuplicateRulesLabel';
import duplicateRulesHelp from '@salesforce/label/c.Core_Import_DuplicateRulesHelp';
import duplicateRulesNone from '@salesforce/label/c.Core_Import_DuplicateRulesNone';
import getChangedValues from '@salesforce/apex/ImportController.getChangedValues';
import openRetry from '@salesforce/apex/ImportController.openRetry';
import retryHeading from '@salesforce/label/c.Core_Import_RetryHeading';
import retryHelp from '@salesforce/label/c.Core_Import_RetryHelp';
import retryFileLabel from '@salesforce/label/c.Core_Import_RetryFileLabel';
import retryColumnsMissing from '@salesforce/label/c.Core_Import_RetryColumnsMissing';
import { INSERT, UPDATE, UPSERT, LOOKUP_REJECT } from 'c/importLoadOptions';

/** How many of the file's rows the column changes are previewed on (R-IT15). */
const CHANGE_SAMPLE_ROWS = 5;

/** Fills a label's {0} with a value. */
function format(label, value) {
  return label.replace('{0}', value);
}

/** A number as an input shows it, or empty. */
function numberText(value) {
  return value === null || value === undefined ? '' : String(value);
}

/** How often the wizard asks how a run is going. */
const POLL_INTERVAL_MS = 3000;
/** How many rows are sent to the server in one request. */
const STAGE_PAGE_SIZE = 500;
/**
 * The largest file kept as a Salesforce File. A bigger file still imports; only the copy of
 * the original is skipped, because sending it would risk the request's heap: it travels as
 * base64, a third larger, and is decoded on the server, against a 6 MB heap.
 */
const MAX_STORED_FILE_BYTES = 2500000;
/** How many values of each column the picker shows, so the choice can be checked by eye. */
const SAMPLE_VALUES = 3;

const IGNORE = 'Ignore';

/**
 * The row entities a module outside Core loads (R-IR6). Their columns are offered only from
 * the targets an installed module supplies: with none installed, Core offers no gift column
 * at all, and a suggested one becomes "Do not load" (the staged row still keeps the whole
 * original line). ADR-0062.
 */
const DEFERRED_ENTITY_PREFIXES = ['Gift.', 'Allocation.', 'SoftCredit.', 'Tribute.'];

const RULES = [
  { value: 'Email exact', help: matchingEmailHelp },
  { value: 'Name plus postal code', help: matchingNamePostalHelp },
  { value: 'External ID', help: matchingExternalIdHelp }
];

const EXTERNAL_ID = 'External ID';

/** How organizations are matched (R-IT2); each says what it risks. */
const ORGANIZATION_RULES = [
  { value: 'Name exact', help: organizationNameHelp },
  { value: EXTERNAL_ID, help: organizationExternalIdHelp }
];

/** What happens when several records match a row (R-IT9); rejecting is the default. */
const SEVERAL_REJECT = 'Reject the row';
const SEVERAL_CHOICES = [
  { value: SEVERAL_REJECT, label: severalRejectOption, help: severalRejectHelp },
  { value: 'Use the most recently changed', label: severalRecentOption, help: severalRecentHelp }
];

/** A person's attributes a value for every row may not set: every row would be one person. */
const PERSON_ATTRIBUTES_NOT_FOR_EVERY_ROW = ['FirstName', 'LastName', 'FullName', 'Email', 'Id'];

/** A column holding a Salesforce record ID matches that record (R-IT10). */
const RECORD_ID_TARGETS = [
  { value: 'Contact1.Id', label: format(targetFirstPersonField, recordIdFieldName) },
  { value: 'Contact2.Id', label: format(targetSecondPersonField, recordIdFieldName) },
  { value: 'Organization.Id', label: format(targetOrganizationField, recordIdFieldName) }
];

/** The row entity of a mapping that loads one object (R-IT12), and its record ID target. */
const RECORD_PREFIX = 'Record.';
const RECORD_ID = 'Record.Id';
/** How a lookup column names its parent unless told otherwise (R-IT13). */
const LOOKUP_BY_ID = 'Id';

/**
 * The import wizard (C-14): choose a mapping, upload a file, check the columns, choose how
 * rows are matched, dry run, commit, and see the result.
 *
 * The file is parsed here rather than on the server and sent up in pages, so a large file
 * never arrives as one request. Nothing is written until the administrator has seen a dry
 * run of the same file with the same mapping, which is the rule the whole screen is built
 * around. See docs/admin-guide/importing.md.
 */
export default class ImportWizard extends LightningElement {
  step = 1;
  loading = true;
  parsing = false;
  permitted = false;
  message;
  templates = [];
  templateId;
  /** Whether the chosen mapping is for a file that arrives regularly, and its name (R-IT6). */
  isRecurring = false;
  sourceName = '';
  matchingRule = 'Email exact';
  headers = [];
  records = [];
  columns = [];
  batch;
  rejectedRows = [];
  fileName;
  pollTimer;
  storeFileError;
  /** The columns an installed module loads, empty where none is (R-IR6). */
  entityTargets = [];
  /** The control totals for this file (R-IB10), kept as typed. */
  expectedCount = '';
  expectedAmount = '';
  /** How this mapping's gifts are matched to scheduled payments (R-IT7), as the template holds it. */
  paymentMatching = 'Match or create';
  matchDateWindowDays = '';
  matchAmountTolerance = '';
  /** How the chosen mapping matches people and organizations (R-IT2, R-IT8, R-IT9). */
  personMatchField = '';
  organizationRule = 'Name exact';
  organizationMatchField = '';
  severalMatches = SEVERAL_REJECT;
  /**
   * The fields matching accepts, per object (R-IT8), and the fields of people and
   * organizations a column can be mapped to besides the fixed list (R-IT11).
   */
  matchFields = {
    contact: [],
    account: [],
    fixedTargets: [],
    personFields: [],
    organizationFields: []
  };
  /** Whether this file only matches and creates nobody (R-IB15). */
  matchOnly = false;
  /** Whether the org's duplicate rules are asked too, as the mapping holds it (R-IT16). */
  useDuplicateRules = false;
  /** The column whose changes are being edited, if any (R-IT15). */
  editingSource;
  /** Each changed value of a finished dry run's first rows (R-IT15). */
  changedValues = [];
  /** Values for every row of this file (R-IB14), as typed: { key, target, value }. */
  fileValues = [];
  fileValueCounter = 0;
  /** A mapping that loads one object (R-IT12, R-IT13): its fields, and how each row loads. */
  objectFields = [];
  keyFields = [];
  loadOperation = INSERT;
  loadMatchField = '';
  lookupNotFound = LOOKUP_REJECT;
  /** The new one-object mapping being made on the first step. */
  choosingObject = false;
  loadableObjects = [];
  newObjectName;
  newTemplateName = '';

  labels = {
    cardTitle,
    stepTemplate,
    stepUpload,
    stepColumns,
    stepMatching,
    stepPreview,
    stepResults,
    nextButton,
    backButton,
    dryRunButton,
    commitButton,
    startOverButton,
    downloadExceptionsButton,
    uploadLabel,
    uploadHint,
    columnHeader,
    targetHeader,
    sampleHeader,
    matchingRuleLabel,
    readOnlyMessage,
    loadingAltText,
    parsingMessage,
    recurringLabel,
    recurringHelp,
    sourceNameLabel,
    controlTotalsHeading,
    controlTotalsHelp,
    expectedCountLabel,
    expectedAmountLabel,
    paymentMatchingHeading,
    paymentMatchingHelp,
    paymentMatchingLabel,
    matchWindowLabel,
    matchToleranceLabel,
    personMatchFieldLabel,
    organizationRuleLabel,
    organizationMatchFieldLabel,
    noMatchFields,
    severalMatchesLabel,
    fileValuesHeading,
    fileValuesHelp,
    addFileValueButton,
    removeFileValueLabel,
    fileValueTargetLabel,
    fileValueLabel,
    matchOnlyLabel,
    matchOnlyHelp,
    loadObjectHeading,
    loadObjectHelp,
    loadObjectLabel,
    loadObjectNameLabel,
    loadObjectCreateButton,
    lookupFieldLabel,
    duplicateRulesLabel,
    duplicateRulesHelp,
    duplicateRulesNone,
    retryHeading,
    retryHelp,
    retryFileLabel
  };

  async connectedCallback() {
    try {
      this.permitted = await canImport();
      if (this.permitted) {
        this.templates = await getTemplates();
        this.entityTargets = (await getEntityTargets()) || [];
        const fields = await getMatchFields();
        this.matchFields = {
          contact: (fields && fields.contact) || [],
          account: (fields && fields.account) || [],
          fixedTargets: (fields && fields.fixedTargets) || [],
          personFields: (fields && fields.personFields) || [],
          organizationFields: (fields && fields.organizationFields) || [],
          contactRules: fields ? fields.contactRules : undefined,
          accountRules: fields ? fields.accountRules : undefined
        };
        if (this.templates.length > 0) {
          this.selectTemplate(this.templates[0].id);
        }
      }
    } catch (error) {
      this.message = this.errorText(error);
    } finally {
      this.loading = false;
    }
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  // ---------------------------------------------------------------------------------------
  // Step one: which mapping
  // ---------------------------------------------------------------------------------------

  get templateOptions() {
    return this.templates.map((template) => ({ label: template.name, value: template.id }));
  }

  get selectedTemplate() {
    return this.templates.find((template) => template.id === this.templateId);
  }

  get templateDescription() {
    return this.selectedTemplate ? this.selectedTemplate.description : '';
  }

  handleTemplateChange(event) {
    this.selectTemplate(event.detail.value);
  }

  selectTemplate(templateId) {
    this.templateId = templateId;
    const template = this.selectedTemplate;
    if (template && template.matchingRule) {
      this.matchingRule = template.matchingRule;
    }
    this.isRecurring = Boolean(template && template.isRecurring);
    this.sourceName = (template && template.sourceName) || '';
    this.paymentMatching = (template && template.paymentMatching) || 'Match or create';
    this.matchDateWindowDays = numberText(template && template.matchDateWindowDays);
    this.matchAmountTolerance = numberText(template && template.matchAmountTolerance);
    this.personMatchField = (template && template.personMatchField) || '';
    this.organizationRule = (template && template.organizationRule) || 'Name exact';
    this.organizationMatchField = (template && template.organizationMatchField) || '';
    this.severalMatches = (template && template.severalMatches) || SEVERAL_REJECT;
    this.useDuplicateRules = Boolean(template && template.useDuplicateRules);
    this.loadOperation = (template && template.loadOperation) || INSERT;
    this.loadMatchField = (template && template.loadMatchField) || '';
    this.lookupNotFound = (template && template.lookupNotFound) || LOOKUP_REJECT;
    this.objectFields = [];
    this.keyFields = [];
    // A mapping saved before a field could be chosen starts with the first one offered.
    if (this.isPersonExternalId && !this.personMatchField && this.personFields.length > 0) {
      this.personMatchField = this.personFields[0].value;
    }
  }

  /** Whether the chosen mapping loads one object rather than people (R-IT12). */
  get loadsOneObject() {
    return Boolean(this.selectedTemplate && this.selectedTemplate.targetObject);
  }

  get loadsPeople() {
    return !this.loadsOneObject;
  }

  /** The operations the chosen object allows: Update only for people (R-IT14). */
  get loadOperations() {
    return (this.selectedTemplate && this.selectedTemplate.loadOperations) || [];
  }

  /** Opens the new one-object mapping, asking for the objects the user may load (R-IT14). */
  async handleChooseObject() {
    this.message = undefined;
    this.choosingObject = true;
    if (this.loadableObjects.length > 0) {
      return;
    }
    try {
      this.loadableObjects = (await getLoadableObjects()) || [];
    } catch (error) {
      this.message = this.errorText(error);
    }
  }

  get objectOptions() {
    return this.loadableObjects.map((object) => ({ label: object.label, value: object.value }));
  }

  handleNewObjectChange(event) {
    this.newObjectName = event.detail.value;
  }

  handleNewTemplateNameChange(event) {
    this.newTemplateName = event.target.value;
  }

  get cannotCreateObjectTemplate() {
    return !this.newObjectName || !String(this.newTemplateName || '').trim();
  }

  /** Creates the one-object mapping and chooses it. */
  async handleCreateObjectTemplate() {
    this.message = undefined;
    try {
      const created = await createObjectTemplate({
        name: this.newTemplateName,
        objectName: this.newObjectName
      });
      this.templates = this.templates.concat([created]);
      this.selectTemplate(created.id);
      this.choosingObject = false;
      this.newObjectName = undefined;
      this.newTemplateName = '';
    } catch (error) {
      this.message = this.errorText(error);
    }
  }

  handleRecurringChange(event) {
    this.isRecurring = event.target.checked;
  }

  handleSourceNameChange(event) {
    this.sourceName = event.target.value;
  }

  /**
   * Leaves step one, saving the recurring mark first when it changed. The server refuses a
   * recurring file with no source name, and the wizard stays on this step to say so.
   */
  async handleTemplateNext() {
    const template = this.selectedTemplate || {};
    const changed =
      this.isRecurring !== Boolean(template.isRecurring) ||
      (this.isRecurring && this.sourceName !== (template.sourceName || ''));
    if (changed) {
      try {
        await saveRecurring({
          templateId: this.templateId,
          isRecurring: this.isRecurring,
          sourceName: this.sourceName
        });
        const saved = { isRecurring: this.isRecurring, sourceName: this.sourceName };
        this.templates = this.templates.map((each) => {
          return each.id === this.templateId ? { ...each, ...saved } : each;
        });
      } catch (error) {
        this.message = this.errorText(error);
        return;
      }
    }
    this.handleNext();
  }

  // ---------------------------------------------------------------------------------------
  // Step two: the file
  // ---------------------------------------------------------------------------------------

  async handleFileChange(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) {
      return;
    }
    this.message = undefined;
    this.parsing = true;
    this.fileName = file.name;
    try {
      const rows = isXlsx(file.name)
        ? await this.readWorkbook(file)
        : parseCsv(await this.readText(file));
      const { headers, records } = toRecords(rows);
      if (headers.length === 0 || records.length === 0) {
        this.message = noHeaderRow;
        return;
      }
      this.headers = headers;
      this.records = records;
      await this.buildColumns(file);
      this.step = 3;
    } catch (error) {
      this.message = this.errorText(error);
    } finally {
      this.parsing = false;
    }
  }

  readText(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(reader.error);
      reader.readAsText(file);
    });
  }

  /** The first sheet of an Excel workbook, as rows; a file it cannot read says what to do. */
  async readWorkbook(file) {
    const buffer = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(reader.error);
      reader.readAsArrayBuffer(file);
    });
    try {
      return await readXlsx(buffer);
    } catch (error) {
      const sentences = {
        [XLSX_ERRORS.unsupportedBrowser]: xlsxUnsupportedBrowser,
        [XLSX_ERRORS.tooLarge]: xlsxTooLarge
      };
      throw new Error(sentences[error.reason] || xlsxUnreadable);
    }
  }

  readBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      // A data URL is "data:<type>;base64,<content>"; only the content is sent.
      reader.onload = () => resolve(String(reader.result).split(',')[1]);
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
  }

  async buildColumns(file) {
    if (this.loadsOneObject && this.objectFields.length === 0) {
      // The object's fields and keys, from the running user's describe (R-IT12).
      const [fields, keys] = await Promise.all([
        getObjectFields({ templateId: this.templateId }),
        getKeyFields({ templateId: this.templateId })
      ]);
      this.objectFields = fields || [];
      this.keyFields = keys || [];
    }
    const suggested = await suggestMapping({ templateId: this.templateId, headers: this.headers });
    const targets = {};
    const lookups = {};
    const changes = {};
    const parsed = JSON.parse(suggested || '{}');
    const offered = new Set(this.targetOptions.map((option) => option.value));
    (parsed.columns || []).forEach((column) => {
      targets[column.source] = this.isOfferedTarget(column.target, offered)
        ? column.target
        : IGNORE;
      lookups[column.source] = column.lookupField;
      changes[column.source] = column.transforms || [];
    });
    this.columns = this.headers.map((heading) => ({
      key: heading,
      source: heading,
      target: targets[heading] || IGNORE,
      lookupField: lookups[heading] || LOOKUP_BY_ID,
      transforms: changes[heading] || [],
      samples: this.records
        .slice(0, SAMPLE_VALUES)
        .map((record) => record[heading])
        .filter((value) => value && value.length > 0)
        .join(', ')
    }));
    this.pendingFile = file;
  }

  // ---------------------------------------------------------------------------------------
  // Step three: the columns
  // ---------------------------------------------------------------------------------------

  get targetOptions() {
    if (this.loadsOneObject) {
      // The object's own fields, from describe (R-IT12).
      return [{ label: doNotLoad, value: IGNORE }].concat(
        this.objectFields.map((field) => ({ label: field.label, value: field.value }))
      );
    }
    const all = [{ label: doNotLoad, value: IGNORE }]
      .concat(this.matchFields.fixedTargets)
      .concat(RECORD_ID_TARGETS)
      .concat(this.matchFieldTargets)
      .concat(this.ownFieldTargets)
      .concat(this.entityTargets.map((target) => ({ value: target.value, label: target.label })));
    // A field offered twice (a fixed column, or an ID field that is also writable) is listed
    // once, under its first name.
    const seen = new Set();
    return all.filter((option) => {
      const key = option.value.toLowerCase();
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
  }

  /** The org's own fields of people and organizations the user may write (R-IT11). */
  get ownFieldTargets() {
    const people = this.matchFields.personFields.flatMap((field) => [
      { value: `Contact1.${field.value}`, label: format(targetFirstPersonField, field.label) },
      { value: `Contact2.${field.value}`, label: format(targetSecondPersonField, field.label) }
    ]);
    const organizations = this.matchFields.organizationFields.map((field) => ({
      value: `Organization.${field.value}`,
      label: format(targetOrganizationField, field.label)
    }));
    return people.concat(organizations);
  }

  /** The fields people are matched on, from the object this mapping stores them on (R-IT3). */
  get personFields() {
    const template = this.selectedTemplate;
    return template && template.personMode === 'Person Accounts'
      ? this.matchFields.account
      : this.matchFields.contact;
  }

  /**
   * A column can hold an ID a row is matched on (R-IT8): each field matching accepts is
   * offered for either person and for the organization.
   */
  get matchFieldTargets() {
    const people = this.personFields.flatMap((field) => [
      { value: `Contact1.${field.value}`, label: format(targetFirstPersonField, field.label) },
      { value: `Contact2.${field.value}`, label: format(targetSecondPersonField, field.label) }
    ]);
    const organizations = this.matchFields.account.map((field) => ({
      value: `Organization.${field.value}`,
      label: format(targetOrganizationField, field.label)
    }));
    return people.concat(organizations);
  }

  /**
   * Whether a suggested target can be shown as chosen. A column a module would load is
   * suggested only while that module offers it; without one it is left as "Do not load".
   */
  isOfferedTarget(target, offered) {
    if (this.loadsOneObject) {
      return offered.has(target);
    }
    const deferred = DEFERRED_ENTITY_PREFIXES.some((prefix) => (target || '').startsWith(prefix));
    return !deferred || offered.has(target);
  }

  /** Whether any column is mapped to something a module outside Core loads. */
  get mapsGift() {
    return this.columns.some((column) =>
      DEFERRED_ENTITY_PREFIXES.some((prefix) => (column.target || '').startsWith(prefix))
    );
  }

  /** The amount control total can be checked only where a module reads gift amounts. */
  get showExpectedAmount() {
    return this.entityTargets.length > 0 && this.mapsGift;
  }

  handleExpectedCountChange(event) {
    this.expectedCount = event.target.value;
  }

  handleExpectedAmountChange(event) {
    this.expectedAmount = event.target.value;
  }

  get paymentMatchingOptions() {
    return [
      { value: 'Match or create', label: paymentMatchOrCreate },
      { value: 'Always create', label: paymentAlwaysCreate },
      { value: 'Match only', label: paymentMatchOnly },
      { value: 'Never match', label: paymentNeverMatch }
    ];
  }

  handlePaymentMatchingChange(event) {
    this.paymentMatching = event.detail.value;
  }

  handleMatchWindowChange(event) {
    this.matchDateWindowDays = event.target.value;
  }

  handleMatchToleranceChange(event) {
    this.matchAmountTolerance = event.target.value;
  }

  /** What is sent with the batch besides the mapping; an empty box is no control total. */
  get batchOptions() {
    const count = String(this.expectedCount || '').trim();
    const amount = this.showExpectedAmount ? String(this.expectedAmount || '').trim() : '';
    const options = {
      expectedCount: count === '' ? null : Number(count),
      expectedAmount: amount === '' ? null : Number(amount),
      matching: {
        personMatchField: this.isPersonExternalId ? this.personMatchField : null,
        organizationRule: this.organizationRule,
        organizationMatchField: this.isOrganizationExternalId ? this.organizationMatchField : null,
        severalMatches: this.severalMatches
      }
    };
    if (this.loadsPeople && this.useDuplicateRules) {
      // Sent only when ticked: the server reads an absent choice as unticked (R-IT16).
      options.matching.useDuplicateRules = true;
    }
    const fileValues = this.fileValues
      .filter((each) => each.target && String(each.value || '').trim() !== '')
      .map((each) => ({ target: each.target, value: String(each.value).trim() }));
    if (fileValues.length > 0) {
      options.fileValues = fileValues;
    }
    if (this.matchOnly) {
      options.matchOnly = true;
    }
    if (this.loadsOneObject) {
      // A one-object mapping's load choices, saved on the template (R-IT12, R-IT13).
      options.load = {
        operation: this.loadOperation,
        matchField: this.loadOperation === UPSERT ? this.loadMatchField : null,
        lookupNotFound: this.lookupNotFound,
        severalMatches: this.severalMatches
      };
    }
    if (this.showExpectedAmount) {
      // Shown only where a module loads gifts, and saved on the template only then (R-IT7).
      const days = String(this.matchDateWindowDays || '').trim();
      const tolerance = String(this.matchAmountTolerance || '').trim();
      Object.assign(options, {
        savePaymentMatching: true,
        paymentMatching: this.paymentMatching,
        matchDateWindowDays: days === '' ? null : Number(days),
        matchAmountTolerance: tolerance === '' ? null : Number(tolerance)
      });
    }
    return JSON.stringify(options);
  }

  handleTargetChange(event) {
    const source = event.target.dataset.source;
    const target = event.detail.value;
    this.columns = this.columns.map((column) => {
      return column.source === source ? { ...column, target, lookupField: LOOKUP_BY_ID } : column;
    });
  }

  /** How a lookup column names its parent (R-IT13). */
  handleLookupFieldChange(event) {
    const source = event.target.dataset.source;
    const lookupField = event.detail.value;
    this.columns = this.columns.map((column) => {
      return column.source === source ? { ...column, lookupField } : column;
    });
  }

  /** The columns as the picker shows them, with a lookup's second picker where it has one. */
  get columnRows() {
    return this.columns.map((column) => {
      const field = this.loadsOneObject
        ? this.objectFields.find((each) => each.value === column.target)
        : undefined;
      const isLookup = Boolean(field && field.isLookup);
      const changeCount = (column.transforms || []).length;
      return {
        ...column,
        changesLabel: changeCount > 0 ? format(changesButtonCount, changeCount) : changesButton,
        isLookup,
        lookupOptions: isLookup
          ? (field.lookupFields || []).map((each) => ({ label: each.label, value: each.value }))
          : []
      };
    });
  }

  get mappingDocument() {
    return JSON.stringify({
      version: 1,
      columns: this.columns.map((column) => {
        const mapped = { source: column.source, target: column.target };
        if (this.loadsOneObject && column.lookupField && column.lookupField !== LOOKUP_BY_ID) {
          mapped.lookupField = column.lookupField;
        }
        if (column.transforms && column.transforms.length > 0) {
          mapped.transforms = column.transforms;
        }
        return mapped;
      }),
      defaults: []
    });
  }

  /** Opens the changes of one column, or closes them when they are open (R-IT15). */
  handleEditChanges(event) {
    const source = event.target.dataset.source;
    this.editingSource = this.editingSource === source ? undefined : source;
  }

  handleChangesChange(event) {
    const { source, transforms } = event.detail;
    this.columns = this.columns.map((column) => {
      return column.source === source ? { ...column, transforms } : column;
    });
  }

  handleChangesDone() {
    this.editingSource = undefined;
  }

  get editingColumn() {
    return this.columns.find((column) => column.source === this.editingSource);
  }

  /** The file's first rows, for the preview of a column's changes. */
  get changeSampleRows() {
    return this.records.slice(0, CHANGE_SAMPLE_ROWS);
  }

  /** Whether the org's duplicate rules are asked too (R-IT16); saved with the mapping. */
  handleDuplicateRulesChange(event) {
    this.useDuplicateRules = event.target.checked;
  }

  /**
   * True when the box is ticked and no rule is switched on for people (or, where the file has
   * organizations, for them), so the box would change nothing. Unknown is not warned about.
   */
  get duplicateRulesMissing() {
    const template = this.selectedTemplate;
    const people =
      template && template.personMode === 'Person Accounts'
        ? this.matchFields.accountRules
        : this.matchFields.contactRules;
    const organizations = this.mapsOrganization ? this.matchFields.accountRules : true;
    return this.useDuplicateRules && (people === false || organizations === false);
  }

  /**
   * Whether a one-object mapping can load (R-IT12): a column on the object, the record ID
   * under an update, and under an upsert a chosen key field that a column feeds.
   */
  get mapsTheObject() {
    const targets = this.columns.map((column) => column.target || '');
    if (!targets.some((target) => target.startsWith(RECORD_PREFIX))) {
      return false;
    }
    if (this.loadOperation === UPDATE) {
      return targets.includes(RECORD_ID);
    }
    if (this.loadOperation === UPSERT) {
      const key = (RECORD_PREFIX + this.loadMatchField).toLowerCase();
      return Boolean(this.loadMatchField) && targets.some((target) => target.toLowerCase() === key);
    }
    return true;
  }

  handleLoadOptionsChange(event) {
    this.loadOperation = event.detail.operation;
    this.loadMatchField = event.detail.matchField || '';
    this.lookupNotFound = event.detail.lookupNotFound;
  }

  get mapsSomebody() {
    return this.columns.some((column) =>
      [
        'Contact1.LastName',
        'Contact1.FullName',
        'Contact1.Email',
        'Contact2.LastName',
        'Contact2.FullName',
        'Contact2.Email',
        'Organization.Name'
      ].includes(column.target)
    );
  }

  // ---------------------------------------------------------------------------------------
  // Step four: the matching rule
  // ---------------------------------------------------------------------------------------

  get ruleOptions() {
    return RULES.map((rule) => ({ label: rule.value, value: rule.value }));
  }

  get ruleHelp() {
    const found = RULES.find((rule) => rule.value === this.matchingRule);
    return found ? found.help : '';
  }

  handleRuleChange(event) {
    this.matchingRule = event.detail.value;
    if (this.isPersonExternalId && !this.personMatchField && this.personFields.length > 0) {
      this.personMatchField = this.personFields[0].value;
    }
  }

  get isPersonExternalId() {
    return this.matchingRule === EXTERNAL_ID;
  }

  get personFieldOptions() {
    return this.personFields.map((field) => ({ label: field.label, value: field.value }));
  }

  get hasPersonFields() {
    return this.personFields.length > 0;
  }

  handlePersonFieldChange(event) {
    this.personMatchField = event.detail.value;
  }

  /** A warning when the chosen ID field is not a column, so nobody would be matched (R-IT8). */
  get personFieldWarning() {
    return this.unmappedWarning(this.isPersonExternalId, this.personMatchField, [
      'Contact1',
      'Contact2'
    ]);
  }

  /** The organization rule is offered only where the mapping names an organization. */
  get mapsOrganization() {
    return this.columns.some((column) => (column.target || '').startsWith('Organization.'));
  }

  get organizationRuleOptions() {
    return ORGANIZATION_RULES.map((rule) => ({ label: rule.value, value: rule.value }));
  }

  get organizationRuleHelp() {
    const found = ORGANIZATION_RULES.find((rule) => rule.value === this.organizationRule);
    return found ? found.help : '';
  }

  handleOrganizationRuleChange(event) {
    this.organizationRule = event.detail.value;
    const fields = this.matchFields.account;
    if (this.isOrganizationExternalId && !this.organizationMatchField && fields.length > 0) {
      this.organizationMatchField = fields[0].value;
    }
  }

  get isOrganizationExternalId() {
    return this.mapsOrganization && this.organizationRule === EXTERNAL_ID;
  }

  get organizationFieldOptions() {
    return this.matchFields.account.map((field) => ({ label: field.label, value: field.value }));
  }

  get hasOrganizationFields() {
    return this.matchFields.account.length > 0;
  }

  handleOrganizationFieldChange(event) {
    this.organizationMatchField = event.detail.value;
  }

  get organizationFieldWarning() {
    return this.unmappedWarning(this.isOrganizationExternalId, this.organizationMatchField, [
      'Organization'
    ]);
  }

  unmappedWarning(applies, field, entities) {
    if (!applies || !field) {
      return '';
    }
    const targets = entities.map((entity) => `${entity}.${field}`);
    const mapped = this.columns.some((column) => targets.includes(column.target));
    return mapped ? '' : matchFieldNotMapped;
  }

  get severalOptions() {
    return SEVERAL_CHOICES.map((choice) => ({ label: choice.label, value: choice.value }));
  }

  get severalHelp() {
    const found = SEVERAL_CHOICES.find((choice) => choice.value === this.severalMatches);
    return found ? found.help : '';
  }

  handleSeveralChange(event) {
    this.severalMatches = event.detail.value;
  }

  // ---------------------------------------------------------------------------------------
  // Values for every row of the file (R-IB14)
  // ---------------------------------------------------------------------------------------

  /**
   * What a value for every row can be for: what a column can, except what names or finds a
   * person, since every row would then be one person.
   */
  get fileValueTargetOptions() {
    if (this.loadsOneObject) {
      // Every row would name the same record (R-IT12).
      const key = this.loadOperation === UPSERT ? RECORD_PREFIX + this.loadMatchField : null;
      return this.targetOptions.filter(
        (option) =>
          option.value !== IGNORE &&
          option.value !== RECORD_ID &&
          (!key || option.value.toLowerCase() !== key.toLowerCase())
      );
    }
    const personField = this.isPersonExternalId ? this.personMatchField : null;
    return this.targetOptions.filter((option) => {
      if (option.value === IGNORE) {
        return false;
      }
      const [entity, attribute] = option.value.split('.');
      if (entity !== 'Contact1' && entity !== 'Contact2') {
        return true;
      }
      return !PERSON_ATTRIBUTES_NOT_FOR_EVERY_ROW.includes(attribute) && attribute !== personField;
    });
  }

  /** Whether this file only matches and creates nobody (R-IB15); for this file only. */
  handleMatchOnlyChange(event) {
    this.matchOnly = event.target.checked;
  }

  handleAddFileValue() {
    this.fileValueCounter += 1;
    this.fileValues = this.fileValues.concat({
      key: `value-${this.fileValueCounter}`,
      target: '',
      value: ''
    });
  }

  handleRemoveFileValue(event) {
    const key = event.target.dataset.key;
    this.fileValues = this.fileValues.filter((each) => each.key !== key);
  }

  handleFileValueTargetChange(event) {
    this.updateFileValue(event.target.dataset.key, { target: event.detail.value });
  }

  handleFileValueChange(event) {
    this.updateFileValue(event.target.dataset.key, { value: event.target.value });
  }

  updateFileValue(key, change) {
    this.fileValues = this.fileValues.map((each) => {
      return each.key === key ? { ...each, ...change } : each;
    });
  }

  // ---------------------------------------------------------------------------------------
  // Steps five and six: the dry run, the commit, the result
  // ---------------------------------------------------------------------------------------

  async handleDryRun() {
    this.message = undefined;
    this.loading = true;
    try {
      const fileId = await this.storeOriginal();
      this.batch = await createBatch({
        templateId: this.templateId,
        fileId,
        fileName: this.fileName,
        mappingDocument: this.mappingDocument,
        matchingRule: this.matchingRule,
        optionsJson: this.batchOptions
      });
      await this.stageAllRows();
      this.batch = await startDryRun({ batchId: this.batch.id });
      this.step = 5;
      this.startPolling();
    } catch (error) {
      this.message = this.errorText(error);
    } finally {
      this.loading = false;
    }
  }

  async storeOriginal() {
    const file = this.pendingFile;
    this.storeFileError = undefined;
    if (!file) {
      return null;
    }
    if (file.size > MAX_STORED_FILE_BYTES) {
      this.storeFileError = originalTooLargeToKeep;
      return null;
    }
    try {
      return await saveFile({ fileName: file.name, base64Content: await this.readBase64(file) });
    } catch (storeError) {
      // Keeping a copy of the file is not worth failing an import over: the import goes
      // ahead and the batch simply has no link back to the original.
      this.storeFileError = format(originalNotKept, this.errorText(storeError));
      return null;
    }
  }

  async stageAllRows() {
    for (let start = 0; start < this.records.length; start += STAGE_PAGE_SIZE) {
      const page = this.records.slice(start, start + STAGE_PAGE_SIZE);
      // Sequential on purpose: the row numbers have to arrive in file order.
      // eslint-disable-next-line no-await-in-loop
      await stageRows({
        batchId: this.batch.id,
        rowsJson: JSON.stringify(page),
        firstRowNumber: start + 2
      });
    }
  }

  async handleCommit() {
    this.message = undefined;
    this.loading = true;
    try {
      this.batch = await startCommit({ batchId: this.batch.id });
      this.step = 6;
      this.startPolling();
    } catch (error) {
      this.message = this.errorText(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Retries the import's fixed rejected rows into it (R-IB17): the file must carry every
   * column of the original, its rows are staged after the import's own and previewed, and
   * the commit then replaces the rejected rows with them.
   */
  async handleRetryFile(event) {
    const file = event.target.files && event.target.files[0];
    if (!file || !this.batch) {
      return;
    }
    this.message = undefined;
    this.loading = true;
    try {
      const rows = isXlsx(file.name)
        ? await this.readWorkbook(file)
        : parseCsv(await this.readText(file));
      const { headers, records } = toRecords(rows);
      if (headers.length === 0 || records.length === 0) {
        this.message = noHeaderRow;
        return;
      }
      const missing = this.headers.filter((heading) => !headers.includes(heading));
      if (missing.length > 0) {
        this.message = format(retryColumnsMissing, missing.join(', '));
        return;
      }
      this.batch = await openRetry({ batchId: this.batch.id });
      this.records = records;
      await this.stageAllRows();
      this.batch = await startDryRun({ batchId: this.batch.id });
      this.rejectedRows = [];
      this.changedValues = [];
      this.step = 5;
      this.startPolling();
    } catch (error) {
      this.message = this.errorText(error);
    } finally {
      this.loading = false;
    }
  }

  startPolling() {
    this.stopPolling();
    this.pollTimer = setInterval(() => this.refresh(), POLL_INTERVAL_MS);
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  async refresh() {
    if (!this.batch) {
      return;
    }
    try {
      this.batch = await getBatch({ batchId: this.batch.id });
      if (this.batch && this.batch.isFinished) {
        this.stopPolling();
        this.rejectedRows = await getRows({
          batchId: this.batch.id,
          status: 'Rejected',
          offsetRows: 0
        });
        // A dry run shows each value a column's changes changed, before and after (R-IT15).
        this.changedValues = this.batch.isDryRun
          ? (await getChangedValues({ batchId: this.batch.id })) || []
          : [];
      }
    } catch (error) {
      this.stopPolling();
      this.message = this.errorText(error);
    }
  }

  /**
   * Hands the rejected rows back as a CSV the administrator can fix in a spreadsheet, with
   * the reason on each one so the fix is obvious.
   */
  handleDownloadExceptions() {
    const headers = ['Row'].concat(this.headers).concat(['Reason']);
    const records = this.rejectedRows.map((row) => {
      const values = row.values ? JSON.parse(row.values) : {};
      const record = { Row: row.rowNumber, Reason: row.errorMessage };
      this.headers.forEach((heading) => {
        record[heading] = values[heading] || '';
      });
      return record;
    });
    const text = toCsv(headers, records);
    const link = document.createElement('a');
    link.href = `data:text/csv;charset=utf-8,${encodeURIComponent(text)}`;
    link.download = `${this.batch ? this.batch.name : 'import'}-exceptions.csv`;
    link.click();
  }

  handleStartOver() {
    this.stopPolling();
    this.step = 1;
    this.batch = undefined;
    this.rejectedRows = [];
    this.headers = [];
    this.records = [];
    this.columns = [];
    this.fileName = undefined;
    this.pendingFile = undefined;
    this.message = undefined;
    this.expectedCount = '';
    this.expectedAmount = '';
    this.fileValues = [];
    this.matchOnly = false;
    this.changedValues = [];
    this.editingSource = undefined;
  }

  // ---------------------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------------------

  handleNext() {
    this.message = undefined;
    this.step = Math.min(this.step + 1, 6);
  }

  handleBack() {
    this.message = undefined;
    if (this.step === 5) {
      // Back from a finished dry run: the next dry run is a new batch, so a changed control
      // total or mapping is checked afresh (R-IB10).
      this.stopPolling();
      this.batch = undefined;
      this.rejectedRows = [];
      this.changedValues = [];
    }
    this.step = Math.max(this.step - 1, 1);
  }

  get isStepTemplate() {
    return this.step === 1;
  }

  get isStepUpload() {
    return this.step === 2;
  }

  get isStepColumns() {
    return this.step === 3;
  }

  get isStepMatching() {
    return this.step === 4;
  }

  get isStepPreview() {
    return this.step === 5;
  }

  get isStepResults() {
    return this.step === 6;
  }

  get showResults() {
    return this.step >= 5;
  }

  get canGoBack() {
    return (
      (this.step > 1 && this.step < 5) ||
      // A retry's preview belongs to a committed import, so there is no step to go back to.
      (this.step === 5 && Boolean(this.batch && this.batch.isFinished && !this.batch.retrying))
    );
  }

  /** A finished import whose fixed rejected rows may be retried into it (R-IB17). */
  get showRetry() {
    return this.step === 6 && Boolean(this.batch && this.batch.isFinished && this.batch.canRetry);
  }

  get cannotLeaveTemplateStep() {
    return !this.templateId;
  }

  get showReadOnlyNotice() {
    return !this.loading && !this.permitted;
  }

  /** An External ID rule needs a field to match on before anything can be matched (R-IT8). */
  get cannotDryRun() {
    if (this.loadsOneObject) {
      return !this.mapsTheObject || this.records.length === 0;
    }
    return (
      !this.mapsSomebody ||
      this.records.length === 0 ||
      (this.isPersonExternalId && !this.personMatchField) ||
      (this.isOrganizationExternalId && !this.organizationMatchField)
    );
  }

  get cannotCommit() {
    return (
      !this.batch ||
      this.batch.status !== 'Dry run complete' ||
      this.batch.controlTotalsAgree === false
    );
  }

  get hasMessage() {
    return Boolean(this.message);
  }

  get showWizard() {
    return this.permitted && !this.loading;
  }

  errorText(error) {
    if (!error) {
      return '';
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message || String(error);
  }
}
