import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBoard from '@salesforce/apex/GrantPipelineController.getBoard';
import moveStage from '@salesforce/apex/GrantPipelineController.moveStage';
import markSubmitted from '@salesforce/apex/GrantPipelineController.markSubmitted';
import { buildColumns, deadlineRows, moveTargets } from 'c/grantPipelineModel';
import { format, messageFrom } from 'c/findCsv';

import TITLE from '@salesforce/label/c.Funders_Pipeline_Title';
import INTRO from '@salesforce/label/c.Funders_Pipeline_Intro';
import SCOPE_EVERYONE from '@salesforce/label/c.Funders_Pipeline_ScopeEveryone';
import SCOPE_MINE from '@salesforce/label/c.Funders_Pipeline_ScopeMine';
import NEW_GRANT from '@salesforce/label/c.Funders_Pipeline_NewGrant';
import TILE_OPEN from '@salesforce/label/c.Funders_Pipeline_TileOpen';
import TILE_REQUESTED from '@salesforce/label/c.Funders_Pipeline_TileRequested';
import TILE_AWARDED from '@salesforce/label/c.Funders_Pipeline_TileAwarded';
import AWARDED_DETAIL from '@salesforce/label/c.Funders_Pipeline_AwardedDetail';
import COLUMN_EMPTY from '@salesforce/label/c.Funders_Pipeline_ColumnEmpty';
import EMPTY from '@salesforce/label/c.Funders_Pipeline_Empty';
import TRUNCATED from '@salesforce/label/c.Funders_Pipeline_Truncated';
import READ_ONLY from '@salesforce/label/c.Funders_Pipeline_ReadOnly';
import NO_FUNDER from '@salesforce/label/c.Funders_Pipeline_NoFunder';
import MOVE_TO from '@salesforce/label/c.Core_Shared_MoveTo';
import OPEN from '@salesforce/label/c.Core_Shared_Open';
import CARD_ACTIONS from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';
import DEADLINES from '@salesforce/label/c.Funders_Pipeline_Deadlines';
import DEADLINES_EMPTY from '@salesforce/label/c.Funders_Pipeline_DeadlinesEmpty';
import DAYS_LEFT from '@salesforce/label/c.Funders_Pipeline_DaysLeft';
import DUE_TODAY from '@salesforce/label/c.Funders_Pipeline_DueToday';
import OVERDUE from '@salesforce/label/c.Funders_Pipeline_Overdue';
import AWARD_TITLE from '@salesforce/label/c.Funders_Pipeline_AwardTitle';
import AWARD_AMOUNT from '@salesforce/label/c.Funders_Pipeline_AwardAmount';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import MOVED from '@salesforce/label/c.Core_Shared_MovedTo';
import ERROR_ACTION from '@salesforce/label/c.Funders_Pipeline_ErrorUnexpected';
import MARK_SUBMITTED from '@salesforce/label/c.Funders_Pipeline_MarkSubmitted';
import MARKED_SUBMITTED from '@salesforce/label/c.Funders_Pipeline_MarkedSubmitted';
import KIND_APPLICATION_LABEL from '@salesforce/label/c.Funders_Pipeline_KindApplication';

const ACTION_OPEN = 'open';
const KIND_REQUIREMENT = 'requirement';
const MOVE_PREFIX = 'move:';
const STAGE_AWARDED = 'Awarded';

const messageOf = (error) => messageFrom(error, ERROR_ACTION);

/**
 * The Grant Pipeline tab (F-01, canonical model 29ZH): the open grants by stage as a board, the
 * totals at the top, a menu on each card to open the grant or move it (moving to Awarded asks for
 * the amount awarded), and the application deadlines coming up (R-GN7).
 *
 * The columns and deadline rows are worked out by the framework-free `grantPipelineModel`; this
 * component only draws them and talks to `GrantPipelineController`. Moving is offered only to a
 * person who may edit grants.
 */
