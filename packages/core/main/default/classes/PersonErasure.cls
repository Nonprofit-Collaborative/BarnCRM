/**
 * Erases one person at their request (the right to be forgotten; canonical model Section 29H,
 * rules R-ER1 to R-ER8; ADR-0110 `0110-erase-a-person-anonymizes-in-place.md`).
 *
 * The person's record is anonymized in place, never deleted, so gifts and totals keep pointing
 * at it. What to empty is worked out from describe: every field that can be empty, except what
 * `DataProtectedFields` protects, a few structural fields, and what a module keeps. Addresses
 * are deleted, relationships, affiliations and memberships are ended, households left empty and
 * kept are anonymized too, a household with members left whose name was typed by hand is named
 * again from them, and the linked Individual is emptied and marked Forget.
 *
 * Reads that decide what to change run in system mode, so a field the user cannot see is not
 * missed; every change runs in user mode, all or nothing. The preview is the same run, rolled
 * back, so it cannot disagree with the erasure.
 *
 * Names that exist only in some orgs (the Individual object and its links, the person account
 * surname) are held as text and resolved through describe (ADR-0009, ADR-0013).
 */
@NamespaceAccessible
public with sharing class PersonErasure {
    @NamespaceAccessible
    public static final String PERMISSION = 'Erase_People';
    @NamespaceAccessible
    public static final String CLEARED = 'Cleared';
    @NamespaceAccessible
    public static final String ENDED = 'Ended';
    @NamespaceAccessible
    public static final String DELETED = 'Deleted';
    @NamespaceAccessible
    public static final String KEPT = 'Kept';
    @NamespaceAccessible
    public static final String UPDATED = 'Updated';

    // detection-only: the Individual object and its links exist only where the org turned on
    // Data Protection and Privacy, and the account link only where people are accounts.
    private static final String INDIVIDUAL_OBJECT = 'Individual';
    private static final Map<Schema.SObjectType, String> INDIVIDUAL_LINK = new Map<Schema.SObjectType, String>{
        Contact.SObjectType => 'IndividualId',
        Account.SObjectType => 'PersonIndividualId'
    };
    // detection-only: the surname is on Account only where people are accounts.
    private static final String SURNAME = 'lastname';

    /** Kept on every record: who owns it, its shape, and the link to its Individual. */
    private static final Set<String> NEVER_CLEARED = new Set<String>{
        'id',
        'name',
        'ownerid',
        'recordtypeid',
        'currencyisocode',
        'masterrecordid',
        'individualid',
        'personindividualid'
    };

    /**
     * Fields the package writes but that say something about the person: the primary
     * organization and the household role. Emptied although `DataProtectedFields` keeps them.
     */
    private static final Set<String> ERASED_THOUGH_KEPT = new Set<String>{
        'primary_affiliation__c',
        'household_role__c'
    };

    /** Checkboxes set rather than reset, so no mailing reaches an erased record. */
    private static final Set<String> SET_FLAGS = new Set<String>{
        'donotcall',
        'persondonotcall',
        'shouldforget'
    };
    private static final List<String> SET_FLAG_PREFIXES = new List<String>{
        'hasoptedout',
        'personhasoptedout'
    };

    /** Address upkeep stood down while the erasure empties addresses itself. */
    private static final List<String> ADDRESS_AUTOMATIONS = new List<String>{
        'Contact_Address_Capture',
        'Account_Address_Capture',
        'Address_Default_Propagation'
    };

    /** What a household with members left is compared on, before and after (R-ER3). */
    private static final List<Schema.SObjectField> HOUSEHOLD_WORDING = new List<Schema.SObjectField>{
        Account.Name,
        Account.Household_Formal_Greeting__c,
        Account.Household_Informal_Greeting__c,
        Account.Member_Count__c,
        Account.Primary_Contact__c,
        Account.Custom_Name__c
    };

    private static final Integer ACCESS_CHUNK = 200;

    /** Activities and files are counted up to this many of each kind (R-ER10). */
    private static final Integer ACTIVITY_CAP = 10000;

    /** One kind of change to one kind of record. Holds labels and Ids, never a value. */
    @NamespaceAccessible
    public class Change {
        @AuraEnabled
        public String action;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public List<Id> recordIds = new List<Id>();
        @AuraEnabled
        public Integer count = 0;
        @AuraEnabled
        public List<String> fields = new List<String>();
        @AuraEnabled
        public String note;

        @NamespaceAccessible
        public Change(String action, String objectLabel, List<Id> recordIds, List<String> fields) {
            this.action = action;
            this.objectLabel = objectLabel;
            if (recordIds != null) {
                this.recordIds.addAll(recordIds);
            }
            this.count = this.recordIds.size();
            if (fields != null) {
                this.fields.addAll(fields);
            }
        }

        /** A change counted rather than listed, with the reason. */
        @NamespaceAccessible
        public Change(String action, String objectLabel, Integer count, String note) {
            this.action = action;
            this.objectLabel = objectLabel;
            this.count = count == null ? 0 : count;
            this.note = note;
        }

        // Getters for other packages: an @AuraEnabled field cannot also be @NamespaceAccessible.
        @NamespaceAccessible
        public String getAction() {
            return action;
        }

        @NamespaceAccessible
        public String getObjectLabel() {
            return objectLabel;
        }
    }

    /** What an erasure or a preview did. */
    @NamespaceAccessible
    public class Result {
        @AuraEnabled
        public Boolean erased = false;
        @AuraEnabled
        public Id erasureId;
        @AuraEnabled
        public String personName;
        @AuraEnabled
        public List<Change> changes = new List<Change>();

        @NamespaceAccessible
        public List<Change> getChanges() {
            return changes;
        }
    }

    /** A refusal the person erasing can act on. Its message is always a custom label. */
    @NamespaceAccessible
    public class ErasureException extends Exception {
    }

    /** History objects whose rows the queued cleanup deletes once the erasure has committed. */
    private static Map<String, Set<Id>> historyToDelete;
    /**
     * What the erasure deleted, emptied from the Recycle Bin once it commits. Visible to tests,
     * which still read purged rows with ALL ROWS and so cannot see the Recycle Bin empty.
     */
    @TestVisible
    private static List<Id> deletedIds;
    private static Map<Schema.SObjectType, Map<String, Schema.DescribeFieldResult>> describedFields = new Map<Schema.SObjectType, Map<String, Schema.DescribeFieldResult>>();

    /** Everything the erasure would change, worked out by running it and rolling it back. */
    @NamespaceAccessible
    public static Result preview(Id personId) {
        SObject person = checkedPerson(personId);
        Savepoint before = Database.setSavepoint();
        try {
            Result result = run(person);
            return result;
        } finally {
            Database.rollback(before);
        }
    }

    /**
     * Erases the person. `typedName` must match the person's current name; `requestReference`
     * is the organization's own reference, kept on the Erasure record.
     */
    @NamespaceAccessible
    public static Result erase(Id personId, String typedName, String requestReference) {
        SObject person = checkedPerson(personId);
        if (normalized(typedName) != normalized((String) person.get('Name'))) {
            throw new ErasureException(Label.Core_Erase_NameMismatch);
        }
        Savepoint before = Database.setSavepoint();
        Result result;
        try {
            result = run(person);
            Erasure__c audit = new Erasure__c(
                Erased_Record_Id__c = String.valueOf(personId),
                Request_Reference__c = String.isBlank(requestReference)
                    ? null
                    : requestReference.trim().left(80),
                Details__c = details(result.changes).left(131072)
            );
            audit.put(
                personId.getSObjectType() == Contact.SObjectType
                    ? 'Contact__c'
                    : 'Person_Account__c',
                personId
            );
            // Bookkeeping the person erasing may not edit (R-ER5, ADR-0021).
            Database.insert(audit, true, AccessLevel.SYSTEM_MODE);
            result.erasureId = audit.Id;
            result.erased = true;
        } catch (Exception failed) {
            Database.rollback(before);
            throw failed;
        }
        finishAfterCommit();
        return result;
    }

    /** The person, refused with a reason when they may not be erased by this user. */
    private static SObject checkedPerson(Id personId) {
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            throw new ErasureException(Label.Core_Erase_NoPermission);
        }
        Schema.SObjectType type = personId == null ? null : personId.getSObjectType();
        if (type != Contact.SObjectType && type != Account.SObjectType) {
            throw new ErasureException(Label.Core_Erase_NotAPerson);
        }
        List<SObject> found = readAll(type, new Set<Id>{ personId });
        if (
            found.isEmpty() ||
            (type == Account.SObjectType && !PersonRecordSelector.isPersonRecord(found[0]))
        ) {
            throw new ErasureException(Label.Core_Erase_NotAPerson);
        }
        String id18 = String.valueOf(personId);
        List<Erasure__c> earlier = [
            SELECT CreatedDate
            FROM Erasure__c
            WHERE Erased_Record_Id__c = :id18
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!earlier.isEmpty()) {
            throw new ErasureException(
                String.format(
                    Label.Core_Erase_AlreadyErased,
                    new List<String>{ earlier[0].CreatedDate.format() }
                )
            );
        }
        return found[0];
    }

    /** The erasure itself, inside the caller's savepoint. */
    private static Result run(SObject person) {
        Id personId = person.Id;
        Schema.SObjectType type = personId.getSObjectType();
        Set<Id> people = new Set<Id>{ personId };
        Result result = new Result();
        result.personName = (String) person.get('Name');
        historyToDelete = new Map<String, Set<Id>>();
        deletedIds = new List<Id>();

        List<PersonErasureExtension> extensions = PersonErasureExtensions.installed();
        Set<Schema.SObjectField> keep = new Set<Schema.SObjectField>();
        for (PersonErasureExtension extension : extensions) {
            Set<Schema.SObjectField> kept = extension.fieldsToKeep(type);
            if (kept != null) {
                keep.addAll(kept);
            }
        }

        // What will change, read before anything does.
        String side = type == Contact.SObjectType ? 'Contact__c' : 'Person_Account__c';
        String related = type == Contact.SObjectType
            ? 'Related_Contact__c'
            : 'Related_Person_Account__c';
        List<SObject> addresses = rows(
            'SELECT Id FROM Address__c WHERE ' + side + ' IN :ids',
            people
        );
        List<SObject> relationships = rows(
            'SELECT Id, ' +
                side +
                ', Start_Date__c, End_Date__c, Description__c' +
                ' FROM Relationship__c WHERE ' +
                side +
                ' IN :ids OR ' +
                related +
                ' IN :ids',
            people
        );
        List<SObject> affiliations = rows(
            'SELECT Id, Start_Date__c, End_Date__c, Description__c, Role__c, Is_Primary__c' +
                ' FROM Affiliation__c WHERE ' +
                side +
                ' IN :ids',
            people
        );
        List<Household_Member__c> memberships = new List<Household_Member__c>();
        Set<Id> households = new Set<Id>();
        for (Household_Member__c membership : HouseholdService.membershipsFor(people)) {
            if (membership.End_Date__c == null || membership.End_Date__c > Date.today()) {
                memberships.add(membership);
                households.add(membership.Household__c);
            }
        }
        Id account = type == Contact.SObjectType ? (Id) person.get('AccountId') : null;
        if (account != null) {
            households.add(account);
        }
        Map<Id, Account> householdsBefore = householdWording(households);
        SObject individual = individualOf(person);

        // The user must be able to make every change before any is made (R-ER5).
        List<String> refused = new List<String>();
        refuseWithout(new List<Id>(people), 'HasEditAccess', type, refused);
        refuseWithout(ids(addresses), 'HasDeleteAccess', Address__c.SObjectType, refused);
        refuseWithout(ids(relationships), 'HasEditAccess', Relationship__c.SObjectType, refused);
        refuseWithout(ids(affiliations), 'HasEditAccess', Affiliation__c.SObjectType, refused);
        refuseWithout(ids(memberships), 'HasEditAccess', Household_Member__c.SObjectType, refused);
        if (individual != null) {
            refuseWithout(
                new List<Id>{ individual.Id },
                'HasEditAccess',
                individual.getSObjectType(),
                refused
            );
        }
        if (!refused.isEmpty()) {
            throw new ErasureException(
                String.format(
                    Label.Core_Erase_CannotEdit,
                    new List<String>{ String.join(refused, ', ') }
                )
            );
        }
        Clearing personPlan = plan(person, keep, Label.Core_Erase_PersonName);
        Clearing individualPlan = individual == null
            ? null
            : plan(individual, new Set<Schema.SObjectField>(), Label.Core_Erase_PersonName);
        refuseBlocked(personPlan);
        refuseBlocked(individualPlan);

        for (String automation : ADDRESS_AUTOMATIONS) {
            AutomationControl.bypass(automation);
        }
        try {
            remove(addresses, Address__c.SObjectType, result);
            endConnections(relationships, side, people, related, result);
            endConnections(affiliations, null, people, null, result);
            List<Household_Member__c> closedMemberships = HouseholdService.endMembershipsFor(
                people
            );
            add(
                result,
                ENDED,
                Household_Member__c.SObjectType,
                ids(closedMemberships),
                endedFields(Household_Member__c.SObjectType, false)
            );

            // Read again: the steps above may have written to the person (R-AD3).
            SObject current = readAll(type, people)[0];
            personPlan = plan(current, keep, Label.Core_Erase_PersonName);
            refuseBlocked(personPlan);
            save(personPlan, result);
            if (individualPlan != null) {
                save(individualPlan, result);
            }
            noteHistory(type, personId, result);
            if (individual != null) {
                noteHistory(individual.getSObjectType(), individual.Id, result);
            }
            // Listed here, but counted once the modules have run: a file a module deletes is
            // not also kept.
            Integer activitiesAt = result.changes.size();
            HouseholdService.afterMembershipChange(households, true);
            settleHouseholds(households, householdsBefore, result);
            for (PersonErasureExtension extension : extensions) {
                List<Change> changes = extension.erase(personId);
                if (changes != null) {
                    result.changes.addAll(changes);
                    // Records a module deleted leave the Recycle Bin with the rest (R-ER8).
                    for (Change change : changes) {
                        if (change.action == DELETED) {
                            deletedIds.addAll(change.recordIds);
                        }
                    }
                }
            }
            noteActivitiesAndFiles(personId, result, activitiesAt);
        } catch (ErasureException refusal) {
            throw refusal;
        } catch (DmlException refusedChange) {
            throw new ErasureException(
                String.format(
                    Label.Core_Erase_Refused,
                    new List<String>{ refusedChange.getDmlMessage(0) }
                )
            );
        } catch (Exception failed) {
            ErrorLogger.log(failed, 'PersonErasure.run');
            throw new ErasureException(
                String.format(Label.Core_Erase_Refused, new List<String>{ failed.getMessage() })
            );
        } finally {
            for (String automation : ADDRESS_AUTOMATIONS) {
                AutomationControl.clearBypass(automation);
            }
        }
        return result;
    }

    // --------------------------------------------------------------------------- the steps

    /** Deletes these records, as the user, and remembers them for the Recycle Bin. */
    private static void remove(List<SObject> records, Schema.SObjectType type, Result result) {
        if (records.isEmpty()) {
            return;
        }
        Database.delete(records, true, AccessLevel.USER_MODE);
        deletedIds.addAll(ids(records));
        add(result, DELETED, type, ids(records), null);
    }

    /**
     * Ends relationships or affiliations and empties what was typed about them (R-ER2).
     * Relationships go in two saves: the person's own side first, whose upkeep may also end the
     * other side, then whatever other side is still open, so no record is saved twice in one
     * statement while its upkeep writes to it.
     */
    private static void endConnections(
        List<SObject> records,
        String side,
        Set<Id> people,
        String related,
        Result result
    ) {
        if (records.isEmpty()) {
            return;
        }
        Schema.SObjectType type = records[0].getSObjectType();
        Boolean affiliation = type == Affiliation__c.SObjectType;
        List<SObject> first = new List<SObject>();
        List<Id> later = new List<Id>();
        for (SObject record : records) {
            if (affiliation || people.contains((Id) record.get(side))) {
                first.add(record);
            } else {
                later.add(record.Id);
            }
        }
        List<Id> changed = endAll(first, affiliation);
        if (!later.isEmpty()) {
            changed.addAll(
                endAll(
                    rows(
                        'SELECT Id, Start_Date__c, End_Date__c, Description__c FROM Relationship__c' +
                        ' WHERE Id IN :ids',
                        new Set<Id>(later)
                    ),
                    false
                )
            );
        }
        add(result, ENDED, type, changed, endedFields(type, affiliation));
    }

    private static List<Id> endAll(List<SObject> records, Boolean affiliation) {
        Date today = Date.today();
        List<SObject> updates = new List<SObject>();
        for (SObject record : records) {
            SObject updated = record.getSObjectType().newSObject(record.Id);
            Date started = (Date) record.get('Start_Date__c');
            Date ended = (Date) record.get('End_Date__c');
            Boolean changes = false;
            if (ended == null || ended > today) {
                updated.put('End_Date__c', today);
                if (started != null && started > today) {
                    updated.put('Start_Date__c', today);
                }
                changes = true;
            }
            List<String> cleared = affiliation
                ? new List<String>{ 'Description__c', 'Role__c' }
                : new List<String>{ 'Description__c' };
            for (String field : cleared) {
                if (record.get(field) != null) {
                    updated.put(field, null);
                    changes = true;
                }
            }
            if (affiliation && record.get('Is_Primary__c') == true) {
                updated.put('Is_Primary__c', false);
                changes = true;
            }
            if (changes) {
                updates.add(updated);
            }
        }
        if (!updates.isEmpty()) {
            Database.update(updates, true, AccessLevel.USER_MODE);
        }
        return ids(updates);
    }

    /**
     * Why a household left empty was kept: upkeep deletes an empty household only when Delete
     * Empty Households is on, so with it off that is the reason; with it on, records still
     * linked to the household kept it.
     */
    private static String keptHouseholdNote() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        Boolean deletesEmpty = settings != null && settings.Delete_Empty_Households__c == true;
        return deletesEmpty
            ? Label.Core_Erase_NoteHouseholdKept
            : Label.Core_Erase_NoteHouseholdKeptSetting;
    }

    /**
     * After upkeep: a household the person left is gone, still has members, or was left empty
     * and kept, in which case it would still carry the person's name and address and is
     * anonymized too (R-ER3). `before` holds each household's wording as it was before the
     * erasure began, so a household with members left is reported with what really changed.
     */
    private static void settleHouseholds(
        Set<Id> householdIds,
        Map<Id, Account> before,
        Result result
    ) {
        if (householdIds.isEmpty()) {
            return;
        }
        Map<Id, SObject> remaining = new Map<Id, SObject>(
            readAll(Account.SObjectType, householdIds)
        );
        Map<Id, Set<Id>> members = HouseholdService.getMemberPersonIds(remaining.keySet());
        Id householdType = HouseholdService.householdRecordTypeId();
        List<Id> gone = new List<Id>();
        List<Id> shared = new List<Id>();
        for (Id householdId : householdIds) {
            SObject household = remaining.get(householdId);
            if (household == null) {
                gone.add(householdId);
            } else if (householdType != null && household.get('RecordTypeId') != householdType) {
                continue;
            } else if (members.containsKey(householdId) && !members.get(householdId).isEmpty()) {
                shared.add(householdId);
            } else {
                Clearing anonymous = plan(
                    household,
                    new Set<Schema.SObjectField>(),
                    Label.Core_Erase_HouseholdName
                );
                anonymous.record.put(Account.Custom_Name__c, true);
                // The package keeps the greetings from plan(), so they are emptied, and
                // listed, here: an emptied household keeps its last ones (R-H4).
                for (
                    Schema.SObjectField greeting : new List<Schema.SObjectField>{
                        Account.Household_Formal_Greeting__c,
                        Account.Household_Informal_Greeting__c
                    }
                ) {
                    anonymous.record.put(greeting, null);
                    if (household.get(greeting) != null) {
                        anonymous.cleared.add(greeting.getDescribe().getLabel());
                    }
                }
                refuseBlocked(anonymous);
                remove(
                    rows(
                        'SELECT Id FROM Address__c WHERE Account__c IN :ids',
                        new Set<Id>{ householdId }
                    ),
                    Address__c.SObjectType,
                    result
                );
                save(anonymous, result, Label.Core_Erase_Household, keptHouseholdNote());
            }
        }
        deletedIds.addAll(gone);
        if (!gone.isEmpty()) {
            add(result, DELETED, Label.Core_Erase_Household, gone, null, null);
        }
        settleSharedHouseholds(shared, remaining, before, result);
    }

    /**
     * Households the person left that still have members (R-ER3). Upkeep has recounted and
     * renamed them, except where a person typed the name (Custom Name, R-H8). A typed name can
     * name the person in any words ("The Reverend and Mrs. Smith", a nickname), so it cannot be
     * edited safely: the erasure turns Custom Name off, as the user, and the name and greetings
     * are made again from the remaining members. A household Nonprofit Cloud names is not
     * BarnCRM's to rename, and is listed for staff to check by hand. Each is reported with the
     * fields that really changed: Updated, or Kept when none did. One save and two reads for
     * every household the person left together.
     */
    private static void settleSharedHouseholds(
        List<Id> householdIds,
        Map<Id, SObject> remaining,
        Map<Id, Account> before,
        Result result
    ) {
        if (householdIds.isEmpty()) {
            return;
        }
        Set<Id> shared = new Set<Id>(householdIds);
        Set<Id> natives = HouseholdSelector.nativeHouseholdAccountsAmong(shared);
        List<Account> released = new List<Account>();
        for (Id householdId : householdIds) {
            if (
                !natives.contains(householdId) &&
                remaining.get(householdId).get('Custom_Name__c') == true
            ) {
                released.add(new Account(Id = householdId, Custom_Name__c = false));
            }
        }
        Set<Id> releasedIds = new Map<Id, Account>(released).keySet();
        if (!released.isEmpty()) {
            Database.update(released, true, AccessLevel.USER_MODE);
            // The Account trigger names a released household too; asked here as well so the
            // erasure does not rest on that automation being on. Naming twice changes nothing.
            HouseholdNamingService.applyNaming(releasedIds);
        }
        Map<Id, Account> after = householdWording(shared);
        for (Id householdId : householdIds) {
            List<String> changed = changedWording(before.get(householdId), after.get(householdId));
            Change change = new Change(
                changed.isEmpty() ? KEPT : UPDATED,
                Label.Core_Erase_Household,
                new List<Id>{ householdId },
                changed
            );
            if (natives.contains(householdId)) {
                change.note = Label.Core_Erase_NoteNativeHousehold;
            } else if (releasedIds.contains(householdId)) {
                change.note = Label.Core_Erase_NoteCustomNameReleased;
            } else {
                change.note = Label.Core_Erase_NoteRenamed;
            }
            result.changes.add(change);
        }
    }

    /** What a household's wording and count are, read in system mode to compare (R-ER3). */
    private static Map<Id, Account> householdWording(Set<Id> householdIds) {
        return new Map<Id, Account>(
            [
                SELECT
                    Id,
                    Name,
                    Custom_Name__c,
                    Household_Formal_Greeting__c,
                    Household_Informal_Greeting__c,
                    Member_Count__c,
                    Primary_Contact__c
                FROM Account
                WHERE Id IN :householdIds
                WITH SYSTEM_MODE
            ]
        );
    }

    /** The labels of the household fields whose value differs, compared case by case. */
    private static List<String> changedWording(Account before, Account after) {
        List<String> changed = new List<String>();
        if (before == null || after == null) {
            return changed;
        }
        for (Schema.SObjectField field : HOUSEHOLD_WORDING) {
            Object was = before.get(field);
            Object now = after.get(field);
            Boolean same;
            if (was == null || now == null) {
                same = was == now;
            } else {
                same = String.valueOf(was).equals(String.valueOf(now));
            }
            if (!same) {
                changed.add(field.getDescribe().getLabel());
            }
        }
        return changed;
    }

    /** Field history of this record: deleted after commit where the user may, otherwise kept. */
    private static void noteHistory(Schema.SObjectType type, Id recordId, Result result) {
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        String historyName = described.isCustom()
            ? described.getName().removeEnd('__c') + '__History'
            : described.getName() + 'History';
        String parentField = described.isCustom() ? 'ParentId' : described.getName() + 'Id';
        Schema.SObjectType history = NamespaceUtil.globalDescribe().get(historyName);
        if (history == null) {
            return;
        }
        Integer howMany = Database.countQueryWithBinds(
            'SELECT COUNT() FROM ' + historyName + ' WHERE ' + parentField + ' = :recordId',
            new Map<String, Object>{ 'recordId' => recordId },
            AccessLevel.SYSTEM_MODE
        );
        String historyLabel = String.format(
            Label.Core_Erase_HistoryOf,
            new List<String>{ described.getLabel() }
        );
        if (history.getDescribe(SObjectDescribeOptions.DEFERRED).isDeletable()) {
            String key = historyName + '.' + parentField;
            if (!historyToDelete.containsKey(key)) {
                historyToDelete.put(key, new Set<Id>());
            }
            historyToDelete.get(key).add(recordId);
            result.changes.add(
                new Change(DELETED, historyLabel, howMany, Label.Core_Erase_NoteHistoryDeleted)
            );
        } else if (howMany > 0) {
            result.changes.add(
                new Change(KEPT, historyLabel, howMany, Label.Core_Erase_NoteHistoryKept)
            );
        }
    }

    /**
     * Tasks, events and files about the person: counted and listed as kept, never changed
     * (R-ER10). A task or event counts once whether it names the person as its Name, its
     * Related To, or one of the people a shared activity names. Counted in system mode, like
     * field history, so the admin learns of ones they cannot open; only counts are shown.
     * Counted after the modules have run, leaving out what a module reported as Deleted, so a
     * record a module deleted is not listed as kept too. The rows go in at `insertAt`.
     */
    private static void noteActivitiesAndFiles(Id personId, Result result, Integer insertAt) {
        Set<Id> people = new Set<Id>{ personId };
        Set<Id> tasks = new Set<Id>();
        for (Task task : [
            SELECT Id
            FROM Task
            WHERE WhoId IN :people OR WhatId IN :people
            WITH SYSTEM_MODE
            LIMIT :ACTIVITY_CAP
        ]) {
            tasks.add(task.Id);
        }
        // TaskRelation exists only where Shared Activities is on, so it is read by name: a
        // static reference would not compile in an org without it.
        if (NamespaceUtil.objectType('TaskRelation') != null) {
            for (
                SObject relation : Database.queryWithBinds(
                    'SELECT TaskId FROM TaskRelation WHERE RelationId IN :people LIMIT :cap',
                    new Map<String, Object>{ 'people' => people, 'cap' => ACTIVITY_CAP },
                    AccessLevel.SYSTEM_MODE
                )
            ) {
                tasks.add((Id) relation.get('TaskId'));
            }
        }
        Set<Id> events = new Set<Id>();
        for (Event event : [
            SELECT Id
            FROM Event
            WHERE WhoId IN :people OR WhatId IN :people
            WITH SYSTEM_MODE
            LIMIT :ACTIVITY_CAP
        ]) {
            events.add(event.Id);
        }
        for (EventRelation relation : [
            SELECT EventId
            FROM EventRelation
            WHERE RelationId IN :people
            WITH SYSTEM_MODE
            LIMIT :ACTIVITY_CAP
        ]) {
            events.add(relation.EventId);
        }
        Set<Id> files = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :people
            WITH SYSTEM_MODE
            LIMIT :ACTIVITY_CAP
        ]) {
            files.add(link.ContentDocumentId);
        }
        Set<Id> deleted = new Set<Id>(deletedIds);
        tasks.removeAll(deleted);
        events.removeAll(deleted);
        files.removeAll(deleted);
        List<Change> rows = new List<Change>();
        noteByHand(rows, labelOf(Task.SObjectType), tasks.size());
        noteByHand(rows, labelOf(Event.SObjectType), events.size());
        noteByHand(rows, Label.Core_Erase_Files, files.size());
        for (Change change : rows) {
            if (insertAt >= result.changes.size()) {
                result.changes.add(change);
            } else {
                result.changes.add(insertAt, change);
            }
            insertAt++;
        }
    }

    private static void noteByHand(List<Change> rows, String objectLabel, Integer howMany) {
        if (howMany > 0) {
            rows.add(new Change(KEPT, objectLabel, howMany, Label.Core_Erase_NoteByHand));
        }
    }

    /** Once committed: empty the Recycle Bin of what was deleted, and queue the history cleanup. */
    private static void finishAfterCommit() {
        if (!deletedIds.isEmpty()) {
            try {
                Database.emptyRecycleBin(deletedIds);
            } catch (Exception cannotEmpty) {
                ErrorLogger.log(cannotEmpty, 'PersonErasure.emptyRecycleBin');
            }
        }
        if (!historyToDelete.isEmpty()) {
            System.enqueueJob(new PersonErasureHistoryCleanup(historyToDelete));
        }
    }

    // ----------------------------------------------------------------- clearing one record

    /** What emptying one record means: the update, and what stands in the way. */
    private class Clearing {
        SObject record;
        List<String> cleared = new List<String>();
        List<String> blocked = new List<String>();
        List<String> required = new List<String>();
    }

    /**
     * Every field of this record that can be emptied and holds a value, worked out from describe
     * (R-ER1). The name, or the surname where the object has one, becomes the placeholder.
     */
    private static Clearing plan(
        SObject record,
        Set<Schema.SObjectField> keep,
        String placeholder
    ) {
        Schema.SObjectType type = record.getSObjectType();
        Map<String, Object> values = record.getPopulatedFieldsAsMap();
        Map<String, Schema.SObjectField> tokens = type.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        Clearing result = new Clearing();
        result.record = type.newSObject(record.Id);
        Boolean accountIsHousehold = accountIsHousehold(type, values);
        Boolean named = false;
        // A household or other business account may not carry person account fields: the
        // standard Person ones and the __pc copies of contact fields. A custom Account field
        // such as Personal_Email__c is not one of them and is still cleared.
        Boolean businessAccount =
            type == Account.SObjectType && !PersonRecordSelector.isPersonRecord(record);
        for (Schema.DescribeFieldResult field : fieldsOf(type).values()) {
            String name = field.getName().toLowerCase();
            Boolean personField =
                (!field.isCustom() && name.startsWith('person')) || name.endsWith('__pc');
            if (
                (businessAccount && personField) ||
                NEVER_CLEARED.contains(name) ||
                keep.contains(tokens.get(name)) ||
                (!ERASED_THOUGH_KEPT.contains(name) &&
                DataProtectedFields.isProtected(type, name)) ||
                isCompound(field)
            ) {
                continue;
            }
            Object value = values.get(field.getName());
            Object wanted = null;
            if (field.getType() == Schema.DisplayType.BOOLEAN) {
                wanted = setOnErase(name) ? true : field.getDefaultValue() == true;
                if (value == null || value == wanted) {
                    continue;
                }
            } else if (name == SURNAME && value != null) {
                wanted = placeholder;
                named = true;
            } else if (value == null || String.isBlank(String.valueOf(value))) {
                continue;
            } else if (!field.isNillable()) {
                result.required.add(shownAs(type, field, accountIsHousehold));
                continue;
            }
            if (!field.isUpdateable()) {
                if (field.isPermissionable()) {
                    result.blocked.add(shownAs(type, field, accountIsHousehold));
                }
                continue;
            }
            result.record.put(field.getName(), wanted);
            result.cleared.add(shownAs(type, field, accountIsHousehold));
        }
        Schema.DescribeFieldResult nameField = fieldsOf(type).get('name');
        if (!named && nameField?.isUpdateable() == true) {
            result.record.put('Name', placeholder);
            result.cleared.add(nameField.getLabel());
        }
        return result;
    }

    /**
     * Whether this contact's account is its household: only in contact mode, and only when the
     * account is a household record. In junction mode, or when the account is an organization,
     * it is an employer and keeps its field label.
     */
    private static Boolean accountIsHousehold(Schema.SObjectType type, Map<String, Object> values) {
        Id householdType = HouseholdService.householdRecordTypeId();
        Id accountId = type == Contact.SObjectType ? (Id) values.get('AccountId') : null;
        if (accountId == null || householdType == null || HouseholdService.isJunctionMode()) {
            return false;
        }
        List<Account> accounts = [
            SELECT RecordTypeId
            FROM Account
            WHERE Id = :accountId
            WITH SYSTEM_MODE
        ];
        return !accounts.isEmpty() && accounts[0].RecordTypeId == householdType;
    }

    /** A field's label as the erase screen lists it: a household account reads as one. */
    private static String shownAs(
        Schema.SObjectType type,
        Schema.DescribeFieldResult field,
        Boolean accountIsHousehold
    ) {
        return accountIsHousehold && field.getName() == 'AccountId'
            ? Label.Core_Erase_Household
            : field.getLabel();
    }

    private static void refuseBlocked(Clearing clearing) {
        if (clearing != null && !clearing.blocked.isEmpty()) {
            throw new ErasureException(
                String.format(
                    Label.Core_Erase_CannotEditFields,
                    new List<String>{
                        clearing.record.getSObjectType()
                            .getDescribe(SObjectDescribeOptions.DEFERRED)
                            .getLabel(),
                        String.join(clearing.blocked, ', ')
                    }
                )
            );
        }
    }

    private static void save(Clearing clearing, Result result) {
        save(clearing, result, labelOf(clearing.record.getSObjectType()), null);
    }

    /** Saves the clearing and reports it under this label, with this note. */
    private static void save(Clearing clearing, Result result, String objectLabel, String note) {
        Database.update(clearing.record, true, AccessLevel.USER_MODE);
        List<Id> one = new List<Id>{ clearing.record.Id };
        add(result, CLEARED, objectLabel, one, clearing.cleared, note);
        if (!clearing.required.isEmpty()) {
            Change kept = new Change(KEPT, objectLabel, one, clearing.required);
            kept.note = Label.Core_Erase_NoteRequired;
            result.changes.add(kept);
        }
    }

    private static Boolean setOnErase(String lowerCaseName) {
        if (SET_FLAGS.contains(lowerCaseName)) {
            return true;
        }
        for (String prefix : SET_FLAG_PREFIXES) {
            if (lowerCaseName.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    /** An address or location field: its parts are cleared one by one. */
    private static Boolean isCompound(Schema.DescribeFieldResult field) {
        Schema.DisplayType kind = field.getType();
        return kind == Schema.DisplayType.ADDRESS ||
            kind == Schema.DisplayType.LOCATION ||
            kind == Schema.DisplayType.BASE64 ||
            field.isCalculated() ||
            field.isAutoNumber();
    }

    // ------------------------------------------------------------------------------ reads

    private static Map<String, Schema.DescribeFieldResult> fieldsOf(Schema.SObjectType type) {
        if (!describedFields.containsKey(type)) {
            Map<String, Schema.DescribeFieldResult> result = new Map<String, Schema.DescribeFieldResult>();
            for (
                Schema.SObjectField token : type.getDescribe(SObjectDescribeOptions.DEFERRED)
                    .fields.getMap()
                    .values()
            ) {
                Schema.DescribeFieldResult field = token.getDescribe();
                result.put(field.getName().toLowerCase(), field);
            }
            describedFields.put(type, result);
        }
        return describedFields.get(type);
    }

    /** These records with every field the erasure may clear, in system mode (R-ER5). */
    private static List<SObject> readAll(Schema.SObjectType type, Set<Id> recordIds) {
        List<String> names = new List<String>();
        for (Schema.DescribeFieldResult field : fieldsOf(type).values()) {
            if (!isCompound(field) || field.getName() == 'Id') {
                names.add(field.getName());
            }
        }
        return Database.queryWithBinds(
            'SELECT ' +
                String.join(names, ', ') +
                ' FROM ' +
                type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
                ' WHERE Id IN :ids',
            new Map<String, Object>{ 'ids' => recordIds },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static List<SObject> rows(String query, Set<Id> recordIds) {
        return Database.queryWithBinds(
            query + ' LIMIT 10000',
            new Map<String, Object>{ 'ids' => recordIds },
            AccessLevel.SYSTEM_MODE
        );
    }

    /** The person's Individual record, where the org has the object and the person a link. */
    private static SObject individualOf(SObject person) {
        Schema.SObjectType type = NamespaceUtil.globalDescribe().get(INDIVIDUAL_OBJECT);
        String link = INDIVIDUAL_LINK.get(person.getSObjectType()).toLowerCase();
        if (type == null || !fieldsOf(person.getSObjectType()).containsKey(link)) {
            return null;
        }
        Object individualId = person.getPopulatedFieldsAsMap()
            .get(fieldsOf(person.getSObjectType()).get(link).getName());
        if (individualId == null) {
            return null;
        }
        List<SObject> found = readAll(type, new Set<Id>{ (Id) individualId });
        return found.isEmpty() ? null : found[0];
    }

    /** Adds the label of this object to `refused` when the user lacks this access to any of these. */
    private static void refuseWithout(
        List<Id> recordIds,
        String access,
        Schema.SObjectType type,
        List<String> refused
    ) {
        if (recordIds.isEmpty()) {
            return;
        }
        List<Id> all = recordIds;
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        Boolean objectAllowed = access == 'HasDeleteAccess'
            ? described.isDeletable()
            : described.isUpdateable();
        Integer missing = objectAllowed ? 0 : all.size();
        for (Integer start = 0; objectAllowed && start < all.size(); start += ACCESS_CHUNK) {
            Set<Id> chunk = new Set<Id>();
            for (Integer i = start; i < Math.min(start + ACCESS_CHUNK, all.size()); i++) {
                chunk.add(all[i]);
            }
            Id userId = UserInfo.getUserId();
            Integer allowed = 0;
            for (UserRecordAccess row : [
                SELECT RecordId, HasEditAccess, HasDeleteAccess
                FROM UserRecordAccess
                WHERE UserId = :userId AND RecordId IN :chunk
                WITH USER_MODE
                LIMIT 200
            ]) {
                if (row.get(access) == true) {
                    allowed++;
                }
            }
            missing += chunk.size() - allowed;
        }
        if (missing > 0) {
            refused.add(missing + ' ' + described.getLabelPlural());
        }
    }

    // ------------------------------------------------------------------------- reporting

    private static void add(
        Result result,
        String action,
        Schema.SObjectType type,
        List<Id> recordIds,
        List<String> fields
    ) {
        add(result, action, labelOf(type), recordIds, fields, null);
    }

    private static void add(
        Result result,
        String action,
        String label,
        List<Id> recordIds,
        List<String> fields,
        String note
    ) {
        if (recordIds == null || recordIds.isEmpty()) {
            return;
        }
        Change change = new Change(action, label, recordIds, fields);
        change.note = note;
        result.changes.add(change);
    }

    private static List<String> endedFields(Schema.SObjectType type, Boolean affiliation) {
        Map<String, Schema.DescribeFieldResult> fields = fieldsOf(type);
        List<String> names = new List<String>{ 'end_date__c' };
        if (type != Household_Member__c.SObjectType) {
            names.add('description__c');
        } else {
            names.add('is_primary__c');
        }
        if (affiliation) {
            names.add('role__c');
            names.add('is_primary__c');
        }
        List<String> labels = new List<String>();
        for (String name : names) {
            labels.add(fields.get(name).getLabel());
        }
        return labels;
    }

    private static String labelOf(Schema.SObjectType type) {
        return type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
    }

    /**
     * The audit text: one line per change, labels and Ids only (R-ER5), with what was done in
     * the words the erase screen shows.
     */
    @TestVisible
    private static String details(List<Change> changes) {
        Map<String, String> shown = new Map<String, String>{
            CLEARED => Label.Core_EraseAction_Cleared,
            ENDED => Label.Core_EraseAction_Ended,
            DELETED => Label.Core_EraseAction_Deleted,
            KEPT => Label.Core_EraseAction_Kept,
            UPDATED => Label.Core_EraseAction_Updated
        };
        List<String> lines = new List<String>();
        for (Change change : changes) {
            String action = shown.containsKey(change.action)
                ? shown.get(change.action)
                : change.action;
            String line = action + ' | ' + change.objectLabel + ' | ' + change.count;
            if (!change.fields.isEmpty()) {
                line += ' | ' + String.join(change.fields, ', ');
            }
            if (String.isNotBlank(change.note)) {
                line += ' | ' + change.note;
            }
            if (!change.recordIds.isEmpty()) {
                line += ' | ' + String.join(change.recordIds, ' ');
            }
            lines.add(line);
        }
        return String.join(lines, '\n');
    }

    private static List<Id> ids(List<SObject> records) {
        return records == null
            ? new List<Id>()
            : new List<Id>(new Map<Id, SObject>(records).keySet());
    }

    private static String normalized(String value) {
        return value == null ? '' : value.normalizeSpace().toLowerCase();
    }
}
