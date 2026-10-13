/**
 * Household upkeep when a person changes.
 *
 * A person with no household gets one: before insert in contact mode, where the household
 * is a reference on the contact, and after insert in junction mode, where it is a
 * membership row that needs the person's id. After every change the households the person
 * came from and went to are recounted, renamed, and, when they have been left empty and
 * the org asks for it, deleted.
 *
 * The person's standard email is settled here too, before the record is written, so that
 * it holds whichever of their three addresses they chose (R-C6).
 */
public with sharing class ContactTriggerHandler extends TriggerHandler {
    /**
     * The households these people were leaving, worked out before their contact records
     * went and carried across to after they are gone.
     *
     * `Household_Member__c.Contact__c` empties itself when the contact it points at is
     * deleted, so by `afterDelete` the row no longer names anybody: the household it
     * belongs to cannot be worked out from it, and it cannot be put back either, because
     * the platform does not restore a lookup it emptied that way. Removing the rows in
     * `beforeDelete`, while they still name the person, is what makes both the delete and
     * the undelete paths work. This mirrors `AccountTriggerHandler`, which has always done
     * it for a person stored as an account.
     */
    private static Set<Id> departingHouseholdIds = new Set<Id>();

    /**
     * The membership rows those people had, read before they were removed. Only a merge uses
     * them: the platform says a delete was a merge (by filling `MasterRecordId`) only after
     * the delete, and by then the rows are gone (C-20, see `afterDelete`).
     */
    private static List<Household_Member__c> departingMemberships = new List<Household_Member__c>();

    /**
     * The membership handler, stood down while this handler removes and moves membership rows
     * itself, so that a household is recounted, renamed and tidied once, after the delete,
     * rather than in the middle of it. Rollups on membership rows are a different handler and
     * still run.
     */
    private static final String MEMBER_HANDLER = 'HouseholdMemberTriggerHandler';

    public override void beforeInsert() {
        HouseholdService.ensureHouseholds((List<Contact>) Trigger.new);
    }

    public override void afterInsert() {
        // Junction mode first: a person saved into it with no household gets one here,
        // because the membership row that joins them to it needs an id the contact did not
        // have before insert (R-H2, ADR-0037). Contact mode did its half before insert.
        HouseholdService.createHouseholdsForNewContacts((List<Contact>) Trigger.new);
        refresh(householdIds((List<Contact>) Trigger.new), false);
    }

    public override void afterUpdate() {
        Map<Id, Contact> previousById = (Map<Id, Contact>) Trigger.oldMap;
        Set<Id> affected = new Set<Id>();
        Set<Id> renamed = new Set<Id>();
        for (Contact record : (List<Contact>) Trigger.new) {
            Contact previous = previousById.get(record.Id);
            Boolean moved = record.AccountId != previous.AccountId;
            if (moved) {
                add(affected, previous.AccountId);
                add(affected, record.AccountId);
            } else if (namingChanged(record, previous)) {
                add(affected, record.AccountId);
                renamed.add(record.Id);
            }
        }
        // In junction mode the account a contact points at is an employer, not their
        // household, so the households to rewrite have to be read from the membership
        // rows. Answers empty in contact mode, where the loop above already has them.
        affected.addAll(HouseholdService.householdIdsForPeople(renamed));
        refresh(affected, true);
    }

    /**
     * Membership rows are taken away while they still name the person, so that the
     * households they were in can be recounted after, and so that undelete can put them
     * back. Does nothing in contact mode, where there are no membership rows.
     */
    public override void beforeDelete() {
        Set<Id> personIds = personIdsOf((List<Contact>) Trigger.old);
        departingMemberships = HouseholdService.membershipsFor(personIds);
        AutomationControl.bypass(MEMBER_HANDLER);
        try {
            departingHouseholdIds = HouseholdService.removeMembershipsFor(personIds);
        } finally {
            AutomationControl.clearBypass(MEMBER_HANDLER);
        }
    }

    /**
     * A delete recounts and renames the households the people left, and tidies away one left
     * empty where the org asks for that.
     *
     * A merge is a delete the platform has filled `MasterRecordId` on, and it is handled so
     * that nothing is lost (C-20). The merged-away person's memberships go to the survivor
     * (junction mode), and a household the merged-away person was in is never tidied away by
     * the merge: gifts, notes and history credited to it would lose their household. A
     * household a merge leaves empty is kept for a person to merge into the survivor's.
     */
    public override void afterDelete() {
        List<Contact> gone = (List<Contact>) Trigger.old;
        Set<Id> affected = departingHouseholdIds;
        departingHouseholdIds = new Set<Id>();
        List<Household_Member__c> removed = departingMemberships;
        departingMemberships = new List<Household_Member__c>();
        affected.addAll(householdIds(gone));

        Map<Id, Id> survivorByMerged = survivorsOf(gone);
        Set<Id> keptByMerge = new Set<Id>();
        if (!survivorByMerged.isEmpty()) {
            keptByMerge = householdsOfMerged(gone, removed, survivorByMerged.keySet());
            AutomationControl.bypass(MEMBER_HANDLER);
            try {
                affected.addAll(
                    HouseholdService.moveMembershipsToSurvivors(removed, survivorByMerged)
                );
            } finally {
                AutomationControl.clearBypass(MEMBER_HANDLER);
            }
        }
        Set<Id> mayTidy = new Set<Id>(affected);
        mayTidy.removeAll(keptByMerge);
        refresh(mayTidy, true);
        refresh(keptByMerge, false);
    }

    /**
     * A person restored from the recycle bin gets their memberships back, and the
     * households they have rejoined are recounted and renamed. Never tidied away here:
     * nobody has left.
     */
    public override void afterUndelete() {
        Set<Id> personIds = personIdsOf((List<Contact>) Trigger.new);
        Set<Id> affected = HouseholdService.restoreMembershipsFor(personIds);
        affected.addAll(HouseholdService.householdIdsForPeople(personIds));
        affected.addAll(householdIds((List<Contact>) Trigger.new));
        refresh(affected, false);
    }

    /** The survivor of each of these records that was deleted by a merge. */
    private static Map<Id, Id> survivorsOf(List<Contact> records) {
        Map<Id, Id> result = new Map<Id, Id>();
        for (Contact record : records) {
            if (record.MasterRecordId != null) {
                result.put(record.Id, record.MasterRecordId);
            }
        }
        return result;
    }

    /** Every household the merged-away people were in, by reference or by membership. */
    private static Set<Id> householdsOfMerged(
        List<Contact> records,
        List<Household_Member__c> removed,
        Set<Id> mergedIds
    ) {
        Set<Id> result = new Set<Id>();
        for (Contact record : records) {
            if (mergedIds.contains(record.Id)) {
                add(result, record.AccountId);
            }
        }
        for (Household_Member__c row : removed) {
            Id personId = row.Contact__c != null ? row.Contact__c : row.Account__c;
            if (mergedIds.contains(personId)) {
                add(result, row.Household__c);
            }
        }
        return result;
    }

    private static Boolean namingChanged(Contact record, Contact previous) {
        return record.FirstName != previous.FirstName ||
            record.LastName != previous.LastName ||
            record.Salutation != previous.Salutation ||
            record.Preferred_Name__c != previous.Preferred_Name__c ||
            record.Deceased__c != previous.Deceased__c ||
            record.Household_Role__c != previous.Household_Role__c ||
            record.Exclude_From_Household_Name__c != previous.Exclude_From_Household_Name__c ||
            record.Exclude_From_Greetings__c != previous.Exclude_From_Greetings__c;
    }

    private static Set<Id> householdIds(List<Contact> records) {
        Set<Id> result = new Set<Id>();
        for (Contact record : records) {
            add(result, record.AccountId);
        }
        return result;
    }

    /**
     * The ids of these people. The membership calls that read them answer empty outside
     * junction mode, so this is handed over without asking which mode the org is in.
     */
    private static Set<Id> personIdsOf(List<Contact> records) {
        Set<Id> result = new Set<Id>();
        if (records == null) {
            return result;
        }
        for (Contact record : records) {
            add(result, record.Id);
        }
        return result;
    }

    private static void add(Set<Id> target, Id value) {
        if (value != null) {
            target.add(value);
        }
    }

    /**
     * One pass over the affected households, done in the one place that upkeep lives.
     */
    private static void refresh(Set<Id> householdIds, Boolean mayDelete) {
        HouseholdService.afterMembershipChange(householdIds, mayDelete);
    }
}
