/**
 * The Nightly Jobs page of the BarnCRM Settings console, for the Giving module (ADR-0038).
 *
 * It answers the three questions an administrator has about a nightly job, in this order: is it
 * switched on, when did it last run, and what did it do. It also carries the only supported way
 * the jobs are ever started or stopped, so the `Manage_Nonprofit_Settings` permission checked
 * here is the authorization for everything the runs do afterwards.
 */
public with sharing class GivingJobsController {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';
    private static final String CONTEXT = 'Giving nightly jobs page';

    /**
     * How long after a job fires its run may still be unrecorded before the page says something
     * is wrong. A batch that starts at 01:15 finishes in minutes, so two hours is generous, and
     * it is measured from the platform's own record of the last firing rather than from a fixed
     * number of hours: a job scheduled ten minutes ago has not missed anything.
     */
    private static final Integer SETTLING_HOURS = 2;

    /** Raised with a message the page shows as it is. */
    public class GivingJobsException extends Exception {
    }

    /** One of the three jobs, as the page shows it. */
    public class JobView {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Boolean scheduled;
        @AuraEnabled
        public Datetime lastRun;
        @AuraEnabled
        public String lastRunSummary;
        @AuraEnabled
        public Boolean stale;
    }

    /** The page, in one round trip. */
    public class JobsView {
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean scheduled;
        @AuraEnabled
        public Datetime nextRunAt;
        @AuraEnabled
        public List<JobView> jobs;
    }

    @AuraEnabled(cacheable=true)
    public static JobsView getJobs() {
        try {
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, CONTEXT);
        }
    }

    /** Starts or stops all three nightly jobs. */
    @AuraEnabled
    public static JobsView setSchedule(Boolean scheduled) {
        try {
            requirePermission();
            if (scheduled == true) {
                GivingScheduler.scheduleAll();
            } else {
                GivingScheduler.stopAll();
            }
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Schedule the Giving nightly jobs');
        }
    }

    /**
     * Runs the top up and the overdue pass now. The view comes back with the previous run still
     * on it: the top up is a batch, so the page refreshes into the new last run once it ends.
     */
    @AuraEnabled
    public static JobsView runNow() {
        try {
            requirePermission();
            GivingScheduler.runNow();
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Run the Giving nightly jobs now');
        }
    }

    private static JobsView currentView() {
        Map<String, GivingScheduler.JobStatus> statuses = GivingScheduler.statuses();
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();

        JobsView view = new JobsView();
        view.canManage = canManage();
        view.scheduled = GivingScheduler.isScheduled();
        view.nextRunAt = GivingScheduler.nextRunAt();
        view.jobs = new List<JobView>{
            jobView(
                statuses.get(GivingScheduler.TOP_UP_JOB_NAME),
                System.Label.Giving_NightlyJobs_TopUpName,
                System.Label.Giving_NightlyJobs_TopUpDescription,
                settings.Installment_Top_Up_Last_Run__c,
                settings.Installment_Top_Up_Last_Run_Summary__c
            ),
            jobView(
                statuses.get(GivingScheduler.OVERDUE_JOB_NAME),
                System.Label.Giving_NightlyJobs_OverdueName,
                System.Label.Giving_NightlyJobs_OverdueDescription,
                settings.Installment_Overdue_Last_Run__c,
                settings.Installment_Overdue_Last_Run_Summary__c
            ),
            jobView(
                statuses.get(GivingScheduler.LEVELS_JOB_NAME),
                System.Label.Giving_NightlyJobs_LevelsName,
                System.Label.Giving_NightlyJobs_LevelsDescription,
                settings.Donor_Levels_Last_Recalculated__c,
                null
            )
        };
        return view;
    }

    private static JobView jobView(
        GivingScheduler.JobStatus status,
        String name,
        String description,
        Datetime lastRun,
        String lastRunSummary
    ) {
        JobView view = new JobView();
        view.name = name;
        view.description = description;
        view.scheduled = status != null && status.scheduled == true;
        view.lastRun = lastRun;
        view.lastRunSummary = lastRunSummary;
        view.stale = isStale(status, lastRun);
        return view;
    }

    /**
     * True when the platform fired this job, long enough ago for it to have finished, and the job
     * recorded nothing since.
     *
     * Being scheduled and having fired are both part of the test on purpose. An org that has not
     * switched the jobs on has not missed anything, and warning it about a run that was never
     * going to happen teaches administrators to ignore the warning. The page says "not scheduled"
     * in that case instead, which is a different sentence with a different button under it.
     */
    private static Boolean isStale(GivingScheduler.JobStatus status, Datetime lastRun) {
        if (status == null || status.scheduled != true || status.previousFireTime == null) {
            return false;
        }
        if (status.previousFireTime > Datetime.now().addHours(-SETTLING_HOURS)) {
            return false;
        }
        return lastRun == null || lastRun < status.previousFireTime;
    }

    private static Boolean canManage() {
        return FeatureManagement.checkPermission(EDIT_PERMISSION);
    }

    private static void requirePermission() {
        if (!canManage()) {
            throw new GivingJobsException(System.Label.Giving_NightlyJobs_PermissionRequired);
        }
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof GivingJobsException)) {
            ErrorLogger.log(caught, context);
            message = System.Label.Giving_NightlyJobs_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
