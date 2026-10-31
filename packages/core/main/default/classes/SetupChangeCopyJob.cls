/**
 * The nightly Setup Changes copy (C-56, canonical model Section 29W). Copies the Setup Audit
 * Trail rows made since the newest kept row into `Setup_Change__c` (R-SU2), then deletes kept
 * rows older than the org's Days to Keep Setup Changes (R-SU4). Health Check lists it among the
 * nightly jobs (`NightlyJobs`), and Org Optimizer's Setup Changes section runs it on demand.
 *
 * One class, two passes: the copy pass reads the trail, and its finish starts the delete pass.
 * The trail is read with dynamic SOQL, so the class compiles in any org (R-SU1); Salesforce
 * shows it only to a user with View Setup and Configuration, so a run whose user cannot read it
 * logs one entry and copies nothing (R-SU3). The kept rows are the package's own copy, written
 * and deleted in system mode and without sharing (ADR-0021): a delete that skipped rows its user
 * cannot see would keep them for ever. It changes nothing but `Setup_Change__c` rows.
 */
public without sharing class SetupChangeCopyJob implements Schedulable, Database.Batchable<SObject> {
    /** The name the scheduled job carries, so it is found again rather than doubled. */
    public static final String JOB_NAME = 'BarnCRM Setup Changes Copy';

    /** Half past one: between the Import row cleanup at 1:15 and the household tidy at 1:45. */
    private static final String NIGHTLY_CRON = '0 30 1 * * ?';

    /** Rows per chunk: one upsert or delete of bookkeeping rows nothing fires on. */
    public static final Integer CHUNK_SIZE = 2000;

    /** Days to Keep Setup Changes (`Setup_Change_Retention_Days__c`), R-SU4. */
    public static final Integer DEFAULT_RETENTION_DAYS = 730;
    public static final Integer MIN_RETENTION_DAYS = 180;
    public static final Integer MAX_RETENTION_DAYS = 3650;

    private static final String LOG_CONTEXT = 'SetupChangeCopyJob';
    private static final String TRAIL_FIELDS = 'Id, Action, Section, Display, CreatedDate, CreatedBy.Name, DelegateUser';
    private static final List<String> UNFINISHED = new List<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };

    /** True for the delete pass, false for the copy pass. */
    @TestVisible
    private Boolean purging = false;

    /** Set by a test so the delete pass is not started from the copy pass's finish. */
    @TestVisible
    private static Boolean chainPurge = true;

    public SetupChangeCopyJob() {
        this.purging = false;
    }

    @TestVisible
    private SetupChangeCopyJob(Boolean purging) {
        this.purging = purging;
    }

    // -------------------------------------------------------------------------------------
    // Schedule
    // -------------------------------------------------------------------------------------

    /** The nightly start: skipped when a copy started by hand is still waiting or running. */
    public void execute(SchedulableContext context) {
        runNow();
    }

    /** Starts the nightly copy, or does nothing when it is already scheduled. */
    public static Id start() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            return existing;
        }
        return ScheduledJobSelector.schedule(JOB_NAME, NIGHTLY_CRON, new SetupChangeCopyJob());
    }

    /** True when the nightly copy is scheduled. */
    public static Boolean isScheduled() {
        return ScheduledJobSelector.triggerIdByName(JOB_NAME) != null;
    }

    /**
     * Whether a copy or delete pass is waiting or running, whoever started it. Read in system
     * mode, as the duplicate scan guard is: without View Setup a person sees only their own jobs.
     */
    public static Boolean isRunning() {
        return [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE
                    JobType = 'BatchApex'
                    AND ApexClass.Name = 'SetupChangeCopyJob'
                    AND Status IN :UNFINISHED
                WITH SYSTEM_MODE
            ] > 0;
    }

    /** Starts one copy now, as the running user, unless one is already waiting or running. */
    public static Boolean runNow() {
        if (isRunning()) {
            return false;
        }
        Database.executeBatch(new SetupChangeCopyJob(), CHUNK_SIZE);
        return true;
    }

    /** Whether the Org Optimizer feature, which owns Setup Changes, is on (R-SU8). */
    public static Boolean featureOn() {
        return FeatureSwitchService.isOn(FeatureSwitchService.ORG_OPTIMIZER);
    }

    /** Days to Keep Setup Changes: empty or unreadable reads as 730, out of range as the nearest end. */
    public static Integer retentionDays() {
        String key = 'Setup_Change_Retention_Days__c';
        Object configured = SettingsService.hasKey(key) ? SettingsService.getValue(key) : null;
        if (configured == null) {
            return DEFAULT_RETENTION_DAYS;
        }
        try {
            Integer value = Decimal.valueOf(String.valueOf(configured)).intValue();
            return Math.max(MIN_RETENTION_DAYS, Math.min(value, MAX_RETENTION_DAYS));
        } catch (Exception ignored) {
            return DEFAULT_RETENTION_DAYS;
        }
    }

    // -------------------------------------------------------------------------------------
    // Batch
    // -------------------------------------------------------------------------------------

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (!featureOn()) {
            // R-SU8: while Org Optimizer is off, the run copies and deletes nothing, quietly.
            return Database.getQueryLocator(
                'SELECT Id FROM Setup_Change__c WHERE Id = null',
                AccessLevel.SYSTEM_MODE
            );
        }
        if (purging) {
            return Database.getQueryLocatorWithBinds(
                'SELECT Id FROM Setup_Change__c WHERE Changed_At__c < :cutoff',
                new Map<String, Object>{ 'cutoff' => Datetime.now().addDays(-retentionDays()) },
                AccessLevel.SYSTEM_MODE
            );
        }
        Datetime since = newestKept();
        try {
            return Database.getQueryLocatorWithBinds(
                'SELECT ' +
                    TRAIL_FIELDS +
                    ' FROM SetupAuditTrail' +
                    (since == null ? '' : ' WHERE CreatedDate >= :since') +
                    ' ORDER BY CreatedDate',
                new Map<String, Object>{ 'since' => since },
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception unreadable) {
            // R-SU3: the trail is refused to this user. Copy nothing; the delete pass still runs.
            ErrorLogger.logMessage(
                String.format(
                    Label.Core_SetupChanges_LogCannotRead,
                    new List<String>{ unreadable.getMessage() }
                ),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
            return Database.getQueryLocator(
                'SELECT Id FROM Setup_Change__c WHERE Id = null',
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (purging) {
            remove(scope);
        } else {
            copy(scope);
        }
    }

    public void finish(Database.BatchableContext context) {
        if (!purging && chainPurge && featureOn()) {
            Database.executeBatch(new SetupChangeCopyJob(true), CHUNK_SIZE);
        }
    }

    // -------------------------------------------------------------------------------------
    // Copy and delete
    // -------------------------------------------------------------------------------------

    /**
     * Writes one kept row per trail row, found again by its Audit Trail ID so a row copied twice
     * (the newest kept second is read again on purpose) is stored once. A row that is not a
     * Setup Audit Trail row is skipped, so only `copy` decides what a kept row holds.
     */
    @TestVisible
    private static void copy(List<SObject> trailRows) {
        List<Setup_Change__c> kept = new List<Setup_Change__c>();
        for (SObject row : trailRows) {
            if (row == null || row.get('Id') == null) {
                continue;
            }
            SObject author = row.getSObject('CreatedBy');
            kept.add(
                new Setup_Change__c(
                    Audit_Trail_Id__c = String.valueOf(row.get('Id')),
                    Changed_At__c = (Datetime) row.get('CreatedDate'),
                    Changed_By__c = author == null ? null : cut((String) author.get('Name'), 121),
                    Delegate_User__c = cut((String) row.get('DelegateUser'), 80),
                    Section__c = cut((String) row.get('Section'), 40),
                    Action__c = cut((String) row.get('Action'), 120),
                    Display__c = cut((String) row.get('Display'), 1000)
                )
            );
        }
        if (kept.isEmpty()) {
            return;
        }
        List<String> failures = new List<String>();
        for (
            Database.UpsertResult result : Database.upsert(
                kept,
                Setup_Change__c.Audit_Trail_Id__c,
                false,
                AccessLevel.SYSTEM_MODE
            )
        ) {
            if (!result.isSuccess() && !result.getErrors().isEmpty()) {
                failures.add(result.getErrors()[0].getMessage());
            }
        }
        logFailures(failures, Label.Core_SetupChanges_LogNotCopied);
    }

    private static void remove(List<SObject> rows) {
        List<String> failures = new List<String>();
        for (Database.DeleteResult result : Database.delete(rows, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess() && !result.getErrors().isEmpty()) {
                failures.add(result.getId() + ': ' + result.getErrors()[0].getMessage());
            }
        }
        logFailures(failures, Label.Core_SetupChanges_LogNotRemoved);
    }

    /** One entry per chunk, so a run that cannot write does not flood the Error Log. */
    private static void logFailures(List<String> failures, String template) {
        if (failures.isEmpty()) {
            return;
        }
        ErrorLogger.logMessage(
            String.format(
                template,
                new List<String>{ String.valueOf(failures.size()), failures[0] }
            ),
            LOG_CONTEXT,
            ErrorLogger.SEVERITY_WARNING
        );
    }

    /** When the newest kept change was made, or null when nothing is kept. */
    private static Datetime newestKept() {
        List<Setup_Change__c> newest = [
            SELECT Changed_At__c
            FROM Setup_Change__c
            WHERE Changed_At__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Changed_At__c DESC
            LIMIT 1
        ];
        return newest.isEmpty() ? null : newest[0].Changed_At__c;
    }

    private static String cut(String value, Integer length) {
        return value == null ? null : value.left(length);
    }
}
