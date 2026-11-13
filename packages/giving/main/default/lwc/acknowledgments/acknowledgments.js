import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import RULE from '@salesforce/schema/Acknowledgment_Rule__c';
import RULE_ORDER from '@salesforce/schema/Acknowledgment_Rule__c.Order__c';
import RULE_ACTIVE from '@salesforce/schema/Acknowledgment_Rule__c.Active__c';
import RULE_CHANNEL from '@salesforce/schema/Acknowledgment_Rule__c.Channel__c';
import RULE_MINIMUM from '@salesforce/schema/Acknowledgment_Rule__c.Minimum_Amount__c';
import RULE_MAXIMUM from '@salesforce/schema/Acknowledgment_Rule__c.Maximum_Amount__c';
import RULE_GIFT_TYPE from '@salesforce/schema/Acknowledgment_Rule__c.Gift_Type__c';
import RULE_APPEAL from '@salesforce/schema/Acknowledgment_Rule__c.Appeal__c';
import RULE_FIRST_GIFT_ONLY from '@salesforce/schema/Acknowledgment_Rule__c.First_Gift_Only__c';
import RULE_DESCRIPTION from '@salesforce/schema/Acknowledgment_Rule__c.Description__c';
import RULE_EMAIL_TEMPLATE from '@salesforce/schema/Acknowledgment_Rule__c.Email_Template__c';
import { refreshApex } from '@salesforce/apex';
import getPage from '@salesforce/apex/AcknowledgmentController.getPage';
import sendEmailsNow from '@salesforce/apex/AcknowledgmentController.sendEmailsNow';
import produceLetters from '@salesforce/apex/AcknowledgmentController.produceLetters';
import markLettersSent from '@salesforce/apex/AcknowledgmentController.markLettersSent';
import setSchedule from '@salesforce/apex/AcknowledgmentController.setSchedule';
import reorderRules from '@salesforce/apex/AcknowledgmentController.reorderRules';

import TITLE from '@salesforce/label/c.Giving_Acknowledgments_Title';
import QUEUE_HEADING from '@salesforce/label/c.Giving_Acknowledgments_QueueHeading';
import EMAIL_QUEUE from '@salesforce/label/c.Giving_Acknowledgments_EmailQueue';
import LETTER_QUEUE from '@salesforce/label/c.Giving_Acknowledgments_LetterQueue';
import UNMATCHED from '@salesforce/label/c.Giving_Acknowledgments_Unmatched';
import WITHOUT_RECIPIENT from '@salesforce/label/c.Giving_Acknowledgments_WithoutRecipient';
import OPTED_OUT from '@salesforce/label/c.Giving_Acknowledgments_OptedOut';
import SEND_EMAILS from '@salesforce/label/c.Giving_Acknowledgments_SendEmails';
import PRODUCE_LETTERS from '@salesforce/label/c.Giving_Acknowledgments_ProduceLetters';
import MARK_SENT from '@salesforce/label/c.Giving_Acknowledgments_MarkSent';
import NIGHTLY from '@salesforce/label/c.Giving_Acknowledgments_Nightly';
import NEXT_RUN from '@salesforce/label/c.Giving_Acknowledgments_NextRun';
import LAST_RUN from '@salesforce/label/c.Core_HealthCheck_LastRunLabel';
import RULES_HEADING from '@salesforce/label/c.Giving_Acknowledgments_RulesHeading';
import NEW_RULE from '@salesforce/label/c.Giving_Acknowledgments_NewRule';
import EDIT_RULE from '@salesforce/label/c.Core_CmdtManager_EditAction';
import EDIT_RULE_OF from '@salesforce/label/c.Giving_Acknowledgments_EditRuleOf';
import MATCH_FROM_AMOUNT from '@salesforce/label/c.Giving_Acknowledgments_MatchFromAmount';
import MATCH_UP_TO_AMOUNT from '@salesforce/label/c.Giving_Acknowledgments_MatchUpToAmount';
import MATCH_FIRST_GIFT_ONLY from '@salesforce/label/c.Giving_Acknowledgments_MatchFirstGiftOnly';
import NEW_RULE_HEADING from '@salesforce/label/c.Giving_Acknowledgments_NewRule';
import EDIT_RULE_HEADING from '@salesforce/label/c.Giving_Acknowledgments_EditRuleHeading';
import TEMPLATE_FIELD from '@salesforce/label/c.Giving_Acknowledgments_TemplateField';
import TEMPLATE_PLACEHOLDER from '@salesforce/label/c.Giving_Acknowledgments_TemplatePlaceholder';
import SAVE_RULE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL_RULE from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import RUNS_HEADING from '@salesforce/label/c.Core_AutoMerge_RecentRuns';
import TEMPLATE_NOT_FOUND from '@salesforce/label/c.Giving_Acknowledgments_TemplateNotFound';
import INACTIVE from '@salesforce/label/c.Core_MatchLogic_Inactive';
import COLUMN_RULE from '@salesforce/label/c.Giving_Acknowledgments_ColumnRule';
import COLUMN_ORDER from '@salesforce/label/c.Giving_Acknowledgments_ColumnOrder';
import COLUMN_CHANNEL from '@salesforce/label/c.Giving_Acknowledgments_ColumnChannel';
import COLUMN_TEMPLATE from '@salesforce/label/c.Core_Import_StepTemplate';
import COLUMN_MATCHES from '@salesforce/label/c.Giving_Acknowledgments_ColumnMatches';
import COLUMN_RUN from '@salesforce/label/c.Giving_Acknowledgments_ColumnRun';
import COLUMN_STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import COLUMN_SENT from '@salesforce/label/c.Giving_Acknowledgments_ColumnSent';
import COLUMN_ERRORS from '@salesforce/label/c.Giving_Acknowledgments_ColumnErrors';
import COLUMN_FINISHED from '@salesforce/label/c.Giving_Acknowledgments_ColumnFinished';
import DOWNLOAD_FILE from '@salesforce/label/c.Giving_Acknowledgments_DownloadFile';
import ANY_AMOUNT from '@salesforce/label/c.Giving_Acknowledgments_AnyAmount';
import MOVE_UP from '@salesforce/label/c.Core_Shared_MoveUp';
import MOVE_DOWN from '@salesforce/label/c.Core_Shared_MoveDown';
import COLUMN_ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import { bodyMessage } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { createDragController } from 'c/barnDrag';
import { dragInstructions, dragMessages } from 'c/barnDragText';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const FILE_DOWNLOAD_PATH = '/sfc/servlet.shepherd/document/download/';
const CHANNEL_EMAIL = 'Email';
const RULES_SECTION = 'rules';

