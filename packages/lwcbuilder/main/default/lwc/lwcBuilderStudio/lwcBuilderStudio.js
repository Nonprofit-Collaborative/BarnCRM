import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStudio from '@salesforce/apex/LwcBuilderController.getStudio';
import saveComponent from '@salesforce/apex/LwcBuilderController.saveComponent';
import { messageFrom, saveBlob } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  BLOCK_TYPES,
  LAYOUTS,
  addBlock,
  addRow,
  addSection,
  emptyDefinition,
  exportSource,
  keyFromName,
  layoutOf,
  locate,
  moveBlock,
  moveItem,
  normalize,
  nudgeBlock,
  parseFieldList,
  removeItem,
  setRowLayout,
  updateItem,
  validate
} from 'c/lwcBuilderModel';

const HELP_PACKAGES = ['LwcBuilder'];
const NEW = '';

function typeLabel(type) {
  switch (type) {
    case 'fields':
      return helpText('LwcBuilder', 'LwcBuilder_Type_Fields');
    case 'relatedList':
      return helpText('LwcBuilder', 'LwcBuilder_Type_RelatedList');
    case 'recordList':
      return helpText('LwcBuilder', 'LwcBuilder_Type_RecordList');
    case 'chart':
      return helpText('LwcBuilder', 'LwcBuilder_Type_Chart');
    case 'text':
      return helpText('LwcBuilder', 'LwcBuilder_Type_Text');
    case 'image':
      return helpText('LwcBuilder', 'LwcBuilder_Type_Image');
    default:
      return helpText('LwcBuilder', 'LwcBuilder_Type_Action');
  }
}

function layoutLabel(layout) {
  switch (layout) {
    case '6-6':
      return helpText('LwcBuilder', 'LwcBuilder_Layout_Halves');
    case '4-4-4':
      return helpText('LwcBuilder', 'LwcBuilder_Layout_Thirds');
    case '3-3-3-3':
      return helpText('LwcBuilder', 'LwcBuilder_Layout_Quarters');
    case '8-4':
      return helpText('LwcBuilder', 'LwcBuilder_Layout_WideLeft');
    case '4-8':
      return helpText('LwcBuilder', 'LwcBuilder_Layout_WideRight');
    default:
      return helpText('LwcBuilder', 'LwcBuilder_Layout_Full');
  }
}

function problemText(code) {
  switch (code) {
    case 'rowWidth':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_RowWidth');
    case 'fieldsNeeded':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_Fields');
    case 'objectNeeded':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_Object');
    case 'parentFieldNeeded':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_ParentField');
    case 'reportNeeded':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_Report');
    case 'imageUrl':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_ImageUrl');
    case 'imageAlt':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_ImageAlt');
    case 'labelNeeded':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_Label');
    case 'actionNeeded':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_Action');
    case 'ruleField':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_RuleField');
    case 'rulePermission':
      return helpText('LwcBuilder', 'LwcBuilder_Problem_RulePermission');
    default:
      return helpText('LwcBuilder', 'LwcBuilder_Problem_Other');
  }
}

/**
 * The LWC Builder page (LB-01, LB-05, LB-06; ADR-NEXT `NEXT-lwc-builder-module.md`): pick or
 * start a component, lay out sections, rows and columns on the grid, drag blocks in (or add and
 * move them with buttons), set each block's properties and visibility rule, preview it with a
 * record, save it, and export it as LWC source. The document logic is c/lwcBuilderModel's.
 */
