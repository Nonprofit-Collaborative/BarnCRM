/**
 * The morning grant reminder run (F-02, R-GQ3): reminds every open requirement coming due, 100
 * per transaction (one email call per chunk). One chunk that fails is logged and the rest still
 * run; a requirement that was not stamped is tried again the next morning.
 */
public with sharing class GrantReminderBatch implements Database.Batchable<SObject> {
    /** Requirements per transaction: one `Messaging.sendEmail` call covers the chunk. */
    public static final Integer CHUNK_SIZE = 100;

    private static final String LOG_CONTEXT = 'GrantReminderBatch';

    /** Starts the run; null when the module is off or both reminder settings are off (R-GQ4). */
    public static Id startMorning() {
        if (!GrantReminderService.isActive()) {
            return null;
        }
        return Database.executeBatch(new GrantReminderBatch(), CHUNK_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Date today = Date.today();
        return GrantReminderSelector.dueLocator(
            GrantReminderService.oldestDue(today),
            GrantReminderService.windowEnd(today, FundersSettings.reminderLeadDays())
        );
    }

    public void execute(Database.BatchableContext context, List<Grant_Requirement__c> scope) {
        try {
            GrantReminderService.remind(scope, Date.today());
        } catch (Exception chunkFailure) {
            ErrorLogger.log(chunkFailure, LOG_CONTEXT);
        }
    }

    public void finish(Database.BatchableContext context) {
        return;
    }
}
