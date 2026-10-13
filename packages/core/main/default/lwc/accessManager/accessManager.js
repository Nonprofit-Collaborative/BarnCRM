import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getAccessOverview from '@salesforce/apex/AccessController.getAccessOverview';
import searchUsersApex from '@salesforce/apex/AccessController.searchUsers';
import assignRoleApex from '@salesforce/apex/AccessController.assignRole';
import removeRoleApex from '@salesforce/apex/AccessController.removeRole';

import ADD_BUTTON from '@salesforce/label/c.Core_Access_AddButton';
import ASSIGN_SUCCESS from '@salesforce/label/c.Core_Access_AssignSuccess';
import CANCEL_BUTTON from '@salesforce/label/c.Core_Access_CancelButton';
import CONFIRM_ADD_MESSAGE from '@salesforce/label/c.Core_Access_ConfirmAddMessage';
import CONFIRM_ADD_TITLE from '@salesforce/label/c.Core_Access_ConfirmAddTitle';
import CONFIRM_REMOVE_MESSAGE from '@salesforce/label/c.Core_Access_ConfirmRemoveMessage';
import CONFIRM_REMOVE_TITLE from '@salesforce/label/c.Core_Access_ConfirmRemoveTitle';
import CREATE_USER_HELP from '@salesforce/label/c.Core_Access_CreateUserHelp';
import CREATE_USER_LINK from '@salesforce/label/c.Core_Access_CreateUserLink';
import ERROR_INVALID_INPUT from '@salesforce/label/c.Core_Access_ErrorInvalidInput';
import ERROR_UNEXPECTED from '@salesforce/label/c.Core_Access_ErrorUnexpected';
import LOADING_ROLES from '@salesforce/label/c.Core_Access_LoadingRoles';
import NO_ONE_IN_ROLE from '@salesforce/label/c.Core_Access_NoOneInRole';
import PAGE_DESCRIPTION from '@salesforce/label/c.Core_Access_PageDescription';
import PAGE_TITLE from '@salesforce/label/c.Core_Access_PageTitle';
import READ_ONLY_NOTICE from '@salesforce/label/c.Core_Access_ReadOnlyNotice';
import REMOVE_BUTTON from '@salesforce/label/c.Core_Access_RemoveButton';
import REMOVE_SUCCESS from '@salesforce/label/c.Core_Access_RemoveSuccess';
import ROLE_LABEL from '@salesforce/label/c.Core_Access_RoleLabel';
import ROLE_PICKER_PLACEHOLDER from '@salesforce/label/c.Core_Access_RolePickerPlaceholder';
import SEARCH_LABEL from '@salesforce/label/c.Core_Access_SearchLabel';
import SEARCH_NO_RESULTS from '@salesforce/label/c.Core_Access_SearchNoResults';
import SEARCH_PLACEHOLDER from '@salesforce/label/c.Core_Access_SearchPlaceholder';
import SELF_REMOVAL_WARNING from '@salesforce/label/c.Core_Access_SelfRemovalWarning';
import REMOVE_PERSON from '@salesforce/label/c.Core_Access_RemovePerson';
import TOAST_ERROR_TITLE from '@salesforce/label/c.Core_Access_ToastErrorTitle';
import TOAST_SUCCESS_TITLE from '@salesforce/label/c.Core_Access_ToastSuccessTitle';
import USERS_IN_ROLE from '@salesforce/label/c.Core_Access_UsersInRole';

const ADMIN_ROLE = 'BarnCRM_Admin_Group';
const SETUP_USERS_PAGE = '/lightning/setup/ManageUsers/home';
const MINIMUM_SEARCH_LENGTH = 2;

/**
 * Squeezes any run of whitespace down to one space. A role description comes from the
 * permission set group's own description element, where the source file may have wrapped
 * it across lines, and the line breaks are not part of the sentence.
 *
 * @param {string} text the text to tidy
 * @returns {string} the same words on one line
 */
function oneLine(text) {
  return text ? text.replace(/\s+/g, ' ').trim() : '';
}

/**
 * Fills the numbered slots in a Custom Label, so that "{0} now has the {1} role."
 * becomes a sentence about a real person.
 *
 * @param {string} template the label text
 * @param {Array<string>} values the values to put in the slots, in order
 * @returns {string} the finished sentence
 */
