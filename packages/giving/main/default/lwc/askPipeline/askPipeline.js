import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBoard from '@salesforce/apex/AskPipelineController.getBoard';
import moveStage from '@salesforce/apex/AskPipelineController.moveStage';
import closeAsk from '@salesforce/apex/AskPipelineController.closeAsk';
import reopenAsk from '@salesforce/apex/AskPipelineController.reopenAsk';
import BarnConfirmModal from 'c/barnConfirmModal';
import { iconFor } from 'c/barnIcons';
import { buildColumns, closedColumn, listRows } from 'c/askPipelineModel';
import { createDragController } from 'c/barnDrag';
import { dragInstructions, dragMessages } from 'c/barnDragText';

import TITLE from '@salesforce/label/c.Giving_AskPipeline_Title';
import VIEW_BOARD from '@salesforce/label/c.Giving_AskPipeline_ViewBoard';
import VIEW_LIST from '@salesforce/label/c.Giving_AskPipeline_ViewList';
import SCOPE_EVERYONE from '@salesforce/label/c.Giving_AskPipeline_ScopeEveryone';
import SCOPE_MINE from '@salesforce/label/c.Giving_AskPipeline_ScopeMine';
import NEW_ASK from '@salesforce/label/c.Giving_AskPipeline_NewAsk';
import TILE_OPEN from '@salesforce/label/c.Giving_AskPipeline_TileOpen';
import TILE_OPEN_AMOUNT from '@salesforce/label/c.Giving_AskPipeline_TileOpenAmount';
import TILE_WON from '@salesforce/label/c.Giving_AskPipeline_TileWon';
import TILE_DECLINED from '@salesforce/label/c.Giving_AskPipeline_TileDeclined';
import WON_DETAIL from '@salesforce/label/c.Giving_AskPipeline_WonDetail';
import OTHER_COLUMN_LABEL from '@salesforce/label/c.Giving_AskPipeline_OtherColumn';
import NO_DONOR from '@salesforce/label/c.Giving_AskPipeline_NoDonor';
import DAYS_IN_STAGE from '@salesforce/label/c.Giving_AskPipeline_DaysInStage';
import MOVE_TO from '@salesforce/label/c.Core_Shared_MoveTo';
import OPEN from '@salesforce/label/c.Core_Shared_Open';
import CLOSE_ASK from '@salesforce/label/c.Giving_AskPipeline_CloseAsk';
import CARD_ACTIONS from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';
import COL_ASK from '@salesforce/label/c.Giving_AskPipeline_ColAsk';
import COL_DONOR from '@salesforce/label/c.Giving_GiftBatch_ColumnDonor';
import COL_STAGE from '@salesforce/label/c.Core_Shared_Stage';
import COL_AMOUNT from '@salesforce/label/c.Giving_AskPipeline_ColAmount';
import COL_TARGET from '@salesforce/label/c.Core_Shared_TargetDate';
import COL_NEXT_STEP from '@salesforce/label/c.Giving_AskPipeline_ColNextStep';
import COL_ASSIGNED from '@salesforce/label/c.Core_Shared_AssignedTo';
import COL_DAYS from '@salesforce/label/c.Giving_AskPipeline_ColDays';
import OUTCOME_LABEL from '@salesforce/label/c.Giving_AskPipeline_OutcomeLabel';
import OUTCOME_WON from '@salesforce/label/c.Giving_AskPipeline_OutcomeWon';
import OUTCOME_DECLINED from '@salesforce/label/c.Giving_AskPipeline_OutcomeDeclined';
import OUTCOME_WITHDRAWN from '@salesforce/label/c.Giving_AskPipeline_OutcomeWithdrawn';
import RESULT_LABEL from '@salesforce/label/c.Giving_AskPipeline_ResultLabel';
import RESULT_GIFT from '@salesforce/label/c.Giving_AskPipeline_ResultGift';
import RESULT_PLEDGE from '@salesforce/label/c.Giving_AskPipeline_ResultPledge';
import RESULT_LINK from '@salesforce/label/c.Giving_AskPipeline_ResultLink';
import RESULT_LATER from '@salesforce/label/c.Giving_AskPipeline_ResultLater';
import FIELD_AMOUNT from '@salesforce/label/c.Giving_AskPipeline_FieldAmount';
import FIELD_GIFT_DATE from '@salesforce/label/c.Giving_AskPipeline_FieldGiftDate';
import FIELD_GIFT_TYPE from '@salesforce/label/c.Giving_AskPipeline_FieldGiftType';
import FIELD_PLEDGE_TOTAL from '@salesforce/label/c.Giving_AskPipeline_FieldPledgeTotal';
import FIELD_FIRST_PAYMENT from '@salesforce/label/c.Giving_AskPipeline_FieldFirstPayment';
import FIELD_FREQUENCY from '@salesforce/label/c.Giving_AskPipeline_FieldFrequency';
import FIELD_PAYMENTS from '@salesforce/label/c.Giving_AskPipeline_FieldPayments';
import FIELD_LINK_GIFT from '@salesforce/label/c.Giving_Section_Gift';
import FIELD_LINK_PLEDGE from '@salesforce/label/c.Giving_AskPipeline_FieldLinkPledge';
import FIELD_NEXT_ASK from '@salesforce/label/c.Giving_AskPipeline_FieldNextAsk';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import MOVED from '@salesforce/label/c.Core_Shared_MovedTo';
import REOPEN_ASK from '@salesforce/label/c.Giving_AskPipeline_ReopenAsk';
import RECENTLY_CLOSED from '@salesforce/label/c.Giving_AskPipeline_RecentlyClosed';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { messageFrom } from 'c/findCsv';

