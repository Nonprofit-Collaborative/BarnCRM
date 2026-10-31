/**
 * R-EN3 for Enrollment__c, run by the Core trigger dispatcher through the registry row
 * `Enrollment_Dates`, switchable from the Automation page (ADR-0017): it fills in an empty Start
 * Date when an enrollment becomes Enrolled and an empty End Date when it ends. It does work for
 * the user rather than enforcing a rule, so an import of history can turn it off.
 */
@NamespaceAccessible
public with sharing class EnrollmentDatesHandler extends TriggerHandler {
    @NamespaceAccessible
    public EnrollmentDatesHandler() {
        return;
    }

    public override String getName() {
        return 'EnrollmentDatesHandler';
    }

    public override void beforeInsert() {
        EnrollmentService.fillStageDates((List<Enrollment__c>) Trigger.new, null);
    }

    public override void beforeUpdate() {
        EnrollmentService.fillStageDates(
            (List<Enrollment__c>) Trigger.new,
            (Map<Id, Enrollment__c>) Trigger.oldMap
        );
    }
}
