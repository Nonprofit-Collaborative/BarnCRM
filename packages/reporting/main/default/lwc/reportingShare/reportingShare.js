import { LightningElement, api } from 'lwc';
import findPeople from '@salesforce/apex/ReportingLibrary.findPeople';
import { helpText } from 'c/barnHelpText';
import { format } from 'c/barnFormat';
import { messageFrom } from 'c/findCsv';

const SEARCH_DELAY = 300;

/**
 * Who a saved report or dashboard is shared with: people and public groups, each Can View or
 * Can Edit. Search finds active people and public groups by name. Fires `save` with
 * `{ sharing: { users: [{ id, name, access }], groups: [...] } }`, and `cancel`.
 */
export default class ReportingShare extends LightningElement {
  @api title = '';

  entries = [];
  term = '';
  found = [];
  searching = false;
  error = '';
  timer;

  @api
  get sharing() {
    return this.toSharing();
  }
  set sharing(value) {
    const source = value && typeof value === 'object' ? value : {};
    const read = (list, kind) =>
      (Array.isArray(list) ? list : [])
        .filter((entry) => entry && entry.id)
        .map((entry) => ({
          id: entry.id,
          name: entry.name || entry.id,
          kind,
          access: entry.access === 'edit' ? 'edit' : 'view'
        }));
    this.entries = [...read(source.users, 'user'), ...read(source.groups, 'group')];
  }

  disconnectedCallback() {
    clearTimeout(this.timer);
  }

  toSharing() {
    const pick = (kind) =>
      this.entries
        .filter((entry) => entry.kind === kind)
        .map((entry) => ({ id: entry.id, name: entry.name, access: entry.access }));
    return { users: pick('user'), groups: pick('group') };
  }

  get heading() {
    return format(helpText('Reporting', 'Reporting_Share_Heading'), this.title);
  }

  get accessOptions() {
    return [
      { value: 'view', label: helpText('Reporting', 'Reporting_Share_View') },
      { value: 'edit', label: helpText('Reporting', 'Reporting_Share_Edit') }
    ];
  }

  get rows() {
    return this.entries.map((entry) => ({
      ...entry,
      key: entry.id,
      kindLabel:
        entry.kind === 'group'
          ? helpText('Reporting', 'Reporting_Share_Group')
          : helpText('Reporting', 'Reporting_Share_Person'),
      removeLabel: format(helpText('Reporting', 'Reporting_Share_Remove'), entry.name),
      accessLabel: format(helpText('Reporting', 'Reporting_Share_AccessFor'), entry.name)
    }));
  }

  get hasRows() {
    return this.entries.length > 0;
  }

  get results() {
    const chosen = new Set(this.entries.map((entry) => entry.id));
    return this.found
      .filter((entry) => !chosen.has(entry.id))
      .map((entry) => ({
        ...entry,
        key: entry.id,
        text:
          entry.kind === 'group'
            ? format(helpText('Reporting', 'Reporting_Share_GroupName'), entry.name)
            : entry.name
      }));
  }

  get hasResults() {
    return this.results.length > 0;
  }

  get labels() {
    return {
      intro: helpText('Reporting', 'Reporting_Share_Intro'),
      search: helpText('Reporting', 'Reporting_Share_Search'),
      none: helpText('Reporting', 'Reporting_Share_None'),
      name: helpText('Reporting', 'Reporting_Share_Name'),
      access: helpText('Reporting', 'Reporting_Share_Access'),
      add: helpText('Reporting', 'Reporting_Share_Add'),
      save: helpText('Reporting', 'Reporting_Save'),
      cancel: helpText('Reporting', 'Reporting_Cancel'),
      remove: helpText('Reporting', 'Reporting_Remove')
    };
  }

  handleSearch(event) {
    this.term = event.detail.value || '';
    clearTimeout(this.timer);
    if (this.term.trim().length < 2) {
      this.found = [];
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = setTimeout(() => this.search(this.term), SEARCH_DELAY);
  }

  async search(term) {
    this.searching = true;
    this.error = '';
    try {
      const found = await findPeople({ term });
      if (term === this.term) {
        this.found = found || [];
      }
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    } finally {
      this.searching = false;
    }
  }

  handleAdd(event) {
    const id = event.currentTarget.dataset.entry;
    const entry = this.found.find((candidate) => candidate.id === id);
    if (entry) {
      this.entries = [
        ...this.entries,
        { id: entry.id, name: entry.name, kind: entry.kind, access: 'view' }
      ];
    }
  }

  handleAccess(event) {
    const id = event.target.dataset.entry;
    const access = event.detail.value;
    this.entries = this.entries.map((entry) => (entry.id === id ? { ...entry, access } : entry));
  }

  handleRemove(event) {
    const id = event.currentTarget.dataset.entry;
    this.entries = this.entries.filter((entry) => entry.id !== id);
  }

  handleSave() {
    this.dispatchEvent(new CustomEvent('save', { detail: { sharing: this.toSharing() } }));
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent('cancel'));
  }
}