export default class GrantPipeline extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    intro: INTRO,
    scopeEveryone: SCOPE_EVERYONE,
    newGrant: NEW_GRANT,
    tileOpen: TILE_OPEN,
    tileRequested: TILE_REQUESTED,
    tileAwarded: TILE_AWARDED,
    columnEmpty: COLUMN_EMPTY,
    empty: EMPTY,
    readOnly: READ_ONLY,
    deadlines: DEADLINES,
    deadlinesEmpty: DEADLINES_EMPTY,
    awardAmount: AWARD_AMOUNT,
    markSubmitted: MARK_SUBMITTED,
    save: SAVE,
    cancel: CANCEL
  };

  scopeOptions = [
    { label: SCOPE_EVERYONE, value: 'all' },
    { label: SCOPE_MINE, value: 'mine' }
  ];

  board;
  columns = [];
  deadlines = [];
  scope = 'all';
  isLoading = true;
  errorMessage;

  awarding;
  awardAmount;
  isSaving = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.board = await getBoard({ mineOnly: this.scope === 'mine' });
      this.errorMessage = undefined;
      this.columns = this.decorate(
        buildColumns(this.board.stages, this.board.stageTotals, this.board.cards)
      );
      const canMark = Boolean(this.board.canMarkSubmitted);
      this.deadlines = deadlineRows(this.board.deadlines, this.board.today).map((row) => {
        const isRequirement = row.kind === KIND_REQUIREMENT;
        return {
          ...row,
          objectApiName: isRequirement ? 'Grant_Requirement__c' : 'Grant__c',
          whatText: isRequirement
            ? `${row.requirementType || ''}: ${row.grantName || ''}`
            : KIND_APPLICATION_LABEL,
          showMark: isRequirement && canMark,
          funderLabel: row.funderName || NO_FUNDER,
          whenText: this.whenText(row.daysLeft),
          whenClass: row.overdue ? 'slds-text-color_error' : 'slds-text-color_weak'
        };
      });
    } catch (error) {
      this.errorMessage = messageOf(error);
      this.columns = [];
      this.deadlines = [];
    } finally {
      this.isLoading = false;
    }
  }

  whenText(daysLeft) {
    if (daysLeft === null || daysLeft === undefined) {
      return '';
    }
    if (daysLeft === 0) {
      return DUE_TODAY;
    }
    return daysLeft < 0 ? format(OVERDUE, -daysLeft) : format(DAYS_LEFT, daysLeft);
  }

  /** What the template needs on each column and card, which it cannot compute itself. */
  decorate(columns) {
    const allStages = this.board.allStages || [];
    const canEdit = this.canEdit;
    return columns.map((column) => ({
      ...column,
      isEmpty: column.cards.length === 0,
      cards: column.cards.map((card) => ({
        ...card,
        funderLabel: card.funderName || NO_FUNDER,
        menuLabel: format(CARD_ACTIONS, card.name),
        menuItems: this.menuFor(card, allStages, canEdit)
      }))
    }));
  }

  menuFor(card, allStages, canEdit) {
    const items = [{ label: OPEN, value: ACTION_OPEN, key: ACTION_OPEN }];
    if (!canEdit) {
      return items;
    }
    moveTargets(allStages, card.stage).forEach((stage) =>
      items.push({
        label: format(MOVE_TO, stage),
        value: MOVE_PREFIX + stage,
        key: MOVE_PREFIX + stage
      })
    );
    return items;
  }

  get canEdit() {
    return Boolean(this.board && this.board.canEdit);
  }

  get canCreate() {
    return Boolean(this.board && this.board.canCreate);
  }

  get showReadOnly() {
    return Boolean(this.board) && !this.canEdit;
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get hasBoard() {
    return Boolean(this.board) && !this.hasError;
  }

  get isEmpty() {
    return this.hasBoard && this.board.openCount === 0;
  }

  get showColumns() {
    return this.hasBoard && !this.isEmpty;
  }

  get hasDeadlines() {
    return this.deadlines.length > 0;
  }

  get truncatedMessage() {
    return this.board && this.board.truncated ? format(TRUNCATED, this.board.cards.length) : null;
  }

  get awardedDetail() {
    return this.board ? format(AWARDED_DETAIL, this.board.awardedCount) : '';
  }

  get isAwarding() {
    return Boolean(this.awarding);
  }

  get awardTitle() {
    return this.awarding ? `${AWARD_TITLE}: ${this.awarding.name}` : AWARD_TITLE;
  }

  handleScope(event) {
    this.scope = event.detail.value;
    this.load();
  }

  handleNewGrant() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Grant__c', actionName: 'new' }
    });
  }

  handleOpenDeadline(event) {
    const { id, object } = event.currentTarget.dataset;
    this.openRecord(id, object);
  }

  openRecord(recordId, objectApiName = 'Grant__c') {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId, objectApiName, actionName: 'view' }
    });
  }

  async handleMarkSubmitted(event) {
    const requirementId = event.currentTarget.dataset.id;
    try {
      await markSubmitted({ requirementId });
      this.toast(MARKED_SUBMITTED, 'success');
      await this.load();
    } catch (error) {
      this.toast(messageOf(error), 'error');
    }
  }

  handleCardMenu(event) {
    const grantId = event.target.dataset.id;
    const value = event.detail.value;
    if (value === ACTION_OPEN) {
      this.openRecord(grantId);
    } else if (value.startsWith(MOVE_PREFIX)) {
      const stage = value.substring(MOVE_PREFIX.length);
      if (stage === STAGE_AWARDED) {
        this.startAward(grantId);
      } else {
        this.move(grantId, stage, null);
      }
    }
  }

  findCard(grantId) {
    for (const column of this.columns) {
      const card = column.cards.find((candidate) => candidate.id === grantId);
      if (card) {
        return card;
      }
    }
    return undefined;
  }

  async move(grantId, stage, amountAwarded) {
    try {
      await moveStage({ grantId, stage, amountAwarded });
      this.toast(format(MOVED, stage), 'success');
      await this.load();
      return true;
    } catch (error) {
      this.toast(messageOf(error), 'error');
      return false;
    }
  }

  // ---------------------------------------------------------------- Awarded

  startAward(grantId) {
    const card = this.findCard(grantId);
    if (!card) {
      return;
    }
    this.awarding = card;
    this.awardAmount = card.amountRequested;
  }

  handleAwardAmount(event) {
    this.awardAmount = event.detail ? event.detail.value : event.target.value;
  }

  handleCancelAward() {
    this.awarding = undefined;
  }

  async handleSaveAward() {
    const input = this.template.querySelector('[data-id="award-amount"]');
    if (input && typeof input.reportValidity === 'function' && input.reportValidity() === false) {
      return;
    }
    this.isSaving = true;
    const amount =
      this.awardAmount === '' || this.awardAmount === undefined || this.awardAmount === null
        ? null
        : Number(this.awardAmount);
    const moved = await this.move(this.awarding.id, STAGE_AWARDED, amount);
    this.isSaving = false;
    if (moved) {
      this.awarding = undefined;
    }
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
