import { LightningElement, wire } from 'lwc';
import Toast from 'lightning/toast';
import { refreshApex } from '@salesforce/apex';
import getTemplates from '@salesforce/apex/ReceiptController.getTemplates';
import getCanManageTemplates from '@salesforce/apex/ReceiptController.getCanManageTemplates';
import restoreDefaultTemplates from '@salesforce/apex/ReceiptController.restoreDefaultTemplates';
import saveTemplate from '@salesforce/apex/ReceiptController.saveTemplate';
import previewTemplate from '@salesforce/apex/ReceiptController.previewTemplate';
import activateTemplate from '@salesforce/apex/ReceiptController.activateTemplate';
import getRuns from '@salesforce/apex/ReceiptController.getRuns';
import getDefaultStatementYear from '@salesforce/apex/ReceiptController.getDefaultStatementYear';
import startStatementRun from '@salesforce/apex/ReceiptController.startStatementRun';

import TEMPLATES_TAB from '@salesforce/label/c.Giving_Receipt_TemplatesTab';
import STATEMENTS_TAB from '@salesforce/label/c.Giving_Receipt_StatementsTab';
import NO_TEMPLATES from '@salesforce/label/c.Giving_Receipt_NoTemplates';
import RESTORE from '@salesforce/label/c.Giving_Receipt_RestoreButton';
import READ_ONLY from '@salesforce/label/c.Giving_Receipt_NoTemplatePermission';
import LETTER_PICKER from '@salesforce/label/c.Giving_Receipt_LetterPicker';
import LETTER_OPTION from '@salesforce/label/c.Giving_Receipt_LetterOption';
import LETTER_OPTION_OFF from '@salesforce/label/c.Giving_Receipt_LetterOptionOff';
import EDITOR from '@salesforce/label/c.Giving_Receipt_EditorLabel';
import LETTERHEAD_NOTE from '@salesforce/label/c.Giving_Receipt_LetterheadNote';
import SAVE from '@salesforce/label/c.Giving_Receipt_SaveButton';
import USE_LETTER from '@salesforce/label/c.Giving_Receipt_UseLetterButton';
import PREVIEW from '@salesforce/label/c.Giving_Receipt_PreviewButton';
import PREVIEW_HEADING from '@salesforce/label/c.Giving_Receipt_PreviewHeading';
import PREVIEW_NOTE from '@salesforce/label/c.Giving_Receipt_PreviewNote';
import NO_PREVIEW_TITLE from '@salesforce/label/c.Giving_Receipt_NoPreviewTitle';
import TAX_NOTE from '@salesforce/label/c.Giving_Receipt_TaxNote';
import TOKENS_INTRO from '@salesforce/label/c.Giving_Receipt_TokensIntro';
import STATEMENT_YEAR from '@salesforce/label/c.Giving_Receipt_StatementYear';
import GENERATE from '@salesforce/label/c.Giving_Receipt_GenerateButton';
import REFRESH from '@salesforce/label/c.Giving_Receipt_RefreshButton';
import COLUMN_RUN from '@salesforce/label/c.Giving_Receipt_ColumnRun';
import COLUMN_YEAR from '@salesforce/label/c.Giving_Receipt_ColumnYear';
import COLUMN_STATUS from '@salesforce/label/c.Giving_Receipt_ColumnStatus';
import COLUMN_DONORS from '@salesforce/label/c.Giving_Receipt_ColumnDonors';
import COLUMN_ISSUED from '@salesforce/label/c.Giving_Receipt_ColumnIssued';
import COLUMN_ERRORS from '@salesforce/label/c.Giving_Receipt_ColumnErrors';
import NO_RUNS from '@salesforce/label/c.Giving_Receipt_NoRuns';
import RESTORED_TITLE from '@salesforce/label/c.Giving_Receipt_RestoredTitle';
import RESTORED_MESSAGE from '@salesforce/label/c.Giving_Receipt_RestoredMessage';
import NOT_RESTORED_TITLE from '@salesforce/label/c.Giving_Receipt_NotRestoredTitle';
import SAVED_TITLE from '@salesforce/label/c.Giving_Receipt_SavedTitle';
import SAVED_MESSAGE from '@salesforce/label/c.Giving_Receipt_SavedMessage';
import NOT_SAVED_TITLE from '@salesforce/label/c.Giving_Receipt_NotSavedTitle';
import ACTIVATED_TITLE from '@salesforce/label/c.Giving_Receipt_ActivatedTitle';
import ACTIVATED_MESSAGE from '@salesforce/label/c.Giving_Receipt_ActivatedMessage';
import NOT_ACTIVATED_TITLE from '@salesforce/label/c.Giving_Receipt_NotActivatedTitle';
import STARTED_TITLE from '@salesforce/label/c.Giving_Receipt_StartedTitle';
import STARTED_MESSAGE from '@salesforce/label/c.Giving_Receipt_StartedMessage';
import NOT_STARTED_TITLE from '@salesforce/label/c.Giving_Receipt_NotStartedTitle';
import UNEXPECTED_ERROR from '@salesforce/label/c.Giving_Receipt_UnexpectedError';
import PAGES_WHAT from '@salesforce/label/c.Giving_SetupNote_RecordPages_What';
import PAGES_WHY from '@salesforce/label/c.Giving_SetupNote_RecordPages_Why';
import PAGES_STEPS from '@salesforce/label/c.Giving_SetupNote_RecordPages_Steps';

