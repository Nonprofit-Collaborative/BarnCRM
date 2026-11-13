import { LightningElement, api } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSponsors from '@salesforce/apex/EventSponsorsController.getSponsors';
import addSponsor from '@salesforce/apex/EventSponsorsController.addSponsor';
import addDeliverable from '@salesforce/apex/EventSponsorsController.addDeliverable';
import setDeliverableStatus from '@salesforce/apex/EventSponsorsController.setDeliverableStatus';
import removeSponsor from '@salesforce/apex/EventSponsorsController.removeSponsor';
import getLeads from '@salesforce/apex/EventSponsorsController.getLeads';
import { downloadCsv, format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import EventRecordModal from 'c/eventRecordModal';
import LEVEL from '@salesforce/schema/Sponsorship_Level__c';
import BarnConfirmModal from 'c/barnConfirmModal';
import { committedTotal, linkedText, progressText, sponsorWord } from 'c/eventSponsorsModel';

import TAB from '@salesforce/label/c.Events_EventTab_Sponsors';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';

const HELP_PACKAGES = ['Events'];
const LEVEL_FIELDS = ['Name', 'Amount__c', 'Sort_Order__c', 'Benefits__c', 'Deliverables__c'];
const SPONSOR_FIELDS = [
  'Name',
  'Status__c',
  'Level__c',
  'Amount__c',
  'Contact__c',
  'Booth__c',
  'Linked_Record_Id__c',
  'Notes__c'
];

function money(value) {
  if (value === null || value === undefined || value === '') {
    return '';
  }
  return Number(value).toLocaleString(undefined, { maximumFractionDigits: 2 });
}

/**
 * The Sponsors tab of the event page (EV-09): the event's sponsorship levels, its sponsors (Core
 * accounts picked here, at a level) with status and amount, and each sponsor's deliverables
 * checklist (logo, booth, passes). A sponsor added at a level starts with the level's amount and
 * checklist. A linked Giving gift or commitment, or Funders award, shows by name when it can be
 * read, and is blank when that module is not installed.
 */
export default class EventSponsors extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  /** The level a new sponsor is added at, or empty for none. */
  newLevelId = '';
  /** The sponsor whose Add Deliverable form is open, with its name and type. */
  adding;

  labels = {
    tab: TAB,
    edit: EDIT,
    remove: REMOVE,
    save: SAVE,
    cancel: CANCEL,
    actions: ACTIONS,
    get intro() {
      return helpText('Events', 'Events_Sponsors_Intro');
    },
    get empty() {
      return helpText('Events', 'Events_Sponsors_Empty');
    },
    get levelsEmpty() {
      return helpText('Events', 'Events_Sponsors_LevelsEmpty');
    },
    get levelsEmptyHeading() {
      return helpText('Events', 'Events_Sponsors_LevelsEmptyHeading');
    },
    get emptyHeading() {
      return helpText('Events', 'Events_Sponsors_EmptyHeading');
    },
    get addSponsor() {
      return helpText('Events', 'Events_Sponsors_AddSponsor');
    },
    get addLevel() {
      return helpText('Events', 'Events_Sponsors_AddLevel');
    },
    get sponsorsHeading() {
      return helpText('Events', 'Events_Sponsors_Heading');
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
      this.data = await getSponsors({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Sponsors_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get hasData() {
    return Boolean(this.data);
  }

  get fieldLabels() {
    return (this.data && this.data.fieldLabels) || {};
  }

  get canAddLevel() {
    return Boolean(this.data && this.data.canAddLevel);
  }

  get canAddSponsor() {
    return Boolean(this.data && this.data.canAddSponsor);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get deliverableStatuses() {
    return (this.data && this.data.deliverableStatuses) || [];
  }

  get deliverableTypes() {
    return (this.data && this.data.deliverableTypes) || [];
  }

  get levelOptions() {
    const levels = (this.data && this.data.levels) || [];
    return [
      { label: helpText('Events', 'Events_Sponsors_NoLevel'), value: '' },
      ...levels.map((level) => ({ label: level.name, value: level.id }))
    ];
  }

  get levelRows() {
    const levels = (this.data && this.data.levels) || [];
    return levels.map((level) => ({
      ...level,
      amountText: money(level.amount),
      menuLabel: format(ACTIONS_FOR, level.name)
    }));
  }

  get hasLevels() {
    return this.levelRows.length > 0;
  }

  get noLevels() {
    return this.hasData && !this.hasLevels;
  }

  get totalsText() {
    const sponsors = (this.data && this.data.sponsors) || [];
    return helpText('Events', 'Events_Sponsors_Totals', money(committedTotal(sponsors)) || '0');
  }

  get sponsorRows() {
    const sponsors = (this.data && this.data.sponsors) || [];
    return sponsors.map((sponsor) => {
      const items = [];
      if (this.data.canEdit) {
        items.push({ value: 'edit', label: EDIT });
        items.push({
          value: 'deliverable',
          label: helpText('Events', 'Events_Sponsors_AddDeliverable')
        });
      }
      items.push({ value: 'leads', label: helpText('Events', 'Events_Sponsors_DownloadLeads') });
      items.push({ value: 'remove', label: REMOVE });
      return {
        ...sponsor,
        href: sponsor.accountId ? `/lightning/r/${sponsor.accountId}/view` : null,
        statusWord: sponsorWord(sponsor.status),
        amountText: money(sponsor.amount),
        progress: progressText(sponsor.deliverables),
        linkedText: linkedText(sponsor),
        menuLabel: format(ACTIONS_FOR, sponsor.name),
        menuItems: items,
        hasDeliverables: sponsor.deliverables.length > 0,
        isAdding: Boolean(this.adding && this.adding.sponsorId === sponsor.id),
        deliverables: sponsor.deliverables.map((item) => ({
          ...item,
          text: [item.name, item.type, item.quantity ? `x ${item.quantity}` : null, item.dueDate]
            .filter(Boolean)
            .join(', '),
          removeLabel: `${REMOVE}: ${item.name}`
        }))
      };
    });
  }

  get hasSponsors() {
    return this.sponsorRows.length > 0;
  }

  get noSponsors() {
    return this.hasData && !this.hasSponsors;
  }

  get cannotSaveDeliverable() {
    return this.busy || !this.adding || !this.adding.name || !this.adding.name.trim();
  }

  handleLevelChoice(event) {
    this.newLevelId = event.detail.value;
  }

  /** Picking an organization adds it as a sponsor at the chosen level at once. */
  async handlePick(event) {
    const accountId = event.detail.recordId;
    if (!accountId) {
      return;
    }
    const picker = event.target;
    await this.run(async () => {
      await addSponsor({
        eventId: this.recordId,
        accountId,
        levelId: this.newLevelId || null
      });
      if (picker && typeof picker.clearSelection === 'function') {
        picker.clearSelection();
      }
    });
  }

  async handleAddLevel() {
    const saved = await EventRecordModal.open({
      label: helpText('Events', 'Events_Sponsors_AddLevel'),
      size: 'small',
      objectApiName: LEVEL.objectApiName,
      fields: LEVEL_FIELDS,
      defaults: { Event__c: this.recordId }
    });
    if (saved) {
      await this.load();
    }
  }

  handleMenu(event) {
    const id = event.target.dataset.id;
    const value = event.detail.value;
    if (event.target.dataset.kind === 'level') {
      const level = this.levelRows.find((row) => row.id === id);
      if (level) {
        this.handleLevel(level, value);
      }
      return;
    }
    const sponsor = this.sponsorRows.find((row) => row.id === id);
    if (!sponsor) {
      return;
    }
    if (value === 'deliverable') {
      this.adding = {
        sponsorId: sponsor.id,
        name: '',
        type: this.deliverableTypes.length ? this.deliverableTypes[0].value : null
      };
    } else if (value === 'remove') {
      this.confirmRemoveSponsor(sponsor);
    } else if (value === 'leads') {
      this.downloadLeads(sponsor);
    } else {
      this.editRecord('Sponsor__c', sponsor);
    }
  }

  handleLevel(level, value) {
    if (value === 'edit') {
      this.editRecord('Level__c', level);
    } else {
      this.confirmRemoveLevel(level);
    }
  }

  handleDeliverableName(event) {
    this.adding = { ...this.adding, name: event.detail.value };
  }

  handleDeliverableType(event) {
    this.adding = { ...this.adding, type: event.detail.value };
  }

  handleDeliverableCancel() {
    this.adding = undefined;
  }

  async handleDeliverableSave() {
    const { sponsorId, name, type } = this.adding;
    await this.run(async () => {
      await addDeliverable({ sponsorId, name, type });
      this.adding = undefined;
    });
  }

  async handleDeliverableStatus(event) {
    const deliverableId = event.target.dataset.id;
    const status = event.detail.value;
    await this.run(() => setDeliverableStatus({ deliverableId, status }));
  }

  async handleDeliverableRemove(event) {
    const deliverableId = event.currentTarget.dataset.id;
    await this.run(() => deleteRecord(deliverableId));
  }

  async editRecord(kind, row) {
    const isLevel = kind === 'Level__c';
    const saved = await EventRecordModal.open({
      label: `${EDIT}: ${row.name}`,
      size: 'small',
      objectApiName: isLevel ? 'Sponsorship_Level__c' : 'Event_Sponsor__c',
      recordId: row.id,
      fields: isLevel ? LEVEL_FIELDS : SPONSOR_FIELDS
    });
    if (saved) {
      await this.load();
    }
  }

  /** EV-28: the sponsor's leads as a CSV file, only attendees who shared their details. */
  async downloadLeads(sponsor) {
    try {
      const leads = await getLeads({ sponsorId: sponsor.id });
      if (!leads.rows.length) {
        this.dispatchEvent(
          new ShowToastEvent({
            message: helpText('Events', 'Events_Sponsors_NoLeads', sponsor.name),
            variant: 'info'
          })
        );
        return;
      }
      downloadCsv(`${sponsor.name} leads`, leads.columns, leads.rows);
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Events', 'Events_Sponsors_LoadFailed')),
          variant: 'error'
        })
      );
    }
  }

  async confirmRemoveSponsor(sponsor) {
    const confirmed = await BarnConfirmModal.open({
      label: `${REMOVE}: ${sponsor.name}`,
      message: helpText('Events', 'Events_Sponsors_RemoveSponsorConfirm', sponsor.name),
      confirmLabel: REMOVE,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      size: 'small'
    });
    if (confirmed) {
      await this.run(() => removeSponsor({ sponsorId: sponsor.id }));
    }
  }

  async confirmRemoveLevel(level) {
    const confirmed = await BarnConfirmModal.open({
      label: `${REMOVE}: ${level.name}`,
      message: helpText('Events', 'Events_Sponsors_RemoveLevelConfirm', level.name),
      confirmLabel: REMOVE,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      size: 'small'
    });
    if (confirmed) {
      await this.run(() => deleteRecord(level.id));
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
