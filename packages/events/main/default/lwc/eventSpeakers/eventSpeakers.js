import { LightningElement, api } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSpeakers from '@salesforce/apex/EventSpeakersController.getSpeakers';
import addSpeaker from '@salesforce/apex/EventSpeakersController.addSpeaker';
import assign from '@salesforce/apex/EventSpeakersController.assign';
import removeSpeaker from '@salesforce/apex/EventSpeakersController.removeSpeaker';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import EventRecordModal from 'c/eventRecordModal';
import BarnConfirmModal from 'c/barnConfirmModal';

import SPEAKERS from '@salesforce/label/c.Events_EventTab_Speakers';
import ADD_SPEAKER from '@salesforce/label/c.Events_Speakers_AddSpeaker';
import ADD_TO_SESSION from '@salesforce/label/c.Events_Speakers_AddToSession';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';

const HELP_PACKAGES = ['Events', 'Core'];
const SPEAKER_FIELDS = [
  'Name',
  'Headline__c',
  'Status__c',
  'Bio__c',
  'Travel_Needs__c',
  'AV_Needs__c'
];
const STATUS_WORDS = {
  Invited: 'pending',
  Confirmed: 'active',
  Declined: 'closed',
  Cancelled: 'inactive'
};

/**
 * The Speakers tab of the event page (EV-05): the event's speakers, each a Core person picked
 * here, with their headline, status and the sessions they are in. Add to Session puts a speaker
 * in a session with a role; removing a speaker removes their assignments first (R-ESP3).
 */
export default class EventSpeakers extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  /** The speaker whose Add to Session form is open, with its choices. */
  assigning;

  labels = {
    speakers: SPEAKERS,
    addSpeaker: ADD_SPEAKER,
    addToSession: ADD_TO_SESSION,
    save: SAVE,
    cancel: CANCEL,
    actions: ACTIONS,
    get intro() {
      return helpText('Events', 'Events_Speakers_Intro');
    },
    get empty() {
      return helpText('Events', 'Events_Speakers_Empty');
    }
  };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.data = await getSpeakers({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Speakers_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get fieldLabels() {
    return (this.data && this.data.fieldLabels) || {};
  }

  get canAdd() {
    return Boolean(this.data && this.data.canAdd);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get rows() {
    const speakers = (this.data && this.data.speakers) || [];
    return speakers.map((speaker) => {
      const items = [{ label: EDIT, value: 'edit' }];
      if (this.data.canAssign && this.data.sessions.length) {
        items.push({ label: ADD_TO_SESSION, value: 'assign' });
      }
      items.push({ label: REMOVE, value: 'remove' });
      return {
        ...speaker,
        href: speaker.contactId ? `/lightning/r/${speaker.contactId}/view` : null,
        statusWord: STATUS_WORDS[speaker.status] || 'neutral',
        menuLabel: format(ACTIONS_FOR, speaker.name),
        menuItems: items,
        isAssigning: Boolean(this.assigning && this.assigning.speakerId === speaker.id),
        assignments: speaker.assignments.map((assignment) => ({
          ...assignment,
          text: `${assignment.sessionName} (${assignment.role})`,
          removeLabel: `${REMOVE}: ${assignment.sessionName}`
        }))
      };
    });
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && Boolean(this.data) && !this.hasRows;
  }

  get sessionOptions() {
    return (this.data && this.data.sessions) || [];
  }

  get roleOptions() {
    return (this.data && this.data.roles) || [];
  }

  get cannotAssign() {
    return this.busy || !this.assigning || !this.assigning.sessionId;
  }

  /** Picking a person adds them as a speaker at once, named after them (R-ESP2). */
  async handlePick(event) {
    const contactId = event.detail.recordId;
    if (!contactId) {
      return;
    }
    const picker = event.target;
    await this.run(async () => {
      await addSpeaker({ eventId: this.recordId, contactId });
      if (picker && typeof picker.clearSelection === 'function') {
        picker.clearSelection();
      }
    });
  }

  handleMenu(event) {
    const speaker = this.rows.find((row) => row.id === event.target.dataset.id);
    if (!speaker) {
      return;
    }
    const value = event.detail.value;
    if (value === 'assign') {
      this.assigning = {
        speakerId: speaker.id,
        sessionId: null,
        role: this.roleOptions.length ? this.roleOptions[0].value : null
      };
    } else if (value === 'remove') {
      this.confirmRemove(speaker);
    } else {
      this.edit(speaker);
    }
  }

  handleSession(event) {
    this.assigning = { ...this.assigning, sessionId: event.detail.value };
  }

  handleRole(event) {
    this.assigning = { ...this.assigning, role: event.detail.value };
  }

  handleAssignCancel() {
    this.assigning = undefined;
  }

  async handleAssignSave() {
    const { speakerId, sessionId, role } = this.assigning;
    await this.run(async () => {
      await assign({ sessionId, speakerId, role });
      this.assigning = undefined;
    });
  }

  async handleUnassign(event) {
    const assignmentId = event.currentTarget.dataset.id;
    await this.run(() => deleteRecord(assignmentId));
  }

  async edit(speaker) {
    const saved = await EventRecordModal.open({
      label: `${EDIT}: ${speaker.name}`,
      size: 'small',
      objectApiName: 'Event_Speaker__c',
      recordId: speaker.id,
      fields: SPEAKER_FIELDS
    });
    if (saved) {
      await this.load();
    }
  }

  async confirmRemove(speaker) {
    const confirmed = await BarnConfirmModal.open({
      label: `${REMOVE}: ${speaker.name}`,
      message: helpText('Events', 'Events_Speakers_RemoveConfirm', speaker.name),
      confirmLabel: REMOVE,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      size: 'small'
    });
    if (confirmed) {
      await this.run(() => removeSpeaker({ speakerId: speaker.id }));
    }
  }

  /** Runs a change, then reloads; a refusal shows in a toast in plain words. */
  async run(change) {
    this.busy = true;
    try {
      await change();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')),
          variant: 'error'
        })
      );
    } finally {
      this.busy = false;
    }
    await this.load();
  }
}
