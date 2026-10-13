/**
 * Every nightly job BarnCRM wants scheduled in this org: Core's own, and those of each
 * dependent package that registers a `NightlyJobProvider` (ADR-0075,
 * health-check-schedules-every-nightly-job). Health Check reads the unscheduled ones into one
 * finding and schedules them all with one fix.
 *
 * A provider is found by class name, as `HealthCheckExtensions` finds an extension: a class
 * name takes no `__` prefix, so it is tried with this package's namespace and then without. A
 * provider that is missing, cannot be built or throws is skipped and logged, because a health
 * report must not fail over a module it can do without.
 */
@NamespaceAccessible
public with sharing class NightlyJobs {
    /** The provider classes dependent packages register, in the order they are asked. */
    @NamespaceAccessible
    public static final List<String> PROVIDER_CLASSES = new List<String>{
        'GivingNightlyJobProvider',
        'ConnectNightlyJobProvider'
    };

    private static final String ERROR_CONTEXT = 'NightlyJobs';

    /** Set by a test to the whole list, so no test depends on what the org has scheduled. */
    @TestVisible
    private static List<NightlyJob> jobsOverride;

    /** Injected by Core's tests by class name, since no other package is there to resolve. */
    @TestVisible
    private static Map<String, NightlyJobProvider> providerOverrides = new Map<String, NightlyJobProvider>();

    /** Every job, Core's first, then each installed provider's. */
    public static List<NightlyJob> all() {
        if (jobsOverride != null) {
            return jobsOverride;
        }
        List<NightlyJob> jobs = new List<NightlyJob>{
            new RollupJob(),
            new SeasonalAddressJob(),
            new ErrorDigestJob(),
            new ImportRowPurgeJob()
        };
        for (String className : PROVIDER_CLASSES) {
            jobs.addAll(providedBy(className));
        }
        return jobs;
    }

    /** The jobs that are not scheduled now, in the order `all` lists them. */
    public static List<NightlyJob> unscheduled() {
        List<NightlyJob> waiting = new List<NightlyJob>();
        for (NightlyJob job : all()) {
            if (job.isScheduled() != true) {
                waiting.add(job);
            }
        }
        return waiting;
    }

    /** The labels of the unscheduled jobs: what the finding names and the fix will schedule. */
    public static List<String> unscheduledLabels() {
        List<String> labels = new List<String>();
        for (NightlyJob job : unscheduled()) {
            labels.add(job.label());
        }
        return labels;
    }

    /** Schedules every job that is not scheduled, and returns the labels of those it did. */
    public static List<String> scheduleAll() {
        List<String> scheduled = new List<String>();
        for (NightlyJob job : unscheduled()) {
            job.schedule();
            scheduled.add(job.label());
        }
        return scheduled;
    }

    /**
     * Stops each named job and schedules it again to run as the running user, for jobs whose
     * owner was deactivated (ADMIN-12): such a job stops running but keeps its trigger, so it
     * reads as scheduled. Every job this class knows is scheduled again by `scheduleAll`, and the
     * end of a running automation pause by AutomationResumeJob. Returns the names that are not
     * scheduled afterwards, such as a module job Health Check never schedules for anyone.
     */
    public static List<String> rescheduleAsRunningUser(List<String> jobNames) {
        Datetime pauseEnds = AutomationControl.pausedUntil();
        for (String name : jobNames) {
            Id triggerId = ScheduledJobSelector.triggerIdByName(name);
            if (triggerId != null) {
                ScheduledJobSelector.abort(triggerId);
            }
        }
        scheduleAll();
        if (jobNames.contains(AutomationResumeJob.JOB_NAME) && pauseEnds != null) {
            AutomationResumeJob.scheduleAt(pauseEnds);
        }
        List<String> stoppedOnly = new List<String>();
        for (String name : jobNames) {
            if (ScheduledJobSelector.triggerIdByName(name) == null) {
                stoppedOnly.add(name);
            }
        }
        return stoppedOnly;
    }

    private static List<NightlyJob> providedBy(String className) {
        try {
            NightlyJobProvider provider = providerOverrides.containsKey(className)
                ? providerOverrides.get(className)
                : resolve(className);
            List<NightlyJob> jobs = provider == null ? null : provider.nightlyJobs();
            return jobs == null ? new List<NightlyJob>() : jobs;
        } catch (Exception failed) {
            ErrorLogger.log(failed, ERROR_CONTEXT);
            return new List<NightlyJob>();
        }
    }

    private static NightlyJobProvider resolve(String className) {
        Type providerType = NamespaceUtil.resolveType(className);
        if (providerType == null) {
            return null;
        }
        Object candidate = providerType.newInstance();
        if (candidate instanceof NightlyJobProvider) {
            return (NightlyJobProvider) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement NightlyJobProvider'),
            ERROR_CONTEXT
        );
        return null;
    }

    /** The nightly rollup recalculation, started and stopped on the Rollups page. */
    public class RollupJob implements NightlyJob {
        public String label() {
            return System.Label.Core_HealthCheck_JobRollups;
        }

        public Boolean isScheduled() {
            return RollupScheduler.isScheduled();
        }

        public void schedule() {
            RollupScheduler.start();
        }
    }

    /** The seasonal address swap, started and stopped in the Addresses section. */
    public class SeasonalAddressJob implements NightlyJob {
        public String label() {
            return System.Label.Core_HealthCheck_JobSeasonalAddresses;
        }

        public Boolean isScheduled() {
            return SeasonalAddressScheduler.isScheduled();
        }

        public void schedule() {
            SeasonalAddressScheduler.start();
        }
    }

    /** The error digest, started and stopped in the Error Log section. */
    public class ErrorDigestJob implements NightlyJob {
        public String label() {
            return System.Label.Core_HealthCheck_JobErrorDigest;
        }

        public Boolean isScheduled() {
            // The same test start() makes, so a job it would leave alone counts as scheduled.
            return ScheduledJobSelector.triggerIdByName(ErrorDigestScheduler.JOB_NAME) != null;
        }

        public void schedule() {
            ErrorDigestScheduler.start();
        }
    }

    /**
     * The nightly Import row cleanup (R-IR5, D-40). How long rows are kept is an Import
     * setting, and 0 keeps them, so the job always belongs on the list.
     */
    public class ImportRowPurgeJob implements NightlyJob {
        public String label() {
            return System.Label.Core_HealthCheck_JobImportRows;
        }

        public Boolean isScheduled() {
            return ImportRowPurgeScheduler.isScheduled();
        }

        public void schedule() {
            ImportRowPurgeScheduler.start();
        }
    }
}
