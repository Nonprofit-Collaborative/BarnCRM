import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import searchPeople from '@salesforce/apex/HouseholdOfPersonController.searchPeople';
import addExistingPerson from '@salesforce/apex/HouseholdOfPersonController.addExistingPerson';
import addNewPerson from '@salesforce/apex/HouseholdOfPersonController.addNewPerson';
import findSameName from '@salesforce/apex/PersonSameNameController.findSameName';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { describeSameNamePerson, joinName } from './sameNameHint';

import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
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

/** The mode that creates one person and returns them, for a picker that offers New Person. */
const PERSON_MODE = 'person';

/**
 * Two dialogs in one.
 *
 * Add Member, from the Members panel: HouseholdAddMemberModal.open({ label, size: 'small',
 * householdId, junctionMode }). It resolves true once someone was added, and false or
 * undefined when closed without adding.
 *
 * New person, from any screen that picks a person (Quick Gift Entry's donor):
 * HouseholdAddMemberModal.open({ label, size: 'small', mode: 'person' }). It shows the contact
 * form with Email, Street, City and Postal Code, saves through the platform exactly as Contact
 * New does (so the household is made automatically and the org's duplicate rules run), and
 * resolves { id, name } with the new person, or with the existing person chosen from the
 * same-name hint. It resolves undefined when closed without a person.
 *
 * Both show the same-name hint (people-giving-24) under the name fields: "Already in BarnCRM:
 * Ana Garcia, Tampa (Garcia Household). Use this person instead?", one click to switch.
 */
export default class HouseholdAddMemberModal extends LightningModal {
  @api householdId;
  /** The flexible way of belonging: search for a person or add someone new. */
  @api junctionMode;
  /** 'person' for the standalone new person dialog; anything else is Add Member. */
  @api mode;

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

  helpReady = isHelpLoaded('Core');
  errorMessage;
  busy = false;

  searchResults = [];
  searchTerm = '';
  searchTimer;
  searchSequence = 0;

  newSalutation = '';
  newFirstName = '';
  newLastName = '';

  sameNameMatches = [];
  sameNameTimer;
  sameNameSequence = 0;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  disconnectedCallback() {
    this.clearSearchTimer();
    this.clearSameNameTimer();
  }

  get personMode() {
    return this.mode === PERSON_MODE;
  }

  /** The flexible way of Add Member: search plus the add-new fields saved by Apex. */
  get searchMode() {
    return !this.personMode && this.junctionMode;
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

  /** The people with the name being typed, each as a sentence and its switch. */
  get sameNameRows() {
    if (!this.helpReady) {
      return [];
    }
    const useLabel = helpText('Core', 'Core_PersonSameName_Use');
    return this.sameNameMatches.map((match) => ({
      id: match.id,
      message: helpText('Core', 'Core_PersonSameName_Hint', describeSameNamePerson(match)),
      useLabel
    }));
  }

  get hasSameName() {
    return this.sameNameRows.length > 0;
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

  /** Both the plain inputs and the contact form's fields land here. */
  handleNewFirstNameChange(event) {
    this.newFirstName = this.valueOf(event);
    this.queueSameName();
  }

  handleNewLastNameChange(event) {
    this.newLastName = this.valueOf(event);
    this.queueSameName();
  }

  valueOf(event) {
    const detail = event.detail;
    const value = detail && detail.value !== undefined ? detail.value : event.target.value;
    return value || '';
  }

  /** The hint waits for a pause in typing, like the search. */
  queueSameName() {
    this.clearSameNameTimer();
    const firstName = this.newFirstName;
    const lastName = this.newLastName;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.sameNameTimer = setTimeout(() => {
      this.runSameName(firstName, lastName);
    }, SEARCH_DEBOUNCE_MS);
  }

  async runSameName(firstName, lastName) {
    const sequence = ++this.sameNameSequence;
    if (lastName.trim().length < SEARCH_MIN_LENGTH) {
      this.sameNameMatches = [];
      return;
    }
    try {
      const found =
        (await findSameName({
          firstName,
          lastName,
          excludeHouseholdId: this.personMode ? null : this.householdId
        })) || [];
      if (sequence === this.sameNameSequence) {
        this.sameNameMatches = found;
      }
    } catch {
      // No hint is not an error: the person can still be saved.
      if (sequence === this.sameNameSequence) {
        this.sameNameMatches = [];
      }
    }
  }

  clearSameNameTimer() {
    this.sameNameSequence++;
    if (this.sameNameTimer) {
      clearTimeout(this.sameNameTimer);
      this.sameNameTimer = undefined;
    }
  }

  /** "Use this person instead?": the existing person, in place of a new one. */
  handleUseSameName(event) {
    const personId = event.currentTarget.dataset.personId;
    const match = this.sameNameMatches.find((candidate) => candidate.id === personId);
    if (!match) {
      return undefined;
    }
    this.clearSameNameTimer();
    if (this.personMode) {
      this.close({ id: match.id, name: match.name });
      return undefined;
    }
    return this.save(addExistingPerson({ householdId: this.householdId, personId }));
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

  /** The contact form saved through the platform. */
  handleFormSuccess(event) {
    this.clearSameNameTimer();
    if (!this.personMode) {
      this.close(true);
      return;
    }
    const id = event.detail && event.detail.id;
    this.close({ id, name: joinName(this.newFirstName, this.newLastName) });
  }

  handleCancel() {
    this.close(this.personMode ? undefined : false);
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
