/**
 * One scheduled job BarnCRM runs overnight, as Health Check's "Schedule all nightly jobs" fix
 * sees it (ADR-NEXT, health-check-schedules-every-nightly-job). Core implements it for its own
 * jobs in `NightlyJobs`; a dependent package implements it for each job its
 * `NightlyJobProvider` returns.
 */
@NamespaceAccessible
public interface NightlyJob {
    /** The job's name as an administrator reads it, from a custom label. */
    String label();

    /** True when the job is scheduled. */
    Boolean isScheduled();

    /**
     * Schedules the job at its usual time under its usual name, so its own page sees and stops
     * it. Does nothing when it is already scheduled.
     */
    void schedule();
}
