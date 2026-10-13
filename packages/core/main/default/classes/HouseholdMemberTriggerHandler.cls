/**
 * Household upkeep on membership changes, which is how people join and leave a
 * household in the flexible membership mode.
 *
 * Every path (added, changed, ended, removed, restored) recounts the households on both
 * sides of the change, rewrites their names and greetings, and tidies away a household
 * that has been left with nobody in it.
 */
public with sharing class HouseholdMemberTriggerHandler extends TriggerHandler {
    public override void afterInsert() {
        refresh(householdIds((List<Household_Member__c>) newRecords()), false);
    }

    public override void afterUpdate() {
        Set<Id> affected = householdIds((List<Household_Member__c>) newRecords());
        affected.addAll(householdIds((List<Household_Member__c>) oldRecords()));
        refresh(affected, true);
    }

    public override void afterDelete() {
        refresh(householdIds((List<Household_Member__c>) oldRecords()), true);
    }

    public override void afterUndelete() {
        refresh(householdIds((List<Household_Member__c>) newRecords()), false);
    }

    private static Set<Id> householdIds(List<Household_Member__c> records) {
        Set<Id> result = new Set<Id>();
        if (records == null) {
            return result;
        }
        for (Household_Member__c record : records) {
            if (record.Household__c != null) {
                result.add(record.Household__c);
            }
        }
        return result;
    }

    /**
     * One pass over the affected households, done in the one place that upkeep lives.
     */
    private static void refresh(Set<Id> householdIds, Boolean mayDelete) {
        HouseholdService.afterMembershipChange(householdIds, mayDelete);
    }
}
