import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { followLinkInWorkspace } from 'c/workspaceTabs';
import getHouseholdsForPerson from '@salesforce/apex/HouseholdOfPersonController.getHouseholdsForPerson';

import TITLE from '@salesforce/label/c.Core_HouseholdPanel_OfPersonTitle';
import EMPTY from '@salesforce/label/c.Core_HouseholdPanel_OfPersonEmpty';
import EMPTY_HEADING from '@salesforce/label/c.Core_HouseholdPanel_OfPersonEmptyHeading';
import LOADING from '@salesforce/label/c.Core_HouseholdPanel_OfPersonLoading';
import LOAD_FAILED from '@salesforce/label/c.Core_HouseholdPanel_OfPersonLoadFailed';
import MEMBER_COUNT_ONE from '@salesforce/label/c.Core_HouseholdPanel_MemberCountOne';
import MEMBER_COUNT_MANY from '@salesforce/label/c.Core_HouseholdPanel_MemberCountMany';
import FORMAL_GREETING from '@salesforce/label/c.Core_HouseholdPanel_FormalGreeting';

/**
 * The household a person belongs to, on the person's own record: its name as a link, how
 * many people are in it, and the formal greeting. In the flexible way of belonging a person
 * can be in more than one household, so the panel lists each one. It goes on a contact page,
 * and on a person account page where the org stores people as accounts.
 */
export default class HouseholdOfPerson extends NavigationMixin(LightningElement) {
  @api recordId;

  @wire(EnclosingTabId) enclosingTabId;

  label = {
    title: TITLE,
    empty: EMPTY,
    emptyHeading: EMPTY_HEADING,
    loading: LOADING,
    formalGreeting: FORMAL_GREETING
  };

  households = [];
  errorMessage;
  loaded = false;

  @wire(getHouseholdsForPerson, { personId: '$recordId' })
  wiredHouseholds({ data, error }) {
    if (data) {
      this.households = data.map((household) => ({
        ...household,
        url: `/${household.householdId}`,
        memberCountText: this.memberCountText(household.memberCount)
      }));
      this.errorMessage = undefined;
      this.loaded = true;
      this.generateUrls();
    } else if (error) {
      this.households = [];
      this.errorMessage = LOAD_FAILED;
      this.loaded = true;
    }
  }

  get isLoading() {
    return !this.loaded;
  }

  get hasHouseholds() {
    return this.households.length > 0;
  }

  get isEmpty() {
    return this.loaded && !this.errorMessage && !this.hasHouseholds;
  }

  /** In a console the household opens as a subtab beside the person. */
  handleHouseholdClick(event) {
    const recordId = event.currentTarget.dataset.recordId;
    followLinkInWorkspace(this, event, { recordId }, () =>
      this[NavigationMixin.Navigate](this.pageReference(recordId))
    );
  }

  memberCountText(count) {
    const number = count || 0;
    return number === 1 ? MEMBER_COUNT_ONE : MEMBER_COUNT_MANY.replace('{0}', number);
  }

  pageReference(householdId) {
    return {
      type: 'standard__recordPage',
      attributes: { recordId: householdId, actionName: 'view' }
    };
  }

  /**
   * The link's address as the platform builds it, so it works in every container (a console
   * tab, the mobile app). The plain record path stands in until that answer arrives, so the
   * link is never empty.
   */
  generateUrls() {
    this.urlRound = (this.urlRound || 0) + 1;
    const round = this.urlRound;
    this.households.forEach((household) => {
      this[NavigationMixin.GenerateUrl](this.pageReference(household.householdId))
        .then((url) => {
          if (url && round === this.urlRound) {
            this.households = this.households.map((row) => {
              return row.householdId === household.householdId ? { ...row, url } : row;
            });
          }
        })
        .catch(() => {
          // The plain record path stays in place.
        });
    });
  }
}
