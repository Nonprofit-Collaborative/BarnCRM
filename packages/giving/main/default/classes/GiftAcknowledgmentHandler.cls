/**
 * The gift's side of acknowledgments: which queue this gift belongs in, and nothing else.
 *
 * It sends no mail. Thanking a donor is a convenience rather than a rule, so its registry row
 * carries `Always_Runs__c` false and an administrator can switch it off before a bulk import
 * exactly as she can switch off the other conveniences (R-A1, and deliberately not ADR-0024).
 *
 * The handler is the same thin wrapper every other one is: the rules themselves are
 * `AcknowledgmentService` methods that take explicit lists and are unit tested without a trigger
 * context.
 */
@NamespaceAccessible
public with sharing class GiftAcknowledgmentHandler extends TriggerHandler {
    @NamespaceAccessible
    public GiftAcknowledgmentHandler() {
        return;
    }

    public override String getName() {
        return 'GiftAcknowledgmentHandler';
    }

    public override void beforeInsert() {
        AcknowledgmentService.applyRules((List<Gift__c>) Trigger.new, null);
    }

    public override void beforeUpdate() {
        AcknowledgmentService.applyRules(
            (List<Gift__c>) Trigger.new,
            (Map<Id, Gift__c>) Trigger.oldMap
        );
    }

    /**
     * After the save, because releasing a claim is DML on another object and a before context is
     * not the place for it. This is the one path by which a gift that has been thanked for is
     * thanked for again, and it runs only when a person put the gift back in the queue (R-AK7).
     */
    public override void afterUpdate() {
        AcknowledgmentService.releaseClaims(
            (List<Gift__c>) Trigger.new,
            (Map<Id, Gift__c>) Trigger.oldMap
        );
    }
}
