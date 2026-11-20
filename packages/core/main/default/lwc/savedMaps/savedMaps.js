import { LightningElement } from 'lwc';
import listMaps from '@salesforce/apex/MapController.listMaps';
import loadMap from '@salesforce/apex/MapController.loadMap';
import saveMap from '@salesforce/apex/MapController.saveMap';
import renameMap from '@salesforce/apex/MapController.renameMap';
import deleteMap from '@salesforce/apex/MapController.deleteMap';
import mapUsers from '@salesforce/apex/MapController.mapUsers';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import BarnConfirmModal from 'c/barnConfirmModal';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { format } from 'c/mapDocument';

function errorText(error) {
  return (error && error.body && error.body.message) || UNEXPECTED_ERROR;
}

/**
 * The Maps panel of Data Manager (MAP-03; admin guide mapper.md, section 4): every saved map
 * with Open, Rename and Delete, and New Map. Open and New Map show the Mapper (c/barnMapper)
 * with the map's name and Save Map. Before a change to a map is saved, the tools that link it
 * (Where Used, from the installed modules) are listed, and a save that reaches any asks first.
 * Save Map waits while a best guess is unchecked or the map has a problem.
 */
export default class SavedMaps extends LightningElement {
  helpReady = isHelpLoaded('Core');

  maps = [];
  loading = true;
  errorMessage;
  noticeMessage;
  busy = false;

  /** The map open in the Mapper: { recordId, name, value }; undefined on the list. */
  editing;
  draft;
  pendingGuesses = 0;
  problemCount = 0;
  users = [];

  renamingId;
  renameValue = '';

  get labels() {
    return {
      title: helpText('Core', 'Core_SavedMaps_Title'),
      intro: helpText('Core', 'Core_SavedMaps_Intro'),
      newMap: helpText('Core', 'Core_SavedMaps_New'),
      open: helpText('Core', 'Core_SavedMaps_Open'),
      rename: helpText('Core', 'Core_SavedMaps_Rename'),
      remove: helpText('Core', 'Core_SavedMaps_Delete'),
      save: helpText('Core', 'Core_SavedMaps_Save'),
      saveName: helpText('Core', 'Core_SavedMaps_SaveName'),
      cancel: CANCEL,
      name: helpText('Core', 'Core_SavedMaps_Name'),
      none: helpText('Core', 'Core_SavedMaps_None'),
      noneHint: helpText('Core', 'Core_SavedMaps_NoneHint'),
      nameColumn: helpText('Core', 'Core_SavedMaps_NameColumn'),
      fillsColumn: helpText('Core', 'Core_SavedMaps_FillsColumn'),
      actionsColumn: helpText('Core', 'Core_SavedMaps_ActionsColumn'),
      waiting: helpText('Core', 'Core_SavedMaps_Waiting')
    };
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.refresh();
  }

  async refresh() {
    this.loading = true;
    try {
      const maps = await listMaps();
      this.maps = (maps || []).map((entry) => ({
        ...entry,
        fills: entry.objectLabel || helpText('Core', 'Core_SavedMaps_FillsOther'),
        openLabel: format(helpText('Core', 'Core_SavedMaps_OpenFor'), entry.name),
        renameLabel: format(helpText('Core', 'Core_SavedMaps_RenameFor'), entry.name),
        deleteLabel: format(helpText('Core', 'Core_SavedMaps_DeleteFor'), entry.name),
        isRenaming: entry.recordId === this.renamingId
      }));
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = errorText(error);
    } finally {
      this.loading = false;
    }
  }

  get hasMaps() {
    return this.maps.length > 0;
  }

  get rows() {
    return this.maps.map((entry) => ({ ...entry, isRenaming: entry.recordId === this.renamingId }));
  }

  // ---- the list -------------------------------------------------------------------------------

  handleNew() {
    this.noticeMessage = undefined;
    this.editing = { recordId: null, name: '', value: { version: 4 } };
    this.draft = undefined;
    this.users = [];
  }

