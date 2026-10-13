import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getPage from '@salesforce/apex/AcknowledgmentController.getPage';
import sendEmailsNow from '@salesforce/apex/AcknowledgmentController.sendEmailsNow';
import produceLetters from '@salesforce/apex/AcknowledgmentController.produceLetters';
import markLettersSent from '@salesforce/apex/AcknowledgmentController.markLettersSent';
import setSchedule from '@salesforce/apex/AcknowledgmentController.setSchedule';

import TITLE from '@salesforce/label/c.Giving_Acknowledgments_Title';
import INTRO from '@salesforce/label/c.Giving_Acknowledgments_Intro';
import OFF from '@salesforce/label/c.Giving_Acknowledgments_Off';
import NO_RULES from '@salesforce/label/c.Giving_Acknowledgments_NoRules';
import QUEUE_HEADING from '@salesforce/label/c.Giving_Acknowledgments_QueueHeading';
import EMAIL_QUEUE from '@salesforce/label/c.Giving_Acknowledgments_EmailQueue';
import LETTER_QUEUE from '@salesforce/label/c.Giving_Acknowledgments_LetterQueue';
import UNMATCHED from '@salesforce/label/c.Giving_Acknowledgments_Unmatched';
import WITHOUT_RECIPIENT from '@salesforce/label/c.Giving_Acknowledgments_WithoutRecipient';
import QUEUE_CAPPED from '@salesforce/label/c.Giving_Acknowledgments_QueueCapped';
import SEND_EMAILS from '@salesforce/label/c.Giving_Acknowledgments_SendEmails';
import EMAILS_STARTED from '@salesforce/label/c.Giving_Acknowledgments_EmailsStarted';
import PRODUCE_LETTERS from '@salesforce/label/c.Giving_Acknowledgments_ProduceLetters';
import LETTERS_READY from '@salesforce/label/c.Giving_Acknowledgments_LettersReady';
import MARK_SENT from '@salesforce/label/c.Giving_Acknowledgments_MarkSent';
import LETTERS_MARKED_SENT from '@salesforce/label/c.Giving_Acknowledgments_LettersMarkedSent';
import NIGHTLY from '@salesforce/label/c.Giving_Acknowledgments_Nightly';
import NEXT_RUN from '@salesforce/label/c.Giving_Acknowledgments_NextRun';
import NOT_SCHEDULED from '@salesforce/label/c.Giving_Acknowledgments_NotScheduled';
import LAST_RUN from '@salesforce/label/c.Giving_Acknowledgments_LastRun';
import NEVER_RUN from '@salesforce/label/c.Giving_Acknowledgments_NeverRun';
import RULES_HEADING from '@salesforce/label/c.Giving_Acknowledgments_RulesHeading';
import NEW_RULE from '@salesforce/label/c.Giving_Acknowledgments_NewRule';
import EDIT_RULE from '@salesforce/label/c.Giving_Acknowledgments_EditRule';
import EDIT_RULE_OF from '@salesforce/label/c.Giving_Acknowledgments_EditRuleOf';
import MATCH_FROM_AMOUNT from '@salesforce/label/c.Giving_Acknowledgments_MatchFromAmount';
import MATCH_UP_TO_AMOUNT from '@salesforce/label/c.Giving_Acknowledgments_MatchUpToAmount';
import MATCH_FIRST_GIFT_ONLY from '@salesforce/label/c.Giving_Acknowledgments_MatchFirstGiftOnly';
import NEW_RULE_HEADING from '@salesforce/label/c.Giving_Acknowledgments_NewRuleHeading';
import EDIT_RULE_HEADING from '@salesforce/label/c.Giving_Acknowledgments_EditRuleHeading';
import TEMPLATE_FIELD from '@salesforce/label/c.Giving_Acknowledgments_TemplateField';
import TEMPLATE_FIELD_HELP from '@salesforce/label/c.Giving_Acknowledgments_TemplateFieldHelp';
import TEMPLATE_PLACEHOLDER from '@salesforce/label/c.Giving_Acknowledgments_TemplatePlaceholder';
import TEMPLATE_REQUIRED from '@salesforce/label/c.Giving_Acknowledgments_TemplateRequired';
import SAVE_RULE from '@salesforce/label/c.Giving_Acknowledgments_SaveRule';
import CANCEL_RULE from '@salesforce/label/c.Giving_Acknowledgments_CancelRule';
import RULE_SAVED from '@salesforce/label/c.Giving_Acknowledgments_RuleSaved';
import RUNS_HEADING from '@salesforce/label/c.Giving_Acknowledgments_RunsHeading';
import NO_RUNS from '@salesforce/label/c.Giving_Acknowledgments_NoRuns';
import TEMPLATE_NOT_FOUND from '@salesforce/label/c.Giving_Acknowledgments_TemplateNotFound';
import INACTIVE from '@salesforce/label/c.Giving_Acknowledgments_Inactive';
import ACTION_FAILED from '@salesforce/label/c.Giving_Acknowledgments_ActionFailed';
import COLUMN_RULE from '@salesforce/label/c.Giving_Acknowledgments_ColumnRule';
import COLUMN_ORDER from '@salesforce/label/c.Giving_Acknowledgments_ColumnOrder';
import COLUMN_CHANNEL from '@salesforce/label/c.Giving_Acknowledgments_ColumnChannel';
import COLUMN_TEMPLATE from '@salesforce/label/c.Giving_Acknowledgments_ColumnTemplate';
import COLUMN_MATCHES from '@salesforce/label/c.Giving_Acknowledgments_ColumnMatches';
import COLUMN_RUN from '@salesforce/label/c.Giving_Acknowledgments_ColumnRun';
import COLUMN_STATUS from '@salesforce/label/c.Giving_Acknowledgments_ColumnStatus';
import COLUMN_SENT from '@salesforce/label/c.Giving_Acknowledgments_ColumnSent';
import COLUMN_ERRORS from '@salesforce/label/c.Giving_Acknowledgments_ColumnErrors';
import COLUMN_FINISHED from '@salesforce/label/c.Giving_Acknowledgments_ColumnFinished';
import DOWNLOAD_FILE from '@salesforce/label/c.Giving_Acknowledgments_DownloadFile';
import ANY_AMOUNT from '@salesforce/label/c.Giving_Acknowledgments_AnyAmount';
import FROM_WHAT from '@salesforce/label/c.Giving_SetupNote_FromAddress_What';
import FROM_WHY from '@salesforce/label/c.Giving_SetupNote_FromAddress_Why';
import FROM_WHERE from '@salesforce/label/c.Giving_SetupNote_FromAddress_Where';
import EMAIL_WHAT from '@salesforce/label/c.Giving_SetupNote_Email_What';
import EMAIL_WHY from '@salesforce/label/c.Giving_SetupNote_Email_Why';
import EMAIL_WHERE from '@salesforce/label/c.Giving_SetupNote_Email_Where';
import TEMPLATES_WHAT from '@salesforce/label/c.Giving_SetupNote_Templates_What';
import TEMPLATES_WHY from '@salesforce/label/c.Giving_SetupNote_Templates_Why';
import TEMPLATES_WHERE from '@salesforce/label/c.Giving_SetupNote_Templates_Where';

