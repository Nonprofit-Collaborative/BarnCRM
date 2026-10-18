/**
 * The nightly run of every active schedule (R-SSC3), and the run a large save hands its
 * schedules to. Ten schedules per transaction (R-SSC6): a schedule on every weekday at the
 * longest horizon (26 weeks) creates 182 shifts, so a chunk stays far inside the 10,000 rows one
 * transaction may write, and every schedule gets its turn however many the org has.
 *
 * One chunk that fails is logged and the rest still run; its schedules are tried again the next
 * night, and the lock each run takes (R-SSC3) means a retry never creates a day twice.
 */
public with sharing class ShiftScheduleBatch implements Database.Batchable<SObject> {
    /** Schedules per transaction (R-SSC6). */
    public static final Integer CHUNK_SIZE = 10;

    private static final String LOG_CONTEXT = 'ShiftScheduleBatch';

    /**
     * A test runs one chunk only (the platform runs a single execute in a test), so a test of
     * many schedules sets the chunk to cover them all.
     */
    @TestVisible
    private static Integer chunkSizeOverride;

    /** Null for the nightly run of every runnable schedule. */
    private final Set<Id> onlyIds;

    /** The nightly run of every active schedule. */
    public ShiftScheduleBatch() {
        this(null);
    }

    /** A run of these schedules only. */
    public ShiftScheduleBatch(Set<Id> onlyIds) {
        this.onlyIds = onlyIds;
    }

    public static Integer chunkSize() {
        return chunkSizeOverride == null ? CHUNK_SIZE : chunkSizeOverride;
    }

    /** Starts the run of every active schedule; null when the module is turned off. */
    public static Id startNightly() {
        if (ShiftScheduleService.isTurnedOff()) {
            return null;
        }
        return Database.executeBatch(new ShiftScheduleBatch(), chunkSize());
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return ShiftScheduleSelector.runnableLocator(onlyIds, ShiftScheduleService.today());
    }

    public void execute(Database.BatchableContext context, List<Shift_Schedule__c> scope) {
        try {
            ShiftScheduleService.run(new Map<Id, Shift_Schedule__c>(scope).keySet());
        } catch (Exception chunkFailure) {
            ErrorLogger.log(chunkFailure, LOG_CONTEXT);
        }
    }

    public void finish(Database.BatchableContext context) {
        return;
    }
}