  async handleOpen(event) {
    const recordId = event.currentTarget.dataset.recordId;
    this.noticeMessage = undefined;
    this.busy = true;
    try {
      const saved = await loadMap({ recordId });
      this.editing = { recordId: saved.recordId, name: saved.name, value: saved.definitionJson };
      this.draft = undefined;
      this.users = (await mapUsers({ recordId })) || [];
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = errorText(error);
    } finally {
      this.busy = false;
    }
  }

  handleRenameStart(event) {
    this.renamingId = event.currentTarget.dataset.recordId;
    const found = this.maps.find((entry) => entry.recordId === this.renamingId);
    this.renameValue = found ? found.name : '';
  }

  handleRenameInput(event) {
    this.renameValue = event.detail.value;
  }

  handleRenameCancel() {
    this.renamingId = undefined;
  }

  async handleRenameSave() {
    this.busy = true;
    try {
      await renameMap({ recordId: this.renamingId, name: this.renameValue });
      this.renamingId = undefined;
      this.errorMessage = undefined;
      await this.refresh();
    } catch (error) {
      this.errorMessage = errorText(error);
    } finally {
      this.busy = false;
    }
  }

  async handleDelete(event) {
    const recordId = event.currentTarget.dataset.recordId;
    const found = this.maps.find((entry) => entry.recordId === recordId);
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: helpText('Core', 'Core_SavedMaps_Delete'),
      message: format(helpText('Core', 'Core_SavedMaps_DeleteConfirm'), found ? found.name : ''),
      confirmLabel: helpText('Core', 'Core_SavedMaps_Delete'),
      cancelLabel: CANCEL,
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return;
    }
    this.busy = true;
    try {
      await deleteMap({ recordId });
      this.errorMessage = undefined;
      await this.refresh();
    } catch (error) {
      this.errorMessage = errorText(error);
    } finally {
      this.busy = false;
    }
  }

  // ---- the Mapper ------------------------------------------------------------------------------

  get isEditing() {
    return Boolean(this.editing);
  }

  handleName(event) {
    this.editing = { ...this.editing, name: event.detail.value };
  }

  handleMapChange(event) {
    this.draft = event.detail.document;
    this.pendingGuesses = event.detail.pendingGuesses;
    this.problemCount = event.detail.problems;
  }

  get hasUsers() {
    return this.users.length > 0;
  }

  get usersText() {
    return format(helpText('Core', 'Core_SavedMaps_UsedBy'), this.users.length);
  }

  get userLines() {
    return this.users.map((user, index) => ({
      key: `user-${index}`,
      text: format(helpText('Core', 'Core_SavedMaps_UserLine'), user.kindLabel, user.name)
    }));
  }

  get saveBlocked() {
    return (
      this.busy ||
      this.pendingGuesses > 0 ||
      this.problemCount > 0 ||
      !this.editing ||
      !String(this.editing.name || '').trim()
    );
  }

  get blockedText() {
    return this.pendingGuesses > 0 ? this.labels.waiting : '';
  }

  async handleSave() {
    const mapper = this.template.querySelector('c-barn-mapper');
    const definitionJson = this.draft || (mapper ? mapper.value : null);
    if (this.editing.recordId && this.users.length > 0) {
      const confirmed = await BarnConfirmModal.open({
        size: 'small',
        label: this.labels.save,
        message: format(helpText('Core', 'Core_SavedMaps_SaveConfirm'), this.users.length),
        confirmLabel: this.labels.save,
        cancelLabel: CANCEL
      });
      if (!confirmed) {
        return;
      }
    }
    this.busy = true;
    try {
      const saved = await saveMap({
        recordId: this.editing.recordId,
        name: this.editing.name,
        definitionJson
      });
      this.noticeMessage = format(helpText('Core', 'Core_SavedMaps_Saved'), saved.name);
      this.errorMessage = undefined;
      this.editing = undefined;
      await this.refresh();
    } catch (error) {
      this.errorMessage = errorText(error);
    } finally {
      this.busy = false;
    }
  }

  handleCancel() {
    this.editing = undefined;
    this.errorMessage = undefined;
  }
}
