import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getHome from '@salesforce/apex/MigrationController.getHome';
import { bodyMessage as messageOf } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** The page state key that names an open kit ends this way (`c__kit`, or the namespace's). */
const KIT_STATE = '__kit';

/** The kit a page state names, whatever namespace prefix its key carries. */
export function kitFromState(state) {
  const key = Object.keys(state || {}).find((name) => name.endsWith(KIT_STATE));
  return key ? state[key] : undefined;
}

/**
 * The Migration Assistant tab (ADR-0232): the Migration Kits for the products
 * detected in this org, each with Start, and the two household tools, Adopt NPSP Households and
 * Convert Nonprofit Cloud Households, where they apply. A kit opens in place, from Start here or
 * from Start Migration on Settings, Integrations, which names it in the page state; Back returns
 * to the list.
 */
export default class MigrationHome extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Migration');
  home;
  errorMessage;
  kitKey;
  pageReference;

  get labels() {
    return {
      title: helpText('Migration', 'Migration_Home_Title'),
      purpose: helpText('Migration', 'Migration_Home_Purpose'),
      kitsHeading: helpText('Migration', 'Migration_Home_KitsHeading'),
      noKits: helpText('Migration', 'Migration_Home_NoKits'),
      start: helpText('Migration', 'Migration_Start'),
      householdsHeading: helpText('Migration', 'Migration_Home_HouseholdsHeading'),
      uninstall: helpText('Migration', 'Migration_Home_Uninstall')
    };
  }

  @wire(CurrentPageReference)
  wiredPage(pageReference) {
    this.pageReference = pageReference;
    this.kitKey = kitFromState(pageReference && pageReference.state);
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Migration').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    try {
      this.home = await getHome();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageOf(error, helpText('Migration', 'Migration_LoadErrorMessage'));
    }
  }

  get kits() {
    return (this.home && this.home.kits) || [];
  }

  get hasKits() {
    return this.kits.length > 0;
  }

  get showNpsp() {
    return Boolean(this.home && this.home.npspHouseholds);
  }

  get showNpc() {
    return Boolean(this.home && this.home.npcHouseholds);
  }

  get showHouseholds() {
    return this.showNpsp || this.showNpc;
  }

  handleStart(event) {
    this.kitKey = event.currentTarget.dataset.kit;
  }

  /** Back to the list, with the kit taken out of the address so a reload shows the list too. */
  handleBack() {
    this.kitKey = undefined;
    if (this.pageReference && kitFromState(this.pageReference.state)) {
      const state = { ...this.pageReference.state };
      Object.keys(state)
        .filter((name) => name.endsWith(KIT_STATE))
        .forEach((name) => delete state[name]);
      this[NavigationMixin.Navigate]({ ...this.pageReference, state }, true);
    }
    return this.load();
  }
}
