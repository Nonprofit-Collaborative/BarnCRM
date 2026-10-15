/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to have Giving's nightly jobs
 * counted and scheduled by Health Check's "Schedule all nightly jobs" fix (ADR-0075,
 * health-check-schedules-every-nightly-job).
 *
 * It lists the installment top up, the installments overdue pass and the donor levels pass, the
 * three jobs `GivingScheduler` runs, each scheduled under the name the Nightly Jobs page already
 * looks for (ADR-0038). The acknowledgment send is not listed: it emails donors, so whether it
 * runs is the organization's choice, made on its own page.
 *
 * `@NamespaceAccessible` for the reason `GivingHealthCheckExtension` is: Core resolves it with
 * `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class GivingNightlyJobProvider implements NightlyJobProvider {
    @NamespaceAccessible
    public GivingNightlyJobProvider() {
        return;
    }

    public List<NightlyJob> nightlyJobs() {
        return new List<NightlyJob>{
            new GivingJob(
                GivingScheduler.TOP_UP_JOB_NAME,
                System.Label.Giving_NightlyJobs_TopUpName
            ),
            new GivingJob(
                GivingScheduler.OVERDUE_JOB_NAME,
                System.Label.Giving_NightlyJobs_OverdueName
            ),
            new GivingJob(
                GivingScheduler.LEVELS_JOB_NAME,
                System.Label.Giving_NightlyJobs_LevelsName
            )
        };
    }

    /** One of the three jobs, scheduled and counted by its job name. */
    @TestVisible
    private class GivingJob implements NightlyJob {
        private final String jobName;
        private final String jobLabel;

        GivingJob(String jobName, String jobLabel) {
            this.jobName = jobName;
            this.jobLabel = jobLabel;
        }

        public String label() {
            return jobLabel;
        }

        public Boolean isScheduled() {
            return GivingScheduler.isJobScheduled(jobName);
        }

        public void schedule() {
            GivingScheduler.scheduleJobNamed(jobName);
        }
    }
}
