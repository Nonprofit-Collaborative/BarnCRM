/**
 * The nightly empty household tidy-up (canonical model R-H12a, ADR-NEXT, decision D-89): moves
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
 * without members, while any record of any object points at it through a child relationship of
 * Account (read by describe, so Core names no module object), an installed module credits
 * records to it (ADR-0070), or something outside BarnCRM depends on it (ADR-0036). A
 * relationship that cannot be read keeps every household in the chunk: not being able to answer
 * is not answering no.
 *
 * The households are the package's own and the job runs as whoever scheduled it, so the reads
 * and the delete are in system mode and without sharing: a tidy-up that skipped what its
 * scheduler cannot see would decide "nothing points at it" on records it never saw (ADR-0021).
 * The delete is a soft delete, so a household removed by mistake comes back from the bin.
 */
public without sharing class EmptyHouseholdTidyBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** Households per chunk: keeps the one-row-per-relationship probe well inside the limits. */
    public static final Integer CHUNK_SIZE = 100;

    private static final String LOG_CONTEXT = 'EmptyHouseholdTidyBatch';

    /** Child relationship subqueries per probe query. */
    private static final Integer SUBQUERIES_PER_QUERY = 10;

    /** Child objects that are the household's own bookkeeping, not records depending on it. */
    private static final List<String> BOOKKEEPING_SUFFIXES = new List<String>{
        'Share',
        'History',
        'Feed'
    };
    private static final Set<String> BOOKKEEPING_OBJECTS = new Set<String>{
        'FeedItem',
        'FeedComment',
        'EntitySubscription'
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

    /** Whether a relationship that could not be read has been logged in this run. */
    private Boolean probeFailureLogged = false;

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

    /** True when the org keeps the households of deleted people (R-H12a). */
    private static Boolean keepsHouseholds() {
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
     * Of these households, those anything still points at: a record in any child relationship
     * of Account (live members and membership rows among them), a record an installed module
     * credits to it, or a dependent outside BarnCRM.
     */
    private Set<Id> withDependents(Set<Id> householdIds) {
        Set<Id> dependent = new Set<Id>();
        if (householdIds.isEmpty()) {
            return dependent;
        }
        dependent.addAll(withChildRecords(householdIds));
        dependent.addAll(HouseholdSelector.getAccountsWithNativeDependents(householdIds));
        dependent.addAll(HouseholdDependentsExtensions.householdsWithDependents(householdIds));
        dependent.retainAll(householdIds);
        return dependent;
    }

    /** Of these households, those with a record in any child relationship of Account. */
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
     * own, so one unreadable relationship does not hide the others. A relationship that cannot
     * be read on its own keeps every household.
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
                    if (!probeFailureLogged) {
                        probeFailureLogged = true;
                        ErrorLogger.logMessage(
                            String.format(
                                System.Label.Core_Households_TidyProbeFailed,
                                new List<String>{ relationship, unreadable.getMessage() }
                            ),
                            LOG_CONTEXT,
                            ErrorLogger.SEVERITY_WARNING
                        );
                    }
                    return householdIds;
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
     * name, on a queryable object, that are not the household's own bookkeeping.
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
            Schema.ChildRelationship relationship : Account.SObjectType.getDescribe()
                .getChildRelationships()
        ) {
            String name = relationship.getRelationshipName();
            if (name == null || relationship.isDeprecatedAndHidden() || seen.contains(name)) {
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

    /** Soft deletes these households; a refusal is one Error Log entry per chunk. */
    private void removeHouseholds(Set<Id> householdIds) {
        if (householdIds.isEmpty()) {
            return;
        }
        List<Account> households = new List<Account>();
        for (Id householdId : householdIds) {
            households.add(new Account(Id = householdId));
        }
        List<String> failures = new List<String>();
        List<Database.DeleteResult> results = Database.delete(
            households,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            Database.DeleteResult result = results[i];
            if (result.isSuccess()) {
                removed++;
            } else if (!result.getErrors().isEmpty()) {
                failures.add(households[i].Id + ': ' + result.getErrors()[0].getMessage());
            }
        }
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
}
