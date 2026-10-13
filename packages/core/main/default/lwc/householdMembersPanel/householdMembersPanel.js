import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getRecord, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import Toast from 'lightning/toast';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';
import getMembershipMode from '@salesforce/apex/HouseholdController.getMembershipMode';
import moveContact from '@salesforce/apex/HouseholdController.moveContact';
import makePrimaryMembership from '@salesforce/apex/HouseholdOfPersonController.makePrimary';
import searchPeople from '@salesforce/apex/HouseholdOfPersonController.searchPeople';
import addExistingPerson from '@salesforce/apex/HouseholdOfPersonController.addExistingPerson';
import addNewPerson from '@salesforce/apex/HouseholdOfPersonController.addNewPerson';

import TITLE from '@salesforce/label/c.Core_HouseholdMembersPanel_Title';
import EMPTY from '@salesforce/label/c.Core_HouseholdMembersPanel_Empty';
import NOT_A_HOUSEHOLD from '@salesforce/label/c.Core_HouseholdMembersPanel_NotAHousehold';
import PRIMARY from '@salesforce/label/c.Core_HouseholdMembersPanel_Primary';
import DECEASED from '@salesforce/label/c.Core_HouseholdMembersPanel_Deceased';
import ADD_MEMBER from '@salesforce/label/c.Core_HouseholdMembersPanel_AddMember';
import MOVE_MEMBER from '@salesforce/label/c.Core_HouseholdMembersPanel_MoveMember';
import MOVE_HELP from '@salesforce/label/c.Core_HouseholdMembersPanel_MoveHelp';
import MOVE_SUCCESS from '@salesforce/label/c.Core_HouseholdMembersPanel_MoveSuccess';
import ADD_SUCCESS from '@salesforce/label/c.Core_HouseholdMembersPanel_AddSuccess';
import SAVE from '@salesforce/label/c.Core_HouseholdMembersPanel_Save';
import CANCEL from '@salesforce/label/c.Core_HouseholdMembersPanel_Cancel';
import MAKE_PRIMARY from '@salesforce/label/c.Core_HouseholdPanel_MakePrimary';
import MAKE_PRIMARY_FOR from '@salesforce/label/c.Core_HouseholdPanel_MakePrimaryFor';
import MOVE_FOR from '@salesforce/label/c.Core_HouseholdPanel_MoveFor';
import MAKE_PRIMARY_SUCCESS from '@salesforce/label/c.Core_HouseholdPanel_MakePrimarySuccess';
import MAKE_PRIMARY_FAILED from '@salesforce/label/c.Core_HouseholdPanel_MakePrimaryFailed';
import LOADING from '@salesforce/label/c.Core_HouseholdPanel_Loading';
import ADD_EXISTING_HEADING from '@salesforce/label/c.Core_HouseholdPanel_AddExistingHeading';
import ADD_EXISTING_PLACEHOLDER from '@salesforce/label/c.Core_HouseholdPanel_AddExistingPlaceholder';
import ADD_EXISTING_RESULT_FOR from '@salesforce/label/c.Core_HouseholdPanel_AddExistingResultFor';
import ADD_EXISTING_NO_RESULTS from '@salesforce/label/c.Core_HouseholdPanel_AddExistingNoResults';
import ADD_NEW_HEADING from '@salesforce/label/c.Core_HouseholdPanel_AddNewHeading';
import SALUTATION from '@salesforce/label/c.Core_HouseholdPanel_Salutation';
import FIRST_NAME from '@salesforce/label/c.Core_HouseholdPanel_FirstName';
import LAST_NAME from '@salesforce/label/c.Core_HouseholdPanel_LastName';

const RECORD_TYPE_FIELD = 'Account.RecordType.DeveloperName';
const PRIMARY_CONTACT_FIELD = 'Account.Primary_Contact__c';
const HOUSEHOLD = 'Household';
const JUNCTION = 'Junction';
const SOURCE_ACCOUNT = 'Account';
// The same floor SettingsSearch uses, so a single keystroke never fires a search.
const SEARCH_DEBOUNCE_MS = 300;
const SEARCH_MIN_LENGTH = 2;

export default class HouseholdMembersPanel extends LightningElement {
  @api recordId;

  label = {
    title: TITLE,
    empty: EMPTY,
    notAHousehold: NOT_A_HOUSEHOLD,
    primary: PRIMARY,
    deceased: DECEASED,
    addMember: ADD_MEMBER,
    moveMember: MOVE_MEMBER,
    moveHelp: MOVE_HELP,
    save: SAVE,
    cancel: CANCEL,
    makePrimary: MAKE_PRIMARY,
    loading: LOADING,
    addExistingHeading: ADD_EXISTING_HEADING,
    addExistingPlaceholder: ADD_EXISTING_PLACEHOLDER,
    addExistingNoResults: ADD_EXISTING_NO_RESULTS,
    addNewHeading: ADD_NEW_HEADING,
    salutation: SALUTATION,
    firstName: FIRST_NAME,
    lastName: LAST_NAME
  };

