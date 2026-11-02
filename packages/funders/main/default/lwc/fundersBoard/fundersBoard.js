import { LightningElement } from 'lwc';
import getBoard from '@salesforce/apex/FundersBoardController.getBoard';
import { concentration, fill, revenueMix, showShare } from 'c/fundersBoardModel';
import { showMoney } from 'c/grantReportModel';

import TITLE from '@salesforce/label/c.Funders_Board_Title';
import HELP from '@salesforce/label/c.Funders_Board_Help';
import MIX from '@salesforce/label/c.Funders_Board_Mix';
import GIFTS from '@salesforce/label/c.Funders_Board_Gifts';
import NOT_SET from '@salesforce/label/c.Core_Settings_NotSet';
import TOTAL from '@salesforce/label/c.Funders_Board_Total';
import CONCENTRATION from '@salesforce/label/c.Funders_Board_Concentration';
import SINGLE_RISK from '@salesforce/label/c.Funders_Board_SingleRisk';
import TOP_FIVE_RISK from '@salesforce/label/c.Funders_Board_TopFiveRisk';
import NO_RISK from '@salesforce/label/c.Funders_Board_NoRisk';
import RESTRICTED from '@salesforce/label/c.Funders_Board_Restricted';
import FUNDS from '@salesforce/label/c.Funders_Board_Funds';
import GRANTS from '@salesforce/label/c.Funders_Board_Grants';
import EMPTY from '@salesforce/label/c.Funders_Board_Empty';
import ERROR_LOAD from '@salesforce/label/c.Funders_Board_ErrorLoad';

const messageOf = (error, fallback) =>
  (error && error.body && error.body.message) || (error && error.message) || fallback;

/**
 * The Board Dashboard tab (F-07, canonical model 29ZH R-GN9): this fiscal year's revenue mix,
 * concentration and restricted balances. The shares and flags are the framework-free
 * `fundersBoardModel`'s; this component only lays them out. It reads and stores nothing else.
 */
export default class FundersBoard extends LightningElement {
  labels = { title: TITLE, help: HELP, mix: MIX, total: TOTAL, concentration: CONCENTRATION };
  labelsRestricted = { title: RESTRICTED, funds: FUNDS, grants: GRANTS, empty: EMPTY };

  board;
  errorMessage;
  isLoading = true;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.board = await getBoard();
      this.errorMessage = undefined;
    } catch (error) {
      this.board = undefined;
      this.errorMessage = messageOf(error, ERROR_LOAD);
    } finally {
      this.isLoading = false;
    }
  }

  money(amount) {
    return showMoney(amount, this.board.currencyCode);
  }

  get mix() {
    return revenueMix(this.board, { notSet: NOT_SET, gifts: GIFTS });
  }

  get hasMix() {
    return Boolean(this.board) && this.mix.rows.length > 0;
  }

  get mixRows() {
    return this.mix.rows.map((row) => ({
      key: row.key,
      name: row.name,
      amount: this.money(row.amount),
      share: showShare(row.share)
    }));
  }

  get mixTotal() {
    return this.money(this.mix.total);
  }

  get spread() {
    return concentration(this.board, this.mix.total);
  }

  get sourceRows() {
    return this.spread.top.map((source) => ({
      key: source.key,
      name: source.name,
      amount: this.money(source.amount),
      share: showShare(source.share)
    }));
  }

  get flags() {
    const spread = this.spread;
    const flags = [];
    if (spread.singleRisk) {
      flags.push({
        key: 'single',
        text: fill(SINGLE_RISK, [spread.largest.name, showShare(spread.largest.share)])
      });
    }
    if (spread.topFiveRisk) {
      flags.push({ key: 'five', text: fill(TOP_FIVE_RISK, [showShare(spread.topFiveShare)]) });
    }
    return flags;
  }

  get hasFlags() {
    return this.flags.length > 0;
  }

  get noRiskText() {
    return fill(NO_RISK, [showShare(this.spread.topFiveShare)]);
  }

  rows(slices) {
    return slices.map((slice) => ({
      key: slice.key,
      name: slice.name,
      amount: this.money(slice.amount)
    }));
  }

  get fundRows() {
    return this.rows((this.board && this.board.restrictedFunds) || []);
  }

  get grantRows() {
    return this.rows((this.board && this.board.restrictedGrants) || []);
  }

  get hasFunds() {
    return this.fundRows.length > 0;
  }

  get hasGrants() {
    return this.grantRows.length > 0;
  }

  get noRestricted() {
    return !this.hasFunds && !this.hasGrants;
  }
}
