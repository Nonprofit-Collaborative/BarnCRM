import { LightningElement, api, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecords } from 'lightning/uiRecordApi';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import ALLOCATION_OBJECT from '@salesforce/schema/Gift_Allocation__c';
import ADD_FUND from '@salesforce/label/c.Giving_FundSplit_AddFund';
import REMOVE_ROW from '@salesforce/label/c.Giving_GiftBatch_RemoveLine';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  amountForPercent,
  dividerPercents,
  isValid,
  leftToAssign,
  moveDivider,
  percentOf,
  problemsOf,
  sameAllocations,
  toAllocations,
  toCents
} from 'c/fundSplitMath';

const FUND_NAME = 'Fund__c.Name';
const ACTIVE_FUNDS = {
  criteria: [{ fieldPath: 'Active__c', operator: 'eq', value: true }]
};
const KEY_STEP = 1;
const PAGE_STEP = 10;

let nextKey = 0;
function newKey() {
  nextKey += 1;
  return `split-${nextKey}`;
}

/**
 * The fund split editor (people-giving-16): rows of a fund and an amount or a percent, with
 * what is left to assign under them, and a stacked bar whose dividers can be dragged to move
 * money between two neighbouring funds. The amount and percent boxes are the main control; the
 * bar is an extra, and each divider is a slider the keyboard moves too (DnD-4).
 *
 * <c-gift-fund-split total={amount} allocations={allocations} onchange={handleSplit}>
 *
 * `allocations` is a list of { fundId, amount } (a fundName is used when given). Every edit
 * fires `change` with detail { allocations, valid }; `valid` is true only when every row has
 * its own fund and an amount, and the rows add up to the total exactly. Saving is the host's:
 * the gift page saves through GiftAllocationController, Quick Gift Entry with the gift.
 */
export default class GiftFundSplit extends LightningElement {
  helpReady = isHelpLoaded('Giving');

  rows = [{ key: newKey(), fundId: null, amount: '', percentText: null }];
  givenNames = {};
  fetchedNames = {};
  touched = false;
  liveMessage = '';
  dragIndex = null;
  _total = 0;

