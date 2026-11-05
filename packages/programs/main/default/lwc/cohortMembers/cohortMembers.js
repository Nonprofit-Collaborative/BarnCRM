import { LightningElement, api } from 'lwc';
import getMembers from '@salesforce/apex/CohortController.getMembers';
import addMembers from '@salesforce/apex/CohortController.addMembers';
import removeMember from '@salesforce/apex/CohortController.removeMember';
import getPersonName from '@salesforce/apex/CohortController.getPersonName';

import TITLE from '@salesforce/label/c.Programs_Cohort_Title';
import MEMBER_COUNT from '@salesforce/label/c.Programs_Cohort_MemberCount';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import REMOVE_FOR from '@salesforce/label/c.Programs_Cohort_RemoveFor';
import ADD_PEOPLE from '@salesforce/label/c.Programs_Cohort_AddPeople';
import CANDIDATES from '@salesforce/label/c.Programs_Cohort_Candidates';
import NO_CANDIDATES from '@salesforce/label/c.Programs_Cohort_NoCandidates';
import SELECT_ALL from '@salesforce/label/c.Programs_Cohort_SelectAll';
import TICK_FOR from '@salesforce/label/c.Programs_Cohort_TickFor';
import SOMEONE_ELSE from '@salesforce/label/c.Programs_Cohort_SomeoneElse';
import PERSON from '@salesforce/label/c.Core_Section_Person';
import ADD_TO_LIST from '@salesforce/label/c.Programs_Cohort_AddToList';
import TAKE_OFF_LIST from '@salesforce/label/c.Programs_Cohort_TakeOffList';
import ADD_TO_COHORT from '@salesforce/label/c.Programs_Cohort_AddToCohort';
import CHOSEN from '@salesforce/label/c.Programs_Cohort_Chosen';
import ADDED_ONE from '@salesforce/label/c.Programs_Cohort_AddedOne';
import ADDED_MANY from '@salesforce/label/c.Programs_Cohort_AddedMany';
import SOME_FAILED from '@salesforce/label/c.Programs_Cohort_SomeFailed';
import NOT_ADDED from '@salesforce/label/c.Programs_Cohort_NotAdded';
import REMOVED from '@salesforce/label/c.Programs_Cohort_Removed';
import MORE_THAN_SHOWN from '@salesforce/label/c.Programs_Cohort_MoreThanShown';
import TOO_MANY from '@salesforce/label/c.Programs_Cohort_TooMany';
import ACTION_FAILED from '@salesforce/label/c.Programs_Cohort_ActionFailed';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

import {
  addPayload,
  addedMessage,
  allTicked,
  candidateRows,
  chosenCount,
  format,
  memberRows,
  withPerson,
  withTicked,
  withoutPerson
} from './members';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The Cohort Members panel on a cohort (P-11, R-CO3): the cohort's members, and many people
 * added in one action, from the program's open enrollments in no cohort and people picked one by
 * one. Each person is added or refused on their own; the refused are listed with the reason.
 */
export default class CohortMembers extends LightningElement {
  helpReady = isHelpLoaded('Programs');

  @api recordId;

  labels = {
    title: TITLE,
    get membersEmpty() {
      return helpText('Programs', 'Programs_Cohort_MembersEmpty');
    },
    remove: REMOVE,
    addPeople: ADD_PEOPLE,
    candidates: CANDIDATES,
    noCandidates: NO_CANDIDATES,
    selectAll: SELECT_ALL,
    someoneElse: SOMEONE_ELSE,
    person: PERSON,
    addToList: ADD_TO_LIST,
    addToCohort: ADD_TO_COHORT,
    notAdded: NOT_ADDED,
    moreThanShown: MORE_THAN_SHOWN,
    loading: LOADING
  };

