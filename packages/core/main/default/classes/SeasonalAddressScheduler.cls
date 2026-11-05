/**
 * The seasonal address swap, a step of the nightly run at 0:30 (ADR-0166
 * nightly-job-dispatcher), which runs while the Seasonal Addresses switch on the Addresses page
 * of the BarnCRM Settings console is on.
 *
 * The switch is an administrator's, not Setup's: saving it on makes sure the nightly run is
 * scheduled (`SettingsService` calls `applySwitch`), and saving it off leaves the step out of
 * tonight's run. An install or upgrade with the switch on schedules the run if it is missing
 * (`scheduleIfEnabled`).
 *
 * Still schedulable: an org upgraded from before the nightly run may have this job scheduled on
 * its own, and when it fires it adopts the old schedules (R-NJ5) and does tonight's swap.
 */
public with sharing class SeasonalAddressScheduler implements Schedulable {
    /** The name the job was scheduled under, now the step's key. */
    public static final String JOB_NAME = 'BarnCRM Seasonal Addresses';

    public void execute(SchedulableContext context) {
        if (context != null) {
            NightlyJobs.adoptOldSchedules();
        }
        Database.executeBatch(new SeasonalAddressBatch(), SeasonalAddressBatch.CHUNK_SIZE);
    }

    /** True when the Seasonal Addresses switch is on. */
    public static Boolean isEnabled() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings != null && settings.Seasonal_Addresses_Enabled__c == true;
    }

    /**
     * Follows the switch just saved: on makes sure the nightly run is scheduled; off needs
     * nothing, since the step reads the switch every night.
     */
    public static void applySwitch(Boolean enabled) {
        if (enabled == true) {
            start();
        }
    }

    /** Schedules the nightly run when the switch is on and the run is missing. */
    public static void scheduleIfEnabled() {
        if (isEnabled() && !NightlyJobs.isScheduled()) {
            start();
        }
    }

    /**
     * An org upgraded from before the switch existed may still run the swap on its own
     * schedule, and its switch would read off while the swap runs. Turns the switch on for such
     * an org, so what the page says is what is happening.
     */
    public static void adoptExistingSchedule() {
        if (!isEnabled() && ScheduledJobSelector.isScheduled(JOB_NAME)) {
            SettingsService.saveBookkeeping(
                new Map<String, Object>{ 'Seasonal_Addresses_Enabled__c' => true }
            );
        }
    }

    /** Makes sure the nightly run, which does the swap, is scheduled. */
    public static Id start() {
        return NightlyJobs.start();
    }

    /** Runs the swap now, without waiting for tonight. */
    public static Id runNow() {
        return Database.executeBatch(new SeasonalAddressBatch(), SeasonalAddressBatch.CHUNK_SIZE);
    }

    /** True when the switch is on and the nightly run is scheduled. */
    public static Boolean isScheduled() {
        return isEnabled() && NightlyJobs.isScheduled();
    }

    /** When the swap is next due, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        return isScheduled() ? NightlyJobs.nextRunAt(step()) : null;
    }

    /** The swap as a step of the nightly run: half past midnight, before the day's mail. */
    public static NightlyStep step() {
        return new NightlyStep(
                JOB_NAME,
                System.Label.Core_HealthCheck_JobSeasonalAddresses,
                0,
                30,
                new SeasonalAddressScheduler()
            )
            .activeWhen(isEnabled());
    }
}
