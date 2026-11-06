import { LightningElement, api } from 'lwc';

/** Cancel Pending Gift (people-giving-19): the quick action that opens c-giving-quick-status. */
export default class GiftCancelPending extends LightningElement {
  @api recordId;
}
