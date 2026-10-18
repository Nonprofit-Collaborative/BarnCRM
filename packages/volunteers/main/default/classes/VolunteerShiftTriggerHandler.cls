/**
 * Record-level rules for Volunteer_Shift__c, run by the Core trigger dispatcher through the
 * registry row `Volunteer_Shift_Rules`, switchable from the console (ADR-0017).
 *
 * R-VS2: a shift saved without a name gets one from its job and its start, for example
 * "Food pantry sort: 14 Mar 2026, 9:00 AM", in the saving user's time zone. A typed name is
 * never overwritten. That a shift ends after it starts (R-VS3) is a validation rule, so it holds
 * with this switched off.
 */
@NamespaceAccessible
public with sharing class VolunteerShiftTriggerHandler extends TriggerHandler {
    private static final String START_FORMAT = 'd MMM yyyy, h:mm a';
    private static final Integer NAME_LENGTH = 80;

    @NamespaceAccessible
    public VolunteerShiftTriggerHandler() {
        return;
    }

    public override String getName() {
        return 'VolunteerShiftTriggerHandler';
    }

    public override void beforeInsert() {
        nameUnnamed((List<Volunteer_Shift__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        nameUnnamed((List<Volunteer_Shift__c>) Trigger.new);
    }

    private static void nameUnnamed(List<Volunteer_Shift__c> shifts) {
        List<Volunteer_Shift__c> unnamed = new List<Volunteer_Shift__c>();
        Set<Id> jobIds = new Set<Id>();
        for (Volunteer_Shift__c shift : shifts) {
            if (String.isBlank(shift.Name) && shift.Volunteer_Job__c != null) {
                unnamed.add(shift);
                jobIds.add(shift.Volunteer_Job__c);
            }
        }
        if (unnamed.isEmpty()) {
            return;
        }
        Map<Id, String> jobNames = VolunteerJobSelector.selectNamesByIds(jobIds);
        for (Volunteer_Shift__c shift : unnamed) {
            String jobName = jobNames.get(shift.Volunteer_Job__c);
            if (jobName == null) {
                continue;
            }
            String name = shift.Start_Time__c == null
                ? jobName
                : jobName + ': ' + shift.Start_Time__c.format(START_FORMAT);
            shift.Name = name.abbreviate(NAME_LENGTH);
        }
    }
}
