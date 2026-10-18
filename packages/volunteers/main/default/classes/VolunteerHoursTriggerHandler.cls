/**
 * Record-level rules for Volunteer_Hours__c, run by the Core trigger dispatcher through the
 * automation registry (`Volunteer_Hours_Rules`), so an administrator can switch them off from
 * the console (ADR-0017).
 *
 * Each rule is a `VolunteerHoursService` method that takes explicit lists; this class only reads
 * the trigger context and decides which records a rule applies to.
 */
@NamespaceAccessible
public with sharing class VolunteerHoursTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public VolunteerHoursTriggerHandler() {
        return;
    }

    public override String getName() {
        return 'VolunteerHoursTriggerHandler';
    }

    public override void beforeInsert() {
        List<Volunteer_Hours__c> entries = (List<Volunteer_Hours__c>) Trigger.new;
        VolunteerHoursService.applyStartingStatus(entries);
        VolunteerHoursService.fillJobsFromShifts(entries);
        VolunteerHoursService.deriveHouseholds(entries);
    }

    public override void beforeUpdate() {
        List<Volunteer_Hours__c> entries = (List<Volunteer_Hours__c>) Trigger.new;
        Map<Id, Volunteer_Hours__c> previousById = (Map<Id, Volunteer_Hours__c>) Trigger.oldMap;
        VolunteerHoursService.refuseStatusChangesOutsideTheService(entries, previousById);

        List<Volunteer_Hours__c> shiftChanged = new List<Volunteer_Hours__c>();
        List<Volunteer_Hours__c> personChanged = new List<Volunteer_Hours__c>();
        for (Volunteer_Hours__c entry : entries) {
            Volunteer_Hours__c previous = previousById.get(entry.Id);
            if (entry.Volunteer_Shift__c != previous.Volunteer_Shift__c) {
                shiftChanged.add(entry);
            }
            // R-VG2: recomputed only when the person changes, so hours stay with the household
            // they were given in when the person later moves (ADR-0071).
            if (
                entry.Contact__c != previous.Contact__c ||
                entry.Account__c != previous.Account__c
            ) {
                personChanged.add(entry);
            }
        }
        if (!shiftChanged.isEmpty()) {
            VolunteerHoursService.fillJobsFromShifts(shiftChanged);
        }
        if (!personChanged.isEmpty()) {
            VolunteerHoursService.deriveHouseholds(personChanged);
        }
    }
}