function format(template, values) {
  return values.reduce(
    (text, value, index) => text.replace(new RegExp(`\\{${index}\\}`, 'g'), () => String(value)),
    template
  );
}

export default class AccessManager extends LightningElement {
  labels = {
    addButton: ADD_BUTTON,
    cancelButton: CANCEL_BUTTON,
    confirmAddTitle: CONFIRM_ADD_TITLE,
    confirmRemoveTitle: CONFIRM_REMOVE_TITLE,
    createUserHelp: CREATE_USER_HELP,
    createUserLink: CREATE_USER_LINK,
    loadingRoles: LOADING_ROLES,
    noOneInRole: NO_ONE_IN_ROLE,
    pageDescription: PAGE_DESCRIPTION,
    pageTitle: PAGE_TITLE,
    readOnlyNotice: READ_ONLY_NOTICE,
    removeButton: REMOVE_BUTTON,
    roleLabel: ROLE_LABEL,
    rolePickerPlaceholder: ROLE_PICKER_PLACEHOLDER,
    searchLabel: SEARCH_LABEL,
    searchNoResults: SEARCH_NO_RESULTS,
    searchPlaceholder: SEARCH_PLACEHOLDER,
    selfRemovalWarning: SELF_REMOVAL_WARNING,
    usersInRole: USERS_IN_ROLE
  };

  setupUsersPage = SETUP_USERS_PAGE;

  @track roles = [];
  @track assignments = [];
  @track searchResults = [];

  canManage = false;
  currentUserId;
  loadError;
  isLoading = true;
  working = false;

  searchTerm = '';
  highlightedIndex = -1;
  selectedUser;
  selectedRole = '';
  pendingAction;

  overviewResult;
  pendingSearchTerm;

  /** The confirmation whose heading already has focus, so it is focused once per opening. */
  focusedConfirmation;

  /**
   * Moves focus to the confirmation's heading when it opens, so a keyboard or screen reader
   * user hears the question rather than having to find it below the table.
   */
  renderedCallback() {
    const open = this.pendingAction;
    if (open && open !== this.focusedConfirmation) {
      const heading = this.template.querySelector('[data-id="confirmation-heading"]');
      if (heading) {
        heading.focus();
      }
    }
    this.focusedConfirmation = open;
  }

  @wire(getAccessOverview)
  handleOverview(response) {
    this.overviewResult = response;
    const { data, error } = response;
    if (data) {
      this.isLoading = false;
      this.canManage = data.canManage;
      this.currentUserId = data.currentUserId;
      this.roles = data.roles || [];
      this.assignments = data.assignments || [];
      this.loadError = data.success ? undefined : data.message;
    } else if (error) {
      this.isLoading = false;
      this.loadError = ERROR_UNEXPECTED;
    }
  }

  /** @returns {boolean} true while the page has nothing to show yet */
  get showSpinner() {
    return this.isLoading || this.working;
  }

  /** @returns {boolean} true when the person may not change roles */
  get isReadOnly() {
    return !this.canManage;
  }

  /** @returns {Array<object>} one card per role, with the people who hold it */
  get roleCards() {
    const usersByRole = {};
    this.assignments.forEach((entry) => {
      usersByRole[entry.roleDeveloperName] = entry.users || [];
    });
    return this.roles.map((role) => {
      const users = (usersByRole[role.developerName] || []).map((person) => ({
        ...person,
        removeLabel: format(REMOVE_PERSON, [person.name])
      }));
      return {
        developerName: role.developerName,
        label: role.label,
        description: oneLine(role.description),
        users,
        hasUsers: users.length > 0,
        count: users.length,
        heading: `${role.label} (${users.length})`
      };
    });
  }

  /** @returns {Array<object>} the five roles as options for the role picker */
  get roleOptions() {
    return this.roles.map((role) => ({ label: role.label, value: role.developerName }));
  }

  /** @returns {boolean} true when a search has run and matched nobody */
  get showNoResults() {
    return (
      this.searchTerm.trim().length >= MINIMUM_SEARCH_LENGTH &&
      this.searchResults.length === 0 &&
      !this.selectedUser
    );
  }

