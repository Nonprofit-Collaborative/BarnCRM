/**
 * Deletes Error Log entries older than the retention setting, whatever their status (rule
 * R-E6, owner decision 2026-10-13, ADMIN-26). Each entry can carry two long text fields, so an
 * Error Log nobody empties slowly fills the org's data storage.
 *
 * Started by the daily Error Log run (`ErrorDigestScheduler`), so no extra scheduled job is
 * needed. A batch, so a flooded log is emptied whatever its size.
 *
 * ADR-0021 is the authority for running without sharing: the delete is package upkeep of a
 * package owned object, and the scheduled run's owner may not see every entry. It deletes
 * nothing else, and the entries go to the Recycle Bin.
 */
public without sharing class ErrorLogRetention implements Database.Batchable<SObject> {
    /** Shipped default, and what a missing or unreadable setting means. */
    public static final Integer DEFAULT_DAYS = 180;

    /** Rows per chunk; an entry is small to delete but each chunk is one DML. */
    public static final Integer CHUNK_SIZE = 2000;

    private final Datetime cutoff;

    public ErrorLogRetention(Datetime cutoff) {
        this.cutoff = cutoff;
    }

    /** How many days entries are kept; 0 keeps every entry. */
    public static Integer retentionDays() {
        Decimal configured = SettingsService.getSettings().Error_Log_Retention_Days__c;
        if (configured == null || configured < 0) {
            return DEFAULT_DAYS;
        }
        return configured.intValue();
    }

    /**
     * Starts the delete when entries are kept for a set time. Returns the batch job, or null
     * when every entry is kept.
     */
    public static Id start() {
        Integer days = retentionDays();
        if (days == 0) {
            return null;
        }
        return Database.executeBatch(
            new ErrorLogRetention(System.now().addDays(-days)),
            CHUNK_SIZE
        );
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            [SELECT Id FROM Error_Log__c WHERE CreatedDate < :cutoff WITH SYSTEM_MODE]
        );
    }

    public void execute(Database.BatchableContext context, List<Error_Log__c> scope) {
        // Some may have been deleted by hand since the batch read them; the rest still go.
        Database.delete(scope, false, AccessLevel.SYSTEM_MODE);
    }

    public void finish(Database.BatchableContext context) {
        // Nothing to record: the Error Log list shows what is left.
        return;
    }
}