  labels = { addFund: ADD_FUND };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
  }

  /** The gift's amount: the rows must add up to it. */
  @api
  get total() {
    return this._total;
  }
  set total(value) {
    const previous = this._total;
    this._total = value === null || value === undefined || value === '' ? 0 : Number(value);
    // A single row that held the whole gift follows the gift when its amount changes.
    if (this.rows.length === 1) {
      const only = this.rows[0];
      const blank = only.amount === '' || only.amount === null || only.amount === undefined;
      if (
        (blank || toCents(only.amount) === toCents(previous)) &&
        toCents(previous) !== toCents(this._total)
      ) {
        this.rows = [{ ...only, amount: this._total, percentText: null }];
        this.notify();
      }
    }
  }

  /** The current split as { fundId, amount } entries. */
  @api
  get allocations() {
    return toAllocations(this.rows);
  }
  set allocations(value) {
    const list = Array.isArray(value) ? value : [];
    if (list.length && sameAllocations(list, this.rows)) {
      return;
    }
    const names = { ...this.givenNames };
    list.forEach((entry) => {
      if (entry && entry.fundId && entry.fundName) {
        names[entry.fundId] = entry.fundName;
      }
    });
    this.givenNames = names;
    this.rows = list.length
      ? list.map((entry) => ({
          key: newKey(),
          fundId: (entry && entry.fundId) || null,
          amount: entry && entry.amount !== undefined && entry.amount !== null ? entry.amount : '',
          percentText: null
        }))
      : [{ key: newKey(), fundId: null, amount: this._total || '', percentText: null }];
  }

  /** Whether the split can be saved as it stands. */
  @api
  get valid() {
    return isValid(this._total, this.rows);
  }

  @wire(getObjectInfo, { objectApiName: ALLOCATION_OBJECT })
  allocationInfo;

  /** Fund names for the bar and its dividers, for funds picked here rather than given. */
  get fundRecordsParam() {
    const ids = this.rows
      .map((row) => row.fundId)
      .filter((id) => id && !this.givenNames[id] && !this.fetchedNames[id]);
    return ids.length ? [{ recordIds: [...new Set(ids)], fields: [FUND_NAME] }] : undefined;
  }

  @wire(getRecords, { records: '$fundRecordsParam' })
  wiredFunds({ data }) {
    if (!data || !data.results) {
      return;
    }
    const names = { ...this.fetchedNames };
    data.results.forEach((entry) => {
      const record = entry && entry.result;
      if (record && record.id && record.fields && record.fields.Name) {
        names[record.id] = record.fields.Name.value;
      }
    });
    this.fetchedNames = names;
  }

  fieldLabel(apiName, fallback) {
    const info = this.allocationInfo && this.allocationInfo.data;
    const field = info && info.fields && info.fields[apiName];
    return field ? field.label : fallback;
  }

  get fundLabel() {
    return this.fieldLabel('Fund__c', 'Fund');
  }

  get amountLabel() {
    return this.fieldLabel('Amount__c', 'Amount');
  }

  get percentLabel() {
    return this.fieldLabel('Percent__c', 'Percent');
  }

  get activeFunds() {
    return ACTIVE_FUNDS;
  }

  nameOf(row, index) {
    if (row.fundId) {
      const name = this.givenNames[row.fundId] || this.fetchedNames[row.fundId];
      if (name) {
        return name;
      }
    }
    return `${this.fundLabel} ${index + 1}`;
  }

  get rowViews() {
    const single = this.rows.length === 1;
    return this.rows.map((row, index) => ({
      ...row,
      number: index + 1,
      percent:
        row.percentText !== null && row.percentText !== undefined
          ? row.percentText
          : row.amount === '' || row.amount === null
            ? ''
            : percentOf(row.amount, this._total),
      removeLabel: REMOVE_ROW.replace('{0}', String(index + 1)),
      removeDisabled: single
    }));
  }

  formatMoney(amount) {
    try {
      return new Intl.NumberFormat(LOCALE, { style: 'currency', currency: CURRENCY }).format(
        amount
      );
    } catch {
      return String(amount);
    }
  }

  get left() {
    return leftToAssign(this._total, this.rows);
  }

  get leftText() {
    return helpText('Giving', 'Giving_FundSplit_LeftToAssign', this.formatMoney(this.left));
  }

  get leftStatus() {
    return toCents(this.left) === 0 ? 'done' : 'attention';
  }

  get problemLines() {
    if (!this.touched) {
      return [];
    }
    const problems = problemsOf(this._total, this.rows);
    const lines = [];
    if (problems.missingFund) {
      lines.push({ key: 'fund', text: helpText('Giving', 'Giving_FundSplit_NeedsFund') });
    }
    if (problems.duplicateFund) {
      lines.push({ key: 'duplicate', text: helpText('Giving', 'Giving_FundSplit_DuplicateFund') });
    }
    if (problems.badAmount) {
      lines.push({ key: 'amount', text: helpText('Giving', 'Giving_FundSplit_NeedsAmount') });
    }
    return lines;
  }

  get hasProblems() {
    return this.problemLines.length > 0;
  }

  // ---------------------------------------------------------------------------------------
  // The bar
  // ---------------------------------------------------------------------------------------

  get showBar() {
    return this.rows.length > 1 && toCents(this._total) !== 0;
  }

  get barHint() {
    return helpText('Giving', 'Giving_FundSplit_BarHint');
  }

  get segments() {
    const total = Math.abs(toCents(this._total)) || 1;
    return this.rows.map((row, index) => {
      const share = Math.max(0, Math.min(100, (Math.abs(toCents(row.amount)) / total) * 100));
      const percent = percentOf(row.amount, this._total);
      return {
        key: row.key,
        style: `width: ${share}%;`,
        className: `split-segment split-segment_${index % 5}`,
        text: share >= 12 ? `${percent}%` : '',
        title: `${this.nameOf(row, index)} ${percent}%`
      };
    });
  }

  get dividers() {
    return dividerPercents(this._total, this.rows).map((position, index) => {
      const first = this.rows[index];
      const second = this.rows[index + 1];
      return {
        key: `divider-${first.key}`,
        index,
        style: `left: ${position}%;`,
        now: Math.round(position),
        label: helpText(
          'Giving',
          'Giving_FundSplit_DividerLabel',
          this.nameOf(first, index),
          this.nameOf(second, index + 1)
        ),
        valueText: this.pairText(index)
      };
    });
  }

  pairText(index) {
    const first = this.rows[index];
    const second = this.rows[index + 1];
    return helpText(
      'Giving',
      'Giving_FundSplit_DividerValue',
      this.nameOf(first, index),
      String(percentOf(first.amount, this._total)),
      this.nameOf(second, index + 1),
      String(percentOf(second.amount, this._total))
    );
  }

  moveTo(index, percent) {
    this.rows = moveDivider(this._total, this.rows, index, percent).map((row) => ({
      ...row,
      percentText: null
    }));
    this.touched = true;
    this.notify();
  }

  percentAt(clientX) {
    const bar = this.template.querySelector('[data-id="bar"]');
    if (!bar) {
      return null;
    }
    const box = bar.getBoundingClientRect();
    if (!box.width) {
      return null;
    }
    return Math.max(0, Math.min(100, ((clientX - box.left) / box.width) * 100));
  }

  handleDividerDown(event) {
    this.dragIndex = Number(event.currentTarget.dataset.index);
    if (event.currentTarget.setPointerCapture && event.pointerId !== undefined) {
      event.currentTarget.setPointerCapture(event.pointerId);
    }
    event.preventDefault();
  }

  handleDividerMove(event) {
    if (this.dragIndex === null) {
      return;
    }
    const percent = this.percentAt(event.clientX);
    if (percent !== null) {
      this.moveTo(this.dragIndex, percent);
    }
  }

  handleDividerUp(event) {
    if (this.dragIndex === null) {
      return;
    }
    if (event.currentTarget.releasePointerCapture && event.pointerId !== undefined) {
      try {
        event.currentTarget.releasePointerCapture(event.pointerId);
      } catch {
        // The capture was already released (the pointer left the window).
      }
    }
    this.liveMessage = this.pairText(this.dragIndex);
    this.dragIndex = null;
  }

  handleDividerKey(event) {
    const index = Number(event.currentTarget.dataset.index);
    const position = dividerPercents(this._total, this.rows)[index];
    let step = 0;
    switch (event.key) {
      case 'ArrowLeft':
      case 'ArrowDown':
        step = -KEY_STEP;
        break;
      case 'ArrowRight':
      case 'ArrowUp':
        step = KEY_STEP;
        break;
      case 'PageDown':
        step = -PAGE_STEP;
        break;
      case 'PageUp':
        step = PAGE_STEP;
        break;
      default:
        return;
    }
    event.preventDefault();
    this.moveTo(index, Math.round(position) + step);
    this.liveMessage = this.pairText(index);
  }

  // ---------------------------------------------------------------------------------------
  // The rows
  // ---------------------------------------------------------------------------------------

  updateRow(key, changes) {
    this.rows = this.rows.map((row) => (row.key === key ? { ...row, ...changes } : row));
    this.touched = true;
    this.notify();
  }

  handleFundChange(event) {
    const fundId = event.detail ? event.detail.recordId || null : null;
    this.updateRow(event.target.dataset.key, { fundId });
  }

  handleAmountChange(event) {
    this.updateRow(event.target.dataset.key, {
      amount: event.detail.value === undefined ? '' : event.detail.value,
      percentText: null
    });
  }

  handlePercentChange(event) {
    const text = event.detail.value;
    const blank = text === '' || text === null || text === undefined;
    this.updateRow(event.target.dataset.key, {
      percentText: blank ? '' : text,
      amount: blank ? '' : amountForPercent(text, this._total)
    });
  }

  handleAddRow() {
    const left = this.left;
    const sameSide =
      toCents(left) !== 0 && Math.sign(toCents(left)) === Math.sign(toCents(this._total));
    this.rows = [
      ...this.rows,
      { key: newKey(), fundId: null, amount: sameSide ? left : '', percentText: null }
    ];
    this.notify();
  }

  handleRemoveRow(event) {
    if (this.rows.length < 2) {
      return;
    }
    const key = event.currentTarget.dataset.key;
    this.rows = this.rows.filter((row) => row.key !== key);
    this.touched = true;
    this.notify();
  }

  notify() {
    this.dispatchEvent(
      new CustomEvent('change', {
        detail: { allocations: toAllocations(this.rows), valid: isValid(this._total, this.rows) }
      })
    );
  }
}
