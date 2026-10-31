/**
 * The morning shift reminder run (V-10, R-VU6): emails every booking due a reminder, 100 per
 * transaction (one email call per chunk). One chunk that fails is logged and the rest still
 * run; a booking that was not stamped is tried again the next morning, while its shift is
 * still ahead.
 */
public with sharing class VolunteerReminderBatch implements Database.Batchable<SObject> {
    /** Bookings per transaction: one `Messaging.sendEmail` call covers the chunk. */
    public static final Integer CHUNK_SIZE = 100;

    private static final String LOG_CONTEXT = 'VolunteerReminderBatch';

    /** Starts the run; null when the module or the reminders setting is off. */
    public static Id startMorning() {
        if (!VolunteerReminderService.isActive()) {
            return null;
        }
        return Database.executeBatch(new VolunteerReminderBatch(), CHUNK_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return VolunteerReminderSelector.dueLocator(
            ShiftScheduleService.now(),
            VolunteerReminderService.windowEnd(VolunteerSettings.reminderLeadDays())
        );
    }

    public void execute(Database.BatchableContext context, List<Volunteer_Signup__c> scope) {
        try {
            VolunteerReminderService.remind(scope);
        } catch (Exception chunkFailure) {
            ErrorLogger.log(chunkFailure, LOG_CONTEXT);
        }
    }

    public void finish(Database.BatchableContext context) {
        return;
    }
}
