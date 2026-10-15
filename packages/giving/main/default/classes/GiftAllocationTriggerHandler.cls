/**
 * Record-level rules for Gift_Allocation__c: the amount and percent are kept in step, and no
 * save may leave a gift over-allocated or under-allocated (R-GA1).
 */
@NamespaceAccessible
public with sharing class GiftAllocationTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public GiftAllocationTriggerHandler() {
        return;
    }

    public override String getName() {
        return 'GiftAllocationTriggerHandler';
    }

    public override void beforeInsert() {
        GiftService.applyAmountAndPercent((List<Gift_Allocation__c>) Trigger.new, null);
    }

    public override void beforeUpdate() {
        GiftService.applyAmountAndPercent(
            (List<Gift_Allocation__c>) Trigger.new,
            (Map<Id, Gift_Allocation__c>) Trigger.oldMap
        );
    }

    public override void afterInsert() {
        check((List<Gift_Allocation__c>) Trigger.new);
    }

    public override void afterUpdate() {
        check((List<Gift_Allocation__c>) Trigger.new);
    }

    public override void afterDelete() {
        check((List<Gift_Allocation__c>) Trigger.old);
    }

    public override void afterUndelete() {
        check((List<Gift_Allocation__c>) Trigger.new);
    }

    /**
     * The gifts these allocations belong to must still add up. The message goes on every
     * allocation of the gift that is in this save, so the person sees it against the row they
     * were editing.
     */
    private void check(List<Gift_Allocation__c> allocations) {
        Set<Id> giftIds = new Set<Id>();
        for (Gift_Allocation__c allocation : allocations) {
            if (allocation.Gift__c != null) {
                giftIds.add(allocation.Gift__c);
            }
        }

        Map<Id, String> problems = GiftService.validateAllocations(giftIds);
        if (problems.isEmpty()) {
            return;
        }
        for (Gift_Allocation__c allocation : allocations) {
            String problem = problems.get(allocation.Gift__c);
            if (problem != null) {
                allocation.addError(problem);
            }
        }
    }
}
