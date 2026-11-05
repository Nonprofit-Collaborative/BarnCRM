/**
 * The nightly run's Record Cleanup step (architect review L-08, canonical model R-NJ8): deletes
 * the history rows past their retention, one pass per object, chained one after another so a
 * pass never shares its limits with the next.
 *
 * Passes, in order: Setting Change (R-S2), Merge Journal, then finished imports and bulk jobs
 * whose undo window has closed (their journal and rows before the batch itself, so no single
 * delete cascades through thousands of children), then Field Utilization Snapshot (R-FU7). Each
 * pass reads its days from BarnCRM Settings, holding them between the bounds Section 12 gives.
 *
 * Rows are read and deleted in system mode (ADR-0021): the run works for the organization,
 * whoever scheduled it, and only these history objects are touched. A delete that fails is
 * logged and the pass goes on.
 */
public with sharing class RecordRetentionBatch implements Database.Batchable<SObject>, Schedulable {
    /** The step's key. */
    public static final String JOB_NAME = 'BarnCRM Record Cleanup';
    public static final Integer CHUNK_SIZE = 2000;
    private static final String LOG_CONTEXT = 'RecordRetentionBatch';

    /** An import or bulk job in one of these is finished and will not change again. */
    private static final List<String> FINISHED = new List<String>{
        'Dry run complete',
        'Trial complete',
        'Complete',
        'Failed',
        'Undone',
        'Undo failed'
    };

    @TestVisible
    private static final Integer SETTING_CHANGES = 0;
    @TestVisible
    private static final Integer MERGE_JOURNAL = 1;
    @TestVisible
    private static final Integer IMPORT_JOURNAL = 2;
    @TestVisible
    private static final Integer IMPORT_ROWS = 3;
    @TestVisible
    private static final Integer IMPORT_BATCHES = 4;
    @TestVisible
    private static final Integer FIELD_UTILIZATION = 5;

    /** False in a test that runs one pass and checks it. */
    @TestVisible
    private static Boolean chain = true;

    @TestVisible
    private final Integer pass;

    public RecordRetentionBatch() {
        this(SETTING_CHANGES);
    }

    @TestVisible
    private RecordRetentionBatch(Integer pass) {
        this.pass = pass;
    }

    /** As a step of the nightly run: starts the first pass. */
    public void execute(SchedulableContext context) {
        Database.executeBatch(new RecordRetentionBatch(SETTING_CHANGES), CHUNK_SIZE);
    }

    /** The step: twenty past one, after the import row cleanup at 1:15. No switch. */
    public static NightlyStep step() {
        return new NightlyStep(
            JOB_NAME,
            System.Label.Core_NightlyJobs_RecordCleanup,
            1,
            20,
            new RecordRetentionBatch()
        );
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocatorWithBinds(query(pass), binds(pass), AccessLevel.SYSTEM_MODE);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        List<String> failures = new List<String>();
        for (
            Database.DeleteResult result : Database.delete(scope, false, AccessLevel.SYSTEM_MODE)
        ) {
            if (!result.isSuccess()) {
                failures.add(result.getId() + ': ' + result.getErrors()[0].getMessage());
            }
        }
        if (!failures.isEmpty()) {
            ErrorLogger.logMessage(
                String.join(failures, '\n').left(30000),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
    }

    public void finish(Database.BatchableContext context) {
        if (chain && pass < FIELD_UTILIZATION) {
            Database.executeBatch(new RecordRetentionBatch(pass + 1), CHUNK_SIZE);
        }
    }

    // -------------------------------------------------------------------------------------
    // What each pass reads
    // -------------------------------------------------------------------------------------

    @TestVisible
    private static String query(Integer pass) {
        String importDone =
            'Status__c IN :finished AND CreatedDate < :cutoff' +
            ' AND (Undo_Deadline__c = null OR Undo_Deadline__c < :now)';
        String batchDone = importDone.replace('Status__c', 'Import_Batch__r.Status__c')
            .replace('CreatedDate', 'Import_Batch__r.CreatedDate')
            .replace('Undo_Deadline__c', 'Import_Batch__r.Undo_Deadline__c');
        if (pass == SETTING_CHANGES) {
            return 'SELECT Id FROM Setting_Change__c WHERE Changed_At__c < :cutoff ORDER BY Changed_At__c';
        } else if (pass == MERGE_JOURNAL) {
            return 'SELECT Id FROM Merge_Journal__c WHERE CreatedDate < :cutoff ORDER BY CreatedDate';
        } else if (pass == IMPORT_JOURNAL) {
            return 'SELECT Id FROM Import_Journal__c WHERE ' + batchDone;
        } else if (pass == IMPORT_ROWS) {
            return 'SELECT Id FROM Import_Row__c WHERE ' + batchDone;
        } else if (pass == IMPORT_BATCHES) {
            return 'SELECT Id FROM Import_Batch__c WHERE ' + importDone + ' ORDER BY CreatedDate';
        }
        return 'SELECT Id FROM Field_Utilization_Snapshot__c WHERE Taken_At__c < :cutoff ORDER BY Taken_At__c';
    }

    private static Map<String, Object> binds(Integer pass) {
        Integer days;
        if (pass == SETTING_CHANGES) {
            days = settingChangeDays();
        } else if (pass == MERGE_JOURNAL) {
            days = mergeJournalDays();
        } else if (pass == FIELD_UTILIZATION) {
            days = fieldUtilizationDays();
        } else {
            days = importHistoryDays();
        }
        Datetime now = Datetime.now();
        return new Map<String, Object>{
            'cutoff' => now.addDays(-days),
            'now' => now,
            'finished' => FINISHED
        };
    }

    // -------------------------------------------------------------------------------------
    // The settings (Section 12)
    // -------------------------------------------------------------------------------------

    public static Integer settingChangeDays() {
        return days('Setting_Change_Retention_Days__c', 730, 180);
    }

    public static Integer mergeJournalDays() {
        return days('Merge_Journal_Retention_Days__c', 365, 30);
    }

    public static Integer importHistoryDays() {
        return days('Import_History_Retention_Days__c', 365, 30);
    }

    public static Integer fieldUtilizationDays() {
        return days('Field_Utilization_Retention_Days__c', 730, 90);
    }

    /** The setting, or its default when empty, held between `minimum` and ten years. */
    private static Integer days(String key, Integer fallback, Integer minimum) {
        Object configured = SettingsService.hasKey(key) ? SettingsService.getValue(key) : null;
        if (configured == null) {
            return fallback;
        }
        try {
            Integer value = Decimal.valueOf(String.valueOf(configured)).intValue();
            return Math.max(minimum, Math.min(value, 3650));
        } catch (Exception ignored) {
            return fallback;
        }
    }
}
