/**
 * The run a schedule's save queues (R-SSC3), so its shifts appear without waiting for the
 * nightly run. Up to a batch chunk of schedules runs here; a larger save (an import, a bulk
 * edit) hands its schedules to `ShiftScheduleBatch`, which takes them a chunk per transaction
 * (R-SSC6).
 *
 * Queuing never fails a save: with no queueable job left in the transaction, or the module
 * turned off, nothing is queued and the nightly run creates the shifts instead, and removes
 * those of a schedule the save marked Rebuild Pending (R-SSC6).
 */
public with sharing class ShiftScheduleGenerator implements Queueable {
    private static final String LOG_CONTEXT = 'ShiftScheduleGenerator';

    private final Set<Id> scheduleIds;

    public ShiftScheduleGenerator(Set<Id> scheduleIds) {
        this.scheduleIds = scheduleIds;
    }

    /** Queues one run for these schedules, when there are any and a job can still be queued. */
    public static void queue(Set<Id> scheduleIds) {
        if (scheduleIds == null || scheduleIds.isEmpty() || ShiftScheduleService.isTurnedOff()) {
            return;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        try {
            System.enqueueJob(new ShiftScheduleGenerator(new Set<Id>(scheduleIds)));
        } catch (Exception notQueued) {
            ErrorLogger.log(notQueued, LOG_CONTEXT);
        }
    }

    public void execute(QueueableContext context) {
        try {
            if (scheduleIds.size() <= ShiftScheduleBatch.chunkSize()) {
                ShiftScheduleService.run(scheduleIds);
            } else {
                Database.executeBatch(
                    new ShiftScheduleBatch(scheduleIds),
                    ShiftScheduleBatch.chunkSize()
                );
            }
        } catch (Exception runFailure) {
            // The nightly run tries these schedules again.
            ErrorLogger.log(runFailure, LOG_CONTEXT);
        }
    }
}