const ACTION_OPEN = 'open';
const ACTION_CLOSE = 'close';
const ACTION_REOPEN = 'reopen';
const WON = 'Won';
const CARD_CLASS = 'slds-item ask-card slds-var-m-bottom_x-small';
const COLUMN_CLASS = 'ask-column';
const MOVE_PREFIX = 'move:';
const CONTACT_PREFIX = '003';

const format = (template, ...values) =>
  values.reduce((text, value, index) => text.replace(`{${index}}`, value), template);

const messageOf = (error) =>
  messageFrom(error, helpText('Giving', 'Giving_AskPipeline_ErrorAction'));

/**
 * The Ask Pipeline (G-26, canonical model Section 25R): every open ask by stage as a board or a
 * list, with the totals at the top, a drag or a menu to move an ask, and the Close Ask dialog that
 * records what a win produced (R-SO5). A Recently Closed column after the stages holds the asks
 * closed in the last 30 days, each with Reopen Ask on its menu (people-giving-19).
 *
 * Dragging a card runs on the Core kit's `c/barnDrag` (pointer events, so touch works after a
 * press and hold, plus Space and the arrow keys); the card's Move to menu stays, and every move
 * is announced in a live region.
 *
 * The columns are worked out by the framework-free `askPipelineModel`; this component only draws
 * them and talks to `AskPipelineController`. Moving, closing and reopening are offered only to a
 * person who may edit asks.
 */
