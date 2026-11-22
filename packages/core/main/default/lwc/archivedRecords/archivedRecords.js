import { LightningElement } from 'lwc';
import getArchive from '@salesforce/apex/ArchiveController.getArchive';
import getArchivedRows from '@salesforce/apex/ArchiveController.getArchivedRows';
import getArchivedRow from '@salesforce/apex/ArchiveController.getArchivedRow';
import restoreArchivedRows from '@salesforce/apex/ArchiveController.restoreArchivedRows';
import BarnConfirmModal from 'c/barnConfirmModal';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { format, messageFrom } from 'c/findCsv';

/**
 * The Archived Records panel on Data Manager (D-221, canonical model Section 29D1, R-ARC1, R-ARC4,
 * admin guide archive-rules.md): pick an archived object and a date range (the big object's index
 * order: an object, then newest first), page through its rows, view a row's fields from its JSON,
 * and restore the rows chosen. A viewer sees every field the archiving person could read, which the
 * panel says. Restored records get new Ids; the restore's log keeps old and new.
 */
export default class ArchivedRecords extends LightningElement {
  helpReady = isHelpLoaded('Core');
  viewer;
  loading = true;
  busy = false;
  errorMessage;
  noticeMessage;
  objectName;
  fromDay;
  toDay;
  rows = [];
  more = false;
  /** The row each shown page started after; the last entry is the current page's. */
  pageStarts = [];
  selectedIds = [];
  detail;

  get labels() {
    return {
      title: helpText('Core', 'Core_ArchiveViewer_Title'),
      intro: helpText('Core', 'Core_ArchiveViewer_Intro'),
      everyField: helpText('Core', 'Core_ArchiveViewer_EveryField'),
      object: helpText('Core', 'Core_ArchiveViewer_Object'),
      fromDay: helpText('Core', 'Core_ArchiveViewer_From'),
      toDay: helpText('Core', 'Core_ArchiveViewer_To'),
      show: helpText('Core', 'Core_ArchiveViewer_Show'),
      noObjects: helpText('Core', 'Core_ArchiveViewer_NoObjects'),
      noRows: helpText('Core', 'Core_ArchiveViewer_NoRows'),
      rowsHeading: helpText('Core', 'Core_ArchiveViewer_RowsHeading'),
      next: helpText('Core', 'Core_ArchiveViewer_Next'),
      previous: helpText('Core', 'Core_ArchiveViewer_Previous'),
      restore: helpText('Core', 'Core_ArchiveViewer_Restore'),
      restoreNote: helpText('Core', 'Core_ArchiveViewer_RestoreNote'),
      fieldsHeading: helpText('Core', 'Core_ArchiveViewer_FieldsHeading'),
      relatedHeading: helpText('Core', 'Core_ArchiveViewer_RelatedHeading'),
      close: helpText('Core', 'Core_ArchiveViewer_Close'),
      cancel: helpText('Core', 'Core_ArchiveRules_Cancel')
    };
  }