export default class LwcBuilderStudio extends LightningElement {
  helpReady = isHelpLoaded(HELP_PACKAGES);
  components = [];
  sourceExport = true;
  canEdit = false;
  selectedId = NEW;
  details = this.blankDetails();
  definition = emptyDefinition();
  keyTouched = false;
  selectedBlockId;
  selectedColumnId;
  previewing = false;
  previewRecordId = '';
  exportFiles;
  dragging;
  problems = [];
  errorMessage;
  isSaving = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.refresh();
  }

  blankDetails() {
    return { id: '', name: '', key: '', description: '', objectName: '', active: true };
  }

  async refresh() {
    try {
      const studio = await getStudio();
      this.components = studio.components || [];
      this.sourceExport = studio.sourceExport !== false;
      this.canEdit = studio.canEdit === true;
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('LwcBuilder', 'LwcBuilder_Error_Generic'));
    }
  }

  get labels() {
    return {
      title: helpText('LwcBuilder', 'LwcBuilder_Studio_Title'),
      intro: helpText('LwcBuilder', 'LwcBuilder_Studio_Intro'),
      component: helpText('LwcBuilder', 'LwcBuilder_Studio_Component'),
      newComponent: helpText('LwcBuilder', 'LwcBuilder_Studio_New'),
      save: helpText('LwcBuilder', 'LwcBuilder_Studio_Save'),
      preview: helpText('LwcBuilder', 'LwcBuilder_Studio_Preview'),
      edit: helpText('LwcBuilder', 'LwcBuilder_Studio_Edit'),
      exportSource: helpText('LwcBuilder', 'LwcBuilder_Studio_Export'),
      name: helpText('LwcBuilder', 'LwcBuilder_Field_Name'),
      key: helpText('LwcBuilder', 'LwcBuilder_Field_Key'),
      keyHelp: helpText('LwcBuilder', 'LwcBuilder_Field_KeyHelp'),
      description: helpText('LwcBuilder', 'LwcBuilder_Field_Description'),
      objectName: helpText('LwcBuilder', 'LwcBuilder_Field_Object'),
      objectHelp: helpText('LwcBuilder', 'LwcBuilder_Field_ObjectHelp'),
      active: helpText('LwcBuilder', 'LwcBuilder_Field_Active'),
      blocks: helpText('LwcBuilder', 'LwcBuilder_Studio_Blocks'),
      blocksHelp: helpText('LwcBuilder', 'LwcBuilder_Studio_BlocksHelp'),
      addSection: helpText('LwcBuilder', 'LwcBuilder_Studio_AddSection'),
      addRow: helpText('LwcBuilder', 'LwcBuilder_Studio_AddRow'),
      sectionTitle: helpText('LwcBuilder', 'LwcBuilder_Studio_SectionTitle'),
      layout: helpText('LwcBuilder', 'LwcBuilder_Studio_Layout'),
      moveUp: helpText('LwcBuilder', 'LwcBuilder_Move_Up'),
      moveDown: helpText('LwcBuilder', 'LwcBuilder_Move_Down'),
      moveLeft: helpText('LwcBuilder', 'LwcBuilder_Move_Left'),
      moveRight: helpText('LwcBuilder', 'LwcBuilder_Move_Right'),
      remove: helpText('LwcBuilder', 'LwcBuilder_Studio_Remove'),
      dropHere: helpText('LwcBuilder', 'LwcBuilder_Studio_DropHere'),
      emptyCanvas: helpText('LwcBuilder', 'LwcBuilder_Studio_EmptyCanvas'),
      properties: helpText('LwcBuilder', 'LwcBuilder_Studio_Properties'),
      noSelection: helpText('LwcBuilder', 'LwcBuilder_Studio_NoSelection'),
      blockTitle: helpText('LwcBuilder', 'LwcBuilder_Prop_Title'),
      fields: helpText('LwcBuilder', 'LwcBuilder_Prop_Fields'),
      fieldsHelp: helpText('LwcBuilder', 'LwcBuilder_Prop_FieldsHelp'),
      twoColumns: helpText('LwcBuilder', 'LwcBuilder_Prop_TwoColumns'),
      object: helpText('LwcBuilder', 'LwcBuilder_Prop_Object'),
      parentField: helpText('LwcBuilder', 'LwcBuilder_Prop_ParentField'),
      filterField: helpText('LwcBuilder', 'LwcBuilder_Prop_FilterField'),
      filterOperator: helpText('LwcBuilder', 'LwcBuilder_Prop_FilterOperator'),
      filterValue: helpText('LwcBuilder', 'LwcBuilder_Prop_FilterValue'),
      orderBy: helpText('LwcBuilder', 'LwcBuilder_Prop_OrderBy'),
      descending: helpText('LwcBuilder', 'LwcBuilder_Prop_Descending'),
      report: helpText('LwcBuilder', 'LwcBuilder_Prop_Report'),
      body: helpText('LwcBuilder', 'LwcBuilder_Prop_Body'),
      url: helpText('LwcBuilder', 'LwcBuilder_Prop_Url'),
      urlHelp: helpText('LwcBuilder', 'LwcBuilder_Prop_UrlHelp'),
      altText: helpText('LwcBuilder', 'LwcBuilder_Prop_AltText'),
      buttonLabel: helpText('LwcBuilder', 'LwcBuilder_Prop_ButtonLabel'),
      kind: helpText('LwcBuilder', 'LwcBuilder_Prop_Kind'),
      actionName: helpText('LwcBuilder', 'LwcBuilder_Prop_ActionName'),
      flowName: helpText('LwcBuilder', 'LwcBuilder_Prop_FlowName'),
      passRecordId: helpText('LwcBuilder', 'LwcBuilder_Prop_PassRecordId'),
      visibility: helpText('LwcBuilder', 'LwcBuilder_Rule_Title'),
      visibilityHelp: helpText('LwcBuilder', 'LwcBuilder_Rule_Help'),
      ruleField: helpText('LwcBuilder', 'LwcBuilder_Rule_Field'),
      ruleOperator: helpText('LwcBuilder', 'LwcBuilder_Rule_Operator'),
      ruleValue: helpText('LwcBuilder', 'LwcBuilder_Rule_Value'),
      rulePermission: helpText('LwcBuilder', 'LwcBuilder_Rule_Permission'),
      ruleLacks: helpText('LwcBuilder', 'LwcBuilder_Rule_Lacks'),
      previewRecord: helpText('LwcBuilder', 'LwcBuilder_Studio_PreviewRecord'),
      problems: helpText('LwcBuilder', 'LwcBuilder_Studio_Problems'),
      exportIntro: helpText('LwcBuilder', 'LwcBuilder_Export_Intro'),
      download: helpText('LwcBuilder', 'LwcBuilder_Export_Download'),
      close: helpText('LwcBuilder', 'LwcBuilder_Export_Close')
    };
  }

  // Choices

  get componentOptions() {
    return [
      { label: this.labels.newComponent, value: NEW },
      ...this.components.map((row) => ({ label: row.name, value: row.id }))
    ];
  }

  get layoutOptions() {
    return Object.keys(LAYOUTS).map((value) => ({ label: layoutLabel(value), value }));
  }

  get palette() {
    return BLOCK_TYPES.map((type) => ({ type, label: typeLabel(type) }));
  }

  get ruleOptions() {
    return [
      { label: helpText('LwcBuilder', 'LwcBuilder_Rule_Always'), value: 'always' },
      { label: helpText('LwcBuilder', 'LwcBuilder_Rule_FieldValue'), value: 'field' },
      { label: helpText('LwcBuilder', 'LwcBuilder_Rule_PermissionType'), value: 'permission' }
    ];
  }

  get operatorOptions() {
    return [
      { label: helpText('LwcBuilder', 'LwcBuilder_Op_Equals'), value: 'equals' },
      { label: helpText('LwcBuilder', 'LwcBuilder_Op_NotEquals'), value: 'notEquals' },
      { label: helpText('LwcBuilder', 'LwcBuilder_Op_Contains'), value: 'contains' },
      { label: helpText('LwcBuilder', 'LwcBuilder_Op_IsBlank'), value: 'isBlank' },
      { label: helpText('LwcBuilder', 'LwcBuilder_Op_IsNotBlank'), value: 'isNotBlank' }
    ];
  }

  get filterOptions() {
    return this.operatorOptions.slice(0, 2);
  }

  get kindOptions() {
    return [
      { label: helpText('LwcBuilder', 'LwcBuilder_Kind_Flow'), value: 'flow' },
      { label: helpText('LwcBuilder', 'LwcBuilder_Kind_QuickAction'), value: 'quickAction' }
    ];
  }

  // The canvas

  get canvas() {
    return this.definition.sections.map((section, sectionIndex, sections) => ({
      id: section.id,
      title: section.title,
      isFirst: sectionIndex === 0,
      isLast: sectionIndex === sections.length - 1,
      rows: section.rows.map((row, rowIndex, rows) => ({
        id: row.id,
        layout: layoutOf(row),
        isFirst: rowIndex === 0,
        isLast: rowIndex === rows.length - 1,
        columns: row.columns.map((column) => ({
          id: column.id,
          css: `slds-col slds-size_${column.width}-of-12 slds-var-p-around_xx-small`,
          zoneCss: `slds-box slds-box_x-small lb-zone${column.id === this.selectedColumnId ? ' lb-zone_selected' : ''}`,
          isEmpty: column.blocks.length === 0,
          blocks: column.blocks.map((block) => ({
            id: block.id,
            columnId: column.id,
            label: typeLabel(block.type),
            title: block.title,
            hasRule:
              block.visibility && block.visibility.type && block.visibility.type !== 'always',
            css: `slds-box slds-box_xx-small slds-var-m-bottom_xx-small lb-block${
              block.id === this.selectedBlockId ? ' lb-block_selected' : ''
            }`
          }))
        }))
      }))
    }));
  }

  get hasSections() {
    return this.definition.sections.length > 0;
  }

  get hasProblems() {
    return this.problems.length > 0;
  }

  get showExport() {
    return this.sourceExport && !this.exportFiles;
  }

  // The selected block and its form

  get selected() {
    const place = this.selectedBlockId ? locate(this.definition, this.selectedBlockId) : null;
    return place && place.kind === 'block' ? place.item : null;
  }

  get form() {
    const block = this.selected;
    if (!block) {
      return null;
    }
    const rule = block.visibility || { type: 'always' };
    return {
      ...block,
      typeLabel: typeLabel(block.type),
      fieldsText: (block.fields || []).join(', '),
      isTwoColumns: block.columns === 2,
      isDescending: block.direction === 'desc',
      isFields: block.type === 'fields',
      isRelatedList: block.type === 'relatedList',
      isList: block.type === 'relatedList' || block.type === 'recordList',
      isRecordList: block.type === 'recordList',
      isChart: block.type === 'chart',
      isText: block.type === 'text',
      isImage: block.type === 'image',
      isAction: block.type === 'action',
      isFlow: block.type === 'action' && block.kind !== 'quickAction',
      isQuickAction: block.type === 'action' && block.kind === 'quickAction',
      rule,
      ruleIsField: rule.type === 'field',
      ruleIsPermission: rule.type === 'permission',
      ruleNeedsValue:
        rule.type === 'field' && rule.operator !== 'isBlank' && rule.operator !== 'isNotBlank',
      ruleLacks: rule.type === 'permission' && rule.has === false
    };
  }

  // Changes, each through the model

  change(definition) {
    this.definition = definition;
    this.exportFiles = undefined;
    if (this.hasProblems) {
      this.problems = this.listProblems();
    }
  }

  listProblems() {
    return validate(this.definition).map((problem, index) => {
      const place = locate(this.definition, problem.id);
      const where = place && place.kind === 'block' ? typeLabel(place.item.type) : '';
      return {
        key: `p${index}`,
        text: where ? `${where}: ${problemText(problem.code)}` : problemText(problem.code)
      };
    });
  }

  handlePick(event) {
    this.selectedId = event.detail.value;
    const row = this.components.find((item) => item.id === this.selectedId);
    this.details = row
      ? {
          id: row.id,
          name: row.name,
          key: row.key,
          description: row.description || '',
          objectName: row.objectName || '',
          active: row.active !== false
        }
      : this.blankDetails();
    this.keyTouched = Boolean(row);
    this.definition = row ? normalize(row.definition) : emptyDefinition();
    this.selectedBlockId = undefined;
    this.selectedColumnId = undefined;
    this.problems = [];
    this.exportFiles = undefined;
  }

  handleNew() {
    this.handlePick({ detail: { value: NEW } });
  }

  handleDetail(event) {
    const prop = event.target.dataset.prop;
    const value = prop === 'active' ? event.target.checked : event.detail.value;
    const details = { ...this.details, [prop]: value };
    if (prop === 'key') {
      this.keyTouched = true;
    }
    if (prop === 'name' && !this.keyTouched) {
      details.key = keyFromName(value);
    }
    this.details = details;
  }

  handleAddSection() {
    const section = addSection(this.definition, '');
    const { definition } = addRow(section.definition, section.id, '12');
    this.selectedColumnId = locate(definition, section.id).item.rows[0].columns[0].id;
    this.change(definition);
  }

  handleSectionTitle(event) {
    this.change(
      updateItem(this.definition, event.target.dataset.id, { title: event.detail.value })
    );
  }

  handleAddRow(event) {
    this.change(addRow(this.definition, event.target.dataset.id, event.detail.value).definition);
  }

  handleRowLayout(event) {
    this.change(setRowLayout(this.definition, event.target.dataset.id, event.detail.value));
  }

  handleMove(event) {
    const { id, delta } = event.currentTarget.dataset;
    this.change(moveItem(this.definition, id, Number(delta)));
  }

  handleRemove(event) {
    const next = removeItem(this.definition, event.currentTarget.dataset.id);
    if (this.selectedBlockId && !locate(next, this.selectedBlockId)) {
      this.selectedBlockId = undefined;
    }
    if (this.selectedColumnId && !locate(next, this.selectedColumnId)) {
      this.selectedColumnId = undefined;
    }
    this.change(next);
  }

  handleSelectColumn(event) {
    this.selectedColumnId = event.currentTarget.dataset.column;
  }

  handleSelectBlock(event) {
    event.stopPropagation();
    this.selectedBlockId = event.currentTarget.dataset.block;
    this.selectedColumnId = event.currentTarget.dataset.column;
  }

  /** A palette button adds its block to the selected column, or starts a section for it. */
  handlePaletteAdd(event) {
    const type = event.currentTarget.dataset.type;
    let definition = this.definition;
    let columnId =
      this.selectedColumnId && locate(definition, this.selectedColumnId)
        ? this.selectedColumnId
        : undefined;
    if (!columnId) {
      this.handleAddSection();
      definition = this.definition;
      columnId = this.selectedColumnId;
    }
    const added = addBlock(definition, columnId, type);
    this.selectedBlockId = added.id;
    this.change(added.definition);
  }

  // Drag and drop: the state is kept here, so it works whatever the browser lets dataTransfer carry.

  handlePaletteDrag(event) {
    this.dragging = { type: event.currentTarget.dataset.type };
    this.markDrag(event);
  }

  handleBlockDrag(event) {
    event.stopPropagation();
    this.dragging = { id: event.currentTarget.dataset.block };
    this.markDrag(event);
  }

  markDrag(event) {
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', JSON.stringify(this.dragging));
    }
  }

  handleDragOver(event) {
    event.preventDefault();
  }

  handleDrop(event) {
    event.preventDefault();
    event.stopPropagation();
    const { column, block } = event.currentTarget.dataset;
    const dragging = this.dragging;
    this.dragging = undefined;
    if (!dragging || !column) {
      return;
    }
    if (dragging.id) {
      this.change(moveBlock(this.definition, dragging.id, column, block));
      this.selectedBlockId = dragging.id;
    } else {
      const added = addBlock(this.definition, column, dragging.type, block);
      this.selectedBlockId = added.id;
      this.change(added.definition);
    }
    this.selectedColumnId = column;
  }

  // The properties form

  handleBlockProp(event) {
    const prop = event.target.dataset.prop;
    const typed =
      event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
    let value = event.target.type === 'checkbox' ? event.target.checked : typed;
    if (prop === 'fields') {
      value = parseFieldList(value);
    } else if (prop === 'columns') {
      value = value ? 2 : 1;
    } else if (prop === 'direction') {
      value = value ? 'desc' : 'asc';
    }
    this.change(updateItem(this.definition, this.selectedBlockId, { [prop]: value }));
  }

  handleRuleProp(event) {
    const prop = event.target.dataset.prop;
    let value = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
    if (prop === 'has') {
      value = !value;
    }
    const current = (this.selected && this.selected.visibility) || { type: 'always' };
    let rule = { ...current, [prop]: value };
    if (prop === 'type') {
      rule =
        value === 'field'
          ? { type: 'field', field: '', operator: 'equals', value: '' }
          : value === 'permission'
            ? { type: 'permission', permission: '', has: true }
            : { type: 'always' };
    }
    this.change(updateItem(this.definition, this.selectedBlockId, { visibility: rule }));
  }

  handleNudge(event) {
    this.change(
      nudgeBlock(this.definition, this.selectedBlockId, event.currentTarget.dataset.direction)
    );
  }

  // Preview, save and export

  handlePreview() {
    this.previewing = !this.previewing;
  }

  handlePreviewRecord(event) {
    this.previewRecordId = event.detail.value;
  }

  get previewDefinition() {
    return this.definition;
  }

  get previewObject() {
    return this.details.objectName || undefined;
  }

  get previewLabel() {
    return this.previewing ? this.labels.edit : this.labels.preview;
  }

  async handleSave() {
    this.problems = this.listProblems();
    if (this.hasProblems) {
      return;
    }
    this.isSaving = true;
    try {
      const saved = await saveComponent({
        componentJson: JSON.stringify({ ...this.details, definition: this.definition })
      });
      this.details = { ...this.details, id: saved.id };
      this.selectedId = saved.id;
      this.keyTouched = true;
      this.errorMessage = undefined;
      this.dispatchEvent(
        new ShowToastEvent({
          title: helpText('LwcBuilder', 'LwcBuilder_Studio_Saved', saved.version),
          variant: 'success'
        })
      );
      await this.refresh();
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('LwcBuilder', 'LwcBuilder_Error_Generic'));
    } finally {
      this.isSaving = false;
    }
  }

  handleExport() {
    const { files } = exportSource(this.definition, this.details);
    this.exportFiles = files.map((file) => ({ ...file, key: file.name }));
  }

  handleCloseExport() {
    this.exportFiles = undefined;
  }

  handleDownload(event) {
    const file = this.exportFiles.find((item) => item.name === event.currentTarget.dataset.name);
    if (file) {
      saveBlob(new Blob([file.content], { type: 'text/plain' }), file.name);
    }
  }
}
