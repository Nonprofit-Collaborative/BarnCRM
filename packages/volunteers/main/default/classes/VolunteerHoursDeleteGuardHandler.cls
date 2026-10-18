/**
 * R-VG9: an Approved hours entry is not deleted, by anyone, including a coordinator whose
 * Modify All on Volunteer Hours includes Delete. Approved hours count in totals, so deleting one
 * would change them with nothing on record. Reopening it first (Manage Volunteers) makes it
 * deletable.
 *
 * Run through the registry row `Volunteer_Hours_Delete_Guard`, which always runs: it enforces a
 * rule, so no switch, pause or bypass reaches it (ADR-0024). A validation rule cannot block a
 * delete, so this is the only place the rule lives.
 */
@NamespaceAccessible
public with sharing class VolunteerHoursDeleteGuardHandler extends TriggerHandler {
    @NamespaceAccessible
    public VolunteerHoursDeleteGuardHandler() {
        return;
    }

    public override String getName() {
        return 'VolunteerHoursDeleteGuardHandler';
    }

    public override void beforeDelete() {
        VolunteerHoursService.refuseDeletingApproved((List<Volunteer_Hours__c>) Trigger.old);
    }
}
