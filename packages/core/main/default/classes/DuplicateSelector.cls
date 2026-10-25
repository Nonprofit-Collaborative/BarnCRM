/**
 * Every query the duplicate scan and the Duplicates panel make (C-20).
 *
 * Almost all of them read records the platform owns: `DuplicateRule` says which rules the org
 * has switched on, and `DuplicateRecordSet` with `DuplicateRecordItem` holds what they found.
 * Canonical model R-DP1 is why there is nothing else to read.
 *
 * Everything is queried in user mode. A suggestion names two records, and a person who cannot
 * see one of them is never shown it, let alone offered a merge of it.
 */
public with sharing class DuplicateSelector {
    /** The objects duplicates are reviewed for, in the order a scan covers them. */
    public static final List<String> REVIEWED_OBJECTS = new List<String>{ 'Contact', 'Account' };

    private static final String PERSON_CONTACTS_QUERY = 'SELECT Id FROM Contact WHERE Id IN :contactIds AND IsPersonAccount = true'; // detection-only: run only after isPersonAccountOrg found person accounts, so a person account's contact half is never proposed as a duplicate of a contact

    private static final Set<String> SCAN_UNFINISHED = new Set<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };

    /** The subtype a person account rule carries (DuplicateRule.SobjectSubtype, API 39.0). */
    @TestVisible
    private static final String PERSON_ACCOUNT_SUBTYPE = 'PersonAccount'; // detection-only: a picklist value of DuplicateRule.SobjectSubtype, compared to tell a person account rule from an organization rule; no person account record or field is read
    private static final String SUBTYPE_FIELD = 'SobjectSubtype';

    /**
     * Set only by tests: the rules the org has, since a test cannot create a duplicate rule.
     * Build them with JSON.deserialize, as their fields cannot be written.
     */
    @TestVisible
    private static List<DuplicateRule> rulesOverride;

    /** Every duplicate rule for these objects, active or not. */
    public static List<DuplicateRule> rulesFor(Set<String> objectNames) {
        if (objectNames == null || objectNames.isEmpty()) {
            return new List<DuplicateRule>();
        }
        if (rulesOverride != null) {
            List<DuplicateRule> matching = new List<DuplicateRule>();
            for (DuplicateRule rule : rulesOverride) {
                if (objectNames.contains(rule.SobjectType)) {
                    matching.add(rule);
                }
            }
            return matching;
        }
        return [
            SELECT Id, DeveloperName, MasterLabel, SobjectType, IsActive
            FROM DuplicateRule
            WHERE SobjectType IN :objectNames
            WITH USER_MODE
            ORDER BY SobjectType, MasterLabel
        ];
    }

    /** The active rules for these objects, identifier by developer name. */
    public static Map<String, Id> activeRuleIdsByName(Set<String> objectNames) {
        Map<String, Id> result = new Map<String, Id>();
        for (DuplicateRule rule : rulesFor(objectNames)) {
            if (rule.IsActive == true) {
                result.put(rule.DeveloperName, rule.Id);
            }
        }
        return result;
    }

    /** One active rule per object among these, for a suggestion whose own rule is unknown. */
    public static Map<String, Id> activeRuleIdByObject(Set<String> objectNames) {
        Map<String, Id> result = new Map<String, Id>();
        for (DuplicateRule rule : rulesFor(objectNames)) {
            if (rule.IsActive == true && !result.containsKey(rule.SobjectType)) {
                result.put(rule.SobjectType, rule.Id);
            }
        }
        return result;
    }

    /**
     * Whether the object has an active rule for this kind of record. A person account rule is
     * a rule on Account with the person account subtype: it compares person accounts only, so it
     * does not count for an organization or household, and the other way round. Any other
     * object's rules have no subtype.
     */
    public static Boolean hasActiveRuleFor(String objectName, Boolean personAccounts) {
        Boolean wantPersonAccounts = personAccounts == true;
        for (DuplicateRule rule : rulesWithSubtype(objectName)) {
            Boolean personRule = PERSON_ACCOUNT_SUBTYPE.equals(
                rule.isSet(SUBTYPE_FIELD) ? (String) rule.get(SUBTYPE_FIELD) : null
            );
            if (rule.IsActive == true && personRule == wantPersonAccounts) {
                return true;
            }
        }
        return false;
    }

    /**
     * The object's rules with their subtype, read only where the org describes the field, so
     * nothing here fails to compile or run in an org without it.
     */
    private static List<DuplicateRule> rulesWithSubtype(String objectName) {
        if (String.isBlank(objectName)) {
            return new List<DuplicateRule>();
        }
        if (rulesOverride != null) {
            return rulesFor(new Set<String>{ objectName });
        }
        Boolean hasSubtype = Schema.SObjectType.DuplicateRule.fields.getMap()
            .containsKey(SUBTYPE_FIELD.toLowerCase());
        return Database.queryWithBinds(
            'SELECT Id, SobjectType, IsActive' +
                (hasSubtype ? ', ' + SUBTYPE_FIELD : '') +
                ' FROM DuplicateRule WHERE SobjectType = :objectName',
            new Map<String, Object>{ 'objectName' => objectName },
            AccessLevel.USER_MODE
        );
    }

    /**
     * The objects among these that have at least one active rule. Account counts only for a
     * rule that compares organizations and households: with a person account rule alone the
     * households pass has nothing to ask, and the platform refuses every chunk of it.
     */
    public static Set<String> objectsWithActiveRules(Set<String> objectNames) {
        Set<String> result = new Set<String>();
        for (DuplicateRule rule : rulesFor(objectNames)) {
            if (rule.IsActive == true) {
                result.add(rule.SobjectType);
            }
        }
        if (result.contains('Account') && !hasActiveRuleFor('Account', false)) {
            result.remove('Account');
        }
        return result;
    }

    /**
     * The suggestions waiting to be looked at, newest first, with their records. A set written
     * when somebody saved past an alert and a set written by the scan are the same thing to the
     * person reviewing them. Sets for other objects (leads) and sets a merge has emptied down to
     * one record are left out.
     */
    public static List<DuplicateRecordSet> openSets(Integer max) {
        return openSetsAfter(max, null);
    }

    /**
     * The next window of open sets after `last` (the oldest of the window before), in the same
     * newest-first order, so a reader can page past sets it cannot use.
     */
    public static List<DuplicateRecordSet> openSetsAfter(Integer max, DuplicateRecordSet last) {
        Integer limitRows = max == null || max <= 0 ? 50 : max;
        List<String> objects = REVIEWED_OBJECTS;
        if (last == null) {
            return [
                SELECT
                    Id,
                    CreatedDate,
                    DuplicateRule.MasterLabel,
                    (SELECT Id, RecordId FROM DuplicateRecordItems ORDER BY CreatedDate)
                FROM DuplicateRecordSet
                WHERE RecordCount > 1 AND DuplicateRule.SobjectType IN :objects
                WITH USER_MODE
                ORDER BY CreatedDate DESC, Id DESC
                LIMIT :limitRows
            ];
        }
        Datetime lastCreated = last.CreatedDate;
        Id lastId = last.Id;
        return [
            SELECT
                Id,
                CreatedDate,
                DuplicateRule.MasterLabel,
                (SELECT Id, RecordId FROM DuplicateRecordItems ORDER BY CreatedDate)
            FROM DuplicateRecordSet
            WHERE
                RecordCount > 1
                AND DuplicateRule.SobjectType IN :objects
                AND (CreatedDate < :lastCreated
                OR (CreatedDate = :lastCreated
                AND Id < :lastId))
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT :limitRows
        ];
    }

    /** These suggestions, with their records. */
    public static List<DuplicateRecordSet> setsByIds(Set<Id> setIds) {
        if (setIds == null || setIds.isEmpty()) {
            return new List<DuplicateRecordSet>();
        }
        return [
            SELECT Id, (SELECT Id, RecordId FROM DuplicateRecordItems ORDER BY CreatedDate)
            FROM DuplicateRecordSet
            WHERE Id IN :setIds
            WITH USER_MODE
        ];
    }

    /** The suggestion entries naming any of these records. */
    public static List<DuplicateRecordItem> itemsForRecords(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<DuplicateRecordItem>();
        }
        return [
            SELECT Id, DuplicateRecordSetId, RecordId
            FROM DuplicateRecordItem
            WHERE RecordId IN :recordIds
            WITH USER_MODE
        ];
    }

    /** Every entry in these suggestions. */
    public static List<DuplicateRecordItem> itemsForSets(Set<Id> setIds) {
        if (setIds == null || setIds.isEmpty()) {
            return new List<DuplicateRecordItem>();
        }
        return [
            SELECT Id, DuplicateRecordSetId, RecordId
            FROM DuplicateRecordItem
            WHERE DuplicateRecordSetId IN :setIds
            WITH USER_MODE
        ];
    }

    /** The reasons written for these suggestions by a match source (R-DP6). */
    public static List<Duplicate_Reason__c> reasonRows(Set<Id> setIds) {
        Set<String> keys = new Set<String>();
        for (Id setId : setIds == null ? new Set<Id>() : setIds) {
            keys.add(String.valueOf(setId));
        }
        // A reviewer without a BarnCRM role reads no reasons and sees the rule's name instead.
        if (keys.isEmpty() || !Schema.SObjectType.Duplicate_Reason__c.isAccessible()) {
            return new List<Duplicate_Reason__c>();
        }
        return [
            SELECT Id, Set_Id__c, Reason__c
            FROM Duplicate_Reason__c
            WHERE Set_Id__c IN :keys
            WITH USER_MODE
        ];
    }

    /** The pairs among these that somebody already said are not duplicates. */
    public static Set<String> dismissedKeys(Set<String> pairKeys) {
        Set<String> result = new Set<String>();
        if (pairKeys == null || pairKeys.isEmpty()) {
            return result;
        }
        for (Duplicate_Dismissal__c dismissal : [
            SELECT Pair_Key__c
            FROM Duplicate_Dismissal__c
            WHERE Pair_Key__c IN :pairKeys
            WITH USER_MODE
        ]) {
            result.add(dismissal.Pair_Key__c);
        }
        return result;
    }

    /**
     * What the latest scan said when it finished, or null when there is none this person can
     * read. The scan writes one entry at the end, at Warning when a chunk could not be
     * checked, so the panel can say so instead of implying a clean result.
     */
    public static Error_Log__c latestScanResult(String context) {
        if (!Schema.SObjectType.Error_Log__c.isAccessible()) {
            return null;
        }
        List<Error_Log__c> entries = [
            SELECT Message__c, Severity__c, CreatedDate
            FROM Error_Log__c
            WHERE Context__c = :context
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return entries.isEmpty() ? null : entries[0];
    }

    /** How many pairs have been dismissed, for the count on the panel. */
    public static Integer dismissalCount() {
        return [SELECT COUNT() FROM Duplicate_Dismissal__c WITH USER_MODE];
    }

    /** The latest runs of the scan, so the panel can say whether one is going on. */
    public static List<AsyncApexJob> recentScanJobs(String className, Integer max) {
        Integer limitRows = max == null || max <= 0 ? 5 : max;
        return [
            SELECT Id, Status, CreatedDate, CompletedDate
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex' AND ApexClass.Name = :className
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :limitRows
        ];
    }

    /**
     * Whether a scan is waiting or running, whoever started it, so a second one is not started
     * beside it: two scans read the same pairs before either writes, and both write them.
     *
     * An upkeep read (ADR-0021), in system mode because a person without View Setup sees only
     * their own jobs, and the scan another administrator started is the one that matters. Only
     * the panel's scan guard and its "scan running" line reach it, its input is a class name
     * the controller holds as a constant, it reads one status field, and its answer is a yes or
     * no that names nobody's job.
     */
    public static Boolean scanRunning(String className) {
        return [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE
                    JobType = 'BatchApex'
                    AND ApexClass.Name = :className
                    AND Status IN :SCAN_UNFINISHED
                WITH SYSTEM_MODE
            ] > 0;
    }

    /**
     * The person account contact halves among these contacts. Empty in an org without person
     * accounts, where the field the question needs does not exist (ADR-0013).
     */
    public static Set<Id> personContactIds(Set<Id> contactIds) {
        Set<Id> result = new Set<Id>();
        if (contactIds == null || contactIds.isEmpty() || !HouseholdService.isPersonAccountOrg()) {
            return result;
        }
        for (
            SObject person : Database.queryWithBinds(
                PERSON_CONTACTS_QUERY,
                new Map<String, Object>{ 'contactIds' => contactIds },
                AccessLevel.USER_MODE
            )
        ) {
            result.add(person.Id);
        }
        return result;
    }

    /** The households among these account identifiers. */
    public static Set<Id> householdIds(Set<Id> accountIds) {
        Id householdType = HouseholdService.householdRecordTypeId();
        if (accountIds == null || accountIds.isEmpty() || householdType == null) {
            return new Set<Id>();
        }
        return new Map<Id, Account>(
                [
                    SELECT Id
                    FROM Account
                    WHERE Id IN :accountIds AND RecordTypeId = :householdType
                    WITH USER_MODE
                ]
            )
            .keySet();
    }

    /** The households among these identifiers, as the panel names them. */
    public static List<Account> householdsByIds(Set<Id> recordIds) {
        Id householdType = HouseholdService.householdRecordTypeId();
        if (recordIds == null || recordIds.isEmpty() || householdType == null) {
            return new List<Account>();
        }
        return [
            SELECT Id, Name, BillingCity, BillingPostalCode
            FROM Account
            WHERE Id IN :recordIds AND RecordTypeId = :householdType
            WITH USER_MODE
        ];
    }

    /** The people among these identifiers, as the panel names them. */
    public static List<Contact> contactsByIds(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id, Name, Email, MailingPostalCode, Account.Name
            FROM Contact
            WHERE Id IN :recordIds
            WITH USER_MODE
        ];
    }
}