/** The ids with one of them taken out and put back at a position among the rest. */
function placeAt(ids, id, index) {
  const others = ids.filter((other) => other !== id);
  others.splice(index, 0, id);
  return others;
}

/** A run's status word for the shared status badge; the badge text stays the run's own status. */
const RUN_STATUS_WORDS = {
  Queued: 'queued',
  Running: 'running',
  'Ready to merge': 'attention',
  Completed: 'completed',
  'Completed with errors': 'warning',
  Failed: 'failed'
};

/**
 * The Thank-Yous page, as Maria reads it: what is waiting, what would send it, the three buttons
 * that do it, and the recent runs, first. The rules come after, in a section headed Rules (Admin)
 * that starts open only for someone who may change them (people-giving-18).
 *
 * The rule order can be changed by dragging a rule row (the Core kit's `c/barnDrag`: mouse, touch
 * after a press and hold, or Space and the arrow keys) or with Move Up and Move Down; either
 * renumbers the rules 10, 20, 30 in one save and announces the move in a live region.
 *
 * A rule is created and edited here, in a standard record edit form, rather than on the
 * standard New page, for one reason: a rule names its email template by developer name, and no
 * lookup to `EmailTemplate` is possible (ADR-0032). So the template is a picker built from the
 * templates this page already lists, offered by name, and every other field is the standard
 * input field with its own validation (ADR-0066,
 * `0066-acknowledgment-rule-template-picker-and-generated-plan-keys.md`).
 */
