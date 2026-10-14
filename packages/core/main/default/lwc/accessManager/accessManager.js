import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import Toast from 'lightning/toast';
import BarnConfirmModal from 'c/barnConfirmModal';

import getAccessOverview from '@salesforce/apex/AccessController.getAccessOverview';
import searchUsersApex from '@salesforce/apex/AccessController.searchUsers';
import assignRoleApex from '@salesforce/apex/AccessController.assignRole';
import removeRoleApex from '@salesforce/apex/AccessController.removeRole';
import assignAddOnApex from '@salesforce/apex/AccessController.assignAddOn';
import removeAddOnApex from '@salesforce/apex/AccessController.removeAddOn';

import ADD_BUTTON from '@salesforce/label/c.Core_Access_AddButton';
import ADD_ON_ADD_BUTTON from '@salesforce/label/c.Core_Access_AddOnAddButton';
import ADD_ON_ASSIGN_SUCCESS from '@salesforce/label/c.Core_Access_AddOnAssignSuccess';
import ADD_ON_CONFIRM_ADD from '@salesforce/label/c.Core_Access_AddOnConfirmAddMessage';
import ADD_ON_CONFIRM_REMOVE from '@salesforce/label/c.Core_Access_AddOnConfirmRemoveMessage';
import ADD_ON_LABEL from '@salesforce/label/c.Core_Access_AddOnLabel';
import ADD_ON_PICKER_PLACEHOLDER from '@salesforce/label/c.Core_Access_AddOnPickerPlaceholder';
import ADD_ON_REMOVE_SUCCESS from '@salesforce/label/c.Core_Access_AddOnRemoveSuccess';
import ADD_ONS_DESCRIPTION from '@salesforce/label/c.Core_Access_AddOnsDescription';
import ADD_ONS_HEADING from '@salesforce/label/c.Core_Access_AddOnsHeading';
import ADD_ONS_READ_ONLY_NOTICE from '@salesforce/label/c.Core_Access_AddOnsReadOnlyNotice';
import NO_ONE_HAS_ADD_ON from '@salesforce/label/c.Core_Access_NoOneHasAddOn';
import ASSIGN_SUCCESS from '@salesforce/label/c.Core_Access_AssignSuccess';
import AUTOMATIC_ACCESS_HELP from '@salesforce/label/c.Core_Access_AutomaticAccessHelp';
import AUTOMATIC_ACCESS_LINK from '@salesforce/label/c.Core_Access_AutomaticAccessLink';
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
// User access policies cannot be created from a package, so this opens the guide with the exact definitions (ADR-0095).
const AUTOMATIC_ACCESS_GUIDE =
  'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/docs/admin-guide/automatic-access.md';
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
    addOnAddButton: ADD_ON_ADD_BUTTON,
    addOnLabel: ADD_ON_LABEL,
    addOnPickerPlaceholder: ADD_ON_PICKER_PLACEHOLDER,
    addOnsDescription: ADD_ONS_DESCRIPTION,
    addOnsHeading: ADD_ONS_HEADING,
    addOnsReadOnlyNotice: ADD_ONS_READ_ONLY_NOTICE,
    noOneHasAddOn: NO_ONE_HAS_ADD_ON,
    automaticAccessHelp: AUTOMATIC_ACCESS_HELP,
    automaticAccessLink: AUTOMATIC_ACCESS_LINK,
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
  automaticAccessGuide = AUTOMATIC_ACCESS_GUIDE;

  @track roles = [];
  @track assignments = [];
  @track searchResults = [];
  @track addOns = [];
  @track addOnAssignments = [];

  canManage = false;
  canAssignAddOns = false;
  selectedAddOn = '';
  currentUserId;
  loadError;
  isLoading = true;
  working = false;

  searchTerm = '';
  highlightedIndex = -1;
  selectedUser;
  selectedRole = '';

  overviewResult;
  pendingSearchTerm;

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
      this.canAssignAddOns = Boolean(data.canAssignAddOns);
      this.addOns = data.addOns || [];
      this.addOnAssignments = data.addOnAssignments || [];
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

  /** @returns {boolean} true when there is at least one extra permission to show */
  get hasAddOns() {
    return this.addOns.length > 0;
  }

  /** @returns {boolean} true when the person may give and remove extra permissions */
  get showAddOnControls() {
    return this.canManage && this.canAssignAddOns;
  }

  /**
   * @returns {boolean} true when the person may change roles but not extra permissions, so
   * the section needs its own notice (without Manage BarnCRM Settings the page notice says it)
   */
  get showAddOnReadOnly() {
    return this.canManage && !this.canAssignAddOns && this.hasAddOns;
  }

  /** @returns {Array<object>} one card per extra permission, with the people given it */
  get addOnCards() {
    const usersByName = {};
    this.addOnAssignments.forEach((entry) => {
      usersByName[entry.permissionSetName] = entry.users || [];
    });
    return this.addOns.map((addOn) => {
      const users = (usersByName[addOn.developerName] || []).map((person) => ({
        ...person,
        removeLabel: format(REMOVE_PERSON, [person.name])
      }));
      return {
        developerName: addOn.developerName,
        label: addOn.label,
        description: oneLine(addOn.description),
        warning: addOn.isDestructive ? addOn.warning : '',
        users,
        hasUsers: users.length > 0,
        heading: `${addOn.label} (${users.length})`
      };
    });
  }

  /** @returns {Array<object>} the extra permissions as options for their picker */
  get addOnOptions() {
    return this.addOns.map((addOn) => ({ label: addOn.label, value: addOn.developerName }));
  }

  /** @returns {object|undefined} the extra permission chosen in the picker */
  get chosenAddOn() {
    return this.addOns.find((addOn) => addOn.developerName === this.selectedAddOn);
  }

  /** @returns {string} what the chosen extra permission grants, shown under the picker */
  get chosenAddOnDescription() {
    return this.chosenAddOn ? oneLine(this.chosenAddOn.description) : '';
  }

  /** @returns {string} the warning for a chosen extra permission that removes data */
  get chosenAddOnWarning() {
    return this.chosenAddOn && this.chosenAddOn.isDestructive ? this.chosenAddOn.warning : '';
  }

  /** @returns {boolean} true while the Give permission button should stay disabled */
  get canSubmitAddOnDisabled() {
    return !(this.selectedUser && this.selectedAddOn) || this.working;
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

  /**
   * @param {object} action the change about to be confirmed
   * @returns {boolean} true when the person is about to remove their own admin role
   */
  isSelfRemoval(action) {
    return (
      !action.isAssign &&
      action.roleDeveloperName === ADMIN_ROLE &&
      action.userId === this.currentUserId
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
      return Promise.resolve();
    }
    return this.confirmAndRun({
      isAssign: true,
      userId: this.selectedUser.userId,
      userName: this.selectedUser.name,
      roleDeveloperName: this.selectedRole,
      roleLabel: this.roleLabelFor(this.selectedRole)
    });
  }

  /**
   * Asks the person to confirm taking a role away.
   *
   * @param {Event} event the click on a Remove button
   */
  handleRemoveClick(event) {
    const { userId, userName, role } = event.currentTarget.dataset;
    return this.confirmAndRun({
      isAssign: false,
      userId,
      userName,
      roleDeveloperName: role,
      roleLabel: this.roleLabelFor(role)
    });
  }

  /**
   * Remembers the chosen extra permission.
   *
   * @param {Event} event the change event from the extra permission picker
   */
  handleAddOnChange(event) {
    this.selectedAddOn = event.detail.value;
  }

  /** Asks the person to confirm giving the chosen extra permission to the chosen person. */
  handleAddOnAddClick() {
    if (!this.selectedUser || !this.selectedAddOn) {
      this.showError(ERROR_INVALID_INPUT);
      return Promise.resolve();
    }
    return this.confirmAndRun(
      this.addOnAction(true, this.selectedUser.userId, this.selectedUser.name, this.selectedAddOn)
    );
  }

  /**
   * Asks the person to confirm taking an extra permission away.
   *
   * @param {Event} event the click on a Remove button on an extra permission card
   */
  handleAddOnRemoveClick(event) {
    const { userId, userName, addOn } = event.currentTarget.dataset;
    return this.confirmAndRun(this.addOnAction(false, userId, userName, addOn));
  }

  /**
   * Describes a change to an extra permission in the same shape as a change to a role.
   *
   * @param {boolean} isAssign true to give it, false to take it away
   * @param {string} userId the person's Id
   * @param {string} userName the person's name
   * @param {string} developerName the extra permission's API name
   * @returns {object} the change
   */
  addOnAction(isAssign, userId, userName, developerName) {
    const addOn = this.addOns.find((candidate) => candidate.developerName === developerName);
    return {
      isAssign,
      isAddOn: true,
      userId,
      userName,
      roleDeveloperName: developerName,
      roleLabel: addOn ? addOn.label : developerName,
      warning: isAssign && addOn && addOn.isDestructive ? addOn.warning : ''
    };
  }

  /**
   * The wording for one change, by whether it gives or takes away and whether it is a role
   * or an extra permission.
   *
   * @param {object} action the change
   * @returns {object} confirm, success and button wording
   */
  wordingFor(action) {
    if (action.isAddOn) {
      return {
        confirm: action.isAssign ? ADD_ON_CONFIRM_ADD : ADD_ON_CONFIRM_REMOVE,
        success: action.isAssign ? ADD_ON_ASSIGN_SUCCESS : ADD_ON_REMOVE_SUCCESS,
        button: action.isAssign ? this.labels.addOnAddButton : this.labels.removeButton
      };
    }
    return {
      confirm: action.isAssign ? CONFIRM_ADD_MESSAGE : CONFIRM_REMOVE_MESSAGE,
      success: action.isAssign ? ASSIGN_SUCCESS : REMOVE_SUCCESS,
      button: action.isAssign ? this.labels.addButton : this.labels.removeButton
    };
  }

  /**
   * Asks the person to confirm a change in a modal, and carries it out when they do.
   * Cancel, Escape and the close button change nothing.
   *
   * @param {object} action the change: isAssign, isAddOn, userId, userName, roleDeveloperName,
   * roleLabel, and for an extra permission that removes data, warning
   * @returns {Promise} settles once the change is done or declined
   */
  async confirmAndRun(action) {
    const wording = this.wordingFor(action);
    const details = [];
    if (this.isSelfRemoval(action)) {
      details.push(this.labels.selfRemovalWarning);
    }
    if (action.warning) {
      details.push(action.warning);
    }
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: action.isAssign ? this.labels.confirmAddTitle : this.labels.confirmRemoveTitle,
      message: format(wording.confirm, [action.userName, action.roleLabel]),
      details,
      confirmLabel: wording.button,
      cancelLabel: this.labels.cancelButton
    });
    if (confirmed) {
      await this.run(action);
    }
  }

  /**
   * Carries out a confirmed change.
   *
   * @param {object} action the change the person confirmed
   * @returns {Promise} settles once the change is done
   */
  run(action) {
    this.working = true;
    let request;
    if (action.isAddOn) {
      const call = action.isAssign ? assignAddOnApex : removeAddOnApex;
      request = call({ userId: action.userId, permissionSetName: action.roleDeveloperName });
    } else {
      const call = action.isAssign ? assignRoleApex : removeRoleApex;
      request = call({ userId: action.userId, roleDeveloperName: action.roleDeveloperName });
    }
    return request
      .then((result) => {
        if (result && result.success) {
          this.showSuccess(
            format(this.wordingFor(action).success, [action.userName, action.roleLabel])
          );
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
    this.selectedAddOn = '';
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
    Toast.show({ label: TOAST_SUCCESS_TITLE, message, variant: 'success' }, this);
  }

  /**
   * Shows a message saying a change did not work.
   *
   * @param {string} message what to say
   */
  showError(message) {
    Toast.show(
      {
        label: TOAST_ERROR_TITLE,
        message: message || ERROR_UNEXPECTED,
        variant: 'error',
        mode: 'sticky'
      },
      this
    );
  }
}
