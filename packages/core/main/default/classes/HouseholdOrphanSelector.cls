/**
 * The reads behind Health Check's orphan findings: people who are in no household, and
 * households nobody is in (plan Section 4.8, C-21, ADR-0048). Detection only; nothing here
 * writes, and cleaning up is C-28's.
 *
 * "In a household" is read exactly as the canonical model defines membership, per mode
 * (R-H3). In contact mode it is the person's Account (R-C1, R-H1). In junction mode it is a
 * current Household Member row (R-M2: no End Date, or one in the future) naming the person
 * by Contact or, for a person stored as an account, by Account (R-M4). A row that names
 * nobody counts for nobody (R-M4).
 *
 * These are reads a person is shown, so they run in user mode (ADR-0021): a record the
 * administrator cannot see is neither counted nor linked. Every count stops at the cap it is
 * given, so a large org is answered with "more than" rather than by counting every row, and
 * every list is short. People stored as accounts are recognised by the record types the org
 * describes as person types, passed in by the caller from OrgShapeDetector, so no person
 * account field is referenced here and Core still compiles on a Platform-only org (ADR-0013).
 *
 * A person who has been erased is never counted as having no household: erasing them takes
 * them out of it on purpose (canonical model R-ER9).
 */
public with sharing class HouseholdOrphanSelector {
    /** The most erased people left out; erasures are rare, and the ids are never shown. */
    private static final Integer ERASED_READ_CAP = 10000;

    private static Set<Id> erased;

    /**
     * Every person an Erasure record names, read once per transaction. System mode, because
     * the ids only leave people out of a count the user is shown in user mode, and the person
     * running Health Check need not be able to read the erasure audit (ADR-0021).
     */
    private static Set<Id> erasedPeople() {
        if (erased == null) {
            erased = new Set<Id>();
            for (Erasure__c erasure : [
                SELECT Contact__c, Person_Account__c
                FROM Erasure__c
                WHERE Contact__c != NULL OR Person_Account__c != NULL
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT :ERASED_READ_CAP
            ]) {
                erased.add(
                    erasure.Contact__c != null ? erasure.Contact__c : erasure.Person_Account__c
                );
            }
        }
        return erased;
    }

    /**
     * Junction mode: the people in no household, contacts and person accounts together, as
     * Health Check and the data hygiene console both count them. Stops at `cap`: the person
     * accounts are not counted once the contacts alone reach it.
     */
    public static Integer countPeopleWithoutMembership(Id householdRecordTypeId, Integer cap) {
        Set<Id> personTypes = OrgShapeDetector.personRecordTypeIds();
        Set<Id> excluded = new Set<Id>(personTypes);
        if (householdRecordTypeId != null) {
            excluded.add(householdRecordTypeId);
        }
        Integer found = countContactsWithoutMembership(excluded, cap);
        if (!personTypes.isEmpty() && found < cap) {
            found += countPersonAccountsWithoutMembership(personTypes, cap);
        }
        return found;
    }

    /** Contact mode: contacts with no account at all. */
    public static Integer countContactsWithoutAccount(Integer cap) {
        return [
            SELECT COUNT()
            FROM Contact
            WHERE AccountId = NULL AND Id NOT IN :erasedPeople()
            WITH USER_MODE
            LIMIT :cap
        ];
    }

    public static List<Contact> contactsWithoutAccount(Integer howMany) {
        return [
            SELECT Id, Name
            FROM Contact
            WHERE AccountId = NULL AND Id NOT IN :erasedPeople()
            WITH USER_MODE
            ORDER BY CreatedDate, Id
            LIMIT :howMany
        ];
    }

    /**
     * Junction mode: contacts with no current membership row, leaving out a contact whose
     * account is of one of the excluded record types. The caller excludes the household type,
     * because a contact linked straight to a household is in it by the simple link (and the
     * membership check reports that already), and the person types, because the person contact
     * of a person account is counted as the account below. Never empty: it always holds the
     * household type.
     */
    public static Integer countContactsWithoutMembership(
        Set<Id> excludedAccountTypes,
        Integer cap
    ) {
        Date today = Date.today();
        return [
            SELECT COUNT()
            FROM Contact
            WHERE
                Id NOT IN (
                    SELECT Contact__c
                    FROM Household_Member__c
                    WHERE Contact__c != NULL AND (End_Date__c = NULL OR End_Date__c > :today)
                )
                AND Id NOT IN :erasedPeople()
                AND (AccountId = NULL
                OR Account.RecordTypeId NOT IN :excludedAccountTypes)
            WITH USER_MODE
            LIMIT :cap
        ];
    }

    public static List<Contact> contactsWithoutMembership(
        Set<Id> excludedAccountTypes,
        Integer howMany
    ) {
        Date today = Date.today();
        return [
            SELECT Id, Name
            FROM Contact
            WHERE
                Id NOT IN (
                    SELECT Contact__c
                    FROM Household_Member__c
                    WHERE Contact__c != NULL AND (End_Date__c = NULL OR End_Date__c > :today)
                )
                AND Id NOT IN :erasedPeople()
                AND (AccountId = NULL
                OR Account.RecordTypeId NOT IN :excludedAccountTypes)
            WITH USER_MODE
            ORDER BY CreatedDate, Id
            LIMIT :howMany
        ];
    }

    /** Junction mode, people stored as accounts: no current membership row names them. */
    public static Integer countPersonAccountsWithoutMembership(
        Set<Id> personRecordTypeIds,
        Integer cap
    ) {
        Date today = Date.today();
        return [
            SELECT COUNT()
            FROM Account
            WHERE
                RecordTypeId IN :personRecordTypeIds
                AND Id NOT IN :erasedPeople()
                AND Id NOT IN (
                    SELECT Account__c
                    FROM Household_Member__c
                    WHERE Account__c != NULL AND (End_Date__c = NULL OR End_Date__c > :today)
                )
            WITH USER_MODE
            LIMIT :cap
        ];
    }

    public static List<Account> personAccountsWithoutMembership(
        Set<Id> personRecordTypeIds,
        Integer howMany
    ) {
        Date today = Date.today();
        return [
            SELECT Id, Name
            FROM Account
            WHERE
                RecordTypeId IN :personRecordTypeIds
                AND Id NOT IN :erasedPeople()
                AND Id NOT IN (
                    SELECT Account__c
                    FROM Household_Member__c
                    WHERE Account__c != NULL AND (End_Date__c = NULL OR End_Date__c > :today)
                )
            WITH USER_MODE
            ORDER BY CreatedDate, Id
            LIMIT :howMany
        ];
    }

    /** Contact mode: households no contact's account points at. */
    public static Integer countHouseholdsWithoutContacts(Id householdRecordTypeId, Integer cap) {
        return [
            SELECT COUNT()
            FROM Account
            WHERE
                RecordTypeId = :householdRecordTypeId
                AND Id NOT IN (SELECT AccountId FROM Contact WHERE AccountId != NULL)
            WITH USER_MODE
            LIMIT :cap
        ];
    }

    public static List<Account> householdsWithoutContacts(
        Id householdRecordTypeId,
        Integer howMany
    ) {
        return [
            SELECT Id, Name
            FROM Account
            WHERE
                RecordTypeId = :householdRecordTypeId
                AND Id NOT IN (SELECT AccountId FROM Contact WHERE AccountId != NULL)
            WITH USER_MODE
            ORDER BY CreatedDate, Id
            LIMIT :howMany
        ];
    }

    /** Junction mode: households no current membership row that names somebody points at. */
    public static Integer countHouseholdsWithoutMembers(Id householdRecordTypeId, Integer cap) {
        Date today = Date.today();
        return [
            SELECT COUNT()
            FROM Account
            WHERE
                RecordTypeId = :householdRecordTypeId
                AND Id NOT IN (
                    SELECT Household__c
                    FROM Household_Member__c
                    WHERE
                        (Contact__c != NULL
                        OR Account__c != NULL)
                        AND (End_Date__c = NULL
                        OR End_Date__c > :today)
                )
            WITH USER_MODE
            LIMIT :cap
        ];
    }

    public static List<Account> householdsWithoutMembers(
        Id householdRecordTypeId,
        Integer howMany
    ) {
        Date today = Date.today();
        return [
            SELECT Id, Name
            FROM Account
            WHERE
                RecordTypeId = :householdRecordTypeId
                AND Id NOT IN (
                    SELECT Household__c
                    FROM Household_Member__c
                    WHERE
                        (Contact__c != NULL
                        OR Account__c != NULL)
                        AND (End_Date__c = NULL
                        OR End_Date__c > :today)
                )
            WITH USER_MODE
            ORDER BY CreatedDate, Id
            LIMIT :howMany
        ];
    }
}
