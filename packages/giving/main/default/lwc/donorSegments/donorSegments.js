/**
 * The Donor Segments page (feature G-28, admin guide donor-segments.md, canonical model
 * Section 25O).
 *
 * A segment is a saved Find query of people or organizations. The page saves starter templates
 * as segments, counts and lists a segment, exports it as CSV laid out for Mailchimp, Constant
 * Contact or with all its columns, and opens it in Find to change it. Every read is the
 * server's, in the person's own access; the CSV is written here with Find's writer (`findCsv`)
 * and the email layouts come from the framework-free `donorSegmentExport`.
 */
import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPage from '@salesforce/apex/DonorSegmentController.getPage';
import saveFromTemplate from '@salesforce/apex/DonorSegmentController.saveFromTemplate';
import countSegment from '@salesforce/apex/DonorSegmentController.countSegment';
import listSegment from '@salesforce/apex/DonorSegmentController.listSegment';
import exportPage from '@salesforce/apex/DonorSegmentController.exportPage';
import { toCsv, fileName, format, messageFrom } from 'c/findCsv';
import {
  MAILCHIMP,
  CONSTANT_CONTACT,
  ALL_COLUMNS,
  isEmailLayout,
  columnsFor,
  createCollector
} from 'c/donorSegmentExport';

import TITLE from '@salesforce/label/c.Giving_Segments_Title';
import INTRO from '@salesforce/label/c.Giving_Segments_Intro';
import TEMPLATES_HEADING from '@salesforce/label/c.Giving_Segments_TemplatesHeading';
import TEMPLATE_FIELD from '@salesforce/label/c.Giving_Segments_TemplateField';
import RECORDS_FIELD from '@salesforce/label/c.Giving_Segments_RecordsField';
import PEOPLE from '@salesforce/label/c.Giving_Segments_People';
import ORGANIZATIONS from '@salesforce/label/c.Giving_Segments_Organizations';
import NAME_FIELD from '@salesforce/label/c.Giving_Segments_NameField';
import SAVE_AS_SEGMENT from '@salesforce/label/c.Giving_Segments_SaveAsSegment';
import SAVED from '@salesforce/label/c.Giving_Segments_Saved';
import SEGMENTS_HEADING from '@salesforce/label/c.Giving_Segments_SegmentsHeading';
import SEGMENT_FIELD from '@salesforce/label/c.Giving_Segments_SegmentField';
import EMPTY from '@salesforce/label/c.Giving_Segments_Empty';
import OPTION_MINE from '@salesforce/label/c.Giving_Segments_OptionMine';
import OPTION_SHARED from '@salesforce/label/c.Giving_Segments_OptionShared';
import COUNT from '@salesforce/label/c.Giving_Segments_Count';
import COUNT_MORE from '@salesforce/label/c.Giving_Segments_CountMore';
import SHOW_LIST from '@salesforce/label/c.Giving_Segments_ShowList';
import LIST_SHOWN from '@salesforce/label/c.Giving_Segments_ListShown';
import LAYOUT_FIELD from '@salesforce/label/c.Giving_Segments_LayoutField';
import LAYOUT_MAILCHIMP from '@salesforce/label/c.Giving_Segments_LayoutMailchimp';
import LAYOUT_CONSTANT_CONTACT from '@salesforce/label/c.Giving_Segments_LayoutConstantContact';
import LAYOUT_ALL from '@salesforce/label/c.Giving_Segments_LayoutAll';
import EXPORT from '@salesforce/label/c.Giving_Segments_Export';
import EXPORTING from '@salesforce/label/c.Giving_Segments_Exporting';
import EXPORTED from '@salesforce/label/c.Giving_Segments_Exported';
import EXPORTED_DUPLICATES from '@salesforce/label/c.Giving_Segments_ExportedDuplicates';
import LIMIT_REACHED from '@salesforce/label/c.Giving_Segments_LimitReached';
import EDIT_IN_FIND from '@salesforce/label/c.Giving_Segments_EditInFind';
import EMAIL_PEOPLE_ONLY from '@salesforce/label/c.Giving_Segments_EmailPeopleOnly';

const PEOPLE_OBJECT = 'Contact';
const ORGANIZATIONS_OBJECT = 'Account';

