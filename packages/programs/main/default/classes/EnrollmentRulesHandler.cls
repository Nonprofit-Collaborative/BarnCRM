/**
 * R-EN2 for Enrollment__c, run by the Core trigger dispatcher through the registry row
 * `Enrollment_Rules`, which always runs: it enforces a rule rather than doing work for anyone, so
 * no switch, pause or bypass reaches it (ADR-0024). A second open enrollment for the same person
 * in the same program is refused on insert, on undelete, and on an update that changes the
 * program, the person or the stage of an enrollment that is open after the save.
 */
@NamespaceAccessible
public with sharing class EnrollmentRulesHandler extends TriggerHandler {
    @NamespaceAccessible
    public EnrollmentRulesHandler() {
        return;
    }

    public override String getName() {
        return 'EnrollmentRulesHandler';
    }

    public override void beforeInsert() {
        EnrollmentService.refuseSecondOpenEnrollments((List<Enrollment__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        Map<Id, Enrollment__c> previousById = (Map<Id, Enrollment__c>) Trigger.oldMap;
        List<Enrollment__c> changed = new List<Enrollment__c>();
        for (Enrollment__c enrollment : (List<Enrollment__c>) Trigger.new) {
            Enrollment__c previous = previousById.get(enrollment.Id);
            if (
                enrollment.Program__c != previous.Program__c ||
                enrollment.Contact__c != previous.Contact__c ||
                enrollment.Account__c != previous.Account__c ||
                enrollment.Stage__c != previous.Stage__c
            ) {
                changed.add(enrollment);
            }
        }
        if (!changed.isEmpty()) {
            EnrollmentService.refuseSecondOpenEnrollments(changed);
        }
    }

    /** Restoring an open enrollment for a person since enrolled again is refused. */
    public override void afterUndelete() {
        EnrollmentService.refuseSecondOpenEnrollments((List<Enrollment__c>) Trigger.new);
    }
}