  /** @returns {boolean} true when there are people to choose from */
  get hasSearchResults() {
    return this.searchResults.length > 0;
  }

  /** @returns {Array<object>} the search results, with the highlighted one marked */
  get searchOptions() {
    return this.searchResults.map((person, index) => ({
      ...person,
      optionId: `access-option-${index}`,
      optionClass:
        index === this.highlightedIndex
          ? 'slds-listbox__option slds-listbox__option_entity slds-has-focus'
          : 'slds-listbox__option slds-listbox__option_entity'
    }));
  }

  /** @returns {string} the id of the highlighted option, for screen readers */
  get activeOptionId() {
    return this.highlightedIndex >= 0 ? `access-option-${this.highlightedIndex}` : '';
  }

  /** @returns {string} whether the search list is open, for screen readers */
  get listboxExpanded() {
    return this.hasSearchResults ? 'true' : 'false';
  }

  /** @returns {boolean} true when both a person and a role have been chosen */
  get canSubmit() {
    return Boolean(this.selectedUser && this.selectedRole) && !this.working;
  }

  /** @returns {boolean} true while the Give access button should stay disabled */
  get canSubmitDisabled() {
    return !this.canSubmit;
  }

  /** @returns {boolean} true when a confirmation is on screen */
  get showConfirmation() {
    return Boolean(this.pendingAction);
  }

  /** @returns {string} the heading of the confirmation on screen */
  get confirmationTitle() {
    if (!this.pendingAction) {
      return '';
    }
    return this.pendingAction.isAssign
      ? this.labels.confirmAddTitle
      : this.labels.confirmRemoveTitle;
  }

  /** @returns {string} the question the confirmation asks */
  get confirmationMessage() {
    if (!this.pendingAction) {
      return '';
    }
    const template = this.pendingAction.isAssign ? CONFIRM_ADD_MESSAGE : CONFIRM_REMOVE_MESSAGE;
    return format(template, [this.pendingAction.userName, this.pendingAction.roleLabel]);
  }

  /** @returns {string} the button that carries out the confirmed action */
  get confirmationButtonLabel() {
    if (!this.pendingAction) {
      return '';
    }
    return this.pendingAction.isAssign ? this.labels.addButton : this.labels.removeButton;
  }

  /** @returns {boolean} true when the person is about to remove their own admin role */
  get showSelfRemovalWarning() {
    return Boolean(
      this.pendingAction &&
      !this.pendingAction.isAssign &&
      this.pendingAction.roleDeveloperName === ADMIN_ROLE &&
      this.pendingAction.userId === this.currentUserId
    );
  }

  /**
   * Searches once at least two characters have been typed, so that an empty or almost
   * empty box does not ask the org for everyone.
   *
   * @param {Event} event the input event from the search box
   */
  handleSearchChange(event) {
    this.searchTerm = event.target.value || '';
    this.selectedUser = undefined;
    this.highlightedIndex = -1;
    if (this.searchTerm.trim().length < MINIMUM_SEARCH_LENGTH) {
      this.searchResults = [];
      this.pendingSearchTerm = undefined;
      return;
    }
    this.runSearch();
  }

  /**
   * Asks Apex for people matching what has been typed. The term the request was made
   * for is remembered, so that a slow answer to an earlier keystroke cannot replace the
   * answer to a later one.
   */
  runSearch() {
    const term = this.searchTerm.trim();
    this.pendingSearchTerm = term;
    searchUsersApex({ term })
      .then((result) => {
        if (this.pendingSearchTerm !== term) {
          return;
        }
        this.searchResults = result && result.success ? result.users || [] : [];
        if (result && !result.success) {
          this.showError(result.message);
        }
      })
      .catch(() => {
        if (this.pendingSearchTerm !== term) {
          return;
        }
        this.searchResults = [];
        this.showError(ERROR_UNEXPECTED);
      });
  }

