/**
 * The Record Inbound Gift Flow action (feature X-03): the inbound gift API for anything already
 * inside Salesforce. It takes many gifts and answers each one in the same position, and a
 * rejected gift is an answer rather than a failure, so one bad gift never stops the others.
 *
 * `global` because a Flow in a subscriber org calls it (ADR-0017, ADR-0051).
 *
 * The label and descriptions here, on `InboundGift` and on `InboundGiftResult` are read by two
 * audiences: an administrator in Flow Builder, and an AI agent the customer runs themselves
 * (their own Agentforce, or their own Hosted MCP server) deciding which tool to call and how to
 * fill it in. So each one says what the action does, what it never does, and the exact format of
 * each value, in under 255 characters. The admin guide page is
 * `docs/admin-guide/using-barncrm-actions-with-ai.md`. BarnCRM ships no AI of its own.
 */
global with sharing class InboundGiftAction {
    @InvocableMethod(
        label='Record Inbound Gift'
        description='Records a gift that has already been received, for a donor who already exists. Never creates a donor, never changes or refunds a gift. Safe to repeat: the same External Id returns the gift already recorded instead of a second one.'
        category='BarnCRM'
    )
    global static List<InboundGiftResult> record(List<InboundGift> gifts) {
        return InboundGiftService.record(gifts);
    }
}
