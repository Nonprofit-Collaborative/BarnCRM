import { LightningElement, api } from 'lwc';

/**
 * Convert Nonprofit Cloud Households on the General page of BarnCRM Settings (MIG-02b, admin
 * guide nonprofit-cloud-households.md): the household adoption panel with source NPC. The
 * settings console places components by name only, so this names the source for it.
 */
export default class NpcHouseholdConversion extends LightningElement {
  /** The console calls this after a save: a membership change changes what a run does. */
  @api
  refresh() {
    return this.refs.panel?.refresh();
  }
}
