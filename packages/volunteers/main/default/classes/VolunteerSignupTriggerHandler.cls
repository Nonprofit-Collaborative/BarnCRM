/**
 * Record-level rules for Volunteer_Signup__c, run by the Core trigger dispatcher through the
 * registry row `Volunteer_Signup_Rules`, switchable from the console (ADR-0017). The rules are
 * `VolunteerSignupService` methods; this class decides which sign-ups each applies to.
 */
@NamespaceAccessible
public with sharing class VolunteerSignupTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public VolunteerSignupTriggerHandler() {
        return;
    }

    public override String getName() {
        return 'VolunteerSignupTriggerHandler';
    }

    public override void beforeInsert() {
        VolunteerSignupService.refuseSecondSignups((List<Volunteer_Signup__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        Map<Id, Volunteer_Signup__c> previousById = (Map<Id, Volunteer_Signup__c>) Trigger.oldMap;
        List<Volunteer_Signup__c> moved = new List<Volunteer_Signup__c>();
        for (Volunteer_Signup__c signup : (List<Volunteer_Signup__c>) Trigger.new) {
            Volunteer_Signup__c previous = previousById.get(signup.Id);
            if (
                signup.Volunteer_Shift__c != previous.Volunteer_Shift__c ||
                signup.Contact__c != previous.Contact__c ||
                signup.Account__c != previous.Account__c
            ) {
                moved.add(signup);
            }
        }
        if (!moved.isEmpty()) {
            VolunteerSignupService.refuseSecondSignups(moved);
        }
    }

    public override void afterInsert() {
        VolunteerSignupService.createHoursForAttendance(
            (List<Volunteer_Signup__c>) Trigger.new,
            null
        );
    }

    /**
     * R-VU2 on undelete: restoring a sign-up for a person who has since been booked onto the
     * same shift again is refused. Undeleting writes no attendance hours.
     */
    public override void afterUndelete() {
        VolunteerSignupService.refuseSecondSignups((List<Volunteer_Signup__c>) Trigger.new);
    }

    public override void afterUpdate() {
        VolunteerSignupService.createHoursForAttendance(
            (List<Volunteer_Signup__c>) Trigger.new,
            (Map<Id, Volunteer_Signup__c>) Trigger.oldMap
        );
    }
}