const TOKENS = [
  '{{OrganizationName}}',
  '{{OrganizationAddress}}',
  '{{OrganizationTaxId}}',
  '{{PlaceOfIssue}}',
  '{{SignerName}}',
  '{{SignerTitle}}',
  '{{DonorName}}',
  '{{ReceiptNumber}}',
  '{{IssueDate}}',
  '{{StatementYear}}',
  '{{Amount}}',
  '{{GiftDate}}',
  '{{GiftType}}',
  '{{GiftLines}}'
];

/**
 * What the editor offers: only what the PDF rendering service prints (ADR-0065,
 * `0065-receipt-letters-are-edited-as-rich-text.md`). No images, fonts, sizes or colors, because
 * the renderer accepts no web fonts and no `data:` images (ADR-0016).
 */
const FORMATS = ['bold', 'italic', 'underline', 'list', 'indent', 'align', 'link', 'header'];

/**
 * The Receipts panel in the settings console: the letters, and the year end run.
 *
 * The letter is edited as rich text, and the letterhead is not in it: the package prints the
 * organization's name, address and logo above every document (ADR-0065). The panel also does
 * not offer a way to edit the tax sentences. They are not on this screen because they are not
 * editable: whatever the letter says, BarnCRM adds what IRS Publication 1771 requires (ADR-0016,
 * R-RC7). The note under the editor says so, so that an administrator looking for them stops
 * looking rather than typing them in twice.
 */
export default class ReceiptSettings extends LightningElement {
  /**
   * What Giving needs from Setup, shown by Core's settingsSetupNotes with its Open in Setup
   * link. Giving's permission sets are given on the Access page, so they need no note here.
   */
  setupNotes = [
    {
      key: 'recordPages',
      what: PAGES_WHAT,
      why: PAGES_WHY,
      steps: PAGES_STEPS,
      link: 'lightningPages'
    }
  ];

  labels = {
    templatesTab: TEMPLATES_TAB,
    statementsTab: STATEMENTS_TAB,
    noTemplates: NO_TEMPLATES,
    restore: RESTORE,
    readOnly: READ_ONLY,
    letterPicker: LETTER_PICKER,
    editor: EDITOR,
    letterheadNote: LETTERHEAD_NOTE,
    save: SAVE,
    useLetter: USE_LETTER,
    preview: PREVIEW,
    previewHeading: PREVIEW_HEADING,
    previewNote: PREVIEW_NOTE,
    taxNote: TAX_NOTE,
    tokensIntro: TOKENS_INTRO,
    statementYear: STATEMENT_YEAR,
    generate: GENERATE,
    refresh: REFRESH,
    columnRun: COLUMN_RUN,
    columnYear: COLUMN_YEAR,
    columnStatus: COLUMN_STATUS,
    columnDonors: COLUMN_DONORS,
    columnIssued: COLUMN_ISSUED,
    columnErrors: COLUMN_ERRORS,
    noRuns: NO_RUNS
  };

  templates = [];
  wiredTemplates;
  runs = [];
  wiredRuns;
  selectedTemplateId;
  draftBody = '';
  previewHtml;
  statementYear;
  working = false;
  loadError;
  canManage = false;
  permissionKnown = false;

  tokens = TOKENS;
  formats = FORMATS;