  /**
   * Moves through the list of people with the arrow keys, chooses one with Enter, and
   * closes the list with Escape.
   *
   * @param {KeyboardEvent} event the key that was pressed in the search box
   */
  handleSearchKeyDown(event) {
    if (!this.hasSearchResults) {
      return;
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      this.highlightedIndex = (this.highlightedIndex + 1) % this.searchResults.length;
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      this.highlightedIndex =
        (this.highlightedIndex - 1 + this.searchResults.length) % this.searchResults.length;
    } else if (event.key === 'Enter' && this.highlightedIndex >= 0) {
      event.preventDefault();
      this.chooseUser(this.searchResults[this.highlightedIndex]);
    } else if (event.key === 'Escape') {
      this.searchResults = [];
      this.highlightedIndex = -1;
    }
  }

  /**
   * Chooses the person whose name was clicked.
   *
   * @param {Event} event the click on one of the search results
   */
  handleUserSelect(event) {
    const userId = event.currentTarget.dataset.userId;
    const person = this.searchResults.find((candidate) => candidate.userId === userId);
    if (person) {
      this.chooseUser(person);
    }
  }

  /**
   * Remembers the chosen person and closes the search list.
   *
   * @param {object} person the person who was chosen
   */
  chooseUser(person) {
    this.selectedUser = person;
    this.searchTerm = person.name;
    this.searchResults = [];
    this.highlightedIndex = -1;
  }

  /**
   * Remembers the chosen role.
   *
   * @param {Event} event the change event from the role picker
   */
  handleRoleChange(event) {
    this.selectedRole = event.detail.value;
  }

  /** Asks the person to confirm giving the chosen role to the chosen person. */
  handleAddClick() {
    if (!this.selectedUser || !this.selectedRole) {
      this.showError(ERROR_INVALID_INPUT);
      return;
    }
    this.pendingAction = {
      isAssign: true,
      userId: this.selectedUser.userId,
      userName: this.selectedUser.name,
      roleDeveloperName: this.selectedRole,
      roleLabel: this.roleLabelFor(this.selectedRole)
    };
  }

  /**
   * Asks the person to confirm taking a role away.
   *
   * @param {Event} event the click on a Remove button
   */
  handleRemoveClick(event) {
    const { userId, userName, role } = event.currentTarget.dataset;
    this.pendingAction = {
      isAssign: false,
      userId,
      userName,
      roleDeveloperName: role,
      roleLabel: this.roleLabelFor(role)
    };
  }

  /** Closes the confirmation without changing anything. */
  handleCancel() {
    this.pendingAction = undefined;
  }

  /** Carries out the confirmed change. */
  handleConfirm() {
    const action = this.pendingAction;
    if (!action) {
      return;
    }
    this.pendingAction = undefined;
    this.working = true;
    const call = action.isAssign ? assignRoleApex : removeRoleApex;
    call({ userId: action.userId, roleDeveloperName: action.roleDeveloperName })
      .then((result) => {
        if (result && result.success) {
          const template = action.isAssign ? ASSIGN_SUCCESS : REMOVE_SUCCESS;
          this.showSuccess(format(template, [action.userName, action.roleLabel]));
          this.resetChooser();
          return refreshApex(this.overviewResult);
        }
        this.showError(result ? result.message : ERROR_UNEXPECTED);
        return null;
      })
      .catch(() => {
        this.showError(ERROR_UNEXPECTED);
      })
      .finally(() => {
        this.working = false;
      });
  }

  /** Empties the person and role choices after a change has been made. */
  resetChooser() {
    this.selectedUser = undefined;
    this.selectedRole = '';
    this.searchTerm = '';
    this.searchResults = [];
    this.highlightedIndex = -1;
  }

  /**
   * Finds the label of a role from its DeveloperName.
   *
   * @param {string} developerName the role's DeveloperName
   * @returns {string} the role's label, or its DeveloperName when it is not loaded
   */
  roleLabelFor(developerName) {
    const role = this.roles.find((candidate) => candidate.developerName === developerName);
    return role ? role.label : developerName;
  }

  /**
   * Shows a message saying a change worked.
   *
   * @param {string} message what to say
   */
  showSuccess(message) {
    this.dispatchEvent(
      new ShowToastEvent({ title: TOAST_SUCCESS_TITLE, message, variant: 'success' })
    );
  }

  /**
   * Shows a message saying a change did not work.
   *
   * @param {string} message what to say
   */
  showError(message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: TOAST_ERROR_TITLE,
        message: message || ERROR_UNEXPECTED,
        variant: 'error',
        mode: 'sticky'
      })
    );
  }
}