  @track members = [];
  membershipMode;
  recordTypeName;
  householdRecordTypeId;
  primaryContactId;
  errorMessage;
  isAdding = false;
  movingPersonId;
  targetHouseholdId;
  busy = false;
  membersLoaded = false;

  // The Add existing person search, flexible membership mode only.
  @track searchResults = [];
  searchTerm = '';
  searchTimer;

  // The Add new person form, flexible membership mode only.
  newSalutation = '';
  newFirstName = '';
  newLastName = '';

  membersResult;

  disconnectedCallback() {
    this.clearSearchTimer();
  }

  @wire(getRecord, { recordId: '$recordId', fields: [RECORD_TYPE_FIELD, PRIMARY_CONTACT_FIELD] })
  wiredAccount({ data, error }) {
    if (data) {
      const recordType = data.fields.RecordType;
      this.recordTypeName =
        recordType && recordType.value ? recordType.value.fields.DeveloperName.value : undefined;
      // In the simple way of belonging the primary contact is the household's own field, which
      // the server does not put on a member, so the badge is worked out here.
      const primary = data.fields.Primary_Contact__c;
      this.primaryContactId = primary ? primary.value : undefined;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(getObjectInfo, { objectApiName: 'Account' })
  wiredAccountInfo({ data, error }) {
    if (data) {
      // Which record type is the household one, so that the move offers households and
      // never an organization.
      const infos = data.recordTypeInfos || {};
      this.householdRecordTypeId = Object.keys(infos).find(
        (id) => infos[id].developerName === HOUSEHOLD || infos[id].name === HOUSEHOLD
      );
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(getMembershipMode)
  wiredMode({ data, error }) {
    if (data) {
      this.membershipMode = data;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(getMembers, { householdId: '$recordId' })
  wiredMembers(result) {
    this.membersResult = result;
    if (result.data) {
      this.members = result.data;
      this.errorMessage = undefined;
      this.membersLoaded = true;
    } else if (result.error) {
      this.members = [];
      this.errorMessage = this.readError(result.error);
      this.membersLoaded = true;
    }
  }

  get isHousehold() {
    return this.recordTypeName === HOUSEHOLD;
  }

  get isJunctionMode() {
    return this.membershipMode === JUNCTION;
  }

  get canAddMember() {
    return this.isHousehold;
  }

  get hasMembers() {
    return this.members.length > 0;
  }

  get hasSearchResults() {
    return this.searchResults.length > 0;
  }

  get showNoSearchResults() {
    return this.searchTerm.trim().length >= SEARCH_MIN_LENGTH && this.searchResults.length === 0;
  }

  /**
   * The search results as the row draws them: what a screen reader hears for each, worked
   * out here so the template stays a plain loop.
   */
  get searchResultRows() {
    return this.searchResults.map((person) => ({
      ...person,
      resultLabel: ADD_EXISTING_RESULT_FOR.replace('{0}', person.name)
    }));
  }

  get isLoading() {
    return this.busy || !this.membersLoaded;
  }

  /**
   * The members as the rows draw them: who is primary, which actions each row offers, and
   * what a screen reader hears for each action. Worked out on the way to the screen because
   * the primary contact and the way of belonging arrive from wires of their own.
   */
  get rows() {
    return this.members.map((member) => {
      const isPrimary = this.isPrimary(member);
      const storedAsAccount = member.source === SOURCE_ACCOUNT;
      return {
        ...member,
        isPrimary,
        badges: this.badgesFor(member, isPrimary),
        // A person stored as an account can only be moved, or named primary, where their
        // membership is a record of its own. Offering the button elsewhere only lets the
        // user click and be refused.
        canMove: this.isJunctionMode || !storedAsAccount,
        canMakePrimary: !isPrimary && (this.isJunctionMode || !storedAsAccount),
        moveLabel: MOVE_FOR.replace('{0}', member.name),
        makePrimaryLabel: MAKE_PRIMARY_FOR.replace('{0}', member.name)
      };
    });
  }

  isPrimary(member) {
    if (this.isJunctionMode) {
      return member.isPrimary === true;
    }
    return !!this.primaryContactId && member.personId === this.primaryContactId;
  }

  get isMoving() {
    return !!this.movingPersonId;
  }

  /**
   * The move offers households only. Until the record type is known nothing is offered,
   * which is better than offering every account in the org.
   */
  get householdFilter() {
    return {
      criteria: [
        {
          fieldPath: 'RecordTypeId',
          operator: 'eq',
          value: this.householdRecordTypeId || ''
        }
      ]
    };
  }

  badgesFor(member, isPrimary) {
    const badges = [];
    if (isPrimary) {
      badges.push({ key: `${member.personId}-primary`, text: PRIMARY });
    }
    if (member.isDeceased) {
      badges.push({ key: `${member.personId}-deceased`, text: DECEASED });
    }
    return badges;
  }

  handleAddClick() {
    this.isAdding = true;
    this.resetAddState();
  }

  handleAddCancel() {
    this.isAdding = false;
    this.resetAddState();
  }

  handleAddSuccess() {
    this.isAdding = false;
    this.toast(ADD_SUCCESS, 'success');
    return this.refresh();
  }

  resetAddState() {
    this.searchTerm = '';
    this.searchResults = [];
    this.newSalutation = '';
    this.newFirstName = '';
    this.newLastName = '';
    this.clearSearchTimer();
  }

  /**
   * Debounced the same way SettingsSearch debounces its own search, so that typing a name
   * fires one query per pause instead of one per keystroke.
   */
  handleSearchInput(event) {
    const term = event.target.value || '';
    this.searchTerm = term;
    this.clearSearchTimer();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => {
      this.runSearch(term);
    }, SEARCH_DEBOUNCE_MS);
  }

  async runSearch(term) {
    if (term.trim().length < SEARCH_MIN_LENGTH) {
      this.searchResults = [];
      return;
    }
    try {
      this.searchResults = (await searchPeople({ searchTerm: term })) || [];
      this.errorMessage = undefined;
    } catch (error) {
      this.searchResults = [];
      this.errorMessage = this.readError(error);
    }
  }

  handleAddExisting(event) {
    const personId = event.currentTarget.dataset.personId;
    this.busy = true;
    return addExistingPerson({ householdId: this.recordId, personId })
      .then(() => {
        this.isAdding = false;
        this.resetAddState();
        this.errorMessage = undefined;
        this.toast(ADD_SUCCESS, 'success');
        return this.refresh();
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleNewSalutationChange(event) {
    this.newSalutation = event.target.value;
  }

  handleNewFirstNameChange(event) {
    this.newFirstName = event.target.value;
  }

  handleNewLastNameChange(event) {
    this.newLastName = event.target.value;
  }

  handleAddNewSave() {
    this.busy = true;
    return addNewPerson({
      householdId: this.recordId,
      salutation: this.newSalutation,
      firstName: this.newFirstName,
      lastName: this.newLastName
    })
      .then(() => {
        this.isAdding = false;
        this.resetAddState();
        this.errorMessage = undefined;
        this.toast(ADD_SUCCESS, 'success');
        return this.refresh();
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  clearSearchTimer() {
    if (this.searchTimer) {
      clearTimeout(this.searchTimer);
      this.searchTimer = undefined;
    }
  }

  handleMoveClick(event) {
    this.movingPersonId = event.target.dataset.personId;
    this.targetHouseholdId = undefined;
  }

  handleMoveCancel() {
    this.movingPersonId = undefined;
    this.targetHouseholdId = undefined;
  }

  handleTargetChange(event) {
    const detail = event.detail || {};
    const value = detail.recordId === undefined ? detail.value : detail.recordId;
    this.targetHouseholdId = Array.isArray(value) ? value[0] : value;
  }

  handleMoveSave() {
    const personId = this.movingPersonId;
    const targetId = this.targetHouseholdId;
    this.busy = true;
    return moveContact({
      contactId: personId,
      targetHouseholdId: targetId,
      sourceHouseholdId: this.recordId
    })
      .then(() => {
        this.movingPersonId = undefined;
        this.targetHouseholdId = undefined;
        this.errorMessage = undefined;
        this.toast(MOVE_SUCCESS, 'success');
        return this.refresh();
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  /**
   * In the simple way of belonging the primary contact is a field on the household, written
   * through the platform so that the user's own access decides whether it is allowed. In the
   * flexible way it is a mark on the membership record, which the server moves.
   */
  handleMakePrimary(event) {
    const personId = event.target.dataset.personId;
    const member = this.members.find((row) => row.personId === personId);
    const name = member ? member.name : '';
    this.busy = true;
    const write = this.isJunctionMode
      ? makePrimaryMembership({ householdId: this.recordId, personId })
      : updateRecord({ fields: { Id: this.recordId, Primary_Contact__c: personId } });
    return write
      .then(() => {
        this.errorMessage = undefined;
        this.toast(MAKE_PRIMARY_SUCCESS.replace('{0}', name), 'success');
        return this.refresh();
      })
      .catch((error) => {
        this.errorMessage = this.isJunctionMode ? this.readError(error) : MAKE_PRIMARY_FAILED;
      })
      .finally(() => {
        this.busy = false;
      });
  }

  refresh() {
    return refreshApex(this.membersResult);
  }

  toast(message, variant) {
    Toast.show({ label: message, variant }, this);
  }

  readError(error) {
    if (!error) {
      return undefined;
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message;
  }
}