const FILE_DOWNLOAD_PATH = '/sfc/servlet.shepherd/document/download/';
const CHANNEL_EMAIL = 'Email';

/**
 * The thank you queue, as Maria reads it: what is waiting, what would send it, and the three
 * buttons that do it.
 *
 * A rule is created and edited here, in a standard record edit form, rather than on the
 * standard New page, for one reason: a rule names its email template by developer name, and no
 * lookup to `EmailTemplate` is possible (ADR-0032). So the template is a picker built from the
 * templates this page already lists, offered by name, and every other field is the standard
 * input field with its own validation (ADR-0066,
 * `0066-acknowledgment-rule-template-picker-and-generated-plan-keys.md`).
 */
export default class Acknowledgments extends NavigationMixin(LightningElement) {
  /** What this page needs from Setup, shown by Core's settingsSetupNotes. */
  setupNotes = [
    { key: 'fromAddress', what: FROM_WHAT, why: FROM_WHY, where: FROM_WHERE },
    {
      key: 'emailDeliverability',
      what: EMAIL_WHAT,
      why: EMAIL_WHY,
      where: EMAIL_WHERE,
      check: 'emailDeliverability'
    },
    { key: 'templates', what: TEMPLATES_WHAT, why: TEMPLATES_WHY, where: TEMPLATES_WHERE }
  ];

