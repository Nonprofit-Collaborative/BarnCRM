import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

/** The page state key that chooses the view, matched by suffix (never a literal prefix). */
const VIEW_STATE = '__view';
const GRID = 'grid';

/**
 * The Find tab (C-34, C-41): Find itself, or the Grid tool when the page was opened with the
 * view state set to `grid` (from the Grid tile in Data Manager). One tab holds both, so the Grid
 * needs no tab of its own and Find's links keep working.
 */
export default class FindPage extends LightningElement {
  viewKey;
  showGrid = false;

  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    const state = (pageReference && pageReference.state) || {};
    this.viewKey = Object.keys(state).find((name) => name.endsWith(VIEW_STATE));
    this.showGrid = Boolean(this.viewKey) && state[this.viewKey] === GRID;
  }
}
