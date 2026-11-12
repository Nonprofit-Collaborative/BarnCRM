import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBoard from '@salesforce/apex/GrantPipelineController.getBoard';
import moveStage from '@salesforce/apex/GrantPipelineController.moveStage';
import markSubmitted from '@salesforce/apex/GrantPipelineController.markSubmitted';
import undoSubmitted from '@salesforce/apex/GrantPipelineController.undoSubmitted';
import {
  buildColumns,
  closedStages,
  deadlineRows,
  daysBetween,
  initialsOf,
  markDrag,
  moveTargets,
  urgencyOf
} from 'c/grantPipelineModel';
import { createDragController } from 'c/barnDrag';
import { dragInstructions, dragMessages } from 'c/barnDragText';
import { format, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import GrantAwardModal from 'c/grantAwardModal';

import TITLE from '@salesforce/label/c.Funders_Pipeline_Title';
import SCOPE_EVERYONE from '@salesforce/label/c.Funders_Pipeline_ScopeEveryone';
import SCOPE_MINE from '@salesforce/label/c.Funders_Pipeline_ScopeMine';
import NEW_GRANT from '@salesforce/label/c.Funders_Pipeline_NewGrant';
import TILE_OPEN from '@salesforce/label/c.Funders_Pipeline_TileOpen';
import TILE_REQUESTED from '@salesforce/label/c.Funders_Pipeline_TileRequested';
import TILE_AWARDED from '@salesforce/label/c.Funders_Pipeline_TileAwarded';
import AWARDED_DETAIL from '@salesforce/label/c.Funders_Pipeline_AwardedDetail';
import NO_FUNDER from '@salesforce/label/c.Funders_Pipeline_NoFunder';
import NO_GRANTS from '@salesforce/label/c.Funders_Pipeline_NoGrants';
import NO_DEADLINES from '@salesforce/label/c.Funders_Pipeline_NoDeadlines';
import MOVE_TO from '@salesforce/label/c.Core_Shared_MoveTo';
import OPEN from '@salesforce/label/c.Core_Shared_Open';
import CARD_ACTIONS from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';
import DEADLINES from '@salesforce/label/c.Funders_Pipeline_Deadlines';
import DAYS_LEFT from '@salesforce/label/c.Funders_Pipeline_DaysLeft';
import DUE_TODAY from '@salesforce/label/c.Funders_Pipeline_DueToday';
import OVERDUE from '@salesforce/label/c.Funders_Pipeline_Overdue';
import AWARD_TITLE from '@salesforce/label/c.Funders_Pipeline_AwardTitle';
import MOVED from '@salesforce/label/c.Core_Shared_MovedTo';
import MARK_SUBMITTED from '@salesforce/label/c.Funders_Pipeline_MarkSubmitted';
import MARKED_SUBMITTED from '@salesforce/label/c.Funders_Pipeline_MarkedSubmitted';
import UNDO from '@salesforce/label/c.Core_AutoMerge_Undo';
import KIND_APPLICATION_LABEL from '@salesforce/label/c.Funders_Pipeline_KindApplication';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const ACTION_OPEN = 'open';
const KIND_REQUIREMENT = 'requirement';
const MOVE_PREFIX = 'move:';
const STAGE_AWARDED = 'Awarded';
const HELP_PACKAGES = ['Funders', 'Core'];

const messageOf = (error) => messageFrom(error, helpText('Funders', 'Funders_Shared_NotSaved'));

/** A record's page in Lightning, for a link's href; a click navigates in place instead. */
const recordHref = (recordId) => `/lightning/r/${recordId}/view`;

/**
 * The Grant Pipeline tab (F-01, canonical model 29ZH): the open grants by stage as a board, the
 * totals as tiles, each grant's name a link and a menu on each card to open it or move it (moving
 * to Awarded opens Record the Award), and the deadlines coming up (R-GN7), each requirement with
 * Mark Submitted and its Undo (modules-17).
 *
 * A person who may edit grants can also drag a card to another column, or onto the Awarded,
 * Declined and Withdrawn zones at the end of the board (DnD-1, c/barnDrag): by pointer, by touch
 * after a short press and hold, or by keyboard from the card's handle (Space, arrows, Space;
 * Escape cancels), each step announced. The card menu stays, and on a phone it is the main way.
 * Dropping on Awarded opens Record the Award, as the menu does.
 *
 * The columns, deadline rows and urgency are worked out by the framework-free
 * `grantPipelineModel`; this component only draws them and talks to `GrantPipelineController`.
 * Moving is offered only to a person who may edit grants.
 */
export default class GrantPipeline extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded(HELP_PACKAGES);

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Funders', 'Funders_Pipeline_Intro');
    },
    get empty() {
      return helpText('Funders', 'Funders_Pipeline_Empty');
    },
    get deadlinesEmpty() {
      return helpText('Funders', 'Funders_Pipeline_DeadlinesEmpty');
    },
    scopeEveryone: SCOPE_EVERYONE,
    newGrant: NEW_GRANT,
    tileOpen: TILE_OPEN,
    tileRequested: TILE_REQUESTED,
    tileAwarded: TILE_AWARDED,
    get columnEmpty() {
      return helpText('Funders', 'Funders_Pipeline_ColumnEmpty');
    },
    noGrants: NO_GRANTS,
    noDeadlines: NO_DEADLINES,
    get readOnly() {
      return helpText('Funders', 'Funders_Pipeline_ReadOnly');
    },
    deadlines: DEADLINES,
    markSubmitted: MARK_SUBMITTED,
    markedSubmitted: MARKED_SUBMITTED,
    undo: UNDO
  };

  icon = iconFor('Grant_Pipeline');

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
  /** What the last Mark Submitted replaced, while its Undo is offered. */
  lastMarked;
  /** The drag in progress, from c/barnDrag, for the highlight. */
  dragState;
  /** What the board last announced to a screen reader. */
  liveText = '';
  drag;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.drag = createDragController({
      root: this.template,
      layout: 'columns',
      // Read when spoken, not now: the help catalog may still be on its way.
      messages: {
        pickedUp: (name) => dragMessages().pickedUp(name),
        position: (zone, position, count) => dragMessages().position(zone, position, count),
        dropped: (name, zone) => dragMessages().dropped(name, zone),
        cancelled: (name) => dragMessages().cancelled(name)
      },
      announce: (text) => {
        this.liveText = text;
      },
      onChange: (state) => {
        this.dragState = state;
      },
      canDrop: (itemId, fromZone, toZone) => fromZone !== toZone,
      onDrop: ({ itemId, fromZone, toZone }) => {
        if (!toZone || fromZone === toZone) {
          return false;
        }
        this.moveTo(itemId, toZone);
        return true;
      }
    });
    this.load();
  }

  disconnectedCallback() {
    if (this.drag) {
      this.drag.destroy();
    }
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
          ...this.urgency(row.daysLeft),
          objectApiName: isRequirement ? 'Grant_Requirement__c' : 'Grant__c',
          whatText: isRequirement
            ? `${row.requirementType || ''}: ${row.grantName || ''}`
            : KIND_APPLICATION_LABEL,
          showMark: isRequirement && canMark,
          funderLabel: row.funderName || NO_FUNDER
        };
      });
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Funders', 'Funders_Pipeline_LoadFailed'));
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

  /** The days-left words and, when due soon or overdue, the status for its badge (vis-modules-17). */
  urgency(daysLeft) {
    const status = urgencyOf(daysLeft);
    return { whenText: this.whenText(daysLeft), urgencyStatus: status, isUrgent: Boolean(status) };
  }

  /** What the template needs on each column and card, which it cannot compute itself. */
  decorate(columns) {
    const allStages = this.board.allStages || [];
    const canEdit = this.canEdit;
    const today = this.board.today;
    return columns.map((column) => ({
      ...column,
      isEmpty: column.cards.length === 0,
      cards: column.cards.map((card) => ({
        ...card,
        ...this.urgency(card.deadline ? daysBetween(today, card.deadline) : null),
        href: recordHref(card.id),
        funderLabel: card.funderName || NO_FUNDER,
        ownerInitials: initialsOf(card.ownerName),
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

  /** The columns as drawn: the drag highlight on the target column and the carried card. */
  get boardColumns() {
    return markDrag(this.columns, this.dragState).map((column) => ({
      ...column,
      zoneClass:
        'grant-column slds-box slds-box_x-small slds-theme_shade' +
        (column.isTarget ? ' grant-zone_target' : ''),
      cards: column.cards.map((card) => ({
        ...card,
        cardClass:
          'slds-item grant-card slds-var-m-bottom_x-small' +
          (card.isDragging ? ' grant-card_dragging' : '')
      }))
    }));
  }

  /** Awarded, Declined and Withdrawn as drop zones at the end of the board (DnD-1). */
  get dropZones() {
    if (!this.canEdit) {
      return [];
    }
    const over = this.dragState && this.dragState.active ? this.dragState.overZone : null;
    return closedStages(this.board.allStages, this.board.stages).map((stage) => ({
      key: stage,
      stage,
      zoneClass:
        'grant-drop-zone slds-box slds-box_x-small' + (over === stage ? ' grant-zone_target' : '')
    }));
  }

  get dragHelp() {
    return dragInstructions();
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
    return this.board && this.board.truncated
      ? format(helpText('Funders', 'Funders_Pipeline_Truncated'), this.board.cards.length)
      : null;
  }

  get awardedDetail() {
    return this.board ? format(AWARDED_DETAIL, this.board.awardedCount) : '';
  }

  get showUndo() {
    return Boolean(this.lastMarked);
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

  /** A card's name is a link (modules-2); a plain click opens the grant in place. */
  handleOpenCard(event) {
    event.preventDefault();
    this.openRecord(event.currentTarget.dataset.id);
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
      const previous = await markSubmitted({ requirementId });
      this.lastMarked = previous && previous.id ? previous : undefined;
      await this.load();
    } catch (error) {
      this.toast(messageOf(error), 'error');
    }
  }

  async handleUndoMarked() {
    const previous = this.lastMarked;
    if (!previous) {
      return;
    }
    try {
      await undoSubmitted({
        requirementId: previous.id,
        status: previous.status,
        submittedDate: previous.dateValue || null
      });
      this.lastMarked = undefined;
      this.toast(helpText('Funders', 'Funders_Undo_Done'), 'success');
      await this.load();
    } catch (error) {
      this.lastMarked = undefined;
      this.toast(messageOf(error), 'error');
    }
  }

  handleDragPointerDown(event) {
    this.drag.pointerDown(event);
  }

  handleDragKeyDown(event) {
    this.drag.keyDown(event);
  }

  handleCardMenu(event) {
    const grantId = event.target.dataset.id;
    const value = event.detail.value;
    if (value === ACTION_OPEN) {
      this.openRecord(grantId);
    } else if (value.startsWith(MOVE_PREFIX)) {
      this.moveTo(grantId, value.substring(MOVE_PREFIX.length));
    }
  }

  /** Moves a grant to a stage; Awarded opens Record the Award instead. */
  moveTo(grantId, stage) {
    if (stage === STAGE_AWARDED) {
      return this.startAward(grantId);
    }
    return this.move(grantId, stage);
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

  async move(grantId, stage) {
    try {
      await moveStage({ grantId, stage, amountAwarded: null });
      this.toast(format(MOVED, stage), 'success');
      await this.load();
      return true;
    } catch (error) {
      this.toast(messageOf(error), 'error');
      return false;
    }
  }

  // ---------------------------------------------------------------- Awarded

  /** Record the Award (modules-16): the dialog saves; on save, a link to build the schedule. */
  async startAward(grantId) {
    const card = this.findCard(grantId);
    if (!card) {
      return false;
    }
    const result = await GrantAwardModal.open({
      label: `${AWARD_TITLE}: ${card.name}`,
      size: 'small',
      grant: card
    });
    if (!result || !result.saved) {
      return false;
    }
    this.dispatchEvent(
      new ShowToastEvent({
        message: helpText('Funders', 'Funders_Award_Saved'),
        messageData: [{ url: recordHref(card.id), label: card.name }],
        variant: 'success'
      })
    );
    await this.load();
    return true;
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