export default class Acknowledgments extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded(['Core', 'Giving']);
  /** The rule form's object and fields, from schema imports so they carry any namespace. */
  ruleForm = {
    object: RULE.objectApiName,
    order: RULE_ORDER.fieldApiName,
    active: RULE_ACTIVE.fieldApiName,
    channel: RULE_CHANNEL.fieldApiName,
    minimum: RULE_MINIMUM.fieldApiName,
    maximum: RULE_MAXIMUM.fieldApiName,
    giftType: RULE_GIFT_TYPE.fieldApiName,
    appeal: RULE_APPEAL.fieldApiName,
    firstGiftOnly: RULE_FIRST_GIFT_ONLY.fieldApiName,
    description: RULE_DESCRIPTION.fieldApiName
  };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(['Core', 'Giving']).then(() => {
        this.helpReady = true;
      });
    }
    this.drag = createDragController({
      root: this.template,
      layout: 'list',
      messages: dragMessages(),
      announce: (text) => {
        this.liveMessage = text;
      },
      onChange: (state) => {
        this.dragState = state;
      },
      onDrop: ({ itemId, fromIndex, toIndex }) => {
        if (fromIndex === toIndex) {
          return false;
        }
        return this.saveOrder(placeAt(this.ruleIds, itemId, toIndex), itemId, false);
      }
    });
  }

  disconnectedCallback() {
    if (this.drag) {
      this.drag.destroy();
    }
  }

  /** What this page needs from Setup, shown by Core's settingsSetupNotes. */
  setupNotes = [
    {
      key: 'fromAddress',
      get what() {
        return helpText('Giving', 'Giving_SetupNote_FromAddress_What');
      },
      get why() {
        return helpText('Giving', 'Giving_SetupNote_FromAddress_Why');
      },
      get steps() {
        return helpText('Giving', 'Giving_SetupNote_FromAddress_Steps');
      },
      link: 'orgWideAddresses'
    },
    {
      key: 'emailDeliverability',
      get what() {
        return helpText('Giving', 'Giving_SetupNote_Email_What');
      },
      get why() {
        return helpText('Giving', 'Giving_SetupNote_Email_Why');
      },
      get steps() {
        return helpText('Core', 'Core_SetupNote_Email_Steps');
      },
      link: 'deliverability',
      check: 'emailDeliverability'
    },
    {
      key: 'templates',
      get what() {
        return helpText('Giving', 'Giving_SetupNote_Templates_What');
      },
      get why() {
        return helpText('Giving', 'Giving_SetupNote_Templates_Why');
      },
      get steps() {
        return helpText('Giving', 'Giving_SetupNote_Templates_Steps');
      },
      link: 'emailTemplates'
    }
  ];

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Giving', 'Giving_Acknowledgments_Intro');
    },
    get off() {
      return helpText('Giving', 'Giving_Acknowledgments_Off');
    },
    get noRules() {
      return helpText('Giving', 'Giving_Acknowledgments_NoRules');
    },
    get rulesHelp() {
      return helpText('Giving', 'Giving_Acknowledgments_RulesHelp');
    },
    get dragInstructions() {
      return dragInstructions();
    },
    moveUp: MOVE_UP,
    moveDown: MOVE_DOWN,
    columnActions: COLUMN_ACTIONS,
    queueHeading: QUEUE_HEADING,
    emailQueue: EMAIL_QUEUE,
    letterQueue: LETTER_QUEUE,
    unmatched: UNMATCHED,
    withoutRecipient: WITHOUT_RECIPIENT,
    optedOut: OPTED_OUT,
    get queueCapped() {
      return helpText('Giving', 'Giving_Acknowledgments_QueueCapped');
    },
    sendEmails: SEND_EMAILS,
    produceLetters: PRODUCE_LETTERS,
    markSent: MARK_SENT,
    nightly: NIGHTLY,
    nextRun: NEXT_RUN,
    get notScheduled() {
      return helpText('Giving', 'Giving_Acknowledgments_NotScheduled');
    },
    lastRun: LAST_RUN,
    get neverRun() {
      return helpText('Giving', 'Giving_Acknowledgments_NeverRun');
    },
    rulesHeading: RULES_HEADING,
    newRule: NEW_RULE,
    editRule: EDIT_RULE,
    templateField: TEMPLATE_FIELD,
    get templateFieldHelp() {
      return helpText('Giving', 'Giving_Acknowledgments_TemplateFieldHelp');
    },
    templatePlaceholder: TEMPLATE_PLACEHOLDER,
    get templateRequired() {
      return helpText('Giving', 'Giving_Acknowledgments_TemplateRequired');
    },
    saveRule: SAVE_RULE,
    cancelRule: CANCEL_RULE,
    runsHeading: RUNS_HEADING,
    get noRuns() {
      return helpText('Giving', 'Giving_Acknowledgments_NoRuns');
    },
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

  icons = { page: iconFor('Acknowledgments') };

  page;
  wiredPage;
  errorMessage;
  noticeMessage;
  liveMessage = '';
  busy = false;

  /** The drag in progress, as c/barnDrag reports it. */
  dragState = {};
  drag;

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
      this.errorMessage = bodyMessage(
        result.error,
        helpText('Giving', 'Giving_Receipt_UnexpectedError')
      );
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

  /** The rules section starts open for someone who may change the rules, closed for the rest. */
  get rulesSectionOpen() {
    return this.canManage ? RULES_SECTION : [];
  }

  get ruleIds() {
    return this.hasRules ? this.page.rules.map((rule) => rule.id) : [];
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
    const last = this.page.rules.length - 1;
    const state = this.dragState || {};
    const others = state.active ? this.ruleIds.filter((id) => id !== state.itemId) : [];
    const dropBefore = state.active ? others[state.overIndex] : undefined;
    return this.page.rules.map((rule, index) => {
      let rowClass = 'slds-hint-parent';
      if (state.active && rule.id === state.itemId) {
        rowClass += ' rule-row_dragging';
      } else if (rule.id === dropBefore) {
        rowClass += ' rule-row_drop';
      }
      return {
        ...rule,
        templateText: rule.templateFound ? rule.templateLabel : TEMPLATE_NOT_FOUND,
        templateMissing: rule.templateFound === false,
        inactive: !rule.active,
        editTitle: EDIT_RULE_OF.replace('{0}', rule.name),
        matchesText: this.describe(rule),
        cannotMoveUp: this.busy || index === 0,
        cannotMoveDown: this.busy || index === last,
        dragId: this.canManage ? rule.id : undefined,
        tabIndex: this.canManage ? '0' : undefined,
        rowClass
      };
    });
  }

  get runs() {
    if (!this.hasRuns) {
      return [];
    }
    return this.page.runs.map((run) => ({
      ...run,
      finishedText: run.finished ? new Date(run.finished).toLocaleString() : '',
      statusWord: RUN_STATUS_WORDS[run.status] || run.status,
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
    fields[RULE_EMAIL_TEMPLATE.fieldApiName] = this.ruleIsEmail ? this.ruleTemplate : null;
    this.template.querySelector('lightning-record-edit-form').submit(fields);
  }

  handleRuleSaved() {
    this.showRuleForm = false;
    this.noticeMessage = helpText('Giving', 'Giving_Acknowledgments_RuleSaved');
    return refreshApex(this.wiredPage);
  }

  handleOpenRule(event) {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: event.currentTarget.dataset.recordId,
        objectApiName: RULE.objectApiName,
        actionName: 'view'
      }
    });
  }

  handleSendEmails() {
    return this.run(sendEmailsNow(), helpText('Giving', 'Giving_Acknowledgments_EmailsStarted'));
  }

  handleProduceLetters() {
    return this.run(produceLetters(), helpText('Giving', 'Giving_Acknowledgments_LettersReady'));
  }

  handleMarkSent(event) {
    return this.run(
      markLettersSent({ runId: event.currentTarget.dataset.recordId }),
      helpText('Giving', 'Giving_Acknowledgments_LettersMarkedSent')
    );
  }

  handleScheduleChange(event) {
    return this.run(setSchedule({ scheduled: event.target.checked }), undefined);
  }

  handleMoveUp(event) {
    return this.moveRule(event.currentTarget.dataset.recordId, -1);
  }

  handleMoveDown(event) {
    return this.moveRule(event.currentTarget.dataset.recordId, 1);
  }

  moveRule(ruleId, offset) {
    const ids = this.ruleIds;
    const from = ids.indexOf(ruleId);
    const to = from + offset;
    if (from < 0 || to < 0 || to >= ids.length) {
      return Promise.resolve(false);
    }
    return this.saveOrder(placeAt(ids, ruleId, to), ruleId, true);
  }

  /**
   * Saves the whole order at once; the server renumbers the rules 10, 20, 30. A Move Up or Move
   * Down is announced here; a drag is announced by the drag controller. Resolves true when saved.
   */
  saveOrder(ids, movedId, announce) {
    const moved = this.page.rules.find((rule) => rule.id === movedId);
    const said = helpText(
      'Giving',
      'Giving_Acknowledgments_RuleMoved',
      moved ? moved.name : '',
      ids.indexOf(movedId) + 1,
      ids.length
    );
    return this.run(reorderRules({ ruleIds: ids }), said).then(() => {
      if (this.errorMessage) {
        return false;
      }
      if (announce) {
        this.liveMessage = said;
      }
      return true;
    });
  }

  // Dragging a rule row through c/barnDrag: Move Up and Move Down do the same.
  handlePointerDown(event) {
    if (this.canManage && !this.busy) {
      this.drag.pointerDown(event);
    }
  }

  handleDragKey(event) {
    if (this.canManage && !this.busy) {
      this.drag.keyDown(event);
    }
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
        this.errorMessage = bodyMessage(
          error,
          helpText('Giving', 'Giving_Receipt_UnexpectedError')
        );
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