  labels = {
    title: TITLE,
    intro: INTRO,
    off: OFF,
    noRules: NO_RULES,
    queueHeading: QUEUE_HEADING,
    emailQueue: EMAIL_QUEUE,
    letterQueue: LETTER_QUEUE,
    unmatched: UNMATCHED,
    withoutRecipient: WITHOUT_RECIPIENT,
    queueCapped: QUEUE_CAPPED,
    sendEmails: SEND_EMAILS,
    produceLetters: PRODUCE_LETTERS,
    markSent: MARK_SENT,
    nightly: NIGHTLY,
    nextRun: NEXT_RUN,
    notScheduled: NOT_SCHEDULED,
    lastRun: LAST_RUN,
    neverRun: NEVER_RUN,
    rulesHeading: RULES_HEADING,
    newRule: NEW_RULE,
    editRule: EDIT_RULE,
    templateField: TEMPLATE_FIELD,
    templateFieldHelp: TEMPLATE_FIELD_HELP,
    templatePlaceholder: TEMPLATE_PLACEHOLDER,
    templateRequired: TEMPLATE_REQUIRED,
    saveRule: SAVE_RULE,
    cancelRule: CANCEL_RULE,
    runsHeading: RUNS_HEADING,
    noRuns: NO_RUNS,
    inactive: INACTIVE,
    columnRule: COLUMN_RULE,
    columnOrder: COLUMN_ORDER,
    columnChannel: COLUMN_CHANNEL,
    columnTemplate: COLUMN_TEMPLATE,
    columnMatches: COLUMN_MATCHES,
    columnRun: COLUMN_RUN,
    columnStatus: COLUMN_STATUS,
    columnSent: COLUMN_SENT,
    columnErrors: COLUMN_ERRORS,
    columnFinished: COLUMN_FINISHED,
    downloadFile: DOWNLOAD_FILE
  };

  page;
  wiredPage;
  errorMessage;
  noticeMessage;
  busy = false;

  /** The rule form: closed, open on a new rule (null id), or open on an existing one. */
  showRuleForm = false;
  editingRuleId;
  ruleChannel;
  ruleTemplate;

  @wire(getPage)
  wiredResult(result) {
    this.wiredPage = result;
    if (result.data) {
      this.page = result.data;
      this.errorMessage = undefined;
    }
    if (result.error) {
      this.errorMessage = this.messageFrom(result.error);
    }
  }

  get hasPage() {
    return !!this.page;
  }

  get showOffNotice() {
    return !!this.page && this.page.enabled === false;
  }

  get hasRules() {
    return !!(this.page && this.page.rules && this.page.rules.length);
  }

  get showNoRules() {
    return !!this.page && !this.hasRules;
  }

  get hasRuns() {
    return !!(this.page && this.page.runs && this.page.runs.length);
  }

  get showNoRuns() {
    return !!this.page && !this.hasRuns;
  }

  get canManage() {
    return !!this.page && this.page.canManage === true;
  }

  /** The templates the org has, offered by name; the rule stores the developer name. */
  get templateOptions() {
    const templates = (this.page && this.page.templates) || [];
    return templates.map((template) => ({
      label: template.label,
      value: template.developerName
    }));
  }

  get ruleIsEmail() {
    return this.ruleChannel === CHANNEL_EMAIL;
  }

  get ruleFormHeading() {
    return this.editingRuleId ? EDIT_RULE_HEADING : NEW_RULE_HEADING;
  }

  get showQueueCapped() {
    return !!this.page && this.page.queueCapped === true;
  }

  get scheduled() {
    return !!this.page && this.page.scheduled === true;
  }

  get nextRunText() {
    if (!this.page || !this.page.nextRunAt) {
      return this.labels.notScheduled;
    }
    return new Date(this.page.nextRunAt).toLocaleString();
  }

  get lastRunText() {
    if (!this.page || !this.page.lastRun) {
      return this.labels.neverRun;
    }
    const when = new Date(this.page.lastRun).toLocaleString();
    return this.page.lastRunSummary ? `${when}: ${this.page.lastRunSummary}` : when;
  }

  /**
   * The rules with the two things a raw record cannot say: whether the template it names actually
   * exists in this org, and what its criteria add up to in one phrase.
   */
  get rules() {
    if (!this.hasRules) {
      return [];
    }
    return this.page.rules.map((rule) => ({
      ...rule,
      templateText: rule.templateFound ? rule.templateLabel : TEMPLATE_NOT_FOUND,
      templateMissing: rule.templateFound === false,
      activeText: rule.active ? '' : this.labels.inactive,
      editTitle: EDIT_RULE_OF.replace('{0}', rule.name),
      matchesText: this.describe(rule)
    }));
  }

