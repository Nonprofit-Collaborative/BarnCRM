/**
 * R-GL2 and R-GS1 (canonical model Sections 29ZA2 and 29ZA3), run by the Core trigger dispatcher
 * through the registry rows `Goal_Dates` (Goal__c) and `Goal_Step_Dates` (Goal_Step__c), each
 * switchable from the Automation page (ADR-0017). Closing a goal (Achieved or Not Achieved) fills
 * an empty Closed Date with today and reopening it empties it; a step's Completed Date follows
 * Done the same way. It does work for the user rather than enforcing a rule, so an import of
 * history can turn it off.
 */
@NamespaceAccessible
public with sharing class ServicePlanDatesHandler extends TriggerHandler {
    @NamespaceAccessible
    public ServicePlanDatesHandler() {
        return;
    }

    public override String getName() {
        return 'ServicePlanDatesHandler';
    }

    public override void beforeInsert() {
        fill(Trigger.new, null);
    }

    public override void beforeUpdate() {
        fill(Trigger.new, Trigger.oldMap);
    }

    private static void fill(List<SObject> records, Map<Id, SObject> oldById) {
        if (records == null || records.isEmpty()) {
            return;
        }
        if (records[0].getSObjectType() == Goal__c.SObjectType) {
            ServicePlanService.fillClosedDates((List<Goal__c>) records, oldById);
        } else if (records[0].getSObjectType() == Goal_Step__c.SObjectType) {
            ServicePlanService.fillCompletedDates((List<Goal_Step__c>) records, oldById);
        }
    }
}
