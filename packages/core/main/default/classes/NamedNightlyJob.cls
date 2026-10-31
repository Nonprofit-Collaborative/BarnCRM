/**
 * A nightly job that is one named scheduled Apex job: scheduled at its usual time under its
 * usual name, and counted as scheduled while a job by that name is (ADR-0075). Core and every
 * `NightlyJobProvider` build one of these per job instead of writing a class for each.
 */
@NamespaceAccessible
public with sharing class NamedNightlyJob implements NightlyJob {
    private final String jobLabel;
    private final String jobName;
    private final String cron;
    private final Schedulable job;

    /**
     * @param jobLabel the job's name as an administrator reads it, from a custom label
     * @param jobName the name the job is scheduled under
     * @param cron when it runs
     * @param job what runs
     */
    @NamespaceAccessible
    public NamedNightlyJob(String jobLabel, String jobName, String cron, Schedulable job) {
        this.jobLabel = jobLabel;
        this.jobName = jobName;
        this.cron = cron;
        this.job = job;
    }

    @NamespaceAccessible
    public String label() {
        return jobLabel;
    }

    @NamespaceAccessible
    public Boolean isScheduled() {
        return ScheduledJobSelector.isScheduled(jobName);
    }

    @NamespaceAccessible
    public void schedule() {
        ScheduledJobSelector.ensure(jobName, cron, job);
    }
}
