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
     * itself, so that a household is recounted and renamed once, after the delete,
     * rather than in the middle of it. Rollups on membership rows are a different handler and
     * still run.
     */
    private static final String MEMBER_HANDLER = 'HouseholdMemberTriggerHandler';

    public override void beforeInsert() {
        HouseholdService.ensureHouseholds((List<Contact>) Trigger.new);
    }

    public override void beforeUpdate() {
        HouseholdService.refuseLeavingHouseholdsForOrganizations(
            (List<Contact>) Trigger.new,
            (Map<Id, Contact>) Trigger.oldMap
        );
    }

    public override void afterInsert() {
        // Junction mode first: a person saved into it with no household gets one here,
        // because the membership row that joins them to it needs an id the contact did not
        // have before insert (R-H2, ADR-0037). Contact mode did its half before insert, and
        // names the person the new household's Primary Contact here. A person saved against
        // a household in junction mode joins it first, so creation then leaves them alone.
        HouseholdService.joinHouseholdsNamedOnNewContacts((List<Contact>) Trigger.new);
        HouseholdService.createHouseholdsForNewContacts((List<Contact>) Trigger.new);
        HouseholdService.seedPrimaryContactsOfNewHouseholds((List<Contact>) Trigger.new);
        refresh(householdIds((List<Contact>) Trigger.new), false);
    }

    public override void afterUpdate() {
        Map<Id, Contact> previousById = (Map<Id, Contact>) Trigger.oldMap;
        Set<Id> affected = new Set<Id>();
        Set<Id> renamed = new Set<Id>();
        // In junction mode the account a contact points at is an employer, not a household,
        // so a change of account is not a change of household and is not settled here.
        Boolean accountIsHousehold = !HouseholdService.isJunctionMode();
        for (Contact record : (List<Contact>) Trigger.new) {
            Contact previous = previousById.get(record.Id);
            if (accountIsHousehold && record.AccountId != previous.AccountId) {
                add(affected, previous.AccountId);
                add(affected, record.AccountId);
            }
            // Checked on its own, so that a save that moves a person and corrects their
            // name in one go still renames the household they are in.
            if (namingChanged(record, previous)) {
                if (accountIsHousehold) {
                    add(affected, record.AccountId);
                }
                renamed.add(record.Id);
            }
        }
        // In junction mode the households to rewrite have to be read from the membership
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
     * A delete recounts and renames the households the people left, and never tidies one away,
     * even left empty (R-H12): deleting the household would purge the people, or their
     * membership rows, from the Recycle Bin, and neither an undelete nor a bulk delete undo
     * could bring them back.
     *
     * A merge is a delete the platform has filled `MasterRecordId` on, and it is handled so
     * that nothing is lost (C-20). The merged-away person's memberships go to the survivor
     * (junction mode). A household a merge leaves empty is kept for a person to merge into
     * the survivor's.
     */
    public override void afterDelete() {
        List<Contact> gone = (List<Contact>) Trigger.old;
        Set<Id> affected = departingHouseholdIds;
        departingHouseholdIds = new Set<Id>();
        List<Household_Member__c> removed = departingMemberships;
        departingMemberships = new List<Household_Member__c>();
        affected.addAll(householdIds(gone));

        Map<Id, Id> survivorByMerged = survivorsOf(gone);
        if (!survivorByMerged.isEmpty()) {
            AutomationControl.bypass(MEMBER_HANDLER);
            try {
                affected.addAll(
                    HouseholdService.moveMembershipsToSurvivors(removed, survivorByMerged)
                );
            } finally {
                AutomationControl.clearBypass(MEMBER_HANDLER);
            }
        }
        if (survivorByMerged.isEmpty()) {
            // A household this delete empties is stamped for the nightly tidy-up (R-H12a).
            HouseholdService.afterPeopleDeleted(affected);
        } else {
            refresh(affected, false);
        }
        if (!survivorByMerged.isEmpty()) {
            // The survivors' addresses, relationships and affiliations, once the merge is
            // saved (PEOPLE-15). Their households were settled above: none is in the merge.
            Set<Id> survivors = new Set<Id>(survivorByMerged.values());
            MergeSettlement.afterMerge(new Set<Id>(), survivors, survivors);
        }
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

    /**
     * Text is compared case-sensitively (`!=` on Strings ignores case in Apex), so that
     * correcting "Mcdonald" to "McDonald" renames the household and greetings too.
     */
    private static Boolean namingChanged(Contact record, Contact previous) {
        return textChanged(record.FirstName, previous.FirstName) ||
            textChanged(record.LastName, previous.LastName) ||
            textChanged(record.Salutation, previous.Salutation) ||
            textChanged(record.Preferred_Name__c, previous.Preferred_Name__c) ||
            record.Deceased__c != previous.Deceased__c ||
            record.Household_Role__c != previous.Household_Role__c ||
            record.Exclude_From_Household_Name__c != previous.Exclude_From_Household_Name__c ||
            record.Exclude_From_Greetings__c != previous.Exclude_From_Greetings__c;
    }

    private static Boolean textChanged(String now, String before) {
        return now == null ? before != null : !now.equals(before);
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
