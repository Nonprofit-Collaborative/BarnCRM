/**
 * The nightly seasonal address swap's schedule, which follows the Seasonal Addresses switch on
 * the Addresses page of the BarnCRM Settings console.
 *
 * The schedule is an administrator's, not Setup's: saving the switch on schedules the job and
 * saving it off stops it (`SettingsService` calls `applySwitch`), which is what "every admin
 * setting lives in the in-app console" means for something that is a scheduled job rather than
 * a field. A job with no in-app way to schedule it is a job nobody schedules, and this package
 * already has one of those. An install or upgrade with the switch on schedules the job if it
 * is missing (`scheduleIfEnabled`).
 */
public with sharing class SeasonalAddressScheduler implements Schedulable {
    /** The name the scheduled job carries, so the settings page can find it again. */
    public static final String JOB_NAME = 'BarnCRM Seasonal Addresses';

    /**
     * Half past midnight. Early enough that a season that starts today is in place before the
     * day's mail merges, and far enough from the rollups at 2:00 AM that the two are not
     * competing for the org's batch slots.
     */
    private static final String NIGHTLY_CRON = '0 30 0 * * ?';

    public void execute(SchedulableContext context) {
        Database.executeBatch(new SeasonalAddressBatch(), SeasonalAddressBatch.CHUNK_SIZE);
    }

    /** True when the Seasonal Addresses switch is on. */
    public static Boolean isEnabled() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings != null && settings.Seasonal_Addresses_Enabled__c == true;
    }

    /**
     * Makes the schedule match the switch just saved: on schedules the nightly swap (nothing
     * happens when it is already scheduled), off stops it.
     */
    public static void applySwitch(Boolean enabled) {
        if (enabled == true) {
            start();
        } else {
            stop();
        }
    }

    /** Schedules the nightly swap when the switch is on and the job is missing. */
    public static void scheduleIfEnabled() {
        if (isEnabled() && !isScheduled()) {
            start();
        }
    }

    /**
     * An org upgraded from before the switch existed may already run the nightly swap, and its
     * switch would read off while the job runs. Turns the switch on for such an org, so what the
     * page says is what is happening. An org that stopped the job has nothing to adopt.
     */
    public static void adoptExistingSchedule() {
        if (!isEnabled() && isScheduled()) {
            SettingsService.saveBookkeeping(
                new Map<String, Object>{ 'Seasonal_Addresses_Enabled__c' => true }
            );
        }
    }

    /** Starts the nightly swap, or does nothing when it is already scheduled. */
    public static Id start() {
        return ScheduledJobSelector.ensure(JOB_NAME, NIGHTLY_CRON, new SeasonalAddressScheduler());
    }

    /** Stops the nightly swap. The addresses stay exactly as the last run left them. */
    public static void stop() {
        ScheduledJobSelector.stopNamed(JOB_NAME);
    }

    /** Runs the swap now, without waiting for tonight. */
    public static Id runNow() {
        return Database.executeBatch(new SeasonalAddressBatch(), SeasonalAddressBatch.CHUNK_SIZE);
    }

    /** True when the nightly swap is scheduled. */
    public static Boolean isScheduled() {
        return ScheduledJobSelector.isScheduled(JOB_NAME);
    }

    /** When the nightly swap is next due, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        return ScheduledJobSelector.nextFireTime(JOB_NAME);
    }

    /** The nightly swap as Health Check's nightly jobs list sees it. */
    public static NightlyJob nightlyJob() {
        return new NamedNightlyJob(
            System.Label.Core_HealthCheck_JobSeasonalAddresses,
            JOB_NAME,
            NIGHTLY_CRON,
            new SeasonalAddressScheduler()
        );
    }
}