  get runs() {
    if (!this.hasRuns) {
      return [];
    }
    return this.page.runs.map((run) => ({
      ...run,
      finishedText: run.finished ? new Date(run.finished).toLocaleString() : '',
      hasFile: !!run.mergeFileId,
      fileUrl: run.mergeFileId ? FILE_DOWNLOAD_PATH + run.mergeFileId : ''
    }));
  }

  get sendDisabled() {
    return this.busy || !this.page || this.page.canSend !== true || !this.page.emailQueue;
  }

  get lettersDisabled() {
    return this.busy || !this.page || this.page.canSend !== true || !this.page.letterQueue;
  }

  get scheduleDisabled() {
    return this.busy || !this.page || this.page.canManage !== true;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasNotice() {
    return !!this.noticeMessage;
  }

  /** What a rule matches, in the words the admin guide uses. */
  describe(rule) {
    const parts = [];
    if (rule.minimumAmount !== null && rule.minimumAmount !== undefined) {
      parts.push(MATCH_FROM_AMOUNT.replace('{0}', rule.minimumAmount));
    }
    if (rule.maximumAmount !== null && rule.maximumAmount !== undefined) {
      parts.push(MATCH_UP_TO_AMOUNT.replace('{0}', rule.maximumAmount));
    }
    if (rule.giftType) {
      parts.push(rule.giftType);
    }
    if (rule.appealName) {
      parts.push(rule.appealName);
    }
    if (rule.firstGiftOnly) {
      parts.push(MATCH_FIRST_GIFT_ONLY);
    }
    return parts.length ? parts.join(', ') : ANY_AMOUNT;
  }

  handleNewRule() {
    this.openRuleForm(undefined);
  }

  handleEditRule(event) {
    this.openRuleForm(event.currentTarget.dataset.recordId);
  }

  openRuleForm(ruleId) {
    const rule = ruleId ? this.page.rules.find((row) => row.id === ruleId) : undefined;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    this.editingRuleId = ruleId;
    // A new rule starts on Email, the field's default, so the picker shows from the start.
    this.ruleChannel = rule ? rule.channel : CHANNEL_EMAIL;
    this.ruleTemplate = rule ? rule.template : undefined;
    this.showRuleForm = true;
  }

  handleChannelChange(event) {
    this.ruleChannel = event.detail.value;
  }

  handleRuleTemplateChange(event) {
    this.ruleTemplate = event.detail.value;
  }

  handleCancelRule() {
    this.showRuleForm = false;
  }

  /**
   * The template goes in with the fields the form collected. The validation rule on the object
   * still refuses an email rule with no template; checking here first only says so beside the
   * picker instead of at the top of the form.
   */
  handleRuleSubmit(event) {
    event.preventDefault();
    const fields = { ...event.detail.fields };
    if (this.ruleIsEmail && !this.ruleTemplate) {
      this.template.querySelector('[data-id="rule-template"]').reportValidity();
      return;
    }
    fields.Email_Template__c = this.ruleIsEmail ? this.ruleTemplate : null;
    this.template.querySelector('lightning-record-edit-form').submit(fields);
  }

  handleRuleSaved() {
    this.showRuleForm = false;
    this.noticeMessage = RULE_SAVED;
    return refreshApex(this.wiredPage);
  }

  handleOpenRule(event) {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: event.currentTarget.dataset.recordId,
        objectApiName: 'Acknowledgment_Rule__c',
        actionName: 'view'
      }
    });
  }

  handleSendEmails() {
    return this.run(sendEmailsNow(), EMAILS_STARTED);
  }

  handleProduceLetters() {
    return this.run(produceLetters(), LETTERS_READY);
  }

  handleMarkSent(event) {
    return this.run(
      markLettersSent({ runId: event.currentTarget.dataset.recordId }),
      LETTERS_MARKED_SENT
    );
  }

  handleScheduleChange(event) {
    return this.run(setSchedule({ scheduled: event.target.checked }), undefined);
  }

  /** Every action is the same three steps, so they are written once. */
  run(promise, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    return promise
      .then((view) => {
        this.page = view;
        this.noticeMessage = notice;
        return refreshApex(this.wiredPage);
      })
      .catch((error) => {
        this.errorMessage = this.messageFrom(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return ACTION_FAILED;
  }
}
