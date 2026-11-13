import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import getBoard from '@salesforce/apex/FundersBoardController.getBoard';
import { concentration, fill, revenueMix, showShare } from 'c/fundersBoardModel';
import { showMoney } from 'c/grantReportModel';
import { messageFrom as messageOf } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { printPage } from 'c/fundersPrint';
import { tabPageReference } from 'c/barnTabs';
import GRANT from '@salesforce/schema/Grant__c';
import REQUIREMENT from '@salesforce/schema/Grant_Requirement__c';
import ANSWER from '@salesforce/schema/Grant_Answer__c';
import TEMPLATE from '@salesforce/schema/Funder_Report_Template__c';

import TITLE from '@salesforce/label/c.Funders_Board_Title';
import MIX from '@salesforce/label/c.Funders_Board_Mix';
import GIFTS from '@salesforce/label/c.Funders_Board_Gifts';
import NOT_SET from '@salesforce/label/c.Core_Settings_NotSet';
import CONCENTRATION from '@salesforce/label/c.Funders_Board_Concentration';
import RESTRICTED from '@salesforce/label/c.Funders_Board_Restricted';
import FUNDS from '@salesforce/label/c.Funders_Board_Funds';
import GRANTS from '@salesforce/label/c.Funders_Board_Grants';
import REVENUE from '@salesforce/label/c.Funders_Board_Revenue';
import AWARDED from '@salesforce/label/c.Funders_Pipeline_TileAwarded';
import NOTHING_YET from '@salesforce/label/c.Funders_Board_NothingYet';
import PRINT from '@salesforce/label/c.Funders_Shared_Print';
import TOOLS from '@salesforce/label/c.Core_SettingsGroup_Tools';
import NAME from '@salesforce/label/c.Core_CmdtManager_NameField';
import PIPELINE from '@salesforce/label/c.Funders_Pipeline_Title';
import CALENDAR from '@salesforce/label/c.Funders_Calendar_Title';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The Funders tabs the home lists, in the app's order; objects are named by their plural. A
 * tile's name is the tab as written (its icon key); the object comes from its schema import.
 */
const TOOL_TABS = [
  { name: 'Grant_Pipeline', help: () => helpText('Funders', 'Funders_Home_PipelineTile') },
  { name: 'Grant_Calendar', help: () => helpText('Funders', 'Funders_Home_CalendarTile') },
  {
    name: 'Grant__c',
    object: GRANT,
    help: () => helpText('Funders', 'Funders_Home_GrantsTile')
  },
  {
    name: 'Grant_Requirement__c',
    object: REQUIREMENT,
    help: () => helpText('Funders', 'Funders_Home_RequirementsTile')
  },
  {
    name: 'Grant_Answer__c',
    object: ANSWER,
    help: () => helpText('Funders', 'Funders_Home_AnswersTile')
  },
  {
    name: 'Funder_Report_Template__c',
    object: TEMPLATE,
    help: () => helpText('Funders', 'Funders_Home_TemplatesTile')
  }
];
const OBJECT_NAMES = TOOL_TABS.filter((tab) => tab.object).map((tab) => tab.object.objectApiName);

const sumOf = (slices) =>
  (slices || []).reduce((sum, slice) => sum + (Number(slice.amount) || 0), 0);

/**
 * The Board Dashboard tab, the Funders app's home (F-07, canonical model 29ZH R-GN9;
 * vis-modules-19): this fiscal year's figures as tiles, the Funders tools, the revenue mix and the
 * concentration as meters, and the restricted balances. The shares and flags are the
 * framework-free `fundersBoardModel`'s; this component only lays them out. Print opens the
 * browser's print dialog without the app chrome, for the board packet.
 */
