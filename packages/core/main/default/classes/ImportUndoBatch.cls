/**
 * The work of undoing one import, in passes (canonical model R-IB8, R-IB9):
 *
 * 1. **Restore.** Each commit journal page, newest first, puts back the values the import
 *    wrote where the record still holds the value written.
 * 2. **A module's own records**, one pass per object an installed entity processor tags
 *    (R-IR6), in the order it names them: a gift goes before its donor, so the donor is judged
 *    after the gifts the import gave them are gone.
 * 3. **People** stored as contacts, then 4. **people stored as accounts**, then
 *    5. **households and organizations**. People go first so a household is judged after its
 *    imported members are gone; deleting an account would otherwise take its contacts with it.
 *
 * The entity processor also says, in every delete pass, why a record must stay (a receipted
 * gift, and the donor it names), and its reasons are journaled with Core's own.
 *
 * Every delete query is filtered by one bound batch identifier and nothing else, and the tag
 * is checked again on each record before it is deleted. A tagged record that has gained
 * something since the import is kept, and journaled with the reason.
 *
 * A chunk the platform stops (a governor limit) cannot be caught; `finish` reads the job's
 * error count so such an undo ends Undo failed, and can be run again, rather than Undone.
 */
@NamespaceAccessible
public with sharing class ImportUndoBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    private static final String PASS_RESTORE = 'Restore';
    @TestVisible
    private static final String PASS_CONTACTS = 'Contacts';
    @TestVisible
    private static final String PASS_PERSON_ACCOUNTS = 'PersonAccounts';
    @TestVisible
    private static final String PASS_ACCOUNTS = 'Accounts';
    /** A module object's pass is this prefix and the object's API name. */
    @TestVisible
    private static final String PASS_TAGGED_PREFIX = 'Tagged:';

    /** Children never counted as something a record gained: the import's own bookkeeping. */
    private static final Set<String> NOT_GAINED = new Set<String>{
        'import_row__c',
        'import_journal__c',
        'rollupcalcitem__c'
    };

    /**
     * The most records one delete chunk takes. Smaller than a save's usual 200, because the
     * checks and the delete's own automation share one transaction's limits.
     */
    private static final Integer MAX_CHUNK = 100;

    /**
     * The share of a transaction's queries the checks leave for the delete and the automation
     * it sets off: half, so 100 of a batch chunk's 200. A check that would eat into them keeps
     * its records instead (R-IB9): a governor limit cannot be caught, so the only safe answer
     * is not to reach it.
     */
    private static final Integer QUERY_HEADROOM_DIVISOR = 2;

    /** How many child relationships one check query asks about (SOQL allows 20). */
    private static final Integer RELATIONSHIPS_PER_QUERY = 20;

    /**
     * How long after a commit completes its own follow-on work (rollups, household naming,
     * run as the person who committed) may still be writing to what it created.
     */
    private static final Integer SETTLE_MINUTES = 10;

    /**
     * Set only by tests: the error count a job reports when the platform stopped a chunk,
     * which a test cannot bring about for real.
     */
    @TestVisible
    private static Integer jobErrorsForTest;

    /** The relationships each object is checked through, described once per transaction. */
    private static final Map<Schema.SObjectType, List<Schema.ChildRelationship>> CHECKED = new Map<Schema.SObjectType, List<Schema.ChildRelationship>>();

    private final Id batchId;
    private final Integer countedAtStart;
    private final String pass;
    private final Datetime undoStartedAt;
    private Integer restored;
    private Boolean failed;
    private Datetime completedAt;
    private Datetime startedAt;
    private Id committedBy;

    /**
     * Starts the first pass of the undo of one batch. `countedAtStart` is the total the person
     * confirmed, kept so the run log can say how many of those were deleted and how many kept.
     */
    @NamespaceAccessible
    public static Id run(Id batchId, Integer countedAtStart) {
        return Database.executeBatch(
            new ImportUndoBatch(
                batchId,
                countedAtStart,
                PASS_RESTORE,
                0,
                false,
                toTheSecond(Datetime.now())
            ),
            scopeFor(PASS_RESTORE, batchId)
        );
    }

    /**
     * The passes in order. Worked out again at each pass's end rather than carried, so it
     * costs nothing to hold; the installed module cannot change while an undo runs.
     */
    @TestVisible
    private static List<String> passes() {
        List<String> result = new List<String>{ PASS_RESTORE };
        for (Schema.SObjectType type : ImportEntityProcessors.taggedTypes()) {
            result.add(
                PASS_TAGGED_PREFIX + type.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
            );
        }
        result.addAll(new List<String>{ PASS_CONTACTS, PASS_PERSON_ACCOUNTS, PASS_ACCOUNTS });
        return result;
    }

    /** The module object a tagged pass deletes, or null when the module no longer names it. */
    private static Schema.SObjectType taggedTypeOf(String pass) {
        if (pass == null || !pass.startsWith(PASS_TAGGED_PREFIX)) {
            return null;
        }
        String objectName = pass.removeStart(PASS_TAGGED_PREFIX);
        for (Schema.SObjectType type : ImportEntityProcessors.taggedTypes()) {
            if (type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() == objectName) {
                return type;
            }
        }
        return null;
    }

    @TestVisible
    private ImportUndoBatch(
        Id batchId,
        Integer countedAtStart,
        String pass,
        Integer restored,
        Boolean failed
    ) {
        this(batchId, countedAtStart, pass, restored, failed, toTheSecond(Datetime.now()));
    }

    /**
     * `undoStartedAt` is when the person pressed Undo, to the second the platform stamps
     * records with, so what the undo itself changes is never mistaken for work done since the
     * import (R-IB9).
     */
    @TestVisible
    private ImportUndoBatch(
        Id batchId,
        Integer countedAtStart,
        String pass,
        Integer restored,
        Boolean failed,
        Datetime undoStartedAt
    ) {
        this.batchId = batchId;
        this.countedAtStart = countedAtStart;
        this.pass = pass;
        this.restored = restored;
        this.failed = failed;
        this.undoStartedAt = undoStartedAt;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Id owner = batchId;
        Import_Batch__c batch = [
            SELECT Completed_At__c, Started_At__c, Committed_By__c, Status__c, Job_Id__c
            FROM Import_Batch__c
            WHERE Id = :owner
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        // A commit the platform aborted never finished: it ended when its job did, or, where
        // that is no longer known, is taken to have ended when it started, so every change
        // since, the committer's own included, is kept (R-IB9, R-IB13).
        completedAt = batch.Completed_At__c == null
            ? ImportBatchService.jobEndedAt(batch)
            : batch.Completed_At__c;
        if (completedAt == null) {
            completedAt = batch.Started_At__c;
        }
        startedAt = batch.Started_At__c;
        committedBy = batch.Committed_By__c;
        // Every query below is in system mode, so a tagged record the person cannot see is
        // still met, refused by the user-mode delete, and journaled as kept (R-IB9), instead
        // of silently staying behind.
        if (PASS_RESTORE.equals(pass)) {
            String phase = ImportJournalService.PHASE_COMMIT;
            return Database.getQueryLocator(
                [
                    SELECT Id, Entries_JSON__c
                    FROM Import_Journal__c
                    WHERE Import_Batch__c = :owner AND Phase__c = :phase
                    WITH SYSTEM_MODE
                    ORDER BY CreatedDate DESC, Id DESC
                ]
            );
        }
        if (pass.startsWith(PASS_TAGGED_PREFIX)) {
            return taggedLocator(owner);
        }
        if (PASS_CONTACTS.equals(pass)) {
            return Database.getQueryLocator(
                [
                    SELECT Id, Name, Created_By_Import_Batch__c
                    FROM Contact
                    WHERE Created_By_Import_Batch__c = :owner
                    WITH SYSTEM_MODE
                ]
            );
        }
        Set<Id> personTypes = OrgShapeDetector.detect().personAccountRecordTypeIds;
        if (PASS_PERSON_ACCOUNTS.equals(pass)) {
            return Database.getQueryLocator(
                [
                    SELECT Id, Name, Created_By_Import_Batch__c
                    FROM Account
                    WHERE Created_By_Import_Batch__c = :owner AND RecordTypeId IN :personTypes
                    WITH SYSTEM_MODE
                ]
            );
        }
        return Database.getQueryLocator(
            [
                SELECT Id, Name, Created_By_Import_Batch__c
                FROM Account
                WHERE
                    Created_By_Import_Batch__c = :owner
                    AND (RecordTypeId = NULL
                    OR RecordTypeId NOT IN :personTypes)
                WITH SYSTEM_MODE
            ]
        );
    }

    /**
     * The records of one module object tagged with this batch. The object name comes from
     * describe, never from the pass text, and an object the module stopped naming reads
     * nothing.
     */
    private Database.QueryLocator taggedLocator(Id owner) {
        Schema.SObjectType type = taggedTypeOf(pass);
        String objectName = type == null
            ? 'Import_Row__c'
            : type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        String filter = type == null ? 'Id = NULL' : ImportEntityProcessors.TAG_FIELD + ' = :owner';
        return Database.getQueryLocatorWithBinds(
            'SELECT Id, Name' +
                (type == null ? '' : ', ' + ImportEntityProcessors.TAG_FIELD) +
                ' FROM ' +
                String.escapeSingleQuotes(objectName) +
                ' WHERE ' +
                filter,
            new Map<String, Object>{ 'owner' => owner },
            AccessLevel.SYSTEM_MODE
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> records) {
        List<Map<String, Object>> journal = new List<Map<String, Object>>();
        try {
            if (PASS_RESTORE.equals(pass)) {
                for (SObject page : records) {
                    restore((Import_Journal__c) page, journal);
                }
            } else {
                deleteTagged(records, journal);
            }
        } catch (Exception e) {
            failed = true;
            ErrorLogger.log(e, 'ImportUndoBatch.execute', batchId);
        }
        ImportJournalService.write(batchId, ImportJournalService.PHASE_UNDO, journal);
    }

    public void finish(Database.BatchableContext context) {
        if (chunkStopped(context)) {
            failed = true;
        }
        try {
            List<String> passes = passes();
            Integer next = passes.indexOf(pass) + 1;
            if (next > 0 && next < passes.size()) {
                Database.executeBatch(
                    new ImportUndoBatch(
                        batchId,
                        countedAtStart,
                        passes[next],
                        restored,
                        failed,
                        undoStartedAt
                    ),
                    scopeFor(passes[next], batchId)
                );
                return;
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportUndoBatch.finish', batchId);
            failed = true;
        }
        ImportUndoService.finish(batchId, countedAtStart, restored, failed);
    }

    /**
     * Whether the platform stopped any chunk of this pass. A governor limit cannot be caught,
     * so `execute` never gets to say it failed and the state it would have set is lost; the
     * job's own error count is the one record of it (R-IB8).
     */
    private Boolean chunkStopped(Database.BatchableContext context) {
        if (jobErrorsForTest != null) {
            return jobErrorsForTest > 0;
        }
        if (context == null || context.getJobId() == null) {
            return false;
        }
        Id jobId = context.getJobId();
        List<AsyncApexJob> jobs = [
            SELECT NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !jobs.isEmpty() && jobs[0].NumberOfErrors != null && jobs[0].NumberOfErrors > 0;
    }

    // -------------------------------------------------------------------------------------
    // Restore
    // -------------------------------------------------------------------------------------

    /**
     * Puts back one page's updates. Entries are taken newest first, so a record updated by
     * two rows is walked back through both. A value is put back only where the record still
     * holds the value the import wrote; one already put back is left silently, which is what
     * makes a second run of a failed undo safe; anything else is journaled as not put back.
     */
    private void restore(Import_Journal__c page, List<Map<String, Object>> journal) {
        List<Map<String, Object>> entries = ImportJournalService.entries(page);
        Map<String, Set<Id>> idsByObject = new Map<String, Set<Id>>();
        Map<String, Set<String>> fieldsByObject = new Map<String, Set<String>>();
        for (Map<String, Object> entry : entries) {
            String objectName = restorable(entry);
            if (objectName == null) {
                continue;
            }
            if (!idsByObject.containsKey(objectName)) {
                idsByObject.put(objectName, new Set<Id>());
                fieldsByObject.put(objectName, new Set<String>());
            }
            idsByObject.get(objectName).add(Id.valueOf((String) entry.get('id')));
            fieldsByObject.get(objectName).addAll(fieldsOf(entry).keySet());
        }
        Map<Id, SObject> current = new Map<Id, SObject>();
        for (String objectName : idsByObject.keySet()) {
            current.putAll(
                read(objectName, fieldsByObject.get(objectName), idsByObject.get(objectName))
            );
        }
        Map<Id, SObject> changes = new Map<Id, SObject>();
        Map<Id, List<String>> changedFields = new Map<Id, List<String>>();
        for (Integer i = entries.size() - 1; i >= 0; i--) {
            Map<String, Object> entry = entries[i];
            String objectName = restorable(entry);
            if (objectName == null) {
                continue;
            }
            Id recordId = Id.valueOf((String) entry.get('id'));
            SObject record = current.get(recordId);
            Map<String, Schema.SObjectField> described = fieldMap(objectName);
            for (String field : fieldsOf(entry).keySet()) {
                Map<String, Object> values = (Map<String, Object>) fieldsOf(entry).get(field);
                Schema.SObjectField token = described.get(field.toLowerCase());
                if (record == null || token == null || !token.getDescribe().isUpdateable()) {
                    journal.add(
                        notRestored(
                            objectName,
                            recordId,
                            field,
                            Label.Core_Import_UndoNotRestoredGone
                        )
                    );
                    continue;
                }
                Object now = record.get(token);
                if (same(now, values.get('before'))) {
                    continue;
                }
                if (!same(now, values.get('after'))) {
                    journal.add(
                        notRestored(
                            objectName,
                            recordId,
                            field,
                            Label.Core_Import_UndoNotRestoredChanged
                        )
                    );
                    continue;
                }
                Object before = typed(values.get('before'), token.getDescribe());
                record.put(token, before);
                if (!changes.containsKey(recordId)) {
                    changes.put(recordId, record.getSObjectType().newSObject(recordId));
                    changedFields.put(recordId, new List<String>());
                }
                changes.get(recordId).put(token, before);
                changedFields.get(recordId).add(field);
            }
        }
        save(changes, changedFields, journal);
    }

    /**
     * Saves the values put back in the running user's own mode: these are the organization's
     * records (ADR-0021). A record the platform refuses is journaled field by field.
     */
    private void save(
        Map<Id, SObject> changes,
        Map<Id, List<String>> changedFields,
        List<Map<String, Object>> journal
    ) {
        if (changes.isEmpty()) {
            return;
        }
        List<SObject> records = changes.values();
        List<Database.SaveResult> results = Database.update(records, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            Id recordId = records[i].Id;
            if (results[i].isSuccess()) {
                restored += changedFields.get(recordId).size();
                continue;
            }
            String objectName = records[i]
                .getSObjectType()
                .getDescribe(SObjectDescribeOptions.DEFERRED)
                .getName();
            for (String field : changedFields.get(recordId)) {
                journal.add(
                    notRestored(objectName, recordId, field, message(results[i].getErrors()))
                );
            }
        }
    }

    /** The object an update entry is on, when it is one Core writes; null otherwise. */
    private static String restorable(Map<String, Object> entry) {
        String objectName = (String) entry.get('object');
        if (
            !ImportJournalService.ACTION_UPDATED.equals(entry.get('action')) ||
            !('Contact'.equals(objectName) || 'Account'.equals(objectName)) ||
            String.isBlank((String) entry.get('id'))
        ) {
            return null;
        }
        return objectName;
    }

    private static Map<String, Object> fieldsOf(Map<String, Object> entry) {
        Object fields = entry.get('fields');
        return fields == null ? new Map<String, Object>() : (Map<String, Object>) fields;
    }

    private static Map<String, Schema.SObjectField> fieldMap(String objectName) {
        return Schema.getGlobalDescribe()
            .get(objectName)
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
    }

    /**
     * The records as they stand now, with the journaled fields that still exist. Read in
     * system mode so a value can be compared even where the user cannot read it; the write
     * that follows is in the user's own mode, so nothing is changed that they could not.
     */
    private static Map<Id, SObject> read(String objectName, Set<String> fields, Set<Id> ids) {
        Map<String, Schema.SObjectField> described = fieldMap(objectName);
        Set<String> selected = new Set<String>{ 'Id' };
        for (String field : fields) {
            Schema.SObjectField token = described.get(field.toLowerCase());
            if (token != null) {
                selected.add(token.getDescribe().getName());
            }
        }
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT ' +
                    String.join(new List<String>(selected), ', ') +
                    ' FROM ' +
                    objectName +
                    ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.SYSTEM_MODE
            )
        );
    }

    /**
     * Whether a stored value equals a journaled one. The journal holds typed values (R-IJ2),
     * so numbers compare as numbers, dates and times by their written form, and text exactly:
     * a value an administrator corrected only in capitals has still been corrected.
     */
    @TestVisible
    private static Boolean same(Object stored, Object journaled) {
        if (stored == null || journaled == null) {
            return stored == null && journaled == null;
        }
        if (
            stored instanceof Decimal ||
            stored instanceof Integer ||
            stored instanceof Long ||
            stored instanceof Double
        ) {
            try {
                return Decimal.valueOf(String.valueOf(stored)) ==
                    Decimal.valueOf(String.valueOf(journaled));
            } catch (Exception notANumber) {
                return false;
            }
        }
        if (stored instanceof Date || stored instanceof Datetime) {
            return JSON.serialize(stored).equals(JSON.serialize(journaled));
        }
        return String.valueOf(stored).equals(String.valueOf(journaled));
    }

    /** A journaled value as the field's own type, so the value put back is the value that was. */
    @TestVisible
    private static Object typed(Object value, Schema.DescribeFieldResult field) {
        if (value == null) {
            return null;
        }
        String text = String.valueOf(value);
        switch on field.getType() {
            when DATE {
                return Date.valueOf(text);
            }
            when DATETIME {
                return (Datetime) JSON.deserialize(JSON.serialize(value), Datetime.class);
            }
            when BOOLEAN {
                return Boolean.valueOf(text);
            }
            when INTEGER {
                return Decimal.valueOf(text).intValue();
            }
            when DOUBLE, CURRENCY, PERCENT {
                return Decimal.valueOf(text);
            }
            when else {
                return text;
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Delete
    // -------------------------------------------------------------------------------------

    /**
     * Deletes this chunk's tagged records, keeping the ones that have gained something since
     * the import. Deleted in the running user's own mode, to the recycle bin (R-IB8). A record
     * the platform refuses is kept and journaled, never retried in a wider form; one the
     * person has no access to delete is journaled as that.
     */
    private void deleteTagged(List<SObject> records, List<Map<String, Object>> journal) {
        Map<Id, SObject> tagged = new Map<Id, SObject>();
        for (SObject record : records) {
            if (record.get('Created_By_Import_Batch__c') == batchId) {
                tagged.put(record.Id, record);
            }
        }
        if (tagged.isEmpty()) {
            return;
        }
        Schema.SObjectType type = records[0].getSObjectType();
        if (!type.getDescribe(SObjectDescribeOptions.DEFERRED).isDeletable()) {
            for (SObject record : tagged.values()) {
                journal.add(kept(record, Label.Core_Import_UndoKeptNoAccess));
            }
            return;
        }
        Map<Id, String> keep = reasonsToKeep(tagged.keySet(), type);
        List<SObject> toDelete = new List<SObject>();
        for (SObject record : tagged.values()) {
            if (keep.containsKey(record.Id)) {
                journal.add(kept(record, keep.get(record.Id)));
            } else {
                toDelete.add(record);
            }
        }
        if (toDelete.isEmpty()) {
            return;
        }
        List<Database.DeleteResult> results = Database.delete(
            toDelete,
            false,
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                journal.add(kept(toDelete[i], refusedBecause(results[i].getErrors())));
            }
        }
    }

    /** Why the platform refused a delete, in the undo's own words where it was access. */
    private static String refusedBecause(List<Database.Error> errors) {
        for (Database.Error error : errors) {
            if (
                error.getStatusCode() == StatusCode.INSUFFICIENT_ACCESS_OR_READONLY ||
                error.getStatusCode() == StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
            ) {
                return Label.Core_Import_UndoKeptNoAccess;
            }
        }
        return message(errors);
    }

    /**
     * Why each of these records is not the import's to delete (R-IB9): it was edited or had an
     * activity logged since; anything created since points at it through any reference the org
     * can filter on; or, for a household or an organization, a person is still on it or
     * something outside BarnCRM depends on it (ADR-0036).
     */
    private Map<Id, String> reasonsToKeep(Set<Id> ids, Schema.SObjectType type) {
        Map<Id, String> keep = new Map<Id, String>();
        markEdited(keep, ids, type);
        List<Schema.ChildRelationship> relationships = checkedRelationships(type);
        for (Integer i = 0; i < relationships.size(); i += RELATIONSHIPS_PER_QUERY) {
            List<Schema.ChildRelationship> chunk = new List<Schema.ChildRelationship>();
            for (
                Integer j = i; j < Math.min(i + RELATIONSHIPS_PER_QUERY, relationships.size()); j++
            ) {
                chunk.add(relationships[j]);
            }
            markGained(keep, ids, type, chunk);
        }
        if (PASS_ACCOUNTS.equals(pass)) {
            Map<String, Object> binds = new Map<String, Object>{ 'ids' => ids };
            markKept(
                keep,
                'SELECT Id FROM Account WHERE Id IN :ids AND Id IN (SELECT AccountId FROM Contact)',
                binds,
                Label.Core_Import_UndoKeptHasPeople
            );
            markKept(
                keep,
                'SELECT Id FROM Account WHERE Id IN :ids AND Id IN ' +
                '(SELECT Household__c FROM Household_Member__c WHERE Contact__c != NULL OR Account__c != NULL)',
                binds,
                Label.Core_Import_UndoKeptHasPeople
            );
            for (Id dependent : HouseholdSelector.getAccountsWithNativeDependents(ids)) {
                keep.put(dependent, Label.Core_Import_UndoKeptNativeDependents);
            }
        }
        markKeptByProcessor(keep, ids, type);
        return keep;
    }

    /**
     * Adds the installed entity processor's reasons to keep (R-IB9): a gift with a receipt,
     * and the donor such a gift still names. Asked for every object, Core's included. A
     * processor that cannot answer, or would leave the delete too few queries, keeps what it
     * was asked about: not knowing is not the same as knowing nothing depends on it.
     */
    private void markKeptByProcessor(Map<Id, String> keep, Set<Id> ids, Schema.SObjectType type) {
        ImportEntityProcessor processor = ImportEntityProcessors.find();
        if (processor == null) {
            return;
        }
        if (!enoughQueries()) {
            notChecked(keep, ids);
            return;
        }
        try {
            Map<Id, String> reasons = processor.reasonsToKeep(batchId, type, ids);
            for (Id recordId : reasons == null ? new Set<Id>() : reasons.keySet()) {
                if (ids.contains(recordId) && !keep.containsKey(recordId)) {
                    keep.put(
                        recordId,
                        String.isBlank(reasons.get(recordId))
                            ? Label.Core_Import_UndoKeptNotChecked
                            : reasons.get(recordId)
                    );
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportUndoBatch.markKeptByProcessor', batchId);
            notChecked(keep, ids);
        }
    }

    /**
     * Keeps a record somebody edited since the import, or logged an activity on. An edit
     * counts when it was made by somebody other than the committer after the commit started,
     * or by anybody once the commit's own follow-on work has settled; an edit the undo itself
     * made (a household renamed as its imported members go) does not count.
     */
    private void markEdited(Map<Id, String> keep, Set<Id> ids, Schema.SObjectType type) {
        Map<String, Schema.SObjectField> fields = type.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        Boolean hasActivities = fields.containsKey('lastactivitydate');
        String query =
            'SELECT Id, LastModifiedDate, LastModifiedById' +
            (hasActivities ? ', LastActivityDate' : '') +
            ' FROM ' +
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            ' WHERE Id IN :ids';
        List<SObject> rows = guardQuery(keep, ids, query, new Map<String, Object>{ 'ids' => ids });
        if (rows == null) {
            return;
        }
        Datetime checkedAt = Datetime.now();
        for (SObject row : rows) {
            Datetime modified = (Datetime) row.get('LastModifiedDate');
            Id modifiedBy = (Id) row.get('LastModifiedById');
            Boolean byTheUndo =
                modifiedBy == UserInfo.getUserId() &&
                modified >= undoStartedAt &&
                modified <= checkedAt;
            Boolean edited =
                (startedAt != null &&
                committedBy != null &&
                modified >= startedAt &&
                modifiedBy != committedBy) ||
                (completedAt != null &&
                modified > completedAt.addMinutes(SETTLE_MINUTES));
            Boolean activity = hasActivities && row.get('LastActivityDate') != null;
            if ((edited && !byTheUndo) || activity) {
                keep.put(row.Id, Label.Core_Import_UndoKeptEdited);
            }
        }
    }

    /**
     * Keeps the records anything created since points at, through one group of child
     * relationships, asked in one query with a subquery each. A group that cannot be asked
     * together is split in half and each half asked again, so one relationship the org cannot
     * filter this way costs a handful of queries, is logged once, and keeps only what it could
     * not check.
     */
    private void markGained(
        Map<Id, String> keep,
        Set<Id> ids,
        Schema.SObjectType type,
        List<Schema.ChildRelationship> relationships
    ) {
        if (relationships.isEmpty()) {
            return;
        }
        Map<String, Object> binds = new Map<String, Object>{
            'ids' => ids,
            'completedAt' => completedAt,
            'startedAt' => startedAt,
            'committedBy' => committedBy,
            'undoer' => UserInfo.getUserId(),
            'undoStartedAt' => undoStartedAt,
            'checkedAt' => Datetime.now()
        };
        if (relationships.size() == 1) {
            List<SObject> rows = guardQuery(keep, ids, gainedQuery(type, relationships), binds);
            if (rows != null) {
                gainedFrom(keep, rows);
            }
            return;
        }
        if (!enoughQueries()) {
            notChecked(keep, ids);
            return;
        }
        try {
            gainedFrom(
                keep,
                Database.queryWithBinds(
                    gainedQuery(type, relationships),
                    binds,
                    AccessLevel.SYSTEM_MODE
                )
            );
        } catch (Exception e) {
            // Not logged here: the half that holds the relationship that failed logs it.
            Integer half = relationships.size() / 2;
            List<Schema.ChildRelationship> first = new List<Schema.ChildRelationship>();
            List<Schema.ChildRelationship> second = new List<Schema.ChildRelationship>();
            for (Integer i = 0; i < relationships.size(); i++) {
                if (i < half) {
                    first.add(relationships[i]);
                } else {
                    second.add(relationships[i]);
                }
            }
            markGained(keep, ids, type, first);
            markGained(keep, ids, type, second);
        }
    }

    /**
     * Keeps each row whose subqueries found anything. Read from the fields the query actually
     * filled rather than by relationship name: an empty subquery comes back as nothing, and
     * asking for it by name can throw.
     */
    private static void gainedFrom(Map<Id, String> keep, List<SObject> rows) {
        for (SObject row : rows) {
            for (Object value : row.getPopulatedFieldsAsMap().values()) {
                if (value instanceof List<SObject> && !((List<SObject>) value).isEmpty()) {
                    if (!keep.containsKey(row.Id)) {
                        keep.put(row.Id, Label.Core_Import_UndoKeptGained);
                    }
                    break;
                }
            }
        }
    }

    /**
     * One query asking, for each relationship, whether a row created since points at the
     * record. "Since" is after the commit completed, or during the commit by somebody other
     * than the committer (R-IB9); a row the undo itself made is not counted.
     */
    private String gainedQuery(
        Schema.SObjectType type,
        List<Schema.ChildRelationship> relationships
    ) {
        String since = completedAt == null ? 'CreatedDate != NULL' : 'CreatedDate > :completedAt';
        if (startedAt != null && committedBy != null) {
            since += ' OR (CreatedDate >= :startedAt AND CreatedById != :committedBy)';
        }
        String filter =
            '(' +
            since +
            ') AND (CreatedById != :undoer OR CreatedDate < :undoStartedAt OR CreatedDate > :checkedAt)';
        List<String> subqueries = new List<String>();
        for (Schema.ChildRelationship relationship : relationships) {
            subqueries.add(
                '(SELECT Id FROM ' +
                    relationship.getRelationshipName() +
                    ' WHERE ' +
                    filter +
                    ' LIMIT 1)'
            );
        }
        return 'SELECT Id, ' +
            String.join(subqueries, ', ') +
            ' FROM ' +
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            ' WHERE Id IN :ids';
    }

    /**
     * The child relationships a record is checked through: every one with a name, through a
     * reference the org can filter on, to an object that stamps who created a row and when.
     * Found by describing the record's object, never by naming another object, so a gift, an
     * activity or a record in a package that did not exist when this was written counts the
     * same (R-IB9). Not counted: the import's own bookkeeping, the rollup engine's work items,
     * and a standard object's read-only views (activity history, attachments as listed on a
     * record), which the running user could not create a row in.
     */
    private static List<Schema.ChildRelationship> checkedRelationships(Schema.SObjectType type) {
        if (CHECKED.containsKey(type)) {
            return CHECKED.get(type);
        }
        List<Schema.ChildRelationship> result = new List<Schema.ChildRelationship>();
        for (Schema.ChildRelationship relationship : type.getDescribe().getChildRelationships()) {
            if (
                String.isBlank(relationship.getRelationshipName()) ||
                relationship.isDeprecatedAndHidden() ||
                !relationship.getField().getDescribe().isFilterable()
            ) {
                continue;
            }
            Schema.DescribeSObjectResult child = relationship.getChildSObject()
                .getDescribe(SObjectDescribeOptions.DEFERRED);
            String childName = child.getName();
            String localName = childName.countMatches('__') > 1
                ? childName.substringAfter('__')
                : childName;
            Map<String, Schema.SObjectField> childFields = child.fields.getMap();
            if (
                NOT_GAINED.contains(localName.toLowerCase()) ||
                !childFields.containsKey('createddate') ||
                !childFields.containsKey('createdbyid') ||
                (!child.isCustom() && !child.isCreateable())
            ) {
                continue;
            }
            result.add(relationship);
        }
        CHECKED.put(type, result);
        return result;
    }

    /**
     * Marks the ids a guard query returns as kept. Read in system mode (ADR-0021): a guard
     * that cannot see a gift would answer "nothing depends on this" for exactly the record it
     * must keep.
     */
    private void markKept(
        Map<Id, String> keep,
        String query,
        Map<String, Object> binds,
        String reason
    ) {
        List<SObject> rows = guardQuery(keep, (Set<Id>) binds.get('ids'), query, binds);
        if (rows == null) {
            return;
        }
        for (SObject record : rows) {
            if (!keep.containsKey(record.Id)) {
                keep.put(record.Id, reason);
            }
        }
    }

    /**
     * Runs one check in system mode. A check that cannot run, or would leave the delete too
     * few queries, keeps every record it was asked about and returns null: not knowing is not
     * the same as knowing nothing depends on it.
     */
    private List<SObject> guardQuery(
        Map<Id, String> keep,
        Set<Id> ids,
        String query,
        Map<String, Object> binds
    ) {
        if (!enoughQueries()) {
            notChecked(keep, ids);
            return null;
        }
        try {
            return Database.queryWithBinds(query, binds, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportUndoBatch.guardQuery', batchId);
            notChecked(keep, ids);
            return null;
        }
    }

    private static Boolean enoughQueries() {
        return Limits.getQueries() < Limits.getLimitQueries() / QUERY_HEADROOM_DIVISOR;
    }

    /** Keeps each record not already kept for a reason a check found. */
    private static void notChecked(Map<Id, String> keep, Set<Id> ids) {
        for (Id recordId : ids) {
            if (!keep.containsKey(recordId)) {
                keep.put(recordId, Label.Core_Import_UndoKeptNotChecked);
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    private static Map<String, Object> kept(SObject record, String reason) {
        return ImportJournalService.kept(
            record.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            record.Id,
            String.valueOf(record.get('Name')),
            reason
        );
    }

    private static Map<String, Object> notRestored(
        String objectName,
        Id recordId,
        String field,
        String reason
    ) {
        return ImportJournalService.notRestored(objectName, recordId, field, reason);
    }

    private static String message(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error error : errors) {
            parts.add(error.getMessage());
        }
        return String.join(parts, ' ');
    }

    /** A time cut to the whole second, the precision the platform stamps records with. */
    private static Datetime toTheSecond(Datetime value) {
        return Datetime.newInstance((value.getTime() / 1000) * 1000);
    }

    /**
     * How many records a pass takes at once: one journal page when putting values back (a
     * page holds at most a chunk's worth of updates, R-IJ1), and otherwise the batch's own
     * chunk size, held at MAX_CHUNK so the checks and the delete fit one transaction.
     */
    private static Integer scopeFor(String pass, Id batchId) {
        if (PASS_RESTORE.equals(pass)) {
            return 1;
        }
        Decimal chunkSize = [
            SELECT Chunk_Size__c
            FROM Import_Batch__c
            WHERE Id = :batchId
            WITH SYSTEM_MODE
            LIMIT 1
        ]
        .Chunk_Size__c;
        return chunkSize == null ||
            chunkSize < 1
            ? MAX_CHUNK
            : Math.min(chunkSize.intValue(), MAX_CHUNK);
    }
}
