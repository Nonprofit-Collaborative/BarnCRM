/**
 * The Opportunity mirror's nightly run (feature X-01, R-OM8), started and stopped from the
 * Opportunity mirror page in the shape ADR-0038 set for the Giving nightly jobs. It runs as the
 * administrator who scheduled it, whose access the run's user mode reads and writes use.
 *
 * 01:30 keeps it clear of the seasonal address swap at 00:30, the Giving jobs at 01:15 and 01:45
 * and the rollups at 02:00, which then count the gifts it made.
 */
public with sharing class OpportunityMirrorSchedulable implements Schedulable {
    public static final String JOB_NAME = 'BarnCRM Connect: Opportunity mirror';
    private static final String CRON = '0 30 1 * * ?';
    /** The scheduled Apex job type, which is what CronJobDetail calls a scheduled class. */
    private static final String SCHEDULED_APEX = '7';
    private static final Set<String> RUNNING_JOB_STATUSES = new Set<String>{
        'Queued',
        'Preparing',
        'Processing',
        'Holding'
    };

    /** Starts tonight's run, unless the mirror is off or a run is still going. */
    public void execute(SchedulableContext context) {
        if (!isRunning()) {
            OpportunityMirrorBatch.run();
        }
    }

    /** Schedules the nightly run; a second press returns the job already there. */
    public static Id schedule() {
        CronTrigger existing = job();
        return existing != null
            ? existing.Id
            : System.schedule(JOB_NAME, CRON, new OpportunityMirrorSchedulable());
    }

    public static void stop() {
        CronTrigger existing = job();
        if (existing != null) {
            System.abortJob(existing.Id);
        }
    }

    /** When the nightly run next starts, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        CronTrigger existing = job();
        return existing == null ? null : existing.NextFireTime;
    }

    /** When the nightly run was scheduled, or null when it is not, for Health Check. */
    public static Datetime scheduledAt() {
        CronTrigger existing = job();
        return existing == null ? null : existing.StartTime;
    }

    /** True while a run is queued or in progress, so only one runs at a time. */
    public static Boolean isRunning() {
        Set<String> statuses = RUNNING_JOB_STATUSES;
        return ![
                SELECT Id
                FROM AsyncApexJob
                WHERE
                    ApexClass.Name = :OpportunityMirrorBatch.CLASS_NAME
                    AND JobType = 'BatchApex'
                    AND Status IN :statuses
                WITH USER_MODE
                LIMIT 1
            ]
            .isEmpty();
    }

    private static CronTrigger job() {
        List<CronTrigger> jobs = [
            SELECT Id, NextFireTime, StartTime
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME AND CronJobDetail.JobType = :SCHEDULED_APEX
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0];
    }
}
