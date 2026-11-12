import { LightningElement, api } from 'lwc';

// Stands in for c/gridTool in the Find page tests, which check the view key it is given.
export default class GridTool extends LightningElement {
  @api stateKey;
}
