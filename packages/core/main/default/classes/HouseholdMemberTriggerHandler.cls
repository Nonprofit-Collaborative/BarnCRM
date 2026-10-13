/**
 * Household upkeep on membership changes, which is how people join and leave a
 * household in the flexible membership mode.
 *
 * Every path (added, changed, ended, removed, restored) recounts the households on both
 * sides of the change, rewrites their names and greetings, and tidies away a household
 * that has been left with nobody in it.
 *
 * Before the save, a row that would make a person a current member of a household they are
 * already a current member of is refused (R-M6), so a hand-made or loaded row cannot count
 * one person twice in a household's count and name.
 */
public with sharing class HouseholdMemberTriggerHandler extends TriggerHandler {
    public override void beforeInsert() {
        refuseSecondCurrentMemberships((List<Household_Member__c>) Trigger.new, null);
    }

    public override void beforeUpdate() {
        refuseSecondCurrentMemberships(
            (List<Household_Member__c>) Trigger.new,
            (Map<Id, Household_Member__c>) Trigger.oldMap
        );
    }

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
     * R-M6. Only rows that become a current membership of a person in a household are
     * checked: a new current row, or an edit that changes the person or the household or
     * brings an ended row back. Any other edit (a role, the primary flag, an end date) of a
     * row that already shares a household with a duplicate a platform merge left behind is
     * let through, so tidying that up is never blocked. One read, in system mode under
     * ADR-0021: a duplicate the user cannot see still counts the person twice.
     */
    private static void refuseSecondCurrentMemberships(
        List<Household_Member__c> records,
        Map<Id, Household_Member__c> previousById
    ) {
        Date today = Date.today();
        List<Household_Member__c> checked = new List<Household_Member__c>();
        Set<Id> personIds = new Set<Id>();
        for (Household_Member__c record : records) {
            Id personId = personOf(record);
            if (personId == null || record.Household__c == null || !isCurrent(record, today)) {
                continue;
            }
            Household_Member__c previous = previousById == null
                ? null
                : previousById.get(record.Id);
            Boolean becomesCurrentMembership =
                previous == null ||
                personOf(previous) != personId ||
                previous.Household__c != record.Household__c ||
                !isCurrent(previous, today);
            if (becomesCurrentMembership) {
                checked.add(record);
                personIds.add(personId);
            }
        }
        if (checked.isEmpty()) {
            return;
        }
        Set<String> taken = new Set<String>();
        for (Household_Member__c existing : HouseholdSelector.getMembershipsForPeople(personIds)) {
            if (
                existing.Household__c != null &&
                (previousById == null || !previousById.containsKey(existing.Id))
            ) {
                taken.add(existing.Household__c + ':' + personOf(existing));
            }
        }
        if (previousById != null) {
            // The other rows in this same save count as they will be after it, not as they were.
            Set<Id> checkedIds = new Map<Id, Household_Member__c>(checked).keySet();
            for (Household_Member__c record : records) {
                if (
                    !checkedIds.contains(record.Id) &&
                    personOf(record) != null &&
                    isCurrent(record, today)
                ) {
                    taken.add(record.Household__c + ':' + personOf(record));
                }
            }
        }
        for (Household_Member__c record : checked) {
            String key = record.Household__c + ':' + personOf(record);
            if (taken.contains(key)) {
                record.addError(Label.Core_Households_ErrorAlreadyCurrentMember);
            } else {
                taken.add(key);
            }
        }
    }

    private static Id personOf(Household_Member__c record) {
        return record.Contact__c != null ? record.Contact__c : record.Account__c;
    }

    private static Boolean isCurrent(Household_Member__c record, Date today) {
        return record.End_Date__c == null || record.End_Date__c > today;
    }

    /**
     * One pass over the affected households, done in the one place that upkeep lives.
     */
    private static void refresh(Set<Id> householdIds, Boolean mayDelete) {
        HouseholdService.afterMembershipChange(householdIds, mayDelete);
    }
}