  @wire(getTemplates)
  handleTemplates(result) {
    this.wiredTemplates = result;
    if (result.data) {
      this.templates = result.data;
      this.loadError = undefined;
      if (!this.selectedTemplateId && this.templates.length > 0) {
        this.selectTemplate(this.templates[0]);
      }
    } else if (result.error) {
      this.loadError = this.messageOf(result.error);
    }
  }

  @wire(getCanManageTemplates)
  handleCanManage({ data, error }) {
    if (data !== undefined || error) {
      this.canManage = data === true;
      this.permissionKnown = true;
    }
  }

  @wire(getRuns)
  handleRuns(result) {
    this.wiredRuns = result;
    if (result.data) {
      this.runs = result.data;
    }
  }

  @wire(getDefaultStatementYear)
  handleDefaultYear({ data }) {
    if (data && this.statementYear === undefined) {
      this.statementYear = data;
    }
  }

  get templateOptions() {
    return this.templates.map((template) => ({
      label: (template.active ? LETTER_OPTION : LETTER_OPTION_OFF)
        .replace('{0}', template.name)
        .replace('{1}', template.type),
      value: template.id
    }));
  }

  get selectedTemplate() {
    return this.templates.find((template) => template.id === this.selectedTemplateId);
  }

  get showUseLetter() {
    const template = this.selectedTemplate;
    return !!template && !template.active;
  }

  get busy() {
    return this.working;
  }

  /** Saving and switching a letter on both need the manage settings permission. */
  get cannotEdit() {
    return this.working || !this.canManage;
  }

  /** Said in words once the answer is known, rather than only greying the buttons out. */
  get readOnly() {
    return this.permissionKnown && !this.canManage;
  }

  get hasTemplates() {
    return this.templates.length > 0;
  }

  get hasRuns() {
    return this.runs.length > 0;
  }

  selectTemplate(template) {
    this.selectedTemplateId = template.id;
    this.draftBody = template.body;
    this.previewHtml = undefined;
  }

  handleTemplateChange(event) {
    const chosen = this.templates.find((template) => template.id === event.detail.value);
    if (chosen) {
      this.selectTemplate(chosen);
    }
  }

  handleBodyChange(event) {
    this.draftBody = event.target.value;
  }

  handleYearChange(event) {
    this.statementYear = parseInt(event.detail.value, 10);
  }

  /**
   * The recovery path for an install whose bootstrap step failed. The letters are created at
   * install (ADR-0029); this is the button that says so out loud when they are not there.
   */
  async handleRestore() {
    await this.act(
      () => restoreDefaultTemplates(),
      [RESTORED_TITLE, RESTORED_MESSAGE],
      NOT_RESTORED_TITLE,
      this.wiredTemplates
    );
  }

  async handleSave() {
    await this.act(
      () => saveTemplate({ templateId: this.selectedTemplateId, body: this.draftBody }),
      [SAVED_TITLE, SAVED_MESSAGE],
      NOT_SAVED_TITLE,
      this.wiredTemplates
    );
  }

  /** The draft as it stands, unsaved, filled in for a sample gift (ADR-0065 point 5). */
  async handlePreview() {
    const template = this.selectedTemplate;
    this.working = true;
    try {
      this.previewHtml = await previewTemplate({
        receiptType: template ? template.type : undefined,
        body: this.draftBody
      });
    } catch (error) {
      this.previewHtml = undefined;
      this.toast(NO_PREVIEW_TITLE, this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  async handleActivate() {
    await this.act(
      () => activateTemplate({ templateId: this.selectedTemplateId }),
      [ACTIVATED_TITLE, ACTIVATED_MESSAGE],
      NOT_ACTIVATED_TITLE,
      this.wiredTemplates
    );
  }

  async handleGenerate() {
    await this.act(
      () => startStatementRun({ statementYear: this.statementYear }),
      [STARTED_TITLE, STARTED_MESSAGE],
      NOT_STARTED_TITLE,
      this.wiredRuns
    );
  }

  async handleRefreshRuns() {
    await refreshApex(this.wiredRuns);
  }

  /** Every write is the same four steps, so they are written once. */
  async act(call, [successTitle, successMessage], failureTitle, wired) {
    this.working = true;
    try {
      await call();
      this.toast(successTitle, successMessage, 'success');
      await refreshApex(wired);
    } catch (error) {
      this.toast(failureTitle, this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  messageOf(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return UNEXPECTED_ERROR;
  }

  toast(title, message, variant) {
    Toast.show({ label: title, message, variant }, this);
  }
}
