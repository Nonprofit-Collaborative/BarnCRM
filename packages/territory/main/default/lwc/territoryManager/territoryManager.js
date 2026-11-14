import { LightningElement } from 'lwc';
import { createRecord, deleteRecord, updateRecord } from 'lightning/uiRecordApi';
import BarnConfirmModal from 'c/barnConfirmModal';
import getPage from '@salesforce/apex/TerritoryController.getPage';
import startRun from '@salesforce/apex/TerritoryController.startRun';
import countRule from '@salesforce/apex/TerritoryController.countRule';
import undoRun from '@salesforce/apex/TerritoryController.undoRun';
import TERRITORY from '@salesforce/schema/Territory__c';
import MEMBER from '@salesforce/schema/Territory_Member__c';
import RULE from '@salesforce/schema/Territory_Rule__c';
import RULE_ID from '@salesforce/schema/Territory_Rule__c.Id';
import RULE_TERRITORY from '@salesforce/schema/Territory_Rule__c.Territory__c';
import RULE_APPLIES_TO from '@salesforce/schema/Territory_Rule__c.Applies_To__c';
import RULE_FILTER from '@salesforce/schema/Territory_Rule__c.Filter_JSON__c';
import RULE_SUMMARY from '@salesforce/schema/Territory_Rule__c.Summary__c';
import RULE_ACTIVE from '@salesforce/schema/Territory_Rule__c.Active__c';
import TERRITORY_ACTIVE from '@salesforce/schema/Territory__c.Active__c';
import TERRITORY_PRIORITY from '@salesforce/schema/Territory__c.Priority__c';
import TERRITORY_ROUTING from '@salesforce/schema/Territory__c.Routing__c';
import TERRITORY_OWNER_USER from '@salesforce/schema/Territory__c.Owner_User__c';
import TERRITORY_DESCRIPTION from '@salesforce/schema/Territory__c.Description__c';
import MEMBER_TERRITORY from '@salesforce/schema/Territory_Member__c.Territory__c';
import MEMBER_USER from '@salesforce/schema/Territory_Member__c.User__c';
import MEMBER_CAPACITY from '@salesforce/schema/Territory_Member__c.Capacity__c';
import MEMBER_ACTIVE from '@salesforce/schema/Territory_Member__c.Active__c';
import { iconFor } from 'c/barnIcons';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  MODE_ASSIGN,
  MODE_PREVIEW,
  hasActiveRule,
  kindOptions,
  kindsOverLimit,
  runRows
} from 'c/territoryModel';

const HELP = 'Territory';
const GUIDE_URL =
  'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/docs/admin-guide/territory-management.md';
/** The object each kind of rule is checked against, for the filter builder. */
const OBJECT_OF_KIND = { People: 'Contact', Households: 'Account', Organizations: 'Account' };

/**
 * The Territory Management page (C-40, C-40b; admin guide territory-management.md): territories
 * with their rules and members, Preview and Assign runs with their results, and Undo. Territories
 * and members are saved through record edit forms and rules through Lightning Data Service; runs
 * go through `TerritoryController`.
 */
export default class TerritoryManager extends LightningElement {
  helpReady = isHelpLoaded(HELP);
  iconName = iconFor('Territory_Management');
  territoryObject = TERRITORY.objectApiName;
  memberObject = MEMBER.objectApiName;
  /** The editors' fields, from schema imports so they carry any namespace. */
  formFields = {
    territoryActive: TERRITORY_ACTIVE.fieldApiName,
    priority: TERRITORY_PRIORITY.fieldApiName,
    routing: TERRITORY_ROUTING.fieldApiName,
    ownerUser: TERRITORY_OWNER_USER.fieldApiName,
    description: TERRITORY_DESCRIPTION.fieldApiName,
    memberTerritory: MEMBER_TERRITORY.fieldApiName,
    memberUser: MEMBER_USER.fieldApiName,
    memberCapacity: MEMBER_CAPACITY.fieldApiName,
    memberActive: MEMBER_ACTIVE.fieldApiName
  };