export default class FundersBoard extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Funders');

  labels = {
    title: TITLE,
    get help() {
      return helpText('Funders', 'Funders_Board_Help');
    },
    get empty() {
      return helpText('Funders', 'Funders_Board_Empty');
    },
    mix: MIX,
    concentration: CONCENTRATION,
    restricted: RESTRICTED,
    funds: FUNDS,
    grants: GRANTS,
    revenue: REVENUE,
    awarded: AWARDED,
    gifts: GIFTS,
    nothingYet: NOTHING_YET,
    print: PRINT,
    name: NAME
  };

  icon = iconFor('Funders_Board');

  board;
  errorMessage;
  isLoading = true;
  objectInfos = {};

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Funders').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  /** The plural names of the Funders objects the person can see, for the tool tiles. */
  @wire(getObjectInfos, { objectApiNames: OBJECT_NAMES })
  wiredInfos({ data }) {
    const infos = {};
    ((data && data.results) || []).forEach((entry) => {
      if (entry && entry.statusCode === 200 && entry.result) {
        infos[entry.result.apiName] = entry.result;
      }
    });
    this.objectInfos = infos;
  }

  async load() {
    this.isLoading = true;
    try {
      this.board = await getBoard();
      this.errorMessage = undefined;
    } catch (error) {
      this.board = undefined;
      this.errorMessage = messageOf(error, helpText('Funders', 'Funders_Board_LoadFailed'));
    } finally {
      this.isLoading = false;
    }
  }

  money(amount) {
    return showMoney(amount, this.board.currencyCode);
  }

  get currencyCode() {
    return (this.board && this.board.currencyCode) || undefined;
  }

  get mix() {
    return revenueMix(this.board, { notSet: NOT_SET, gifts: GIFTS });
  }

  get hasMix() {
    return Boolean(this.board) && this.mix.rows.length > 0;
  }

  /** A meter per row: the share has a shape, and the amount and percent are in its text. */
  meterRows(rows) {
    return rows.map((row) => ({
      key: row.key,
      label: `${row.name}: ${this.money(row.amount)}`,
      percent: Math.round((Number(row.share) || 0) * 100),
      share: showShare(row.share)
    }));
  }

  get mixRows() {
    return this.meterRows(this.mix.rows);
  }

  get spread() {
    return concentration(this.board, this.mix.total);
  }

  get sourceRows() {
    return this.meterRows(this.spread.top);
  }

  // ------------------------------------------------------------------ tiles

  get revenueTotal() {
    return this.board ? this.mix.total : 0;
  }

  get awardedTotal() {
    return this.board ? sumOf(this.board.grantsBySource) : 0;
  }

  get showGifts() {
    return Boolean(this.board && this.board.givingAvailable);
  }

  get giftsTotal() {
    return this.board ? Number(this.board.giftsThisYear) || 0 : 0;
  }

  get showRestrictedTile() {
    return Boolean(this.board && this.board.ledgerAvailable);
  }

  get restrictedTotal() {
    return this.board ? sumOf(this.board.restrictedGrants) : 0;
  }

  // ------------------------------------------------------------------ tools

  get toolGroups() {
    const tiles = [];
    TOOL_TABS.forEach((tab) => {
      const label = this.toolLabel(tab);
      if (!label) {
        return;
      }
      tiles.push({
        name: tab.name,
        label,
        description: this.toolDescription(tab.name),
        iconName: iconFor(tab.name)
      });
    });
    return [{ name: 'tools', label: TOOLS, tiles }];
  }

  toolLabel(tab) {
    if (tab.name === 'Grant_Pipeline') {
      return PIPELINE;
    }
    if (tab.name === 'Grant_Calendar') {
      return CALENDAR;
    }
    const info = this.objectInfos[tab.object.objectApiName];
    return info ? info.labelPlural : '';
  }

  toolDescription(name) {
    const tab = TOOL_TABS.find((candidate) => candidate.name === name);
    return tab.help();
  }

  async handleTool(event) {
    const name = event.detail.name;
    const tab = TOOL_TABS.find((candidate) => candidate.name === name);
    if (!tab) {
      return;
    }
    this[NavigationMixin.Navigate](
      tab.object
        ? {
            type: 'standard__objectPage',
            attributes: { objectApiName: tab.object.objectApiName, actionName: 'home' }
          }
        : await tabPageReference(name)
    );
  }

  handlePrint() {
    printPage(this);
  }

  // ------------------------------------------------------------- the sections

  get flags() {
    const spread = this.spread;
    const flags = [];
    if (spread.singleRisk) {
      flags.push({
        key: 'single',
        text: fill(helpText('Funders', 'Funders_Board_SingleRisk'), [
          spread.largest.name,
          showShare(spread.largest.share)
        ])
      });
    }
    if (spread.topFiveRisk) {
      flags.push({
        key: 'five',
        text: fill(helpText('Funders', 'Funders_Board_TopFiveRisk'), [
          showShare(spread.topFiveShare)
        ])
      });
    }
    return flags;
  }

  get hasFlags() {
    return this.flags.length > 0;
  }

  get noRiskText() {
    return fill(helpText('Funders', 'Funders_Board_NoRisk'), [showShare(this.spread.topFiveShare)]);
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
