/**
 * The nightly email send's schedule, and the toggle on the Acknowledgments page that starts and
 * stops it.
 *
 * This follows C-18 rather than `GivingScheduler` on purpose (ADR-0032). `GivingScheduler` is
 * called by a module turn-on step that does not exist, so the jobs it knows about are scheduled
 * in no real org. A job with no in-app way to schedule it is a job nobody schedules, and this
 * package already has three of those. The schedule is an administrator's, so it lives on her
 * page.
 *
 * The nightly send is off by default. Most organizations want to look at the queue for the first
 * month, and a package that started mailing donors on install would deserve everything it got.
 */
public with sharing class AcknowledgmentScheduler implements Schedulable {
	/** The name the scheduled job carries, so the page can find it again. */
	public static final String JOB_NAME = 'BarnCRM Giving Acknowledgments';

	private static final String LOG_CONTEXT = 'AcknowledgmentScheduler.execute';

	public void execute(SchedulableContext context) {
		try {
			if (!AcknowledgmentService.isEnabled()) {
				// Switched off since the schedule was started. Nothing to do, and nothing wrong.
				return;
			}
			AcknowledgmentRunService.startEmailRun();
		} catch (Exception nightlyFailure) {
			// A scheduled job's exception goes nowhere a person will ever look, so it goes here.
			ErrorLogger.log(nightlyFailure, LOG_CONTEXT);
		}
	}

	/** Switches the nightly send on, scheduling the nightly run when it is not (R-NJ4). */
	public static Id start() {
		return NightlyJobs.turnOn(JOB_NAME);
	}

	/** Switches the nightly send off. The queue stays exactly as it is. */
	public static void stop() {
		NightlyJobs.turnOff(JOB_NAME);
	}

	/** True when the nightly send is switched on and the nightly run is scheduled. */
	public static Boolean isScheduled() {
		return NightlyJobs.isStepScheduled(JOB_NAME, false);
	}

	/** When the nightly send is next due, or null when it is not scheduled. */
	public static Datetime nextRunAt() {
		return isScheduled() ? NightlyJobs.nextRunAt(step()) : null;
	}

	/**
	 * The send as a step of the nightly run (ADR-0166 nightly-job-dispatcher): quarter to three,
	 * after the installment top up and the overdue pass, so a gift that arrived overnight has its
	 * totals before the donor is thanked. Shipped off: it emails donors.
	 */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				System.Label.Giving_Acknowledgments_Title,
				2,
				45,
				new AcknowledgmentScheduler()
			)
			.withSwitch(false);
	}
}