  get columns() {
    return [
      { label: helpText('Core', 'Core_ArchiveViewer_ColumnName'), fieldName: 'name' },
      { label: helpText('Core', 'Core_ArchiveViewer_ColumnOriginalId'), fieldName: 'originalId' },
      {
        label: helpText('Core', 'Core_ArchiveViewer_ColumnArchivedAt'),
        fieldName: 'archivedAt',
        type: 'date',
        typeAttributes: {
          year: 'numeric',
          month: 'short',
          day: 'numeric',
          hour: '2-digit',
          minute: '2-digit'
        }
      },
      { label: helpText('Core', 'Core_ArchiveViewer_ColumnRule'), fieldName: 'ruleName' },
      { label: helpText('Core', 'Core_ArchiveViewer_ColumnArchivedBy'), fieldName: 'archivedBy' },
      {
        type: 'button',
        initialWidth: 120,
        typeAttributes: {
          label: helpText('Core', 'Core_ArchiveViewer_View'),
          name: 'view',
          variant: 'base'
        }
      }
    ];
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.viewer = await getArchive();
      if (this.hasObjects && !this.objectName) {
        this.objectName = this.viewer.objects[0].name;
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  get hasObjects() {
    return Boolean(this.viewer && this.viewer.objects && this.viewer.objects.length);
  }

  get objectOptions() {
    return ((this.viewer && this.viewer.objects) || []).map((one) => ({
      label: one.label === one.name ? one.name : `${one.label} (${one.name})`,
      value: one.name
    }));
  }

  get usageText() {
    const count = (this.viewer && this.viewer.archivedCount) || 0;
    const cap = (this.viewer && this.viewer.cap) || 0;
    return format(
      helpText('Core', 'Core_ArchiveRules_UsageText'),
      count.toLocaleString(),
      cap.toLocaleString()
    );
  }

  get canRestore() {
    return Boolean(this.viewer && this.viewer.canRestore);
  }

  get hideCheckbox() {
    return !this.canRestore;
  }

  get mostRestored() {
    return (this.viewer && this.viewer.mostRestored) || 50;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showNoRows() {
    return this.shown && !this.hasRows;
  }

  shown = false;

  get hasPrevious() {
    return this.pageStarts.length > 1;
  }

  get nextDisabled() {
    return this.busy || !this.more;
  }

  get previousDisabled() {
    return this.busy || !this.hasPrevious;
  }

  get restoreDisabled() {
    return this.busy || this.selectedIds.length === 0;
  }

  get restoreLabel() {
    return this.selectedIds.length
      ? format(helpText('Core', 'Core_ArchiveViewer_RestoreCount'), this.selectedIds.length)
      : this.labels.restore;
  }

  handleObject(event) {
    this.objectName = event.detail.value;
  }

  handleFrom(event) {
    this.fromDay = event.target.value || undefined;
  }

  handleTo(event) {
    this.toDay = event.target.value || undefined;
  }

  handleShow() {
    this.pageStarts = [];
    this.readPage(null);
  }

  handleNext() {
    const last = this.rows[this.rows.length - 1];
    if (last) {
      this.readPage(last.id);
    }
  }

  handlePrevious() {
    this.pageStarts.pop();
    const start = this.pageStarts.pop();
    this.readPage(start === undefined ? null : start);
  }

  async readPage(afterRowId) {
    if (!this.objectName) {
      return;
    }
    this.busy = true;
    this.errorMessage = undefined;
    this.detail = undefined;
    try {
      const page = await getArchivedRows({
        objectName: this.objectName,
        fromDay: this.fromDay || null,
        toDay: this.toDay || null,
        afterRowId
      });
      this.rows = (page && page.rows) || [];
      this.more = Boolean(page && page.more);
      this.pageStarts = [...this.pageStarts, afterRowId];
      this.selectedIds = [];
      this.shown = true;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  handleSelection(event) {
    this.selectedIds = (event.detail.selectedRows || []).map((row) => row.id);
  }

  async handleRowAction(event) {
    const row = event.detail.row;
    this.busy = true;
    this.errorMessage = undefined;
    try {
      const found = await getArchivedRow({ objectName: this.objectName, rowId: row.id });
      this.detail = {
        ...found,
        heading: format(
          helpText('Core', 'Core_ArchiveViewer_DetailHeading'),
          found.name || row.name
        ),
        fields: (found.fields || []).map((field) => ({
          ...field,
          valueKey: `${field.name}-value`
        })),
        hasChildren: Boolean(found.children && found.children.length),
        children: (found.children || []).map((group) => ({
          ...group,
          text: format(
            helpText('Core', 'Core_ArchiveViewer_RelatedCount'),
            group.label,
            group.count
          )
        }))
      };
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  handleCloseDetail() {
    this.detail = undefined;
  }

  async handleRestore() {
    const count = this.selectedIds.length;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: this.restoreLabel,
      message: format(helpText('Core', 'Core_ArchiveViewer_RestoreConfirm'), count),
      confirmLabel: this.labels.restore,
      cancelLabel: this.labels.cancel
    });
    if (!confirmed) {
      return;
    }
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await restoreArchivedRows({ objectName: this.objectName, rowIds: this.selectedIds });
      this.noticeMessage = format(helpText('Core', 'Core_ArchiveViewer_RestoreStarted'), count);
      this.selectedIds = [];
      const table = this.template.querySelector('[data-id="rows"]');
      if (table) {
        table.selectedRows = [];
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }
}
