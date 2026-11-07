import { LightningElement } from 'lwc';
import getView from '@salesforce/apex/DuplicateRulesStarter.getView';
import start from '@salesforce/apex/DuplicateRulesStarter.start';
import BarnConfirmModal from 'c/barnConfirmModal';
import { bodyMessage } from 'c/findCsv';
import { helpText } from 'c/barnHelpText';

import TITLE from '@salesforce/label/c.Core_DuplicateStarter_Title';
import SET_UP from '@salesforce/label/c.Core_DuplicateStarter_SetUp';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';

const POLL_MS = 10000;
const ACTIONABLE = ['Create', 'Repair'];

/**
 * Duplicate Rules Starter (C-61, D-156, ADR "Duplicate Rules Starter and report subscriptions
 * through the org connection"), opened from the rules box on Duplicate Matching, Review. Shows
 * the org's own rules (left unchanged), what Set Up would create or repair, the recommended
 * rule in words, then queues the work through the org connection and reads again every ten
 * seconds while it runs.
 */
export default class DuplicateRulesStarter extends LightningElement {
  view;
  chosen = [];
  working = false;
  errorMessage;
  timer;

  labels = {
    title: TITLE,
    setUp: SET_UP,
    refresh: REFRESH,
    get intro() {
      return helpText('Core', 'Core_DuplicateStarter_Intro');
    },
    get noPermission() {
      return helpText('Core', 'Core_AutomationInventory_NoConnectionPermission');
    },
    get connectionNeeded() {
      return helpText('Core', 'Core_DuplicateStarter_ConnectionNeeded');
    },
    get running() {
      return helpText('Core', 'Core_DuplicateStarter_Running');
    },
    get orgRulesLead() {
      return helpText('Core', 'Core_DuplicateStarter_OrgRulesLead');
    },
    get stepsLead() {
      return helpText('Core', 'Core_DuplicateStarter_StepsLead');
    }
  };

  connectedCallback() {
    this.load(true);
  }

  disconnectedCallback() {
    clearTimeout(this.timer);
  }

  async load(first) {
    clearTimeout(this.timer);
    try {
      this.view = await getView();
      this.errorMessage = undefined;
      if (first) {
        this.chosen = this.view.sets
          .filter((set) => ACTIONABLE.includes(set.action))
          .map((set) => set.key);
      }
      if (this.view.running) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(() => this.load(false), POLL_MS);
      }
    } catch (error) {
      this.errorMessage = bodyMessage(error);
    }
  }

  get needsPermission() {
    return Boolean(this.view && !this.view.canUse);
  }

  get needsConnection() {
    return Boolean(this.view && this.view.canUse && !this.view.connected);
  }

  get running() {
    return Boolean(this.view && this.view.running);
  }

  get lastResultVariant() {
    return this.view && this.view.lastResultFailed ? 'error' : 'success';
  }

  get sets() {
    const chosen = new Set(this.chosen);
    return ((this.view && this.view.sets) || []).map((set) => ({
      ...set,
      actionable: ACTIONABLE.includes(set.action),
      checked: chosen.has(set.key),
      hasSteps: Boolean(set.steps && set.steps.length),
      hasOrgRules: Boolean(set.orgRules && set.orgRules.length),
      stateText:
        set.action === 'None'
          ? helpText('Core', 'Core_DuplicateStarter_StateActive')
          : set.action === 'Wait' && !(set.steps && set.steps.length)
            ? helpText('Core', 'Core_DuplicateStarter_StateWait')
            : undefined,
      noOrgRules: helpText('Core', 'Core_DuplicateStarter_NoOrgRules')
    }));
  }

  get setUpDisabled() {
    return (
      this.working || this.running || !this.view || !this.view.connected || this.chosen.length === 0
    );
  }

  handleChoose(event) {
    const key = event.target.dataset.key;
    this.chosen = event.target.checked
      ? [...this.chosen.filter((each) => each !== key), key]
      : this.chosen.filter((each) => each !== key);
  }

  async handleSetUp() {
    const chosen = this.sets.filter((set) => set.checked && set.actionable);
    const confirmed = await BarnConfirmModal.open({
      label: TITLE,
      size: 'small',
      message: helpText('Core', 'Core_DuplicateStarter_ConfirmMessage'),
      items: chosen.flatMap((set) => set.steps),
      confirmLabel: SET_UP,
      cancelLabel: CANCEL
    });
    if (confirmed !== true) {
      return;
    }
    this.working = true;
    this.errorMessage = undefined;
    try {
      this.view = await start({ keys: chosen.map((set) => set.key) });
      this.load(false);
    } catch (error) {
      this.errorMessage = bodyMessage(error);
    } finally {
      this.working = false;
    }
  }

  handleRefresh() {
    this.load(false);
  }
}
