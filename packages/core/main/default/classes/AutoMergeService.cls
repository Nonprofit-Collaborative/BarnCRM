/**
 * Auto-merge of exact people matches, journaled and undoable (C-51, canonical model R-DP9 and
 * R-DP10, ADR-0145 advanced duplicate management).
 *
 * Candidates are the open people pairs in the review list that meet the Exact Match For
 * Auto-Merge setting. The kept person is the one whose household has more members, else the
 * record created first; the values the merge rules choose (MergeRuleService) are written onto
 * them by the platform's own merge. Everything runs in user mode, as the administrator.
 *
 * Before each merge a Merge Journal row records the values the rules change and every related
 * record whose link to the merged-away person can be changed. Undo undeletes the merged-away
 * person from the Recycle Bin, never a recreated copy, puts back each value still as the merge
 * left it and moves each recorded related record still on the kept person back. What it cannot
 * restore is written on the row.
 */
public with sharing class AutoMergeService {
    public static final String NAME_AND_EMAIL = 'Name and email';
    public static final String NAME_AND_PHONE = 'Name and phone';
    public static final String NAME_EMAIL_AND_PHONE = 'Name, email and phone';
    public static final String NAME_AND_BIRTHDATE = 'Name and birthdate';
    private static final Set<String> EXACT_RULES = new Set<String>{
        NAME_AND_EMAIL,
        NAME_AND_PHONE,
        NAME_EMAIL_AND_PHONE,
        NAME_AND_BIRTHDATE
    };

    public static final String MERGED = 'Merged';
    public static final String UNDONE = 'Undone';
    public static final String PARTLY_UNDONE = 'Partly Undone';
    public static final String UNDO_FAILED = 'Undo Failed';

    /** The most pairs one run takes, and the days a run can be undone (the Recycle Bin's). */
    public static final Integer MAX_PAIRS = 1000;
    public static final Integer UNDO_DAYS = 15;

    private static final String CONTEXT = 'Auto-merge';
    private static final String SEPARATOR = ':';
    private static final Integer SETS_PER_READ = 500;
    private static final Integer MAX_READS = 4;
    /** Queries left untouched for the merge itself when recording related records. */
    private static final Integer QUERY_RESERVE = 30;
    private static final Integer MAX_CHILD_ROWS = 2000;
    /**
     * Journal key for the membership rows a merge gave the kept person (junction mode). Not an
     * "Object.Field" link: the contact trigger deletes the merged-away person's own rows before
     * the merge and copies them to the kept person, and undelete brings the originals back, so
     * undo removes these copies instead of moving anything (C-20, ContactTriggerHandler).
     */
    private static final String ADDED_MEMBERSHIPS = 'Household_Member__c+';
    private static final Set<String> PERSON_FIELDS = new Set<String>{
        'Id',
        'Name',
        'FirstName',
        'LastName',
        'Email',
        'Phone',
        'Birthdate',
        'AccountId',
        'CreatedDate',
        'LastModifiedDate'
    };

    /** Test seam: pairs of people standing in for the review list, as [first, second]. */
    @TestVisible
    private static List<List<Id>> pairsForTest;

    /** Pairs a run could not merge, counted for its summary. */
    public static Integer failureCount = 0;

    /** One value the merge rules change on the kept person. */
    public class Change {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String before;
        @AuraEnabled
        public String after;
    }

    /** One pair auto-merge would merge, as the preview shows it. */
    public class Candidate {
        @AuraEnabled
        public String ref;
        @AuraEnabled
        public Id survivorId;
        @AuraEnabled
        public String survivorName;
        @AuraEnabled
        public Id mergedId;
        @AuraEnabled
        public String mergedName;
        @AuraEnabled
        public List<Change> changes = new List<Change>();
        public Id setId;
        public Contact survivor;
        public Map<String, Object> values;
    }

    /** The Exact Match For Auto-Merge setting; blank or unknown reads as Name and email. */
    public static String exactRule() {
        String configured = SettingsService.getSettings().Auto_Merge_Exact_Match__c;
        return EXACT_RULES.contains(configured) ? configured : NAME_AND_EMAIL;
    }

    // ------------------------------------------------------------------ finding the pairs

    /** Every pair auto-merge would take now, at most MAX_PAIRS, each person in one pair. */
    public static List<Candidate> candidates() {
        List<String> refs = new List<String>();
        if (pairsForTest != null) {
            for (List<Id> pair : pairsForTest) {
                refs.add(ref(null, pair[0], pair[1]));
            }
        } else {
            refs = openPeoplePairs();
        }
        return candidatesFor(refs);
    }

    /**
     * The pairs among these references ("set:first:second") that are still exact, read again
     * now, so a pair changed or dismissed since the preview is passed over.
     */
    public static List<Candidate> candidatesFor(List<String> refs) {
        List<Candidate> result = new List<Candidate>();
        Set<Id> people = new Set<Id>();
        Set<Id> setIds = new Set<Id>();
        for (String reference : refs) {
            List<String> parts = reference.split(SEPARATOR, -1);
            people.add((Id) parts[1]);
            people.add((Id) parts[2]);
            if (String.isNotBlank(parts[0])) {
                setIds.add((Id) parts[0]);
            }
        }
        Set<Id> openSets = new Map<Id, DuplicateRecordSet>(DuplicateSelector.setsByIds(setIds))
            .keySet();
        List<String> mergeable = MergeRuleService.mergeableFields();
        Map<Id, Contact> byId = new Map<Id, Contact>(readPeople(people, mergeable));
        Map<Id, Integer> members = memberCounts(byId.values());
        String rule = exactRule();
        Set<Id> used = new Set<Id>();
        for (String reference : refs) {
            List<String> parts = reference.split(SEPARATOR, -1);
            Id setId = String.isBlank(parts[0]) ? null : (Id) parts[0];
            Contact first = byId.get((Id) parts[1]);
            Contact second = byId.get((Id) parts[2]);
            Boolean usable =
                first != null &&
                second != null &&
                (setId == null || openSets.contains(setId)) &&
                !used.contains(first.Id) &&
                !used.contains(second.Id) &&
                isExact(first, second, rule);
            if (usable && result.size() < MAX_PAIRS) {
                used.add(first.Id);
                used.add(second.Id);
                result.add(candidate(setId, first, second, members, mergeable));
            }
        }
        return result;
    }

    /** The open suggestions that pair exactly two people nobody dismissed, as references. */
    private static List<String> openPeoplePairs() {
        List<String> refs = new List<String>();
        List<DuplicateService.Pair> pairs = new List<DuplicateService.Pair>();
        Map<String, Id> setByKey = new Map<String, Id>();
        List<DuplicateRecordSet> window = DuplicateSelector.openSetsAfter(SETS_PER_READ, null);
        Integer reads = 1;
        while (true) {
            for (DuplicateRecordSet found : window) {
                List<DuplicateRecordItem> items = found.DuplicateRecordItems;
                if (
                    items.size() == 2 &&
                    items[0].RecordId.getSObjectType() == Contact.SObjectType &&
                    items[1].RecordId.getSObjectType() == Contact.SObjectType
                ) {
                    DuplicateService.Pair pair = new DuplicateService.Pair(
                        items[0].RecordId,
                        items[1].RecordId,
                        null
                    );
                    pairs.add(pair);
                    setByKey.put(pair.key, found.Id);
                }
            }
            if (window.size() < SETS_PER_READ || reads >= MAX_READS) {
                break;
            }
            window = DuplicateSelector.openSetsAfter(SETS_PER_READ, window[window.size() - 1]);
            reads++;
        }
        for (
            DuplicateService.Pair pair : DuplicateService.withoutDismissed(
                DuplicateService.actionablePairs(pairs)
            )
        ) {
            refs.add(ref(setByKey.get(pair.key), pair.left, pair.right));
        }
        return refs;
    }

    /**
     * True when the two meet the rule: the same normalized first and last name, and the same
     * email, phone (digits), both, or birthdate, each filled in on both. Two people whose
     * birthdates are both filled in and differ are never exact (R-DP9).
     */
    public static Boolean isExact(Contact first, Contact second, String rule) {
        Map<String, Object> a = first.getPopulatedFieldsAsMap();
        Map<String, Object> b = second.getPopulatedFieldsAsMap();
        Date firstBorn = (Date) a.get('Birthdate');
        Date secondBorn = (Date) b.get('Birthdate');
        if (firstBorn != null && secondBorn != null && firstBorn != secondBorn) {
            return false;
        }
        String firstName = FuzzyMatch.normalize((String) a.get('FirstName'));
        Boolean sameName =
            String.isNotEmpty(firstName) &&
            firstName.equals(FuzzyMatch.normalize((String) b.get('FirstName'))) &&
            FuzzyMatch.normalize((String) a.get('LastName'))
                .equals(FuzzyMatch.normalize((String) b.get('LastName')));
        if (!sameName) {
            return false;
        }
        Boolean sameEmail = same(
            MatchSourceService.email((String) a.get('Email')),
            MatchSourceService.email((String) b.get('Email'))
        );
        Boolean samePhone = same(
            MatchSourceService.phone((String) a.get('Phone')),
            MatchSourceService.phone((String) b.get('Phone'))
        );
        if (rule == NAME_AND_PHONE) {
            return samePhone;
        }
        if (rule == NAME_EMAIL_AND_PHONE) {
            return sameEmail && samePhone;
        }
        if (rule == NAME_AND_BIRTHDATE) {
            return firstBorn != null && firstBorn == secondBorn;
        }
        return sameEmail;
    }

    private static Boolean same(String first, String second) {
        return first != null && first.equals(second);
    }

    /**
     * The pair as it would be merged: the kept person is the one whose household has more
     * members (they stay with their family), else the record created first.
     */
    private static Candidate candidate(
        Id setId,
        Contact first,
        Contact second,
        Map<Id, Integer> members,
        List<String> mergeable
    ) {
        Integer firstCount = memberCount(members, first);
        Integer secondCount = memberCount(members, second);
        Boolean keepFirst = firstCount != secondCount
            ? firstCount > secondCount
            : first.CreatedDate != second.CreatedDate
                  ? first.CreatedDate < second.CreatedDate
                  : String.valueOf(first.Id).compareTo(String.valueOf(second.Id)) < 0;
        Contact survivor = keepFirst ? first : second;
        Contact merged = keepFirst ? second : first;
        Candidate result = new Candidate();
        result.ref = ref(setId, first.Id, second.Id);
        result.setId = setId;
        result.survivor = survivor;
        result.survivorId = survivor.Id;
        result.survivorName = (String) survivor.getPopulatedFieldsAsMap().get('Name');
        result.mergedId = merged.Id;
        result.mergedName = (String) merged.getPopulatedFieldsAsMap().get('Name');
        result.values = MergeRuleService.winningValues(survivor, merged, mergeable);
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Contact.fields.getMap();
        for (String field : result.values.keySet()) {
            Change change = new Change();
            change.label = fields.get(field).getDescribe().getLabel();
            change.before = text(survivor.get(field));
            change.after = text(result.values.get(field));
            result.changes.add(change);
        }
        return result;
    }

    private static Integer memberCount(Map<Id, Integer> members, Contact person) {
        Integer count = members.get((Id) person.getPopulatedFieldsAsMap().get('AccountId'));
        return count == null ? 0 : count;
    }

    private static String ref(Id setId, Id first, Id second) {
        return (setId == null ? '' : String.valueOf(setId)) +
            SEPARATOR +
            first +
            SEPARATOR +
            second;
    }

    private static String text(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static List<Contact> readPeople(Set<Id> ids, List<String> mergeable) {
        if (ids.isEmpty()) {
            return new List<Contact>();
        }
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Contact.fields.getMap();
        Map<String, String> names = new Map<String, String>();
        for (String name : PERSON_FIELDS) {
            Schema.SObjectField token = fields.get(name);
            if (token != null && token.getDescribe().isAccessible()) {
                names.put(name.toLowerCase(), name);
            }
        }
        for (String name : mergeable) {
            names.put(name.toLowerCase(), name);
        }
        names.put('id', 'Id');
        return Database.queryWithBinds(
            'SELECT ' + String.join(names.values(), ', ') + ' FROM Contact WHERE Id IN :ids',
            new Map<String, Object>{ 'ids' => ids },
            AccessLevel.USER_MODE
        );
    }

    /** How many people each household has, as this person can see them. */
    private static Map<Id, Integer> memberCounts(List<Contact> people) {
        Set<Id> households = new Set<Id>();
        for (Contact person : people) {
            Id household = (Id) person.getPopulatedFieldsAsMap().get('AccountId');
            if (household != null) {
                households.add(household);
            }
        }
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (households.isEmpty()) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT AccountId household, COUNT(Id) members
            FROM Contact
            WHERE AccountId IN :households
            WITH USER_MODE
            GROUP BY AccountId
        ]) {
            counts.put((Id) row.get('household'), (Integer) row.get('members'));
        }
        return counts;
    }

    // ------------------------------------------------------------------ merging

    /**
     * Merges each pair with the platform's merge in user mode, recording a journal row first,
     * and closes its suggestion. A pair that fails is rolled back alone, logged and counted.
     * Answers how many were merged.
     */
    public static Integer mergeAll(List<Candidate> pairs, String runId) {
        Set<Id> mergedIds = new Set<Id>();
        for (Candidate pair : pairs) {
            mergedIds.add(pair.mergedId);
        }
        Map<Id, Moved> moved = movedRecords(mergedIds);
        Set<Id> survivorIds = new Set<Id>();
        for (Candidate pair : pairs) {
            survivorIds.add(pair.survivorId);
        }
        Map<Id, Set<Id>> membershipsBefore = membershipIds(survivorIds);
        // Not named "merged": Apex names are case-insensitive, so it would hide the MERGED status.
        Integer mergedCount = 0;
        for (Candidate pair : pairs) {
            Savepoint beforePair = Database.setSavepoint();
            try {
                Contact master = new Contact(Id = pair.survivorId);
                Map<String, Object> changed = new Map<String, Object>();
                for (String field : pair.values.keySet()) {
                    master.put(field, pair.values.get(field));
                    changed.put(
                        field,
                        new Map<String, Object>{
                            'before' => pair.survivor.get(field),
                            'after' => pair.values.get(field)
                        }
                    );
                }
                Moved records = moved.get(pair.mergedId);
                Database.MergeResult result = Database.merge(
                    master,
                    pair.mergedId,
                    false,
                    AccessLevel.USER_MODE
                );
                if (!result.isSuccess()) {
                    throw new DuplicateService.DuplicateException(
                        result.getErrors()[0].getMessage()
                    );
                }
                List<Id> added = addedMemberships(pair.survivorId, membershipsBefore);
                if (!added.isEmpty()) {
                    records.byLink.put(ADDED_MEMBERSHIPS, added);
                }
                Database.insert(
                    new Merge_Journal__c(
                        Run_Id__c = runId,
                        Survivor_Id__c = pair.survivorId,
                        Merged_Id__c = pair.mergedId,
                        Merged_Name__c = pair.mergedName == null ? null : pair.mergedName.left(255),
                        Status__c = MERGED,
                        Changed_Values__c = JSON.serialize(changed),
                        Moved_Records__c = JSON.serialize(records.byLink),
                        Notes__c = notes(records.notes)
                    ),
                    AccessLevel.USER_MODE
                );
                DuplicateService.closeSet(pair.setId);
                mergedCount++;
            } catch (Exception caught) {
                Database.rollback(beforePair);
                failureCount++;
                ErrorLogger.log(caught, CONTEXT);
            }
        }
        return mergedCount;
    }

    /** Each person's current membership row ids (junction mode; empty otherwise). */
    private static Map<Id, Set<Id>> membershipIds(Set<Id> personIds) {
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        for (Id personId : personIds) {
            result.put(personId, new Set<Id>());
        }
        if (personIds.isEmpty() || !HouseholdService.isJunctionMode()) {
            return result;
        }
        for (Household_Member__c row : [
            SELECT Id, Contact__c
            FROM Household_Member__c
            WHERE Contact__c IN :personIds
            WITH USER_MODE
        ]) {
            result.get(row.Contact__c).add(row.Id);
        }
        return result;
    }

    /**
     * The membership rows the merge just gave this kept person. Also records the kept person's
     * rows now, which is where the next pair with the same kept person starts from.
     */
    private static List<Id> addedMemberships(Id survivorId, Map<Id, Set<Id>> before) {
        if (!HouseholdService.isJunctionMode()) {
            return new List<Id>();
        }
        Set<Id> now = membershipIds(new Set<Id>{ survivorId }).get(survivorId);
        List<Id> added = new List<Id>();
        for (Id rowId : now) {
            if (!before.get(survivorId).contains(rowId)) {
                added.add(rowId);
            }
        }
        before.put(survivorId, now);
        return added;
    }

    /** The related records of one merged-away person, by "Object.Field", and what was missed. */
    private class Moved {
        Map<String, List<Id>> byLink = new Map<String, List<Id>>();
        List<String> notes = new List<String>();
    }

    /**
     * Every related record pointing at these people through a link the person merging can
     * change, which is what the merge will move to the kept person. One query per link for
     * all of them; a link that cannot be read, or would leave too few queries for the merge,
     * is named in the notes instead.
     */
    private static Map<Id, Moved> movedRecords(Set<Id> mergedIds) {
        Map<Id, Moved> result = new Map<Id, Moved>();
        for (Id mergedId : mergedIds) {
            result.put(mergedId, new Moved());
        }
        if (mergedIds.isEmpty()) {
            return result;
        }
        for (Schema.ChildRelationship link : Schema.SObjectType.Contact.getChildRelationships()) {
            Schema.DescribeFieldResult field = link.getField().getDescribe();
            Schema.DescribeSObjectResult child = link.getChildSObject()
                .getDescribe(SObjectDescribeOptions.DEFERRED);
            // Memberships are not moved by the merge: see ADDED_MEMBERSHIPS.
            if (
                link.getChildSObject() == Household_Member__c.SObjectType ||
                !field.isUpdateable() ||
                !field.isFilterable() ||
                !child.isQueryable() ||
                !child.isUpdateable()
            ) {
                continue;
            }
            String key = child.getName() + '.' + field.getName();
            String missed;
            if (Limits.getQueries() >= Limits.getLimitQueries() - QUERY_RESERVE) {
                missed = key;
            } else {
                try {
                    List<SObject> rows = Database.queryWithBinds(
                        'SELECT Id, ' +
                            field.getName() +
                            ' FROM ' +
                            child.getName() +
                            ' WHERE ' +
                            field.getName() +
                            ' IN :ids LIMIT ' +
                            MAX_CHILD_ROWS,
                        new Map<String, Object>{ 'ids' => mergedIds },
                        AccessLevel.USER_MODE
                    );
                    for (SObject row : rows) {
                        Moved records = result.get((Id) row.get(field.getName()));
                        if (records != null) {
                            if (!records.byLink.containsKey(key)) {
                                records.byLink.put(key, new List<Id>());
                            }
                            records.byLink.get(key).add(row.Id);
                        }
                    }
                    if (rows.size() >= MAX_CHILD_ROWS) {
                        missed = key;
                    }
                } catch (Exception unreadable) {
                    missed = key;
                }
            }
            if (missed != null) {
                for (Moved records : result.values()) {
                    records.notes.add(
                        String.format(
                            Label.Core_AutoMerge_NoteNotRecorded,
                            new List<Object>{ missed }
                        )
                    );
                }
            }
        }
        return result;
    }

    private static String notes(List<String> lines) {
        return lines.isEmpty() ? null : String.join(lines, '\n').left(32768);
    }

    // ------------------------------------------------------------------ undo

    /**
     * Undoes these merges: undeletes each merged-away person, then puts back each changed value
     * still as the merge left it and moves each recorded related record still on the kept
     * person back. Each row ends Undone, Partly Undone or Undo Failed, with what was not
     * restored in its notes.
     */
    public static void undo(List<Merge_Journal__c> journals) {
        Map<Id, List<String>> notesById = new Map<Id, List<String>>();
        List<Merge_Journal__c> restored = restorePeople(journals, notesById);
        restoreValues(restored, notesById);
        moveBack(restored, notesById);
        removeAddedMemberships(restored, notesById);
        for (Merge_Journal__c journal : journals) {
            List<String> lines = notesById.get(journal.Id);
            if (journal.Status__c != UNDO_FAILED) {
                journal.Status__c = lines.isEmpty() ? UNDONE : PARTLY_UNDONE;
            }
            List<String> all = new List<String>();
            if (String.isNotBlank(journal.Notes__c)) {
                all.add(journal.Notes__c);
            }
            all.addAll(lines);
            journal.Notes__c = notes(all);
        }
        Database.update(journals, false, AccessLevel.USER_MODE);
    }

    private static List<Merge_Journal__c> restorePeople(
        List<Merge_Journal__c> journals,
        Map<Id, List<String>> notesById
    ) {
        List<Id> mergedIds = new List<Id>();
        for (Merge_Journal__c journal : journals) {
            notesById.put(journal.Id, new List<String>());
            mergedIds.add(journal.Merged_Id__c);
        }
        List<Database.UndeleteResult> results = Database.undelete(
            mergedIds,
            false,
            AccessLevel.USER_MODE
        );
        List<Merge_Journal__c> restored = new List<Merge_Journal__c>();
        for (Integer i = 0; i < journals.size(); i++) {
            if (results[i].isSuccess()) {
                restored.add(journals[i]);
                continue;
            }
            journals[i].Status__c = UNDO_FAILED;
            notesById.get(journals[i].Id)
                .add(
                    String.format(
                        Label.Core_AutoMerge_NoteNotUndeleted,
                        new List<Object>{
                            journals[i].Merged_Name__c,
                            results[i].getErrors()[0].getMessage()
                        }
                    )
                );
        }
        return restored;
    }

    private static void restoreValues(
        List<Merge_Journal__c> journals,
        Map<Id, List<String>> notesById
    ) {
        Map<Id, Map<String, Object>> changesById = new Map<Id, Map<String, Object>>();
        Set<String> fieldNames = new Set<String>();
        Set<Id> survivorIds = new Set<Id>();
        for (Merge_Journal__c journal : journals) {
            Map<String, Object> changes = String.isBlank(journal.Changed_Values__c)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(journal.Changed_Values__c);
            if (!changes.isEmpty()) {
                changesById.put(journal.Id, changes);
                fieldNames.addAll(changes.keySet());
                survivorIds.add(journal.Survivor_Id__c);
            }
        }
        if (changesById.isEmpty()) {
            return;
        }
        // Only names that are Contact fields go into the query, whatever the row says.
        Map<String, Schema.SObjectField> contactFields = Schema.SObjectType.Contact.fields.getMap();
        for (String name : new List<String>(fieldNames)) {
            if (!contactFields.containsKey(name)) {
                fieldNames.remove(name);
            }
        }
        fieldNames.add('Id');
        Map<Id, Contact> survivors = new Map<Id, Contact>(
            (List<Contact>) Database.queryWithBinds(
                'SELECT ' +
                    String.join(new List<String>(fieldNames), ', ') +
                    ' FROM Contact WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => survivorIds },
                AccessLevel.USER_MODE
            )
        );
        List<Contact> updates = new List<Contact>();
        List<Merge_Journal__c> updated = new List<Merge_Journal__c>();
        for (Merge_Journal__c journal : journals) {
            Map<String, Object> changes = changesById.get(journal.Id);
            Contact survivor = survivors.get(journal.Survivor_Id__c);
            if (changes == null) {
                continue;
            }
            if (survivor == null) {
                notesById.get(journal.Id).add(Label.Core_AutoMerge_NoteSurvivorGone);
                continue;
            }
            Map<String, Object> putBack = new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Contact' },
                'Id' => survivor.Id
            };
            for (String field : changes.keySet()) {
                Map<String, Object> change = (Map<String, Object>) changes.get(field);
                Boolean unchanged =
                    fieldNames.contains(field) &&
                    JSON.serialize(survivor.get(field)).equals(JSON.serialize(change.get('after')));
                if (unchanged) {
                    putBack.put(field, change.get('before'));
                } else {
                    notesById.get(journal.Id)
                        .add(
                            String.format(
                                Label.Core_AutoMerge_NoteValueChanged,
                                new List<Object>{ field }
                            )
                        );
                }
            }
            if (putBack.size() > 2) {
                updates.add((Contact) JSON.deserialize(JSON.serialize(putBack), Contact.class));
                updated.add(journal);
            }
        }
        List<Database.SaveResult> saves = Database.update(updates, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < saves.size(); i++) {
            if (!saves[i].isSuccess()) {
                notesById.get(updated[i].Id)
                    .add(
                        String.format(
                            Label.Core_AutoMerge_NoteValuesRefused,
                            new List<Object>{ saves[i].getErrors()[0].getMessage() }
                        )
                    );
            }
        }
    }

    private static void moveBack(List<Merge_Journal__c> journals, Map<Id, List<String>> notesById) {
        // Each recorded related record: which link, back to whom, and whose journal it is.
        Map<String, Map<Id, Merge_Journal__c>> ownerByLink = new Map<String, Map<Id, Merge_Journal__c>>();
        for (Merge_Journal__c journal : journals) {
            if (String.isBlank(journal.Moved_Records__c)) {
                continue;
            }
            Map<String, Object> byLink = (Map<String, Object>) JSON.deserializeUntyped(
                journal.Moved_Records__c
            );
            for (String key : byLink.keySet()) {
                if (key == ADDED_MEMBERSHIPS) {
                    continue;
                }
                if (!ownerByLink.containsKey(key)) {
                    ownerByLink.put(key, new Map<Id, Merge_Journal__c>());
                }
                for (Object recordId : (List<Object>) byLink.get(key)) {
                    ownerByLink.get(key).put((Id) String.valueOf(recordId), journal);
                }
            }
        }
        Map<String, Schema.SObjectType> types = ownerByLink.isEmpty()
            ? new Map<String, Schema.SObjectType>()
            : Schema.getGlobalDescribe();
        for (String key : ownerByLink.keySet()) {
            Map<Id, Merge_Journal__c> owners = ownerByLink.get(key);
            String objectName = key.substringBefore('.');
            String fieldName = key.substringAfter('.');
            List<SObject> moves = new List<SObject>();
            List<Merge_Journal__c> moveOwners = new List<Merge_Journal__c>();
            Set<Id> found = new Set<Id>();
            try {
                // Only a real object and field go into the query, whatever the row says.
                Schema.SObjectType type = types.get(objectName);
                if (type == null || !type.getDescribe().fields.getMap().containsKey(fieldName)) {
                    throw new DuplicateService.DuplicateException(key);
                }
                Set<Id> ids = owners.keySet();
                for (
                    SObject row : Database.queryWithBinds(
                        'SELECT Id, ' + fieldName + ' FROM ' + objectName + ' WHERE Id IN :ids',
                        new Map<String, Object>{ 'ids' => ids },
                        AccessLevel.USER_MODE
                    )
                ) {
                    found.add(row.Id);
                    Merge_Journal__c owner = owners.get(row.Id);
                    String now = String.valueOf(row.get(fieldName));
                    // On the kept person, or emptied since by automation that keeps the link
                    // (household upkeep clears the Primary Contact of a household the merge
                    // emptied): either way it goes back to the restored person.
                    if (now == owner.Survivor_Id__c || now == null) {
                        SObject move = row.getSObjectType().newSObject(row.Id);
                        move.put(fieldName, owner.Merged_Id__c);
                        moves.add(move);
                        moveOwners.add(owner);
                    } else if (now != owner.Merged_Id__c) {
                        // A link already back on the restored person counts as restored: one
                        // that automation keeps (a household's Primary Contact, recomputed when
                        // the memberships come back with the undelete) is back before this runs.
                        // Anything else was moved since.
                        addOnce(notesById, owner, Label.Core_AutoMerge_NoteRecordMovedSince, key);
                    }
                }
                List<Database.SaveResult> saves = Database.update(
                    moves,
                    false,
                    AccessLevel.USER_MODE
                );
                for (Integer i = 0; i < saves.size(); i++) {
                    if (!saves[i].isSuccess()) {
                        addOnce(
                            notesById,
                            moveOwners[i],
                            Label.Core_AutoMerge_NoteRecordRefused,
                            key
                        );
                    }
                }
            } catch (Exception unreadable) {
                for (Merge_Journal__c owner : new Set<Merge_Journal__c>(owners.values())) {
                    addOnce(notesById, owner, Label.Core_AutoMerge_NoteRecordRefused, key);
                }
                continue;
            }
            for (Id recordId : owners.keySet()) {
                if (!found.contains(recordId)) {
                    addOnce(
                        notesById,
                        owners.get(recordId),
                        Label.Core_AutoMerge_NoteRecordGone,
                        key
                    );
                }
            }
        }
    }

    /**
     * Takes away the membership rows each merge gave the kept person, so the kept person leaves
     * the households they joined only through the merge; the restored person's own rows came
     * back with the undelete. A row deleted since needs nothing; one moved to somebody else
     * since is left and noted. Deleted with the user's access, so the membership trigger
     * recounts and renames the households.
     */
    private static void removeAddedMemberships(
        List<Merge_Journal__c> journals,
        Map<Id, List<String>> notesById
    ) {
        Map<Id, Merge_Journal__c> ownerByRow = new Map<Id, Merge_Journal__c>();
        for (Merge_Journal__c journal : journals) {
            if (String.isBlank(journal.Moved_Records__c)) {
                continue;
            }
            Object rows = ((Map<String, Object>) JSON.deserializeUntyped(journal.Moved_Records__c))
                .get(ADDED_MEMBERSHIPS);
            for (Object rowId : rows == null ? new List<Object>() : (List<Object>) rows) {
                ownerByRow.put((Id) String.valueOf(rowId), journal);
            }
        }
        if (ownerByRow.isEmpty()) {
            return;
        }
        String key = String.valueOf(Household_Member__c.SObjectType);
        List<Household_Member__c> removing = new List<Household_Member__c>();
        List<Merge_Journal__c> removingOwners = new List<Merge_Journal__c>();
        try {
            Set<Id> rowIds = ownerByRow.keySet();
            for (Household_Member__c row : [
                SELECT Id, Contact__c
                FROM Household_Member__c
                WHERE Id IN :rowIds
                WITH USER_MODE
            ]) {
                Merge_Journal__c owner = ownerByRow.get(row.Id);
                if (String.valueOf(row.Contact__c) == owner.Survivor_Id__c) {
                    removing.add(row);
                    removingOwners.add(owner);
                } else {
                    addOnce(notesById, owner, Label.Core_AutoMerge_NoteRecordMovedSince, key);
                }
            }
            List<Database.DeleteResult> results = Database.delete(
                removing,
                false,
                AccessLevel.USER_MODE
            );
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    addOnce(
                        notesById,
                        removingOwners[i],
                        Label.Core_AutoMerge_NoteRecordRefused,
                        key
                    );
                }
            }
        } catch (Exception unreadable) {
            for (Merge_Journal__c owner : new Set<Merge_Journal__c>(ownerByRow.values())) {
                addOnce(notesById, owner, Label.Core_AutoMerge_NoteRecordRefused, key);
            }
        }
    }

    /** One note per journal, link and kind, however many records it is about. */
    private static void addOnce(
        Map<Id, List<String>> notesById,
        Merge_Journal__c owner,
        String format,
        String key
    ) {
        String line = String.format(format, new List<Object>{ key });
        List<String> lines = notesById.get(owner.Id);
        if (!lines.contains(line)) {
            lines.add(line);
        }
    }
}
