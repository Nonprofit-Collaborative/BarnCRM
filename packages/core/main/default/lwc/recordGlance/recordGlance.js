import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import LOCALE from '@salesforce/i18n/locale';
import getCards from '@salesforce/apex/RecordGlanceController.getCards';
import { cardViews } from './recordGlanceModel';

/**
 * A host for small summary cards that installed modules add to Core's Contact and Account
 * record pages (people-14, ADR-NEXT `NEXT-record-glance-extension.md`). Core has no content of
 * its own here: with no module installed, or none with something to say, it draws nothing.
 */
export default class RecordGlance extends NavigationMixin(LightningElement) {
  _recordId;
  cards = [];

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const changed = value !== this._recordId;
    this._recordId = value;
    if (changed && this.isConnected) {
      this.load();
    }
  }

  connectedCallback() {
    this.load();
  }

  get hasCards() {
    return this.cards.length > 0;
  }

  async load() {
    if (!this._recordId) {
      this.cards = [];
      return;
    }
    try {
      this.cards = cardViews(await getCards({ recordId: this._recordId }), LOCALE);
    } catch {
      // A module that cannot answer is logged on the server; the page shows no card.
      this.cards = [];
    }
  }

  handleAction(event) {
    const cardKey = event.currentTarget.dataset.card;
    const actionKey = event.currentTarget.dataset.action;
    const card = this.cards.find((c) => c.key === cardKey);
    const action = card && card.actions.find((a) => a.key === actionKey);
    if (action && action.pageReference) {
      this[NavigationMixin.Navigate](action.pageReference);
    }
  }
}
