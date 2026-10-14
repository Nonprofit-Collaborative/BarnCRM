import { LightningElement } from 'lwc';
import search from '@salesforce/apex/SettingsController.search';
import INPUT_LABEL from '@salesforce/label/c.Core_SettingsSearch_InputLabel';
import PLACEHOLDER from '@salesforce/label/c.Core_SettingsSearch_Placeholder';
import RESULTS_HEADING from '@salesforce/label/c.Core_SettingsSearch_ResultsHeading';
import NO_RESULTS from '@salesforce/label/c.Core_SettingsSearch_NoResultsMessage';
import SEARCH_ERROR from '@salesforce/label/c.Core_SettingsSearch_ErrorMessage';

const DEBOUNCE_MS = 300;

export default class SettingsSearch extends LightningElement {
  labels = {
    inputLabel: INPUT_LABEL,
    placeholder: PLACEHOLDER,
    resultsHeading: RESULTS_HEADING,
    noResults: NO_RESULTS,
    searchError: SEARCH_ERROR
  };

  results = [];
  searched = false;
  failed = false;
  timer;
  /** Counts searches, so a slow answer to an earlier term cannot replace a newer one. */
  searchSequence = 0;

  disconnectedCallback() {
    this.clearTimer();
  }

  get hasResults() {
    return this.results.length > 0;
  }

  get showNoResults() {
    return this.searched && !this.failed && this.results.length === 0;
  }

  handleInput(event) {
    const term = event.target.value;
    this.clearTimer();
    // A search still on its way for an earlier term is out of date from this keystroke on.
    this.searchSequence++;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = setTimeout(() => {
      this.runSearch(term);
    }, DEBOUNCE_MS);
  }

  async runSearch(term) {
    const sequence = ++this.searchSequence;
    this.failed = false;
    if (!term || term.trim().length === 0) {
      this.results = [];
      this.searched = false;
      return;
    }
    let hits;
    let failed = false;
    try {
      hits = await search({ term });
    } catch {
      failed = true;
    }
    if (sequence !== this.searchSequence) {
      return;
    }
    this.failed = failed;
    this.results = failed
      ? []
      : (hits || []).map((hit, index) => ({
          ...hit,
          rowId: `${hit.section}-${hit.key}-${index}`
        }));
    this.searched = true;
  }

  handleSelect(event) {
    const section = event.currentTarget.dataset.section;
    const key = event.currentTarget.dataset.key;
    this.dispatchEvent(new CustomEvent('settingselect', { detail: { section, key } }));
  }

  clearTimer() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
  }
}