  page;
  busy = false;
  errorMessage;
  statusMessage;
  onlyUnassigned = false;
  /** The editor open: { kind: 'territory' | 'member' | 'rule', recordId, territoryId }. */
  editor;
  ruleDraft;
  ruleCount;
  openRunId;

  get labels() {
    return {
      title: helpText('Territory', 'Territory_Page_Title'),
      intro: helpText('Territory', 'Territory_Page_Intro'),
      newTerritory: helpText('Territory', 'Territory_Page_NewTerritory'),
      preview: helpText('Territory', 'Territory_Page_Preview'),
      assign: helpText('Territory', 'Territory_Page_Assign'),
      onlyUnassigned: helpText('Territory', 'Territory_Page_OnlyUnassigned'),
      refresh: helpText('Territory', 'Territory_Page_Refresh'),
      running: helpText('Territory', 'Territory_Page_Running'),
      territories: helpText('Territory', 'Territory_Page_Territories'),
      noTerritories: helpText('Territory', 'Territory_Page_NoTerritories'),
      rules: helpText('Territory', 'Territory_Page_Rules'),
      noRules: helpText('Territory', 'Territory_Page_NoRules'),
      members: helpText('Territory', 'Territory_Page_Members'),
      noMembers: helpText('Territory', 'Territory_Page_NoMembers'),
      addRule: helpText('Territory', 'Territory_Page_AddRule'),
      addMember: helpText('Territory', 'Territory_Page_AddMember'),
      edit: helpText('Territory', 'Territory_Page_Edit'),
      remove: helpText('Territory', 'Territory_Page_Delete'),
      save: helpText('Territory', 'Territory_Page_Save'),
      cancel: helpText('Territory', 'Territory_Page_Cancel'),
      appliesTo: helpText('Territory', 'Territory_Page_AppliesTo'),
      ruleActive: helpText('Territory', 'Territory_Page_RuleActive'),
      checkRule: helpText('Territory', 'Territory_Page_CheckRule'),
      inactive: helpText('Territory', 'Territory_Page_Inactive'),
      runs: helpText('Territory', 'Territory_Page_Runs'),
      noRuns: helpText('Territory', 'Territory_Page_NoRuns'),
      show: helpText('Territory', 'Territory_Page_Show'),
      undo: helpText('Territory', 'Territory_Page_Undo'),
      sample: helpText('Territory', 'Territory_Page_Sample')
    };
  }

