/**
 * Record-level rules for Volunteer_Job__c, run by the Core trigger dispatcher through the
 * registry row `Volunteer_Job_Rules`, which always runs: it enforces a rule rather than doing
 * work for anyone, so no switch, pause or bypass reaches it (ADR-0024).
 *
 * R-VJ1: a job with shifts or hours is deactivated, not deleted. Deleting it would take its
 * shifts and sign-ups with it and leave its hours, Approved ones included, naming no job and no
 * shift. The message says what to do instead, as R-F2 does for a fund.
 */
@NamespaceAccessible
public with sharing class VolunteerJobTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public VolunteerJobTriggerHandler() {
        return;
    }

    public override String getName() {
        return 'VolunteerJobTriggerHandler';
    }

    public override void beforeDelete() {
        List<Volunteer_Job__c> jobs = (List<Volunteer_Job__c>) Trigger.old;
        Set<Id> jobIds = new Map<Id, Volunteer_Job__c>(jobs).keySet();
        Set<Id> inUse = VolunteerIntegritySelector.selectJobIdsInUse(jobIds);
        for (Volunteer_Job__c job : jobs) {
            if (inUse.contains(job.Id)) {
                job.addError(Label.Volunteers_Job_InUseNotDeletable);
            }
        }
    }
}
