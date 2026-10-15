/**
 * The nightly empty household tidy-up (canonical model R-H12a, ADR-0120, decision D-89): moves
 * to the Recycle Bin each household that deleting people left empty, once those people can no
 * longer be restored, and only when nothing else points at the household.
 *
 * A candidate is a household stamped `Emptied_By_Deletion__c` by the settle-up after a person
 * delete. It is kept, and asked about again next night, while any Contact whose Account was the
 * household or any Household Member row naming it is still in the Recycle Bin: those are the
 * records a delete of the household would purge (D-88), so while one is there the people could
 * still be restored. Both are read in every membership mode.
 *
 * It is kept for good, and stays on Health Check's and Data Hygiene's lists of households
 * without members, while a record of any object points at it through a child relationship of
 * Account (read by describe, so Core names no module object), a membership row names a person
 * who still exists, an installed module credits records to it (ADR-0070), or something outside
 * BarnCRM depends on it (ADR-0036). Three of Core's own lookups are the household's own records
 * rather than dependents: its addresses (moved to the Recycle Bin with it, in the same
 * transaction), the import rows that created it (an audit record whose lookup clears), and
 * membership rows whose person is gone (they cascade). A relationship that cannot be read keeps
 * every household in the chunk and is logged by name: not being able to answer is not
 * answering no.
 *
 * The households are the package's own and the job runs as whoever scheduled it, so the reads
 * and the deletes are in system mode and without sharing: a tidy-up that skipped what its
 * scheduler cannot see would decide "nothing points at it" on records it never saw (ADR-0021).
 * Every delete is a soft delete, so a household removed by mistake comes back from the bin.
 */
public without sharing class EmptyHouseholdTidyBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** Households per chunk: keeps the one-row-per-relationship probe well inside the limits. */
    public static final Integer CHUNK_SIZE = 100;

    private static final String LOG_CONTEXT = 'EmptyHouseholdTidyBatch';

    /** Child relationship subqueries per probe query. */
    private static final Integer SUBQUERIES_PER_QUERY = 10;

    /**
     * Child objects that are the household's own bookkeeping, not records depending on it.
     * `RecordActionHistory` (a History) also matters for another reason: it is stored as a big
     * object, and a subquery on it with real rows ends the transaction with a platform fault no
     * catch can handle (found on `oi-test`). Big objects (`__b`) are skipped for the same reason.
     */
    private static final List<String> BOOKKEEPING_SUFFIXES = new List<String>{
        'Share',
        'History',
        'Feed',
        '__b'
    };
    private static final Set<String> BOOKKEEPING_OBJECTS = new Set<String>{
        'FeedItem',
        'FeedComment',
        'EntitySubscription'
    };

    /**
     * Core's own lookups to Account that are part of the household rather than dependents on
     * it, identified by field. Membership rows are read on their own (`withLivingMembers`).
     */
    private static final Set<Schema.SObjectField> OWN_RECORDS = new Set<Schema.SObjectField>{
        Address__c.Account__c,
        Import_Row__c.Household__c,
        Household_Member__c.Household__c
    };

    /** Set by a test to probe these relationship names instead of every child relationship. */
    @TestVisible
    private static List<String> relationshipsOverride;

    private static List<String> cachedRelationships;

    /**
     * Set by a test to the records it emptied from the Recycle Bin. In a test, and for a while
     * after `emptyRecycleBin` in an org, `ALL ROWS` still returns a purged record until the
     * platform removes it physically; the tidy-up simply waits for that, a test cannot.
     */
    @TestVisible
    private static Set<Id> purgedForTest = new Set<Id>();

    /** Households moved to the Recycle Bin, across chunks. */
    @TestVisible
    private Integer removed = 0;

    /** Households kept because something still points at them, across chunks. */
    @TestVisible
    private Integer keptWithDependents = 0;

    /** Households kept because a former member is still in the Recycle Bin, across chunks. */
    @TestVisible
    private Integer keptForRecycleBin = 0;

    /** Relationships already logged as unreadable in this run, so each is logged once. */
    private Set<String> unreadableLogged = new Set<String>();

    public Database.QueryLocator start(Database.BatchableContext context) {
        Id householdType = HouseholdService.householdRecordTypeId();
        Boolean tidies = householdType != null && !keepsHouseholds();
        String soql = tidies
            ? 'SELECT Id FROM Account WHERE Emptied_By_Deletion__c != null AND RecordTypeId = :householdType'
            : 'SELECT Id FROM Account WHERE Id = null';
        return Database.getQueryLocatorWithBinds(
            soql,
            new Map<String, Object>{ 'householdType' => householdType },
            AccessLevel.SYSTEM_MODE
        );
    }

    public void execute(Database.BatchableContext context, List<Account> scope) {
        if (keepsHouseholds()) {
            return;
        }
        Set<Id> candidates = new Map<Id, Account>(scope).keySet();
        Set<Id> inRecycleBin = withFormerMembersInRecycleBin(candidates);
        keptForRecycleBin += inRecycleBin.size();

        Set<Id> remaining = new Set<Id>(candidates);
        remaining.removeAll(inRecycleBin);
        Set<Id> dependent = withDependents(remaining);
        keptWithDependents += dependent.size();
        remaining.removeAll(dependent);

        removeHouseholds(remaining);
    }

    public void finish(Database.BatchableContext context) {
        // A scheduled run notifies nobody (Job_Notifications__c), so the counts go to the log.
        System.debug(
            LoggingLevel.INFO,
            LOG_CONTEXT +
                ': removed ' +
                removed +
                ', kept with dependents ' +
                keptWithDependents +
                ', kept while former members are in the Recycle Bin ' +
                keptForRecycleBin
        );
    }

    /**
     * True when the org keeps the households of deleted people (R-H12a), or when household
     * upkeep is off (ADR-0124): a feature that is off does no work, nightly jobs included.
     */
    private static Boolean keepsHouseholds() {
        if (!FeatureSwitchService.isOn(FeatureSwitchService.HOUSEHOLD_UPKEEP)) {
            return true;
        }
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings != null && settings.Keep_Households_Of_Deleted_People__c == true;
    }

    /**
     * Of these households, those a delete would purge a restorable record from: a deleted
     * Contact whose Account is the household, or a deleted membership row naming it. Both
     * fields survive a soft delete, and both are read whatever the membership mode is now.
     */
    private static Set<Id> withFormerMembersInRecycleBin(Set<Id> householdIds) {
        Set<Id> found = new Set<Id>();
        for (Contact person : [
            SELECT Id, AccountId
            FROM Contact
            WHERE IsDeleted = TRUE AND AccountId IN :householdIds
            WITH SYSTEM_MODE
            ALL ROWS
        ]) {
            if (!purgedForTest.contains(person.Id)) {
                found.add(person.AccountId);
            }
        }
        for (Household_Member__c membership : [
            SELECT Id, Household__c
            FROM Household_Member__c
            WHERE IsDeleted = TRUE AND Household__c IN :householdIds
            WITH SYSTEM_MODE
            ALL ROWS
        ]) {
            if (!purgedForTest.contains(membership.Id)) {
                found.add(membership.Household__c);
            }
        }
        return found;
    }

    /**
     * Of these households, those anything still points at: a record in a child relationship
     * of Account other than the household's own records, a membership row of a person who
     * still exists, a record an installed module credits to it, or a dependent outside
     * BarnCRM.
     */
    private Set<Id> withDependents(Set<Id> householdIds) {
        Set<Id> dependent = new Set<Id>();
        if (householdIds.isEmpty()) {
            return dependent;
        }
        dependent.addAll(withLivingMembers(householdIds));
        dependent.addAll(withChildRecords(householdIds));
        dependent.addAll(HouseholdSelector.getAccountsWithNativeDependents(householdIds));
        dependent.addAll(HouseholdDependentsExtensions.householdsWithDependents(householdIds));
        dependent.retainAll(householdIds);
        return dependent;
    }

    /**
     * Of these households, those with a membership row, current or ended, naming a person who
     * still exists: deleting the household would cascade that person's history away. A row
     * whose person was deleted names nobody (the platform clears the lookup), and goes with
     * the household. An erased person is anonymized in place, not deleted (R-ER3), so their
     * ended row keeps the household.
     */
    private static Set<Id> withLivingMembers(Set<Id> householdIds) {
        Set<Id> found = new Set<Id>();
        for (Household_Member__c membership : [
            SELECT Household__c
            FROM Household_Member__c
            WHERE Household__c IN :householdIds AND (Contact__c != NULL OR Account__c != NULL)
            WITH SYSTEM_MODE
        ]) {
            found.add(membership.Household__c);
        }
        return found;
    }

    /** Of these households, those with a record in any dependent child relationship. */
    private Set<Id> withChildRecords(Set<Id> householdIds) {
        Set<Id> found = new Set<Id>();
        List<String> pending = new List<String>();
        for (String relationship : dependentRelationships()) {
            pending.add(relationship);
            if (pending.size() == SUBQUERIES_PER_QUERY) {
                found.addAll(probe(pending, householdIds));
                pending = new List<String>();
            }
        }
        if (!pending.isEmpty()) {
            found.addAll(probe(pending, householdIds));
        }
        return found;
    }

    /**
     * One query for a group of relationships; when it cannot run, each relationship on its
     * own, so one unreadable relationship does not hide the others. Each relationship that
     * cannot be read is logged by name, once a run, and keeps every household in the chunk.
     */
    private Set<Id> probe(List<String> relationships, Set<Id> householdIds) {
        try {
            return childRecordsIn(relationships, householdIds);
        } catch (Exception groupFailed) {
            Set<Id> found = new Set<Id>();
            for (String relationship : relationships) {
                try {
                    found.addAll(childRecordsIn(new List<String>{ relationship }, householdIds));
                } catch (Exception unreadable) {
                    found.addAll(householdIds);
                    if (unreadableLogged.add(relationship)) {
                        ErrorLogger.logMessage(
                            String.format(
                                System.Label.Core_Households_TidyProbeFailed,
                                new List<String>{ relationship, unreadable.getMessage() }
                            ),
                            LOG_CONTEXT,
                            ErrorLogger.SEVERITY_WARNING
                        );
                    }
                }
            }
            return found;
        }
    }

    private static Set<Id> childRecordsIn(List<String> relationships, Set<Id> householdIds) {
        List<String> subqueries = new List<String>();
        for (String relationship : relationships) {
            subqueries.add('(SELECT Id FROM ' + relationship + ' LIMIT 1)');
        }
        String soql =
            'SELECT Id, ' +
            String.join(subqueries, ', ') +
            ' FROM Account WHERE Id IN :householdIds';
        Set<Id> found = new Set<Id>();
        for (
            Account household : (List<Account>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'householdIds' => householdIds },
                AccessLevel.SYSTEM_MODE
            )
        ) {
            // Read what came back rather than asking by name: a person account org answers some
            // relationships under another name than the one queried (PersonAssets as Assets).
            for (Object value : household.getPopulatedFieldsAsMap().values()) {
                if (value instanceof List<SObject> && !((List<SObject>) value).isEmpty()) {
                    found.add(household.Id);
                    break;
                }
            }
        }
        return found;
    }

    /**
     * Every child relationship of Account whose records depend on the household: those with a
     * name, on a queryable object, that are neither the household's own bookkeeping nor one of
     * Core's own records of the household (`OWN_RECORDS`).
     */
    @TestVisible
    private static List<String> dependentRelationships() {
        if (relationshipsOverride != null) {
            return relationshipsOverride;
        }
        if (cachedRelationships != null) {
            return cachedRelationships;
        }
        List<String> names = new List<String>();
        Set<String> seen = new Set<String>();
        for (
            Schema.ChildRelationship relationship : Account.SObjectType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .getChildRelationships()
        ) {
            String name = relationship.getRelationshipName();
            if (
                name == null ||
                relationship.isDeprecatedAndHidden() ||
                seen.contains(name) ||
                OWN_RECORDS.contains(relationship.getField())
            ) {
                continue;
            }
            Schema.DescribeSObjectResult child = relationship.getChildSObject()
                .getDescribe(SObjectDescribeOptions.DEFERRED);
            if (!child.isQueryable() || isBookkeeping(child.getName())) {
                continue;
            }
            seen.add(name);
            names.add(name);
        }
        cachedRelationships = names;
        return names;
    }

    @TestVisible
    private static Boolean isBookkeeping(String objectName) {
        if (BOOKKEEPING_OBJECTS.contains(objectName)) {
            return true;
        }
        for (String suffix : BOOKKEEPING_SUFFIXES) {
            if (objectName.endsWith(suffix)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Soft deletes these households, each with its addresses, so no address is left without an
     * owner. The addresses go first, so a household that cannot be deleted gets them back. (The
     * platform still clears the lookup of an address already in the Recycle Bin when its
     * household follows, so restoring both means re-linking by hand.) A refusal is one Error
     * Log entry per chunk.
     */
    private void removeHouseholds(Set<Id> householdIds) {
        if (householdIds.isEmpty()) {
            return;
        }
        List<Address__c> addresses = [
            SELECT Id, Account__c
            FROM Address__c
            WHERE Account__c IN :householdIds
            WITH SYSTEM_MODE
        ];
        List<String> failures = new List<String>();
        Set<Id> addressesRefused = new Set<Id>();
        if (!addresses.isEmpty()) {
            List<Database.DeleteResult> addressResults = Database.delete(
                addresses,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Integer i = 0; i < addressResults.size(); i++) {
                if (!addressResults[i].isSuccess()) {
                    addressesRefused.add(addresses[i].Account__c);
                    failures.add(addresses[i].Id + ': ' + firstError(addressResults[i]));
                }
            }
        }
        List<Account> households = new List<Account>();
        for (Id householdId : householdIds) {
            if (!addressesRefused.contains(householdId)) {
                households.add(new Account(Id = householdId));
            }
        }
        Set<Id> kept = new Set<Id>(addressesRefused);
        List<Database.DeleteResult> results = Database.delete(
            households,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                removed++;
            } else {
                kept.add(households[i].Id);
                failures.add(households[i].Id + ': ' + firstError(results[i]));
            }
        }
        restoreAddressesOf(kept, addresses);
        if (!failures.isEmpty()) {
            ErrorLogger.logMessage(
                String.format(
                    System.Label.Core_Households_TidyNotRemoved,
                    new List<String>{ String.valueOf(failures.size()), failures[0] }
                ),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
    }

    /** Puts back the addresses of households that stay, so none is left without its addresses. */
    private static void restoreAddressesOf(Set<Id> keptHouseholds, List<Address__c> addresses) {
        List<Address__c> restoring = new List<Address__c>();
        for (Address__c address : addresses) {
            if (keptHouseholds.contains(address.Account__c)) {
                restoring.add(address);
            }
        }
        if (!restoring.isEmpty()) {
            Database.undelete(restoring, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static String firstError(Database.DeleteResult result) {
        return result.getErrors().isEmpty() ? '' : result.getErrors()[0].getMessage();
    }
}
