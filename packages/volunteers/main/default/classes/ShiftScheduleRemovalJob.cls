/**
 * Removes the future shifts of schedules deleted in a save too large to remove them itself
 * (R-SSC5, R-SSC6). The save names the shifts by Id before the delete, because the platform then
 * empties their link to the schedule (SetNull) and nothing else could find them.
 *
 * Each shift is checked again here: one that has started, been Cancelled, or gained a sign-up or
 * hours since the save is kept. A job removes up to `SHIFTS_PER_JOB` shifts and queues the next
 * for the rest. A job that cannot be queued is logged, and its shifts stay as unlinked open
 * shifts a coordinator can delete by hand.
 */
public with sharing class ShiftScheduleRemovalJob implements Queueable {
    /** Shifts per transaction: well inside the 10,000 rows one transaction may delete. */
    public static final Integer SHIFTS_PER_JOB = 5000;

    private static final String LOG_CONTEXT = 'ShiftScheduleRemovalJob';

    /** Set by a test to split a few shifts across jobs. */
    @TestVisible
    private static Integer shiftsPerJobOverride;

    private final List<Id> shiftIds;

    public ShiftScheduleRemovalJob(List<Id> shiftIds) {
        this.shiftIds = shiftIds;
    }

    /** Queues the removal of these shifts, when there are any. */
    public static void queue(Set<Id> shiftIds) {
        if (shiftIds == null || shiftIds.isEmpty()) {
            return;
        }
        enqueue(new List<Id>(shiftIds));
    }

    public void execute(QueueableContext context) {
        try {
            Integer perJob = shiftsPerJobOverride == null ? SHIFTS_PER_JOB : shiftsPerJobOverride;
            Set<Id> now = new Set<Id>();
            List<Id> later = new List<Id>();
            for (Id shiftId : shiftIds) {
                if (now.size() < perJob) {
                    now.add(shiftId);
                } else {
                    later.add(shiftId);
                }
            }
            ShiftScheduleService.removeShifts(now);
            if (!later.isEmpty()) {
                enqueue(later);
            }
        } catch (Exception removalFailure) {
            ErrorLogger.log(removalFailure, LOG_CONTEXT);
        }
    }

    private static void enqueue(List<Id> shiftIds) {
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            ErrorLogger.logMessage(
                'No queueable job was left to remove ' +
                    shiftIds.size() +
                    ' future shifts of deleted shift schedules.',
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
            return;
        }
        try {
            System.enqueueJob(new ShiftScheduleRemovalJob(shiftIds));
        } catch (Exception notQueued) {
            ErrorLogger.log(notQueued, LOG_CONTEXT);
        }
    }
}