  get guideUrl() {
    return GUIDE_URL;
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    try {
      this.page = await getPage();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  /* ---------- what the template reads ---------- */

  get territories() {
    const list = (this.page && this.page.territories) || [];
    return list.map((territory) => ({
      ...territory,
      heading: territory.active ? territory.name : `${territory.name} (${this.labels.inactive})`,
      detail: helpText(
        'Territory',
        'Territory_Page_TerritoryDetail',
        territory.priority,
        territory.routing
      ),
      ownerLine: territory.ownerName
        ? helpText('Territory', 'Territory_Page_OwnerLine', territory.ownerName)
        : '',
      hasRules: (territory.rules || []).length > 0,
      hasMembers: (territory.members || []).length > 0,
      rules: (territory.rules || []).map((rule) => ({
        ...rule,
        line: `${rule.appliesTo}: ${rule.summary || helpText('Territory', 'Territory_Page_EveryRecord')}`,
        lineClass: rule.active ? '' : 'slds-text-color_weak'
      })),
      members: (territory.members || []).map((member) => ({
        ...member,
        line:
          member.capacity === null || member.capacity === undefined
            ? member.userName
            : helpText(
                'Territory',
                'Territory_Page_MemberCapacity',
                member.userName,
                member.capacity
              ),
        lineClass: member.active && member.userActive ? '' : 'slds-text-color_weak'
      }))
    }));
  }

  get hasTerritories() {
    return this.territories.length > 0;
  }

  get runs() {
    return runRows(this.page && this.page.runs).map((run) => ({
      ...run,
      line: helpText(
        'Territory',
        'Territory_Page_RunLine',
        run.name,
        run.mode,
        run.status,
        run.checked || 0,
        run.changes || 0,
        run.failed || 0
      ),
      isOpen: run.id === this.openRunId,
      territoryLines: run.summary.territories.map((entry) => ({
        key: entry.id,
        text: helpText(
          'Territory',
          'Territory_Page_TerritoryCount',
          entry.name,
          entry.changes,
          entry.noRoom || 0
        )
      })),
      sampleLines: run.summary.sample.map((entry) => ({
        key: entry.id,
        text: helpText(
          'Territory',
          'Territory_Page_SampleLine',
          entry.name,
          entry.fromName || helpText('Territory', 'Territory_Page_NoTerritory'),
          entry.toName,
          entry.ownerName || helpText('Territory', 'Territory_Page_OwnerKept')
        )
      }))
    }));
  }

  get hasRuns() {
    return this.runs.length > 0;
  }

  get isRunning() {
    return Boolean(this.page && this.page.busy);
  }

  get runDisabled() {
    return this.busy || this.isRunning || !this.page || !hasActiveRule(this.page.territories);
  }

  get limitWarning() {
    if (!this.page) {
      return '';
    }
    const over = kindsOverLimit(this.page.territories, this.page.maxRules);
    return over.length
      ? helpText('Territory', 'Territory_Page_TooManyRules', over.join(', '), this.page.maxRules)
      : '';
  }

  get editingTerritory() {
    return Boolean(this.editor && this.editor.kind === 'territory');
  }

  get editingMember() {
    return Boolean(this.editor && this.editor.kind === 'member');
  }

  get editingRule() {
    return Boolean(this.editor && this.editor.kind === 'rule');
  }

  get kindChoices() {
    return kindOptions();
  }

  get ruleObject() {
    return this.ruleDraft ? OBJECT_OF_KIND[this.ruleDraft.appliesTo] : undefined;
  }

  get ruleCountLine() {
    return this.ruleCount === undefined
      ? ''
      : helpText('Territory', 'Territory_Page_RuleCount', this.ruleCount);
  }

  /* ---------- territories and members ---------- */

  handleNewTerritory() {
    this.editor = { kind: 'territory' };
  }

  handleEditTerritory(event) {
    this.editor = { kind: 'territory', recordId: event.target.dataset.id };
  }

  handleAddMember(event) {
    this.editor = { kind: 'member', territoryId: event.target.dataset.id };
  }

  handleFormSuccess() {
    this.editor = undefined;
    this.statusMessage = helpText('Territory', 'Territory_Page_Saved');
    this.load();
  }

  handleFormError(event) {
    this.errorMessage = (event.detail && event.detail.message) || messageFrom(event.detail);
  }

  handleCancel() {
    this.editor = undefined;
    this.ruleDraft = undefined;
    this.ruleCount = undefined;
  }

  async handleDelete(event) {
    // Read before the dialog: the event's target is gone once it closes.
    const { id, name } = event.target.dataset;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: this.labels.remove,
      message: helpText('Territory', 'Territory_Page_DeleteConfirm', name),
      confirmLabel: this.labels.remove,
      cancelLabel: this.labels.cancel,
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return;
    }
    await this.withBusy(async () => {
      await deleteRecord(id);
      await this.load();
    });
  }

  /* ---------- rules ---------- */

  handleAddRule(event) {
    this.openRule({ territoryId: event.target.dataset.id, appliesTo: 'People', active: true });
  }

  handleEditRule(event) {
    const id = event.target.dataset.id;
    for (const territory of (this.page && this.page.territories) || []) {
      const rule = (territory.rules || []).find((each) => each.id === id);
      if (rule) {
        this.openRule({ ...rule, territoryId: territory.id });
      }
    }
  }

  openRule(rule) {
    this.editor = { kind: 'rule', recordId: rule.id, territoryId: rule.territoryId };
    this.ruleDraft = {
      appliesTo: rule.appliesTo,
      filterJson: rule.filterJson || '',
      summary: rule.summary || '',
      active: rule.active !== false,
      valid: true
    };
    this.ruleCount = undefined;
  }

  handleKindChange(event) {
    this.ruleDraft = {
      ...this.ruleDraft,
      appliesTo: event.detail.value,
      filterJson: '',
      summary: ''
    };
    this.ruleCount = undefined;
  }

  handleFilterChange(event) {
    this.ruleDraft = {
      ...this.ruleDraft,
      filterJson: event.detail.value,
      summary: event.detail.summary || '',
      valid: event.detail.valid
    };
    this.ruleCount = undefined;
  }

  handleRuleActiveChange(event) {
    this.ruleDraft = { ...this.ruleDraft, active: event.detail.checked };
  }

  async handleCheckRule() {
    await this.withBusy(async () => {
      this.ruleCount = await countRule({
        appliesTo: this.ruleDraft.appliesTo,
        filterJson: this.ruleDraft.filterJson
      });
    });
  }

  async handleSaveRule() {
    if (!this.ruleDraft.valid) {
      this.errorMessage = helpText('Territory', 'Territory_Page_FixConditions');
      return;
    }
    const fields = {
      [RULE_APPLIES_TO.fieldApiName]: this.ruleDraft.appliesTo,
      [RULE_FILTER.fieldApiName]: this.ruleDraft.filterJson || null,
      [RULE_SUMMARY.fieldApiName]: (this.ruleDraft.summary || '').slice(0, 255),
      [RULE_ACTIVE.fieldApiName]: this.ruleDraft.active
    };
    await this.withBusy(async () => {
      if (this.editor.recordId) {
        await updateRecord({ fields: { ...fields, [RULE_ID.fieldApiName]: this.editor.recordId } });
      } else {
        await createRecord({
          apiName: RULE.objectApiName,
          fields: { ...fields, [RULE_TERRITORY.fieldApiName]: this.editor.territoryId }
        });
      }
      this.handleCancel();
      this.statusMessage = helpText('Territory', 'Territory_Page_Saved');
      await this.load();
    });
  }

  /* ---------- runs ---------- */

  handleOnlyUnassigned(event) {
    this.onlyUnassigned = event.detail.checked;
  }

  handlePreview() {
    this.run(MODE_PREVIEW);
  }

  async handleAssign() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: this.labels.assign,
      message: helpText('Territory', 'Territory_Page_AssignConfirm'),
      confirmLabel: this.labels.assign,
      cancelLabel: this.labels.cancel
    });
    if (confirmed) {
      this.run(MODE_ASSIGN);
    }
  }

  async run(mode) {
    await this.withBusy(async () => {
      await startRun({ mode, onlyUnassigned: this.onlyUnassigned });
      this.statusMessage = this.labels.running;
      await this.load();
    });
  }

  handleRefresh() {
    this.load();
  }

  handleShowRun(event) {
    const id = event.target.dataset.id;
    this.openRunId = this.openRunId === id ? undefined : id;
  }

  async handleUndo(event) {
    // Read before the dialog: the event's target is gone once it closes.
    const runId = event.target.dataset.id;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: this.labels.undo,
      message: helpText('Territory', 'Territory_Page_UndoConfirm'),
      confirmLabel: this.labels.undo,
      cancelLabel: this.labels.cancel
    });
    if (!confirmed) {
      return;
    }
    await this.withBusy(async () => {
      await undoRun({ runId });
      this.statusMessage = helpText('Territory', 'Territory_Page_Undoing');
      await this.load();
    });
  }

  async withBusy(work) {
    this.busy = true;
    this.errorMessage = undefined;
    this.statusMessage = undefined;
    try {
      await work();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }
}
