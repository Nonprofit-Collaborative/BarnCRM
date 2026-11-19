/**
 * The hourly check of the Mirror Case bridge (N-10, owner decision 2026-11-14 "Hourly if cases
 * exist"): one scheduled job, at a quarter past every hour, whose work is
 * `CaseProviderRequests.startHourly`, which sends unsent Cases and reads status only when an open
 * request or an open Case of the chosen Type exists. The nightly step (`CaseProviderRequests.step`)
 * runs the same work, which is what schedules this job and keeps it scheduled; so the Nightly Jobs
 * card is where an administrator sees it, switches it off and starts it now (ADR-0166).
 *
 * Found again by name and never doubled, as `TabAccessScheduler` is: a job of this name on
 * another cron is replaced under the same name. A class of its own because Apex refuses to queue
 * a class that is both Queueable and Schedulable ("Queueable cannot be implemented with other
 * system interfaces").
 */
public with sharing class CaseProviderRequestsHourly implements Schedulable {
	/** The name the scheduled job carries, so it is found again rather than doubled. */
	public static final String JOB_NAME = 'BarnCRM Mirror: Case requests hourly';

	/** Every hour at a quarter past, clear of the hourly tab access check on the hour. */
	@TestVisible
	private static final String HOURLY_CRON = '0 15 * * * ?';

	public void execute(SchedulableContext context) {
		CaseProviderRequests.startHourly();
	}

	/**
	 * Schedules the hourly check as the running user, or keeps the one already scheduled. A job
	 * of this name on another cron is aborted and scheduled again, so there is never more than one.
	 *
	 * @return the scheduled job's trigger Id
	 */
	public static Id ensure() {
		String cron = ScheduledJobSelector.cronExpressionByName(JOB_NAME);
		if (cron != null && cron != HOURLY_CRON) {
			ScheduledJobSelector.stopNamed(JOB_NAME);
		}
		return ScheduledJobSelector.ensure(JOB_NAME, HOURLY_CRON, new CaseProviderRequestsHourly());
	}

	/** Removes the hourly job; does nothing when it is not scheduled. */
	public static void stop() {
		ScheduledJobSelector.stopNamed(JOB_NAME);
	}

	/** True when the hourly job is scheduled. */
	public static Boolean isScheduled() {
		return ScheduledJobSelector.isScheduled(JOB_NAME);
	}
}
