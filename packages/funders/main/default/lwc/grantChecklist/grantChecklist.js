import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChecklist from '@salesforce/apex/GrantManagementController.getChecklist';
import addChecklistTasks from '@salesforce/apex/GrantManagementController.addChecklistTasks';
import setTaskDone from '@salesforce/apex/GrantManagementController.setTaskDone';
import { checklistProgress } from 'c/grantManagementModel';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/**
 * The Checklist card on a grant's page (F-10, canonical model R-GQ7): the grant's Task
 * requirements, ticked done here, and Add Checklist Tasks for the steps of its stage.
 */
export default class GrantChecklist extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded('Funders');
  icon = iconFor('Grant_Checklist_Item__c');
  card;
  errorMessage;
  isLoading = true;

  wiredCard;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Funders').then(() => {
        this.helpReady = true;
      });
    }
  }

  // Cached read (D-200 P11); each save below refreshes it with load().
  @wire(getChecklist, { grantId: '$recordId' })
  receiveChecklist(result) {
    this.wiredCard = result;
    const { data, error } = result;
    if (data) {
      this.card = data;
      this.errorMessage = undefined;
    } else if (error) {
      this.card = undefined;
      this.errorMessage = messageFrom(error, helpText('Funders', 'Funders_Manage_LoadFailed'));
    }
    if (data || error) {
      this.isLoading = false;
    }
  }

  load() {
    return refreshApex(this.wiredCard);
  }

  get t() {
    return this.helpReady
      ? {
          title: helpText('Funders', 'Funders_Checklist_Title'),
          empty: helpText('Funders', 'Funders_Checklist_Empty'),
          add: helpText('Funders', 'Funders_Checklist_Add'),
          due: helpText('Funders', 'Funders_Manage_Due')
        }
      : {};
  }

  get tasks() {
    const canEdit = Boolean(this.card && this.card.canEdit);
    return ((this.card && this.card.tasks) || []).map((task) => ({
      ...task,
      locked: !canEdit
    }));
  }

  get hasTasks() {
    return this.tasks.length > 0;
  }

  get canAdd() {
    return Boolean(this.card && this.card.canAdd);
  }

  get progress() {
    const { done, total } = checklistProgress(this.tasks);
    return total && this.helpReady
      ? helpText('Funders', 'Funders_Checklist_Progress', done, total)
      : '';
  }

  async handleDone(event) {
    const requirementId = event.target.dataset.id;
    const done = event.target.checked;
    try {
      await setTaskDone({ requirementId, done });
      await this.load();
    } catch (error) {
      event.target.checked = !done;
      this.toast(messageFrom(error, helpText('Funders', 'Funders_Shared_NotSaved')), 'error');
    }
  }

  async handleAdd() {
    try {
      const added = await addChecklistTasks({ grantId: this.recordId });
      this.toast(
        added
          ? helpText('Funders', 'Funders_Checklist_Added', added)
          : helpText('Funders', 'Funders_Checklist_NoneToAdd'),
        added ? 'success' : 'info'
      );
      await this.load();
    } catch (error) {
      this.toast(messageFrom(error, helpText('Funders', 'Funders_Shared_NotSaved')), 'error');
    }
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