  data;
  ticked = [];
  picked = [];
  pickedId;
  failures = [];
  loading = true;
  busy = false;
  errorMessage;
  resultMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Programs').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  load() {
    this.loading = true;
    return getMembers({ cohortId: this.recordId })
      .then((data) => {
        this.data = data;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.loading = false;
      });
  }

  get showSpinner() {
    return this.loading || this.busy;
  }

  get loaded() {
    return !!this.data;
  }

  get members() {
    return memberRows(this.data && this.data.members, { removeFor: REMOVE_FOR });
  }

  get memberCount() {
    return format(MEMBER_COUNT, this.members.length);
  }

  get hasMembers() {
    return this.members.length > 0;
  }

  get canEdit() {
    return !!(this.data && this.data.canEdit);
  }

  get canEnroll() {
    return !!(this.data && this.data.canEnroll);
  }

  get candidates() {
    return candidateRows(this.data && this.data.candidates, this.ticked, { tickFor: TICK_FOR });
  }

  get hasCandidates() {
    return this.candidates.length > 0;
  }

  get pickedPeople() {
    return this.picked.map((one) => ({ ...one, takeOffLabel: format(TAKE_OFF_LIST, one.name) }));
  }

  get hasPicked() {
    return this.picked.length > 0;
  }

  get moreThanShown() {
    return !!(this.data && this.data.moreThanShown);
  }

  get personObjectApiName() {
    return this.data && this.data.hasPersonAccounts ? 'Account' : 'Contact';
  }

  /** In a person account org, only person accounts: an organization is never a participant. */
  get personFilter() {
    if (!this.data || !this.data.personFilterField) {
      return undefined;
    }
    return { criteria: [{ fieldPath: this.data.personFilterField, operator: 'eq', value: true }] };
  }

  get chosen() {
    return chosenCount(this.data && this.data.candidates, this.ticked, this.picked);
  }

  get chosenMessage() {
    const max = this.data ? this.data.maxPerAction : 200;
    return this.chosen > max ? format(TOO_MANY, max) : format(CHOSEN, this.chosen);
  }

  get addDisabled() {
    const max = this.data ? this.data.maxPerAction : 200;
    return this.busy || this.chosen === 0 || this.chosen > max;
  }

  get addToListDisabled() {
    return this.busy || !this.pickedId;
  }

  get hasFailures() {
    return this.failures.length > 0;
  }

  // ------------------------------------------------------------------------- choosing

  handleTick(event) {
    this.clearMessages();
    this.ticked = withTicked(this.ticked, event.target.dataset.enrollment, event.target.checked);
  }

  handleSelectAll() {
    this.clearMessages();
    this.ticked = allTicked(this.data && this.data.candidates, this.ticked);
  }

  handlePersonChange(event) {
    this.pickedId = event.detail ? event.detail.recordId : undefined;
  }

  handleAddToList() {
    const personId = this.pickedId;
    if (!personId) {
      return Promise.resolve();
    }
    this.clearMessages();
    return getPersonName({ personId })
      .catch(() => undefined)
      .then((name) => {
        this.picked = withPerson(this.picked, { id: personId, name });
        this.pickedId = undefined;
        const picker = this.template.querySelector('[data-id="person-picker"]');
        if (picker && typeof picker.clearSelection === 'function') {
          picker.clearSelection();
        }
      });
  }

  handleTakeOff(event) {
    this.picked = withoutPerson(this.picked, event.target.dataset.person);
  }

  // ------------------------------------------------------------------------- saving

  handleAdd() {
    if (this.addDisabled) {
      return Promise.resolve();
    }
    const payload = addPayload(this.data && this.data.candidates, this.ticked, this.picked);
    this.clearMessages();
    this.busy = true;
    return addMembers({ cohortId: this.recordId, ...payload })
      .then((data) => {
        this.data = data;
        this.failures = (data.failures || []).map((one, index) => ({ ...one, key: String(index) }));
        this.resultMessage = addedMessage(data, {
          addedOne: ADDED_ONE,
          addedMany: ADDED_MANY,
          someFailed: SOME_FAILED
        });
        this.ticked = [];
        this.picked = [];
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleRemove(event) {
    const enrollmentId = event.target.dataset.enrollment;
    this.clearMessages();
    this.busy = true;
    return removeMember({ cohortId: this.recordId, enrollmentId })
      .then((data) => {
        this.data = data;
        this.resultMessage = REMOVED;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  clearMessages() {
    this.errorMessage = undefined;
    this.resultMessage = undefined;
    this.failures = [];
  }
}
