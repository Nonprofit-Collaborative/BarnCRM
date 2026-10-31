/**
 * The nightly ask reminder job. Scheduled by `GivingScheduler` with the module's other daily jobs
 * so that nobody opens Setup to schedule Apex (Principle 1).
 *
 * It does nothing when the Ask Reminders setting is off (R-AC2), and it is safe to run twice on
 * the same day: a donor already reminded for its date is skipped (R-AC3).
 */
public with sharing class AskReminderSchedulable implements Schedulable {
    public void execute(SchedulableContext context) {
        try {
            if (!AskReminderService.isEnabled()) {
                return;
            }
            Database.executeBatch(new AskReminderBatch(), AskReminderBatch.CHUNK_SIZE);
        } catch (Exception jobFailure) {
            ErrorLogger.log(jobFailure, 'AskReminderSchedulable');
        }
    }
}
