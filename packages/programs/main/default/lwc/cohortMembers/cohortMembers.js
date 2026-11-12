import { LightningElement, api } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import getMembers from '@salesforce/apex/CohortController.getMembers';
import addMembers from '@salesforce/apex/CohortController.addMembers';
import removeMember from '@salesforce/apex/CohortController.removeMember';
import getPersonName from '@salesforce/apex/CohortController.getPersonName';

import TITLE from '@salesforce/label/c.Programs_Cohort_Title';
import MEMBER_COUNT from '@salesforce/label/c.Programs_Cohort_MemberCount';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import REMOVE_FOR from '@salesforce/label/c.Programs_Cohort_RemoveFor';
import ADD_PEOPLE from '@salesforce/label/c.Programs_Cohort_AddPeople';
import CANDIDATES from '@salesforce/label/c.Programs_Cohort_Candidates';
import SELECT_ALL from '@salesforce/label/c.Programs_Cohort_SelectAll';
import TICK_FOR from '@salesforce/label/c.Programs_Cohort_TickFor';
import SOMEONE_ELSE from '@salesforce/label/c.Programs_Cohort_SomeoneElse';
import PERSON from '@salesforce/label/c.Core_Section_Person';
import ADD_TO_LIST from '@salesforce/label/c.Programs_Cohort_AddToList';
import TAKE_OFF_LIST from '@salesforce/label/c.Programs_Cohort_TakeOffList';
import ADD_TO_COHORT from '@salesforce/label/c.Programs_Cohort_AddToCohort';
import CHOSEN from '@salesforce/label/c.Programs_Cohort_Chosen';
import NOT_ADDED from '@salesforce/label/c.Programs_Cohort_NotAdded';
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
import { createDragController } from 'c/barnDrag';
import { dragInstructions, dragMessages } from 'c/barnDragText';

const HELP = ['Programs', 'Core'];
const MEMBERS_ZONE = 'members';

/**
 * The Cohort Members panel on a cohort (P-11, R-CO3): the cohort's members, and many people
 * added in one action, from the program's open enrollments in no cohort and people picked one by
 * one. Each person is added or refused on their own; the refused are listed with the reason.
 */
export default class CohortMembers extends LightningElement {
  helpReady = isHelpLoaded(HELP);

  @api recordId;

  labels = {
    title: TITLE,
    get membersEmpty() {
      return helpText('Programs', 'Programs_Cohort_MembersEmpty');
    },
    get dragHint() {
      return helpText('Programs', 'Programs_Cohort_DragHint');
    },
    remove: REMOVE,
    addPeople: ADD_PEOPLE,
    candidates: CANDIDATES,
    get noCandidates() {
      return helpText('Programs', 'Programs_Cohort_NoCandidates');
    },
    selectAll: SELECT_ALL,
    someoneElse: SOMEONE_ELSE,
    person: PERSON,
    addToList: ADD_TO_LIST,
    addToCohort: ADD_TO_COHORT,
    notAdded: NOT_ADDED,
    get moreThanShown() {
      return helpText('Programs', 'Programs_Cohort_MoreThanShown');
    },
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
  /** The last drag step, read out by the aria-live region. */
  announcement = '';
  /** c/barnDrag's state while a person is dragged: who, and whether over the member list. */
  dragState;
  drag;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    // DnD-4: drag a person (or everyone ticked, when the dragged one is ticked) from the
    // enrolled list onto the member list, by mouse, touch press and hold, or keyboard (Space,
    // Left Arrow to the member list, Space). Ticks, Select All and Add to Cohort stay.
    this.drag = createDragController({
      root: this.template,
      layout: 'columns',
      messages: dragMessages(),
      announce: (text) => {
        this.announcement = text;
      },
      onChange: (state) => {
        this.dragState = state;
      },
      canDrop: (itemId, fromZone, toZone) => toZone === MEMBERS_ZONE,
      onDrop: ({ itemId, toZone }) => {
        if (toZone !== MEMBERS_ZONE) {
          return false;
        }
        const group = this.ticked.includes(itemId) ? this.ticked : [itemId];
        return this.addChosen(group, []).then((ok) => {
          if (ok) {
            this.ticked = this.ticked.filter((id) => !group.includes(id));
          }
          return ok;
        });
      }
    });
    this.load();
  }

  disconnectedCallback() {
    if (this.drag) {
      this.drag.destroy();
    }
  }

  get dragHelp() {
    return dragInstructions();
  }

  get membersZoneClass() {
    const over =
      this.dragState && this.dragState.active && this.dragState.overZone === MEMBERS_ZONE;
    return over ? 'members-zone members-zone_over' : 'members-zone';
  }

  handlePointerDown(event) {
    this.drag.pointerDown(event);
  }

  handleDragKey(event) {
    this.drag.keyDown(event);
  }

  load() {
    this.loading = true;
    return getMembers({ cohortId: this.recordId })
      .then((data) => {
        this.data = data;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Cohort'));
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
    return this.chosen > max
      ? format(helpText('Programs', 'Programs_Cohort_TooMany'), max)
      : format(CHOSEN, this.chosen);
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
    return this.addChosen(this.ticked, this.picked).then((ok) => {
      if (ok) {
        this.ticked = [];
        this.picked = [];
      }
    });
  }

  /** Adds these ticked enrollments and picked people; resolves true when the server answered. */
  addChosen(ticked, picked) {
    const payload = addPayload(this.data && this.data.candidates, ticked, picked);
    this.clearMessages();
    this.busy = true;
    return addMembers({ cohortId: this.recordId, ...payload })
      .then((data) => {
        this.data = data;
        this.failures = (data.failures || []).map((one, index) => ({ ...one, key: String(index) }));
        this.resultMessage = addedMessage(data, {
          addedOne: helpText('Programs', 'Programs_Cohort_AddedOne'),
          addedMany: helpText('Programs', 'Programs_Cohort_AddedMany'),
          someFailed: helpText('Programs', 'Programs_Cohort_SomeFailed')
        });
        return true;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Cohort'));
        return false;
      })
      .finally(() => {
        this.busy = false;
      });
  }

  async handleRemove(event) {
    const enrollmentId = event.target.dataset.enrollment;
    const members = (this.data && this.data.members) || [];
    const member = members.find((candidate) => candidate.enrollmentId === enrollmentId);
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: helpText('Programs', 'Programs_Cohort_RemoveTitle'),
      message: helpText(
        'Programs',
        'Programs_Cohort_RemoveConfirm',
        member ? member.personName : ''
      ),
      confirmLabel: REMOVE,
      confirmVariant: 'destructive',
      cancelLabel: CANCEL
    });
    if (!confirmed) {
      return undefined;
    }
    this.clearMessages();
    this.busy = true;
    return removeMember({ cohortId: this.recordId, enrollmentId })
      .then((data) => {
        this.data = data;
        this.resultMessage = helpText('Programs', 'Programs_Cohort_Removed');
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Cohort'));
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
