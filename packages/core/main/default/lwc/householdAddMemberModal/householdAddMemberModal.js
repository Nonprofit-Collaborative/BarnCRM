import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import searchPeople from '@salesforce/apex/HouseholdOfPersonController.searchPeople';
import addExistingPerson from '@salesforce/apex/HouseholdOfPersonController.addExistingPerson';
import addNewPerson from '@salesforce/apex/HouseholdOfPersonController.addNewPerson';

import SAVE from '@salesforce/label/c.Core_HouseholdMembersPanel_Save';
import CANCEL from '@salesforce/label/c.Core_HouseholdMembersPanel_Cancel';
import ADD_EXISTING_HEADING from '@salesforce/label/c.Core_HouseholdPanel_AddExistingHeading';
import ADD_EXISTING_PLACEHOLDER from '@salesforce/label/c.Core_HouseholdPanel_AddExistingPlaceholder';
import ADD_EXISTING_RESULT_FOR from '@salesforce/label/c.Core_HouseholdPanel_AddExistingResultFor';
import ADD_EXISTING_NO_RESULTS from '@salesforce/label/c.Core_HouseholdPanel_AddExistingNoResults';
import ADD_NEW_HEADING from '@salesforce/label/c.Core_HouseholdPanel_AddNewHeading';
import SALUTATION from '@salesforce/label/c.Core_HouseholdPanel_Salutation';
import FIRST_NAME from '@salesforce/label/c.Core_HouseholdPanel_FirstName';
import LAST_NAME from '@salesforce/label/c.Core_HouseholdPanel_LastName';

// The same floor SettingsSearch uses, so a single keystroke never fires a search.
const SEARCH_DEBOUNCE_MS = 300;
const SEARCH_MIN_LENGTH = 2;

/**
 * The Add Member dialog of the Members panel, opened with HouseholdAddMemberModal.open({
 * label, size: 'small', householdId, junctionMode }). It resolves true once someone was added,
 * and false or undefined when closed without adding. The calls and their parameters are the
 * ones the panel made when the chooser sat inside it.
 */
export default class HouseholdAddMemberModal extends LightningModal {
  @api householdId;
  /** The flexible way of belonging: search for a person or add someone new. */
  @api junctionMode;

  labels = {
    save: SAVE,
    cancel: CANCEL,
    addExistingHeading: ADD_EXISTING_HEADING,
    addExistingPlaceholder: ADD_EXISTING_PLACEHOLDER,
    addExistingNoResults: ADD_EXISTING_NO_RESULTS,
    addNewHeading: ADD_NEW_HEADING,
    salutation: SALUTATION,
    firstName: FIRST_NAME,
    lastName: LAST_NAME
  };

  errorMessage;
  busy = false;

  searchResults = [];
  searchTerm = '';
  searchTimer;
  searchSequence = 0;

  newSalutation = '';
  newFirstName = '';
  newLastName = '';

  disconnectedCallback() {
    this.clearSearchTimer();
  }

  get hasSearchResults() {
    return this.searchResults.length > 0;
  }

  get showNoSearchResults() {
    return this.searchTerm.trim().length >= SEARCH_MIN_LENGTH && this.searchResults.length === 0;
  }

  /** The results with what a screen reader hears for each. */
  get searchResultRows() {
    return this.searchResults.map((person) => ({
      ...person,
      resultLabel: ADD_EXISTING_RESULT_FOR.replace('{0}', person.name)
    }));
  }

  /** Debounced, so typing a name fires one query per pause instead of one per keystroke. */
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
    const sequence = ++this.searchSequence;
    if (term.trim().length < SEARCH_MIN_LENGTH) {
      this.searchResults = [];
      return;
    }
    try {
      const found = (await searchPeople({ searchTerm: term })) || [];
      if (sequence === this.searchSequence) {
        this.searchResults = found;
        this.errorMessage = undefined;
      }
    } catch (error) {
      if (sequence === this.searchSequence) {
        this.searchResults = [];
        this.errorMessage = this.readError(error);
      }
    }
  }

  clearSearchTimer() {
    // A search still on its way for an earlier term is out of date from then on.
    this.searchSequence++;
    if (this.searchTimer) {
      clearTimeout(this.searchTimer);
      this.searchTimer = undefined;
    }
  }

  handleAddExisting(event) {
    const personId = event.currentTarget.dataset.personId;
    return this.save(addExistingPerson({ householdId: this.householdId, personId }));
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
    return this.save(
      addNewPerson({
        householdId: this.householdId,
        salutation: this.newSalutation,
        firstName: this.newFirstName,
        lastName: this.newLastName
      })
    );
  }

  /** The simple way: the contact form saved through the platform. */
  handleFormSuccess() {
    this.close(true);
  }

  handleCancel() {
    this.close(false);
  }

  save(call) {
    this.busy = true;
    return call
      .then(() => {
        this.clearSearchTimer();
        this.close(true);
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
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
