/**
 * The Record Inbound Gift Flow action (feature X-03): the inbound gift API for anything already
 * inside Salesforce. It takes many gifts and answers each one in the same position, and a
 * rejected gift is an answer rather than a failure, so one bad gift never stops the others.
 *
 * `global` because a Flow in a subscriber org calls it (ADR-0017, ADR-0051).
 */
global with sharing class InboundGiftAction {
    @InvocableMethod(
        label='Record Inbound Gift'
        description='Records a gift sent by another system, once, however many times it is sent.'
        category='BarnCRM'
    )
    global static List<InboundGiftResult> record(List<InboundGift> gifts) {
        return InboundGiftService.record(gifts);
    }
}