export default class DonorSegments extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    intro: INTRO,
    templatesHeading: TEMPLATES_HEADING,
    templateField: TEMPLATE_FIELD,
    recordsField: RECORDS_FIELD,
    nameField: NAME_FIELD,
    saveAsSegment: SAVE_AS_SEGMENT,
    segmentsHeading: SEGMENTS_HEADING,
    segmentField: SEGMENT_FIELD,
    empty: EMPTY,
    showList: SHOW_LIST,
    layoutField: LAYOUT_FIELD,
    export: EXPORT,
    editInFind: EDIT_IN_FIND,
    emailPeopleOnly: EMAIL_PEOPLE_ONLY
  };

  loaded = false;
  busy = false;
  errorMessage;
  noticeMessage;

  templates = [];
  segments = [];
  exportLimit = 0;
  findTabApiName;
  stateKey;

  templateKey;
  objectName = PEOPLE_OBJECT;
  segmentName = '';

  segmentId;
  countText;
  listRows;
  listColumns;
  listText;
  layout = MAILCHIMP;

  connectedCallback() {
    this.load();
  }

  async load(selectId) {
    this.busy = true;
    try {
      this.applyPage(await getPage(), selectId);
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
      this.loaded = true;
    }
  }

  applyPage(page, selectId) {
    this.templates = page.templates || [];
    this.segments = page.segments || [];
    this.exportLimit = page.exportLimit;
    this.findTabApiName = page.findTabApiName;
    this.stateKey = page.stateKey;
    if (!this.templateKey && this.templates.length) {
      this.templateKey = this.templates[0].key;
      this.segmentName = this.defaultName();
    }
    const wanted = selectId || this.segmentId;
    if (wanted && this.segments.some((segment) => segment.recordId === wanted)) {
      this.selectSegment(wanted);
    }
  }

  // -----------------------------------------------------------------------------------------
  // Templates
  // -----------------------------------------------------------------------------------------

  get templateOptions() {
    return this.templates.map((template) => ({ label: template.label, value: template.key }));
  }

  get selectedTemplate() {
    return this.templates.find((template) => template.key === this.templateKey);
  }

  get templateDescription() {
    return this.selectedTemplate ? this.selectedTemplate.description : '';
  }

  get objectOptions() {
    const template = this.selectedTemplate;
    const options = [];
    if (!template || template.forPeople) {
      options.push({ label: PEOPLE, value: PEOPLE_OBJECT });
    }
    if (!template || template.forOrganizations) {
      options.push({ label: ORGANIZATIONS, value: ORGANIZATIONS_OBJECT });
    }
    return options;
  }

  get saveDisabled() {
    return this.busy || !this.templateKey || !this.segmentName || !this.segmentName.trim();
  }

  defaultName() {
    const template = this.selectedTemplate;
    if (!template) {
      return '';
    }
    const kind = this.objectName === ORGANIZATIONS_OBJECT ? ORGANIZATIONS : PEOPLE;
    return format(OPTION_MINE, template.label, kind);
  }

  handleTemplateChange(event) {
    const keepName = this.segmentName !== this.defaultName();
    this.templateKey = event.detail.value;
    if (!keepName) {
      this.segmentName = this.defaultName();
    }
  }

  handleObjectChange(event) {
    const keepName = this.segmentName !== this.defaultName();
    this.objectName = event.detail.value;
    if (!keepName) {
      this.segmentName = this.defaultName();
    }
  }

  handleNameChange(event) {
    this.segmentName = event.detail.value;
  }

  async handleSave() {
    this.clearMessages();
    this.busy = true;
    try {
      const page = await saveFromTemplate({
        templateKey: this.templateKey,
        objectName: this.objectName,
        name: this.segmentName
      });
      this.noticeMessage = format(SAVED, this.segmentName.trim());
      this.segmentId = undefined;
      this.applyPage(page, page.savedId);
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  // -----------------------------------------------------------------------------------------
  // Segments
  // -----------------------------------------------------------------------------------------

  get hasSegments() {
    return this.segments.length > 0;
  }

  get showEmpty() {
    return this.loaded && !this.hasSegments;
  }

  get segmentOptions() {
    return this.segments.map((segment) => {
      const kind = segment.people ? PEOPLE : ORGANIZATIONS;
      return {
        label: segment.mine
          ? format(OPTION_MINE, segment.name, kind)
          : format(OPTION_SHARED, segment.name, kind, segment.ownerName || ''),
        value: segment.recordId
      };
    });
  }

  get selectedSegment() {
    return this.segments.find((segment) => segment.recordId === this.segmentId);
  }

  get hasSelection() {
    return Boolean(this.selectedSegment);
  }

  get layoutOptions() {
    const options = [{ label: LAYOUT_ALL, value: ALL_COLUMNS }];
    if (this.selectedSegment && this.selectedSegment.people) {
      options.unshift(
        { label: LAYOUT_MAILCHIMP, value: MAILCHIMP },
        { label: LAYOUT_CONSTANT_CONTACT, value: CONSTANT_CONTACT }
      );
    }
    return options;
  }

  get showPeopleOnlyNote() {
    return this.hasSelection && !this.selectedSegment.people;
  }

  get hasList() {
    return Array.isArray(this.listRows);
  }

  handleSegmentChange(event) {
    this.clearMessages();
    this.selectSegment(event.detail.value);
  }

  selectSegment(segmentId) {
    this.segmentId = segmentId;
    this.countText = undefined;
    this.listRows = undefined;
    this.listColumns = undefined;
    this.listText = undefined;
    const segment = this.selectedSegment;
    this.layout = segment && segment.people ? MAILCHIMP : ALL_COLUMNS;
    this.count();
  }

  async count() {
    const segmentId = this.segmentId;
    try {
      const result = await countSegment({ segmentId });
      if (segmentId === this.segmentId) {
        this.countText = format(
          result.more ? COUNT_MORE : COUNT,
          Number(result.count).toLocaleString()
        );
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  async handleShowList() {
    this.clearMessages();
    this.busy = true;
    try {
      const result = await listSegment({ segmentId: this.segmentId });
      this.listColumns = result.columns.map((column) => ({
        label: column.label,
        fieldName: column.path,
        type: 'text',
        wrapText: false
      }));
      this.listRows = result.rows.map((row) => {
        const shown = { Id: row.Id };
        for (const column of result.columns) {
          const value = row[column.path];
          shown[column.path] = value === undefined || value === null ? '' : String(value);
        }
        return shown;
      });
      this.listText = format(LIST_SHOWN, this.listRows.length);
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  handleLayoutChange(event) {
    this.layout = event.detail.value;
  }

  /**
   * Reads the segment page by page until the server says it is done or the export row limit
   * is reached, then writes one CSV file. The limit is a convenience here, as in Find (R-SQ3).
   */
  async handleExport() {
    this.clearMessages();
    this.busy = true;
    const segment = this.selectedSegment;
    const layout = this.layout;
    const collector = createCollector(layout, segment.name);
    const rows = [];
    let read = 0;
    let afterId = null;
    let columns;
    let limited = false;
    try {
      for (;;) {
        // eslint-disable-next-line no-await-in-loop
        const page = await exportPage({ segmentId: segment.recordId, layout, afterId });
        columns = columns || columnsFor(layout, page.columns);
        read += page.rows.length;
        rows.push(...collector.add(page.rows));
        this.noticeMessage = format(EXPORTING, read.toLocaleString());
        afterId = page.lastId;
        if (rows.length >= this.exportLimit) {
          limited = !page.done || rows.length > this.exportLimit;
          rows.length = Math.min(rows.length, this.exportLimit);
          break;
        }
        if (page.done) {
          break;
        }
      }
      const csv = toCsv(columns, rows);
      this.download(
        new Blob([csv], { type: 'text/csv;charset=utf-8' }),
        fileName(`${segment.name}-${layout}`)
      );
      const done = collector.duplicates
        ? format(EXPORTED_DUPLICATES, rows.length.toLocaleString(), collector.duplicates)
        : format(EXPORTED, rows.length.toLocaleString());
      this.noticeMessage = limited
        ? `${done} ${format(LIMIT_REACHED, Number(this.exportLimit).toLocaleString())}`
        : done;
    } catch (error) {
      this.noticeMessage = undefined;
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  download(blob, name) {
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = name;
    link.click();
    URL.revokeObjectURL(link.href);
  }

  handleEditInFind() {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: this.findTabApiName },
      state: { [this.stateKey]: this.segmentId }
    });
  }

  get exportDisabled() {
    return this.busy || !this.hasSelection;
  }

  get emailLayoutChosen() {
    return isEmailLayout(this.layout);
  }

  clearMessages() {
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
  }
}
