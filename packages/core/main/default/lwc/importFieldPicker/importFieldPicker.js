import { LightningElement, api } from 'lwc';
import usedLabel from '@salesforce/label/c.Core_CmdtManager_StatusInUse';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { buildModel, selectedText, stepIndex } from './fieldPickerModel';

/** For the Check Columns step: the fields worth suggesting for columns not yet matched. */
export { suggestFields } from './fieldSuggest';

const OPTION = 'slds-media slds-listbox__option slds-listbox__option_plain slds-media_small';

/**
 * A type-to-search picker for the field a spreadsheet column loads into (admin-13). A plain
 * dropdown cannot be searched and Contact alone has over 100 fields; this one filters as the
 * administrator types, groups people-file fields under Person, Second person and Organization,
 * pins "Do not load" at the top, and marks the fields another column already loads into.
 *
 * Keyboard: type to search; the Down arrow moves into the list; Up, Down, Home and End move
 * along it; Enter or Space chooses; Escape closes. A screen reader hears how many fields match.
 * Fires `change` with `{ value }`, the same event the dropdown it replaces fired.
 *
 * See docs/admin-guide/importing.md, "Check Columns".
 */
export default class ImportFieldPicker extends LightningElement {
  /** The column's name, for the screen reader (the label is not shown). */
  @api label;
  /** The fields to choose from: `{ label, value }`. */
  @api options = [];
  /** The chosen value. */
  @api value;
  /** The value that means "do not load this column", pinned at the top of the list. */
  @api pinnedValue;
  /** Values other columns already load into, marked "In use". */
  @api usedValues = [];
  @api disabled = false;

  helpReady = isHelpLoaded('Core');
  open = false;
  typed = false;
  query = '';
  returning = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  get usedLabel() {
    return usedLabel;
  }

  get comboClass() {
    return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click${
      this.open ? ' slds-is-open' : ''
    }`;
  }

  get ariaExpanded() {
    return this.open ? 'true' : 'false';
  }

  get placeholder() {
    return this.helpReady ? helpText('Core', 'Core_Import_FieldPickerPlaceholder') : '';
  }

  get selectedLabel() {
    return selectedText(this.options, this.value);
  }

  get inputValue() {
    return this.open && this.typed ? this.query : this.selectedLabel;
  }

  /** The list as shown now: pinned choice, then matching fields under their groups. */
  get model() {
    const built = buildModel({
      options: this.options,
      query: this.open && this.typed ? this.query : '',
      usedValues: this.usedValues,
      selected: this.value,
      pinnedValue: this.pinnedValue
    });
    let index = 0;
    const decorate = (item) => ({
      ...item,
      index: index++,
      optionClass: item.selected ? `${OPTION} slds-is-selected` : OPTION
    });
    const pinned = built.pinned ? decorate(built.pinned) : null;
    const groups = built.groups.map((group) => ({
      ...group,
      items: group.items.map(decorate)
    }));
    return { pinned, groups, count: built.count, total: index };
  }

  get noMatches() {
    return this.model.count === 0;
  }

  get noMatchText() {
    return helpText('Core', 'Core_Import_FieldPickerNone');
  }

  get countText() {
    if (!this.open || !this.typed || this.model.count === 0) {
      return '';
    }
    return helpText('Core', 'Core_Import_FieldPickerCount', this.model.count);
  }

  // ---- opening and closing --------------------------------------------------------------

  openList() {
    if (this.disabled || this.open) {
      return;
    }
    this.open = true;
    this.typed = false;
    this.query = '';
  }

  closeList() {
    this.open = false;
    this.typed = false;
    this.query = '';
  }

  handleFocus() {
    // Focus coming back after a choice must not reopen the list.
    if (this.returning) {
      this.returning = false;
      return;
    }
    this.openList();
    this.selectInputText();
  }

  handleOpen() {
    this.openList();
  }

  selectInputText() {
    // The input is already rendered; select its text so the first key typed replaces it.
    const input = this.refInput();
    if (input && typeof input.select === 'function') {
      input.select();
    }
  }

  /** Close when focus leaves the picker altogether, not when it moves into the list. */
  handleFocusOut() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      const combo = this.template.querySelector('[data-id="combobox"]');
      const active = this.template.activeElement;
      if (this.open && (!combo || !active || !combo.contains(active))) {
        this.closeList();
      }
    }, 0);
  }

  // ---- typing ----------------------------------------------------------------------------

  handleInput(event) {
    this.open = true;
    this.typed = true;
    this.query = event.target.value;
  }

  handleInputKey(event) {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      this.openList();
      this.focusOption(0);
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      this.openList();
      this.focusOption(this.model.total - 1);
    } else if (event.key === 'Escape' && this.open) {
      event.preventDefault();
      this.closeList();
    } else if (event.key === 'Enter' && this.open && this.typed) {
      // Enter on a search with one match chooses it.
      const found = this.optionElements().filter(
        (option) => option.dataset.value !== this.pinnedValue
      );
      if (found.length === 1) {
        event.preventDefault();
        this.choose(found[0].dataset.value);
      }
    }
  }

  // ---- the list ---------------------------------------------------------------------------

  handleListKey(event) {
    const options = this.optionElements();
    const current = options.findIndex((each) => each === event.target);
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      this.focusOption(stepIndex(current, 1, options.length));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      if (current <= 0) {
        this.focusInput();
      } else {
        this.focusOption(current - 1);
      }
    } else if (event.key === 'Home') {
      event.preventDefault();
      this.focusOption(0);
    } else if (event.key === 'End') {
      event.preventDefault();
      this.focusOption(options.length - 1);
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      if (current >= 0) {
        this.choose(options[current].dataset.value);
      }
    } else if (event.key === 'Escape') {
      event.preventDefault();
      this.closeList();
      this.focusInput();
    } else if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
      // A letter typed in the list goes back to the search box.
      this.focusInput();
    }
  }

  handleOptionClick(event) {
    this.choose(event.currentTarget.dataset.value);
  }

  choose(value) {
    this.closeList();
    this.dispatchEvent(new CustomEvent('change', { detail: { value } }));
    this.returning = true;
    this.focusInput();
    // When the input already had focus no focus event fires; do not leave the flag set.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this.returning = false;
    }, 0);
  }

  // ---- focus helpers ----------------------------------------------------------------------

  refInput() {
    return this.template.querySelector('[data-id="input"]');
  }

  optionElements() {
    return Array.from(this.template.querySelectorAll('[data-id="option"]'));
  }

  focusInput() {
    const input = this.refInput();
    if (input) {
      input.focus();
    }
  }

  focusOption(index) {
    const options = this.optionElements();
    if (options[index]) {
      options[index].focus();
    }
  }

  @api
  focus() {
    this.focusInput();
  }
}
