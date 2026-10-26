/**
 * Keeps a stewardship plan's Completed Date in step with its Status.
 *
 * A plan closed by the package already carries its date. A plan whose Status someone changes by
 * hand does not, and the Completed_Date_Matches_Status validation rule would otherwise reject the
 * save. So a plan set to Complete or Cancelled gets today's date when it has none, and a plan set
 * back to Running loses its date.
 */
@NamespaceAccessible
public with sharing class StewardshipPlanTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public StewardshipPlanTriggerHandler() {
        return;
    }

    public override void beforeInsert() {
        syncCompletedDates(newRecords());
    }

    public override void beforeUpdate() {
        syncCompletedDates(newRecords());
    }

    /** Fills or clears Completed Date to match Status. */
    @NamespaceAccessible
    public static void syncCompletedDates(List<SObject> records) {
        if (records == null) {
            return;
        }
        for (SObject record : records) {
            Stewardship_Plan__c plan = (Stewardship_Plan__c) record;
            if (plan.Status__c == null) {
                continue;
            }
            if (plan.Status__c == StewardshipService.STATUS_RUNNING) {
                plan.Completed_Date__c = null;
            } else if (plan.Completed_Date__c == null) {
                plan.Completed_Date__c = System.today();
            }
        }
    }
}