export default class AskPipeline extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded(['Giving', 'Core']);

  icons = { pipeline: iconFor('Ask_Pipeline') };

  labels = {
    title: TITLE,
    get dragInstructions() {
      return dragInstructions();
    },
    get intro() {
      return helpText('Giving', 'Giving_AskPipeline_Intro');
    },
    viewBoard: VIEW_BOARD,
    viewList: VIEW_LIST,
    scopeEveryone: SCOPE_EVERYONE,
    scopeMine: SCOPE_MINE,
    newAsk: NEW_ASK,
    tileOpen: TILE_OPEN,
    tileOpenAmount: TILE_OPEN_AMOUNT,
    tileWon: TILE_WON,
    tileDeclined: TILE_DECLINED,
    get columnEmpty() {
      return helpText('Giving', 'Giving_AskPipeline_ColumnEmpty');
    },
    get empty() {
      return helpText('Giving', 'Giving_AskPipeline_Empty');
    },
    get readOnly() {
      return helpText('Giving', 'Giving_AskPipeline_ReadOnly');
    },
    closeAsk: CLOSE_ASK,
    outcomeLabel: OUTCOME_LABEL,
    resultLabel: RESULT_LABEL,
    fieldAmount: FIELD_AMOUNT,
    fieldGiftDate: FIELD_GIFT_DATE,
    fieldGiftType: FIELD_GIFT_TYPE,
    fieldPledgeTotal: FIELD_PLEDGE_TOTAL,
    fieldFirstPayment: FIELD_FIRST_PAYMENT,
    fieldFrequency: FIELD_FREQUENCY,
    fieldPayments: FIELD_PAYMENTS,
    fieldLinkGift: FIELD_LINK_GIFT,
    fieldLinkPledge: FIELD_LINK_PLEDGE,
    get linkHelp() {
      return helpText('Giving', 'Giving_AskPipeline_LinkHelp');
    },
    fieldNextAsk: FIELD_NEXT_ASK,
    get nextAskHelp() {
      return helpText('Giving', 'Giving_AskPipeline_NextAskHelp');
    },
    save: SAVE,
    cancel: CANCEL
  };

  viewOptions = [
    { label: VIEW_BOARD, value: 'board' },
    { label: VIEW_LIST, value: 'list' }
  ];

  scopeOptions = [
    { label: SCOPE_EVERYONE, value: 'all' },
    { label: SCOPE_MINE, value: 'mine' }
  ];

  outcomeOptions = [
    { label: OUTCOME_WON, value: 'Won' },
    { label: OUTCOME_DECLINED, value: 'Declined' },
    { label: OUTCOME_WITHDRAWN, value: 'Withdrawn' }
  ];

  resultOptions = [
    { label: RESULT_GIFT, value: 'gift' },
    { label: RESULT_PLEDGE, value: 'pledge' },
    { label: RESULT_LINK, value: 'link' },
    { label: RESULT_LATER, value: 'later' }
  ];

  listColumns = [
    {
      label: COL_ASK,
      type: 'button',
      typeAttributes: { label: { fieldName: 'name' }, name: ACTION_OPEN, variant: 'base' }
    },
    { label: COL_DONOR, fieldName: 'donorLabel' },
    { label: COL_STAGE, fieldName: 'stageLabel' },
    { label: COL_AMOUNT, fieldName: 'amount', type: 'currency' },
    { label: COL_TARGET, fieldName: 'targetDate', type: 'date-local' },
    { label: COL_NEXT_STEP, fieldName: 'nextStep' },
    { label: COL_ASSIGNED, fieldName: 'ownerName' },
    { label: COL_DAYS, fieldName: 'daysInStage', type: 'number' }
  ];

  /** The display info every record picker in the suite carries, so two look-alikes differ. */
  giftDisplayInfo = { primaryField: 'Name', additionalFields: ['Gift_Date__c', 'Amount__c'] };
  pledgeDisplayInfo = {
    primaryField: 'Name',
    additionalFields: ['Start_Date__c', 'Expected_Total__c']
  };

  board;
  columns = [];
  closed;
  view = 'board';
  scope = 'all';
  isLoading = true;
  errorMessage;
  liveMessage = '';

  /** The drag in progress, as c/barnDrag reports it: the carried card and the column under it. */
  dragState = {};
  drag;

  closing;
  form = {};
  closeError;
  isSaving = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(['Giving', 'Core']).then(() => {
        this.helpReady = true;
      });
    }
    this.drag = createDragController({
      root: this.template,
      layout: 'columns',
      messages: dragMessages(),
      announce: (text) => {
        this.liveMessage = text;
      },
      onChange: (state) => {
        this.dragState = state;
      },
      onDrop: ({ itemId, toZone }) => {
        const card = this.findCard(itemId);
        if (!toZone || !card || card.stage === toZone) {
          return false;
        }
        return this.move(itemId, toZone, false);
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
        buildColumns(this.board.stages, this.board.stageTotals, this.board.cards, this.board.today)
      );
      const closed = closedColumn(this.board.recentlyClosed);
      this.closed = closed ? this.decorateClosed(closed) : undefined;
    } catch (error) {
      this.errorMessage = messageOf(error);
      this.columns = [];
      this.closed = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  /** What the template needs on each column and card, which it cannot compute itself. */
  decorate(columns) {
    const stages = this.board.stages || [];
    const canEdit = this.canEdit;
    return columns.map((column) => ({
      ...column,
      title: column.isOther ? OTHER_COLUMN_LABEL : column.stage,
      isEmpty: column.cards.length === 0,
      cards: column.cards.map((card) => ({
        ...card,
        donorLabel: card.donorName || NO_DONOR,
        stageLabel: column.isOther ? `${card.stage} (${OTHER_COLUMN_LABEL})` : card.stage,
        daysText:
          card.daysInStage === null || card.daysInStage === undefined
            ? null
            : format(DAYS_IN_STAGE, card.daysInStage),
        menuLabel: format(CARD_ACTIONS, card.name),
        canDrag: canEdit,
        menuItems: this.menuFor(card, stages, canEdit)
      }))
    }));
  }

  /** The Recently Closed column: each card shows how it ended and offers Reopen Ask. */
  decorateClosed(column) {
    const canEdit = this.canEdit;
    const outcomes = {
      Won: OUTCOME_WON,
      Declined: OUTCOME_DECLINED,
      Withdrawn: OUTCOME_WITHDRAWN
    };
    return {
      ...column,
      title: RECENTLY_CLOSED,
      isEmpty: false,
      cards: column.cards.map((card) => {
        const items = [{ label: OPEN, value: ACTION_OPEN, key: ACTION_OPEN }];
        if (canEdit) {
          items.push({ label: REOPEN_ASK, value: ACTION_REOPEN, key: ACTION_REOPEN });
        }
        return {
          ...card,
          donorLabel: card.donorName || NO_DONOR,
          daysText: null,
          menuLabel: format(CARD_ACTIONS, card.name),
          canDrag: false,
          outcomeLabel: outcomes[card.outcome] || card.outcome,
          outcomeStatus: card.outcome === WON ? 'success' : 'closed',
          menuItems: items
        };
      })
    };
  }

  menuFor(card, stages, canEdit) {
    const items = [{ label: OPEN, value: ACTION_OPEN, key: ACTION_OPEN }];
    if (!canEdit) {
      return items;
    }
    stages
      .filter((stage) => stage !== card.stage)
      .forEach((stage) =>
        items.push({
          label: format(MOVE_TO, stage),
          value: MOVE_PREFIX + stage,
          key: MOVE_PREFIX + stage
        })
      );
    items.push({ label: CLOSE_ASK, value: ACTION_CLOSE, key: ACTION_CLOSE });
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

  /** Nothing open and nothing recently closed: the empty state instead of a bare board. */
  get isEmpty() {
    return this.hasBoard && this.board.openCount === 0 && !this.closed;
  }

  /** The stage columns, then Recently Closed, with the drop highlight and the carried card. */
  get boardColumns() {
    const all = this.closed ? [...this.columns, this.closed] : this.columns;
    const state = this.dragState || {};
    return all.map((column) => {
      // Only a stage in the list takes a drop: not Other, not Recently Closed.
      const isZone = this.canEdit && !column.isOther && !column.isClosed;
      return {
        ...column,
        zoneId: isZone ? column.stage : undefined,
        dropClass:
          state.active && isZone && column.stage === state.overZone
            ? `${COLUMN_CLASS} ask-column_drop`
            : COLUMN_CLASS,
        cards: column.cards.map((card) => {
          let cardClass = CARD_CLASS;
          if (card.canDrag && isZone) {
            cardClass += ' ask-card_movable';
          }
          if (state.active && card.id === state.itemId) {
            cardClass += ' ask-card_dragging';
          }
          const movable = card.canDrag && isZone;
          return {
            ...card,
            cardClass,
            showHandle: movable,
            dragId: movable ? card.id : undefined,
            tabIndex: movable ? '0' : undefined
          };
        })
      };
    });
  }

  get showBoard() {
    return this.hasBoard && !this.isEmpty && this.view === 'board';
  }

  get showList() {
    return this.hasBoard && !this.isEmpty && this.view === 'list';
  }

  get truncatedMessage() {
    return this.board && this.board.truncated
      ? format(helpText('Giving', 'Giving_AskPipeline_Truncated'), this.board.cards.length)
      : null;
  }

  get wonDetail() {
    return this.board ? format(WON_DETAIL, this.board.wonCount) : '';
  }

  get rows() {
    return listRows(this.columns);
  }

  handleView(event) {
    this.view = event.detail.value;
  }

  handleScope(event) {
    this.scope = event.detail.value;
    this.load();
  }

  handleNewAsk() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Ask__c', actionName: 'new' }
    });
  }

  openRecord(recordId) {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId, objectApiName: 'Ask__c', actionName: 'view' }
    });
  }

  handleRowAction(event) {
    this.openRecord(event.detail.row.id);
  }

  handleCardMenu(event) {
    const askId = event.target.dataset.id;
    const value = event.detail.value;
    if (value === ACTION_OPEN) {
      this.openRecord(askId);
    } else if (value === ACTION_CLOSE) {
      this.startClose(askId);
    } else if (value === ACTION_REOPEN) {
      this.reopen(askId);
    } else if (value.startsWith(MOVE_PREFIX)) {
      this.move(askId, value.substring(MOVE_PREFIX.length));
    }
  }

  // Drag and drop through c/barnDrag; the card's Move to menu does the same.
  handlePointerDown(event) {
    if (event.currentTarget.dataset.dragId) {
      this.drag.pointerDown(event);
    }
  }

  handleDragKey(event) {
    if (event.currentTarget.dataset.dragId) {
      this.drag.keyDown(event);
    }
  }

  /**
   * Moves an ask to another stage. A move from the menu is announced here; a drag is announced
   * by the drag controller. Resolves true when the move was saved, false when it was refused.
   */
  async move(askId, stage, announce = true) {
    const card = this.findCard(askId);
    try {
      await moveStage({ askId, stage });
      this.toast(format(MOVED, stage), 'success');
      if (announce) {
        this.liveMessage = helpText(
          'Giving',
          'Giving_AskPipeline_Moved',
          card ? card.donorLabel : askId,
          stage
        );
      }
      await this.load();
      return true;
    } catch (error) {
      this.toast(messageOf(error), 'error');
      return false;
    }
  }

  /** Reopens a recently closed ask after a one-line confirm (people-giving-19). */
  async reopen(askId) {
    const card = this.closed && this.closed.cards.find((candidate) => candidate.id === askId);
    if (!card) {
      return;
    }
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: REOPEN_ASK,
      message: helpText('Giving', 'Giving_AskPipeline_ReopenConfirm', card.donorLabel, card.stage),
      confirmLabel: REOPEN_ASK,
      cancelLabel: CANCEL
    });
    if (!confirmed) {
      return;
    }
    try {
      await reopenAsk({ askId });
      const done = helpText('Giving', 'Giving_AskPipeline_Reopened', card.donorLabel, card.stage);
      this.toast(done, 'success');
      this.liveMessage = done;
      await this.load();
    } catch (error) {
      this.toast(messageOf(error), 'error');
    }
  }

  findCard(askId) {
    for (const column of this.columns) {
      const card = column.cards.find((candidate) => candidate.id === askId);
      if (card) {
        return card;
      }
    }
    return undefined;
  }

  // ---------------------------------------------------------------- Close Ask

  startClose(askId) {
    const card = this.findCard(askId);
    if (!card) {
      return;
    }
    this.closing = card;
    this.closeError = undefined;
    this.form = {
      outcome: 'Won',
      result: 'gift',
      amount: card.amount,
      giftDate: this.board.today,
      giftType: undefined,
      frequency: 'Monthly',
      payments: 12,
      linkedId: undefined,
      nextAskDate: undefined
    };
  }

  get isClosing() {
    return Boolean(this.closing);
  }

  get closeTitle() {
    return this.closing ? `${CLOSE_ASK}: ${this.closing.donorLabel}` : CLOSE_ASK;
  }

  get isWon() {
    return this.form.outcome === 'Won';
  }

  get isGift() {
    return this.isWon && this.form.result === 'gift';
  }

  get isPledge() {
    return this.isWon && this.form.result === 'pledge';
  }

  get isLink() {
    return this.isWon && this.form.result === 'link';
  }

  get hasCloseError() {
    return Boolean(this.closeError);
  }

  get giftTypes() {
    return (this.board && this.board.giftTypes) || [];
  }

  get frequencies() {
    return (this.board && this.board.frequencies) || [];
  }

  /** Only the ask's own donor's records are offered (R-SO5); the server checks again. */
  get donorFilter() {
    const donorId = this.closing && this.closing.donorId;
    if (!donorId) {
      return undefined;
    }
    const fieldPath = donorId.startsWith(CONTACT_PREFIX) ? 'Donor_Contact__c' : 'Donor_Account__c';
    return { criteria: [{ fieldPath, operator: 'eq', value: donorId }] };
  }

  handleFormChange(event) {
    const field = event.target.dataset.field;
    let value = event.detail ? event.detail.value : event.target.value;
    if (field === 'linkedId') {
      value = event.detail ? event.detail.recordId : undefined;
    }
    this.form = { ...this.form, [field]: value };
  }

  handleCancelClose() {
    this.closing = undefined;
    this.closeError = undefined;
  }

  async handleSaveClose() {
    const inputs = [...this.template.querySelectorAll('[data-close-input]')];
    const valid = inputs.every(
      (input) => typeof input.reportValidity !== 'function' || input.reportValidity() !== false
    );
    if (!valid) {
      return;
    }
    this.isSaving = true;
    this.closeError = undefined;
    const form = this.form;
    try {
      const result = await closeAsk({
        input: {
          askId: this.closing.id,
          outcome: form.outcome,
          result: this.isWon ? form.result : null,
          amount: form.amount === '' || form.amount === undefined ? null : Number(form.amount),
          giftDate: form.giftDate || null,
          giftType: form.giftType || null,
          frequency: form.frequency || null,
          payments: form.payments ? Number(form.payments) : null,
          linkedId: form.linkedId || null,
          nextAskDate: form.nextAskDate || null
        }
      });
      if (result && result.success) {
        this.closing = undefined;
        this.toast(helpText('Giving', 'Giving_AskPipeline_Closed'), 'success');
        await this.load();
      } else {
        this.closeError =
          (result && result.error) || helpText('Giving', 'Giving_AskPipeline_ErrorAction');
      }
    } catch (error) {
      this.closeError = messageOf(error);
    } finally {
      this.isSaving = false;
    }
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
