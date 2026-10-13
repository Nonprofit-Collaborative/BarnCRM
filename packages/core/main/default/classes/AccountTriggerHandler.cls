/**
 * Household upkeep when a household or a person record changes.
 *
 * A new household is never left without a name. When someone clears the custom name box,
 * the household goes back to being named from the org's patterns. In an org that stores
 * people as accounts, a new person gets a household and a membership of it, and every
 * later change to that person settles the households they belong to up again: a rename, a
 * deletion, a restore from the recycle bin.
 *
 * The person half of this class is the account side of what `ContactTriggerHandler` does
 * for a person stored as a contact, and it watches the same fields. What differs is where
 * the household is written down. A contact carries its household on the record itself, so
 * the contact handler can read it in any context, and it survives the contact being
 * deleted and restored. A person stored as an account is joined to a household by a
 * `Household_Member__c` row instead, and the platform empties that row's person lookup
 * when the account is deleted and does not fill it in again when the account is restored.
 * So the delete work happens in `beforeDelete`, while the rows still say what they are
 * for, and only the settling up is left to `afterDelete`.
 *
 * A person stored as an account also has their standard email settled before the record is
 * written, so that it holds whichever of their three addresses they chose (R-C6).
 */
public with sharing class AccountTriggerHandler extends TriggerHandler {
    /**
     * The households the people currently being deleted are leaving. Filled in
     * `beforeDelete` and consumed in `afterDelete`, which is also where it is emptied
     * again: one DML of 400 records runs the pair twice, so each half has to hand over
     * only its own chunk.
     */
    private static Set<Id> departingHouseholdIds = new Set<Id>();

    /**
     * The membership rows the people being deleted had, read before they were removed. Only
     * a merge uses them: the platform says a delete was a merge (by filling `MasterRecordId`)
     * only after the delete, and by then the rows are gone (C-20, see `afterDelete`).
     */
    private static List<Household_Member__c> departingMemberships = new List<Household_Member__c>();

    /**
     * The membership handler, stood down while this handler removes and moves membership rows
     * itself, so that a household is recounted, renamed and tidied once, after the delete,
     * rather than in the middle of it.
     */
    private static final String MEMBER_HANDLER = 'HouseholdMemberTriggerHandler';

    private static final String CONTEXT = 'AccountTriggerHandler';

    public override void beforeInsert() {
        HouseholdService.refuseHandSetPrimaryContacts((List<Account>) newRecords(), null);
        nameNewHouseholds((List<Account>) newRecords());
        PreferredEmailService.applyToPersonRecords((List<Account>) newRecords());
    }

    public override void beforeUpdate() {
        HouseholdService.refuseHandSetPrimaryContacts(
            (List<Account>) newRecords(),
            (Map<Id, Account>) oldRecordsById()
        );
        nameNewHouseholds((List<Account>) newRecords());
        PreferredEmailService.applyToPersonRecords((List<Account>) newRecords());
    }

    public override void afterInsert() {
        createHouseholdsForNewPeople((List<Account>) newRecords());
    }

    public override void afterUpdate() {
        Map<Id, Account> previousById = (Map<Id, Account>) oldRecordsById();
        Boolean watchPeople = handlesPeople();
        Set<Id> released = new Set<Id>();
        List<Account> renamedPeople = new List<Account>();
        for (Account record : (List<Account>) newRecords()) {
            Account previous = previousById.get(record.Id);
            Boolean wasCustom = previous != null && previous.Custom_Name__c == true;
            if (wasCustom && record.Custom_Name__c != true) {
                released.add(record.Id);
            }
            if (watchPeople && PersonRecordSelector.namingChanged(record, previous)) {
                renamedPeople.add(record);
            }
        }
        // A household that Nonprofit Cloud manages natively keeps its name: applyNaming
        // leaves it alone (mutual exclusion, product-plan Section 11.2 item 9).
        HouseholdNamingService.applyNaming(released);
        // R-H4 and R-H11. A person renamed, marked deceased, given a preferred name, moved
        // to another household role or excluded from the wording changes what every
        // household they belong to is called.
        HouseholdService.afterMembershipChange(householdIdsOf(renamedPeople), true);
    }

    /**
     * Takes the memberships of the people being deleted with them, while the rows still
     * say whose memberships they are, and remembers the households that affects.
     *
     * `Household_Member__c.Account__c` empties itself when the account it points at is
     * deleted, so by `afterDelete` the row no longer names anybody: the household it
     * belongs to cannot be worked out from it, and it cannot be put back either, because
     * the platform does not restore a lookup it emptied that way when the record comes
     * back out of the recycle bin. Removing the rows here, first, is what makes both the
     * delete and the undelete paths work.
     */
    public override void beforeDelete() {
        Set<Id> personIds = personIdsOf((List<Account>) oldRecords());
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
     * empty where the org asks for that (R-H12).
     *
     * A merge is a delete the platform has filled `MasterRecordId` on, and it is handled as
     * it is for a person stored as a contact (C-20). The merged-away person's memberships go
     * to the survivor, a household keeps its primary member, and a household the
     * merged-away person was in is never tidied away by the merge: gifts, notes and history
     * credited to it would lose their household. The survivors' real-time totals are then
     * recalculated, for the survivors only.
     */
    public override void afterDelete() {
        List<Account> gone = (List<Account>) oldRecords();
        Set<Id> affected = departingHouseholdIds;
        departingHouseholdIds = new Set<Id>();
        List<Household_Member__c> removed = departingMemberships;
        departingMemberships = new List<Household_Member__c>();

        Map<Id, Id> survivorByMerged = survivorsOf(gone);
        Set<Id> keptByMerge = new Set<Id>();
        if (!survivorByMerged.isEmpty()) {
            keptByMerge = householdsOfMerged(removed, survivorByMerged.keySet());
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
        HouseholdService.afterMembershipChange(mayTidy, true);
        HouseholdService.afterMembershipChange(keptByMerge, false);
        recalculateSurvivors(gone, survivorByMerged);
        settleSurvivors(gone, survivorByMerged);
    }

    /**
     * What the merge moved onto the survivors without running their children's triggers,
     * settled once the merge is saved (PEOPLE-15, MergeSettlement): a household that took in
     * another household's members is recounted and renamed, every survivor keeps one default
     * address, and a surviving person's relationships and primary affiliation are settled.
     */
    private static void settleSurvivors(List<Account> gone, Map<Id, Id> survivorByMerged) {
        if (survivorByMerged.isEmpty()) {
            return;
        }
        // People in either membership mode: relationships and affiliations do not depend on it.
        Set<Id> mergedPeople = new Set<Id>();
        if (HouseholdService.isPersonAccountOrg()) {
            mergedPeople = new Map<Id, SObject>(PersonRecordSelector.filterPeople(gone)).keySet();
        }
        Id householdType = HouseholdService.householdRecordTypeId();
        Set<Id> households = new Set<Id>();
        Set<Id> people = new Set<Id>();
        for (Account record : gone) {
            Id survivorId = survivorByMerged.get(record.Id);
            if (survivorId == null) {
                continue;
            }
            if (mergedPeople.contains(record.Id)) {
                people.add(survivorId);
            } else if (householdType != null && record.RecordTypeId == householdType) {
                households.add(survivorId);
            }
        }
        MergeSettlement.afterMerge(households, new Set<Id>(survivorByMerged.values()), people);
    }

    /**
     * A person restored from the recycle bin gets their memberships back, and the
     * households they have rejoined are recounted and renamed. Never tidied away here:
     * nobody has left.
     */
    public override void afterUndelete() {
        Set<Id> personIds = personIdsOf((List<Account>) newRecords());
        Set<Id> affected = HouseholdService.restoreMembershipsFor(personIds);
        affected.addAll(HouseholdService.householdIdsForPeople(personIds));
        HouseholdService.afterMembershipChange(affected, false);
    }

    /** The survivor of each of these records that was deleted by a merge. */
    private static Map<Id, Id> survivorsOf(List<Account> records) {
        Map<Id, Id> result = new Map<Id, Id>();
        for (Account record : records) {
            if (record.MasterRecordId != null) {
                result.put(record.Id, record.MasterRecordId);
            }
        }
        return result;
    }

    /** Every household the merged-away people were members of. */
    private static Set<Id> householdsOfMerged(
        List<Household_Member__c> removed,
        Set<Id> mergedIds
    ) {
        Set<Id> result = new Set<Id>();
        for (Household_Member__c row : removed) {
            if (mergedIds.contains(row.Account__c) && row.Household__c != null) {
                result.add(row.Household__c);
            }
        }
        return result;
    }

    /**
     * The real-time totals on the survivors of an account merge, recalculated for the
     * survivors only (C-20). A merged household or organization has its own totals; a
     * merged person stored as an account also has the totals on the contact the platform
     * keeps behind it, which the merge changes too, so the survivors' person contacts are
     * recalculated as well. A failure is logged and never fails the merge: the nightly run
     * puts a total right, as for every rollup.
     */
    private static void recalculateSurvivors(List<Account> gone, Map<Id, Id> survivorByMerged) {
        if (survivorByMerged.isEmpty()) {
            return;
        }
        try {
            RollupService.runAfterMerge(String.valueOf(Account.SObjectType), gone);
            Set<Id> survivingPeople = new Set<Id>();
            if (handlesPeople()) {
                Set<Id> mergedPeople = personIdsOf(gone);
                for (Id mergedId : survivorByMerged.keySet()) {
                    if (mergedPeople.contains(mergedId)) {
                        survivingPeople.add(survivorByMerged.get(mergedId));
                    }
                }
            }
            if (!survivingPeople.isEmpty()) {
                RollupService.runForSurvivors(
                    String.valueOf(Contact.SObjectType),
                    new Set<Id>(PersonRecordSelector.getPersonContactIds(survivingPeople).values())
                );
            }
        } catch (Exception failed) {
            ErrorLogger.log(failed, CONTEXT);
        }
    }

    /**
     * True when this org keeps people on the account object and joins them to households
     * with membership rows. Asked once per context rather than once per record.
     */
    private static Boolean handlesPeople() {
        return HouseholdService.isPersonAccountOrg() && HouseholdService.isJunctionMode();
    }

    /**
     * The people among these records. A record that holds an organization or a household
     * rather than a person is left out, and on an org that does not keep people as
     * accounts the answer is empty without anything being read.
     */
    private static Set<Id> personIdsOf(List<Account> records) {
        Set<Id> result = new Set<Id>();
        if (records == null || records.isEmpty() || !handlesPeople()) {
            return result;
        }
        for (SObject person : PersonRecordSelector.filterPeople(records)) {
            if (person.Id != null) {
                result.add(person.Id);
            }
        }
        return result;
    }

    /**
     * The households every person among these records belongs to.
     */
    private static Set<Id> householdIdsOf(List<Account> records) {
        return HouseholdService.householdIdsForPeople(personIdsOf(records));
    }

    /**
     * A household saved with no name gets a placeholder rather than a save error. The
     * naming service replaces it as soon as the household has a member.
     */
    private static void nameNewHouseholds(List<Account> records) {
        Id recordTypeId = HouseholdService.householdRecordTypeId();
        if (recordTypeId == null) {
            return;
        }
        for (Account record : records) {
            Boolean isHousehold = record.RecordTypeId == recordTypeId;
            if (isHousehold && record.Custom_Name__c != true && String.isBlank(record.Name)) {
                record.Name = Label.Core_Households_NamePlaceholder;
            }
        }
    }

    /**
     * R-H2. Only in an org that stores people as accounts, only in junction mode, and only
     * when automatic household creation is on.
     *
     * That is the same setting a person stored as a contact is given a household by
     * (ADR-0037). The separate person account setting this used to read is retired: it
     * shipped off, so an org that took the recommended setup got no households at all and
     * was told nothing about it.
     */
    private static void createHouseholdsForNewPeople(List<Account> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        if (!handlesPeople()) {
            return;
        }
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        if (settings == null || settings.Auto_Create_Households__c != true) {
            return;
        }
        List<SObject> people = PersonRecordSelector.filterPeople(records);
        if (people.isEmpty()) {
            return;
        }
        // HouseholdService guards its own creation pass against the saves it makes coming
        // back round through this trigger (ADR-0037).
        HouseholdService.createHouseholdsForPersonAccounts(people);
    }
}
