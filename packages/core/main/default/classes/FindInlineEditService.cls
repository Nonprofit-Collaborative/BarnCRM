/**
 * Saving values edited in Find's results grid (C-36, canonical model R-SQ10).
 *
 * An edit is a small bulk update: every field is one a bulk update may write (BulkUpdateFields,
 * R-BU4), every value is typed as a bulk update's set value is, the records are read again and
 * saved as the person in user mode, and the save is one Update data job with a commit journal
 * page, so Data jobs (Data Manager) lists it and its undo is the import undo (R-BU5). The job record
 * and the journal are the package's own bookkeeping, written in system mode (ADR-0021).
 */
public with sharing class FindInlineEditService {
    public static final Integer MAX_RECORDS = 200;

    /** A record the save refused, and why, for the grid to mark. */
    public class RowError {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String message;
    }

    /** What one save did. */
    public class SaveSummary {
        @AuraEnabled
        public Integer saved = 0;
        @AuraEnabled
        public Integer unchanged = 0;
        @AuraEnabled
        public List<RowError> errors = new List<RowError>();
        /** The data job that records the save; empty when nothing was sent to the database. */
        @AuraEnabled
        public String jobId;
    }

    /**
     * Saves the grid's draft values: a list of maps, each an `Id` and field values, in the form
     * lightning-datatable reports them.
     */
    public static SaveSummary save(String objectApiName, String editsJson) {
        Schema.SObjectType type = BulkUpdateFields.writableObject(objectApiName);
        String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        Map<Id, Map<String, Object>> wantedById = readEdits(type, editsJson);
        Set<String> fieldNames = new Set<String>();
        for (Map<String, Object> wanted : wantedById.values()) {
            fieldNames.addAll(wanted.keySet());
        }
        Set<Id> ids = wantedById.keySet();
        Map<Id, SObject> current = new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT Id, ' +
                    String.join(new List<String>(fieldNames), ', ') +
                    ' FROM ' +
                    objectName +
                    ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        );

        SaveSummary summary = new SaveSummary();
        List<SObject> toSave = new List<SObject>();
        List<Map<String, Object>> beforeOf = new List<Map<String, Object>>();
        List<Map<String, Object>> afterOf = new List<Map<String, Object>>();
        for (Id recordId : ids) {
            SObject record = current.get(recordId);
            if (record == null) {
                summary.errors.add(rowError(recordId, System.Label.Core_Find_ErrorEditNotFound));
                continue;
            }
            SObject change = type.newSObject(recordId);
            Map<String, Object> before = new Map<String, Object>();
            Map<String, Object> after = new Map<String, Object>();
            Map<String, Object> wanted = wantedById.get(recordId);
            for (String field : wanted.keySet()) {
                Object was = record.get(field);
                Object becomes = wanted.get(field);
                if (!same(was, becomes)) {
                    before.put(field, was);
                    after.put(field, becomes);
                    change.put(field, becomes);
                }
            }
            if (after.isEmpty()) {
                summary.unchanged++;
                continue;
            }
            toSave.add(change);
            beforeOf.add(before);
            afterOf.add(after);
        }

        List<Map<String, Object>> journal = new List<Map<String, Object>>();
        List<Database.SaveResult> results = toSave.isEmpty()
            ? new List<Database.SaveResult>()
            : Database.update(toSave, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            Id recordId = toSave[i].Id;
            if (results[i].isSuccess()) {
                summary.saved++;
                journal.add(
                    ImportJournalService.updated(
                        objectName,
                        recordId,
                        null,
                        beforeOf[i],
                        afterOf[i]
                    )
                );
            } else {
                String message = message(results[i].getErrors());
                summary.errors.add(rowError(recordId, message));
                journal.add(ImportJournalService.failed(objectName, recordId, message));
            }
        }
        if (!journal.isEmpty()) {
            Import_Batch__c job = createJob(type, objectName, ids, summary);
            ImportJournalService.write(job.Id, ImportJournalService.PHASE_COMMIT, journal);
            summary.jobId = job.Id;
        }
        return summary;
    }

    /** The edits by record, each field found in describe and each value typed for it. */
    private static Map<Id, Map<String, Object>> readEdits(
        Schema.SObjectType type,
        String editsJson
    ) {
        List<Object> rows;
        try {
            rows = (List<Object>) JSON.deserializeUntyped(editsJson);
        } catch (Exception unreadable) {
            rows = null;
        }
        if (rows == null || rows.isEmpty()) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorNoChanges
            );
        }
        if (rows.size() > MAX_RECORDS) {
            throw new BulkUpdateFields.BulkUpdateException(System.Label.Core_Find_ErrorEditTooMany);
        }
        Map<String, Schema.DescribeFieldResult> fieldByName = new Map<String, Schema.DescribeFieldResult>();
        Map<Id, Map<String, Object>> wantedById = new Map<Id, Map<String, Object>>();
        for (Object rawRow : rows) {
            Map<String, Object> row = rawRow instanceof Map<String, Object>
                ? (Map<String, Object>) rawRow
                : new Map<String, Object>();
            Id recordId = recordIdOf(type, row.get('Id'));
            Map<String, Object> wanted = wantedById.containsKey(recordId)
                ? wantedById.get(recordId)
                : new Map<String, Object>();
            for (String key : row.keySet()) {
                if (key == 'Id') {
                    continue;
                }
                if (!fieldByName.containsKey(key.toLowerCase())) {
                    fieldByName.put(key.toLowerCase(), BulkUpdateFields.writableField(type, key));
                }
                Schema.DescribeFieldResult field = fieldByName.get(key.toLowerCase());
                wanted.put(field.getName(), typedOrCleared(field, row.get(key)));
            }
            if (!wanted.isEmpty()) {
                wantedById.put(recordId, wanted);
            }
        }
        if (wantedById.isEmpty()) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorNoChanges
            );
        }
        return wantedById;
    }

    private static Id recordIdOf(Schema.SObjectType type, Object raw) {
        Id recordId;
        try {
            recordId = Id.valueOf(String.valueOf(raw));
        } catch (Exception notAnId) {
            throw new BulkUpdateFields.BulkUpdateException(System.Label.Core_Find_ErrorEditRecord);
        }
        if (recordId.getSObjectType() != type) {
            throw new BulkUpdateFields.BulkUpdateException(System.Label.Core_Find_ErrorEditRecord);
        }
        return recordId;
    }

    /** An empty value clears a field that may be empty; anything else is typed (R-BU4). */
    private static Object typedOrCleared(Schema.DescribeFieldResult field, Object raw) {
        Boolean empty = raw == null || String.isBlank(String.valueOf(raw));
        if (empty && field.getType() != Schema.DisplayType.BOOLEAN) {
            if (!field.isNillable()) {
                throw new BulkUpdateFields.BulkUpdateException(
                    String.format(
                        System.Label.Core_BulkUpdate_ErrorRequired,
                        new List<Object>{ field.getLabel() }
                    )
                );
            }
            return null;
        }
        return BulkUpdateFields.typed(field, raw);
    }

    /** The data job that records one save, complete when it is written (R-SQ10, R-BU1). */
    private static Import_Batch__c createJob(
        Schema.SObjectType type,
        String objectName,
        Set<Id> ids,
        SaveSummary summary
    ) {
        Datetime now = Datetime.now();
        List<Object> idList = new List<Object>();
        for (Id recordId : ids) {
            idList.add(String.valueOf(recordId));
        }
        Map<String, Object> query = new Map<String, Object>{
            'version' => 1,
            'object' => objectName,
            'fields' => new List<Object>{ 'Id' },
            'filter' => new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => 'Id',
                        'operator' => 'in',
                        'value' => idList
                    }
                }
            }
        };
        Import_Batch__c job = new Import_Batch__c(
            Operation__c = BulkUpdateService.OPERATION_UPDATE,
            Operation_JSON__c = JSON.serialize(
                new Map<String, Object>{
                    'version' => 1,
                    'source' => 'inline edit',
                    'query' => query,
                    'changes' => new List<Object>(),
                    'confirmedCount' => ids.size()
                }
            ),
            Status__c = ImportBatchService.STATUS_COMPLETE,
            Is_Dry_Run__c = false,
            Row_Count__c = ids.size(),
            Rows_Created__c = 0,
            Rows_Updated__c = summary.saved,
            Rows_Matched__c = summary.unchanged,
            Rows_Rejected__c = summary.errors.size(),
            Started_At__c = now,
            Completed_At__c = now,
            Committed_By__c = UserInfo.getUserId(),
            Undo_Deadline__c = now.addDays(ImportBatchService.undoWindowDays()),
            Run_Log__c = String.format(
                System.Label.Core_Find_LogEdited,
                new List<Object>{
                    UserInfo.getName(),
                    now.format(),
                    type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural(),
                    summary.saved.format(),
                    summary.unchanged.format(),
                    summary.errors.size().format()
                }
            )
        );
        Database.insert(job, AccessLevel.SYSTEM_MODE);
        return job;
    }

    /** Numbers as numbers, text exactly, as a bulk update compares them. */
    private static Boolean same(Object stored, Object wanted) {
        if (stored == null || wanted == null) {
            return stored == null && wanted == null;
        }
        if (stored instanceof Decimal || stored instanceof Integer || stored instanceof Double) {
            try {
                return Decimal.valueOf(String.valueOf(stored)) ==
                    Decimal.valueOf(String.valueOf(wanted));
            } catch (Exception notANumber) {
                return false;
            }
        }
        if (stored instanceof String || wanted instanceof String) {
            return String.valueOf(stored).equals(String.valueOf(wanted));
        }
        return stored == wanted;
    }

    private static RowError rowError(Id recordId, String message) {
        RowError error = new RowError();
        error.recordId = recordId;
        error.message = message;
        return error;
    }

    private static String message(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error error : errors) {
            parts.add(error.getMessage());
        }
        return String.join(parts, ' ');
    }
}
