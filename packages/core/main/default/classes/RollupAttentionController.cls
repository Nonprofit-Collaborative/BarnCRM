/**
 * The Rollup Builder's Needs attention list (rollup proposal slice S13, canonical model Section
 * 14A): the records waiting in the Rollup Queue, the ones that could not be saved with Retry,
 * whether the nightly run is scheduled, and how the last full run ended.
 *
 * Reads run in user mode, so only someone the BarnCRM Admin permission set lets read the queue
 * sees it. Retry needs the Manage BarnCRM Settings permission and goes through `RollupQueue`,
 * which writes entries in system mode (R-RQ5).
 */
public with sharing class RollupAttentionController {
    /** Failed records shown at most, so a long list stays one screen's worth of reading. */
    @TestVisible
    private static final Integer RECORDS_SHOWN = 200;

    /** One record whose totals could not be saved. */
    public class FailedRecord {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public Id entryId { get; set; }
        @AuraEnabled
        public Id recordId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String error { get; set; }
        @AuraEnabled
        public Datetime failedAt { get; set; }
        @AuraEnabled
        public Integer attempts { get; set; }
    }

    /** What the list shows. */
    public class Attention {
        @AuraEnabled
        public Boolean canManage { get; set; }
        @AuraEnabled
        public String waiting { get; set; }
        @AuraEnabled
        public List<FailedRecord> failed { get; set; }
        @AuraEnabled
        public Boolean nightlyScheduled { get; set; }
        @AuraEnabled
        public String lastRun { get; set; }
    }

    /** Everything Needs attention shows, read fresh each time. */
    @AuraEnabled
    public static Attention getAttention() {
        try {
            Attention attention = new Attention();
            attention.canManage = BarnCRMPermissions.canManageSettings();
            attention.waiting = waiting();
            attention.failed = failedRecords();
            attention.nightlyScheduled = RollupScheduler.isScheduled();
            attention.lastRun = lastRun(RollupFullRecalcBatch.progress());
            return attention;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Puts Failed entries back in the queue (R-RQ4).
     *
     * @param entryIds the entries of the records selected, or null or empty for Retry all
     * @return the list, read again
     */
    @AuraEnabled
    public static Attention retry(List<Id> entryIds) {
        try {
            if (!BarnCRMPermissions.canManageSettings()) {
                throw new RollupService.RollupServiceException(
                    Label.Core_Rollups_ErrorNoPermission
                );
            }
            RollupQueue.retry(
                entryIds == null || entryIds.isEmpty() ? null : new Set<Id>(entryIds)
            );
            return getAttention();
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /** "1,204 records waiting, oldest 3 minutes ago", or that nothing is waiting. */
    private static String waiting() {
        AggregateResult totals = [
            SELECT SUM(Record_Count__c) records, MIN(CreatedDate) oldest
            FROM Rollup_Queue__c
            WHERE Status__c = :RollupQueue.STATUS_PENDING
            WITH USER_MODE
        ];
        Decimal records = (Decimal) totals.get('records');
        Datetime oldest = (Datetime) totals.get('oldest');
        if (records == null || records == 0 || oldest == null) {
            return Label.Core_RollupBuilder_NothingWaiting;
        }
        Long minutes = (Datetime.now().getTime() - oldest.getTime()) / 60000;
        return String.format(
            Label.Core_RollupBuilder_Waiting,
            new List<String>{ records.format(), minutes.format() }
        );
    }

    /** Each record of each Failed entry, named as its record is, newest failure first. */
    private static List<FailedRecord> failedRecords() {
        List<FailedRecord> rows = new List<FailedRecord>();
        Map<String, Set<Id>> idsByTarget = new Map<String, Set<Id>>();
        for (Rollup_Queue__c entry : [
            SELECT Id, Target_Object__c, Record_Ids__c, Attempts__c, Last_Error__c, LastModifiedDate
            FROM Rollup_Queue__c
            WHERE Status__c = :RollupQueue.STATUS_FAILED
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT :RECORDS_SHOWN
        ]) {
            for (Id recordId : RollupQueue.idsOf(entry)) {
                if (rows.size() == RECORDS_SHOWN) {
                    break;
                }
                FailedRecord row = new FailedRecord();
                row.key = String.valueOf(entry.Id) + String.valueOf(recordId);
                row.entryId = entry.Id;
                row.recordId = recordId;
                row.name = recordId;
                row.error = entry.Last_Error__c;
                row.failedAt = entry.LastModifiedDate;
                row.attempts = entry.Attempts__c == null ? 0 : entry.Attempts__c.intValue();
                rows.add(row);
                String target = entry.Target_Object__c;
                if (!idsByTarget.containsKey(target)) {
                    idsByTarget.put(target, new Set<Id>());
                }
                idsByTarget.get(target).add(recordId);
            }
        }
        Map<Id, String> names = namesOf(idsByTarget);
        for (FailedRecord row : rows) {
            if (names.containsKey(row.recordId)) {
                row.name = names.get(row.recordId);
            }
        }
        return rows;
    }

    /**
     * The name of each record the user can see (R-RQ2: the queue holds identifiers as text).
     * The entity and its name attribute come from describe, never from the entry's text.
     */
    private static Map<Id, String> namesOf(Map<String, Set<Id>> idsByTarget) {
        Map<Id, String> names = new Map<Id, String>();
        for (String target : idsByTarget.keySet()) {
            Schema.SObjectType type = SettingsService.typeByName(target);
            if (type == null) {
                continue;
            }
            String nameField;
            for (Schema.SObjectField field : type.getDescribe().fields.getMap().values()) {
                if (field.getDescribe().isNameField()) {
                    nameField = String.valueOf(field);
                    break;
                }
            }
            if (nameField == null) {
                continue;
            }
            Set<Id> ids = idsByTarget.get(target);
            for (
                SObject record : Database.queryWithBinds(
                    'SELECT Id, ' +
                        nameField +
                        ' FROM ' +
                        String.valueOf(type) +
                        ' WHERE Id IN :ids',
                    new Map<String, Object>{ 'ids' => ids },
                    AccessLevel.USER_MODE
                )
            ) {
                names.put(record.Id, String.valueOf(record.get(nameField)));
            }
        }
        return names;
    }

    /** How the last full run ended, or that one is going, or that none has run. */
    @TestVisible
    private static String lastRun(RollupFullRecalcBatch.Progress progress) {
        if (progress == null || progress.jobId == null) {
            return Label.Core_RollupBuilder_LastRunNever;
        }
        if (progress.running) {
            return String.format(
                Label.Core_RollupBuilder_LastRunGoing,
                new List<String>{ progress.chunksDone.format(), progress.chunksTotal.format() }
            );
        }
        return String.format(
            Label.Core_RollupBuilder_LastRun,
            new List<String>{
                progress.status,
                progress.finishedAt == null ? '' : progress.finishedAt.format(),
                progress.chunksStopped.format()
            }
        );
    }

    private static AuraHandledException asUserError(Exception caught) {
        String message;
        if (caught instanceof RollupService.RollupServiceException) {
            message = caught.getMessage();
        } else {
            ErrorLogger.log(caught, 'RollupAttentionController');
            message = Label.Core_Rollups_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
