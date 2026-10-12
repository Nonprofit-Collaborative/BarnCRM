import { LightningElement, api } from 'lwc';

export default class RollupDefinitions extends LightningElement {
  @api builder;
  @api refresh = jest.fn();
}
