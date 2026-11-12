/**
 * The Giving module's five nightly jobs, switched on and off together from the Nightly Jobs page
 * of the BarnCRM Settings console (ADR-0038). Each is a step of Core's one nightly run (ADR-0166
 * nightly-job-dispatcher), keyed by the name it was once scheduled under.
 *
 * The pledge reminders joined the other four in 1.5 (G-37). Scheduling them sends nothing on its
 * own: like the ask reminders, the step does nothing while its setting is off, and
 * `Pledge_Reminders_Enabled__c` ships off (D-162). The Pledge Reminders page keeps its own switch
 * for that one step.
 *
 * All five are safe to run twice on the same day: topping up a schedule adds only the
 * installments that are missing, marking overdue and placing donors on their giving level are
 * recalculations, and both reminder passes skip a donor or payment already reminded.
 */
public with sharing class GivingScheduler {
	/** The names the jobs were scheduled under, now their step keys. */
	public static final String TOP_UP_JOB_NAME = 'BarnCRM Giving Installment Top Up';
	public static final String OVERDUE_JOB_NAME = 'BarnCRM Giving Installments Overdue';
	public static final String LEVELS_JOB_NAME = 'BarnCRM Giving Donor Levels';
	public static final String ASK_JOB_NAME = 'BarnCRM Giving Ask Reminders';
	public static final String PLEDGE_JOB_NAME = PledgeReminderScheduler.JOB_NAME;

	/** What the settings page knows about one of the five jobs. */
	public class JobStatus {
		public String jobName;
		public Boolean scheduled = false;
		public Datetime nextRunAt;
		/**
		 * When the nightly run last started this job, which is not when the job last finished.
		 * The two together are how the page tells "started and recorded nothing" from "never
		 * started".
		 */
		public Datetime previousFireTime;
	}

	/**
	 * The five jobs as steps of the nightly run. The times, and why they are these times: the
	 * top up runs first so the overdue pass sees every payment it created, and the donor level
	 * pass runs an hour after the rollups at 02:00, because the ladder reads a giving total the
	 * rollups maintain. The pledge reminders follow at 03:15, after the overdue pass, and the ask
	 * reminders at 03:30, on settled data (G-29). The nightly run also never starts a step before
	 * the one before it has finished.
	 */
	public static List<NightlyStep> steps() {
		return new List<NightlyStep>{
			new NightlyStep(
					TOP_UP_JOB_NAME,
					System.Label.Giving_NightlyJobs_TopUpName,
					1,
					15,
					new InstallmentTopUpSchedulable()
				)
				.withSwitch(true),
			new NightlyStep(
					OVERDUE_JOB_NAME,
					System.Label.Giving_NightlyJobs_OverdueName,
					1,
					45,
					new InstallmentSchedulable()
				)
				.withSwitch(true),
			new NightlyStep(
					LEVELS_JOB_NAME,
					System.Label.Giving_NightlyJobs_LevelsName,
					3,
					0,
					new DonorLevelSchedulable()
				)
				.withSwitch(true),
			PledgeReminderScheduler.step(),
			new NightlyStep(
					ASK_JOB_NAME,
					System.Label.Giving_NightlyJobs_AskRemindersName,
					3,
					30,
					new AskReminderSchedulable()
				)
				.withSwitch(true)
		};
	}

	/**
	 * Switches all five jobs on and makes sure the nightly run is scheduled. Returns the run's
	 * trigger Id, once.
	 */
	public static List<Id> scheduleAll() {
		Id runId;
		for (String jobName : jobNames()) {
			runId = NightlyJobs.turnOn(jobName);
		}
		return runId == null ? new List<Id>() : new List<Id>{ runId };
	}

	/** True when the job with this name is switched on and the nightly run is scheduled. */
	public static Boolean isJobScheduled(String jobName) {
		return jobNames().contains(jobName) &&
			NightlyJobs.isStepScheduled(jobName, jobName != PLEDGE_JOB_NAME);
	}

	/**
	 * Switches just the one job with this name on, doing nothing for a name that is not one of
	 * the five.
	 */
	public static void scheduleJobNamed(String jobName) {
		if (jobNames().contains(jobName)) {
			NightlyJobs.turnOn(jobName);
		}
	}

	/**
	 * Switches all five jobs off. Nothing already generated, marked Overdue, placed on a level or
	 * logged as reminded is changed. The nightly run stays scheduled for the other steps.
	 */
	public static void stopAll() {
		for (String jobName : jobNames()) {
			NightlyJobs.turnOff(jobName);
		}
	}

	/**
	 * True when the four jobs that keep giving data moving are all on. Three out of four is not
	 * "on": the overdue pass without the top up marks payments overdue on a schedule nothing is
	 * extending, so the page offers Schedule in that state and `scheduleAll` switches on
	 * whichever job is off. The pledge reminders are left out of the test, because an
	 * administrator may stop them on their own page while the rest keep running.
	 */
	public static Boolean isScheduled() {
		for (JobStatus status : statuses().values()) {
			if (status.jobName != PLEDGE_JOB_NAME && status.scheduled != true) {
				return false;
			}
		}
		return true;
	}

	/** When the next of the five jobs is due, or null when none of them is on. */
	public static Datetime nextRunAt() {
		Datetime earliest = null;
		for (JobStatus status : statuses().values()) {
			if (status.nextRunAt == null) {
				continue;
			}
			if (earliest == null || status.nextRunAt < earliest) {
				earliest = status.nextRunAt;
			}
		}
		return earliest;
	}

	/**
	 * Starts the top up, the overdue pass and both reminder passes now, without waiting for
	 * tonight. Donor levels are not included: that pass has its own Recalculate now button on the
	 * Donor Levels page, and a second button for the same work is a second thing to keep true
	 * (ADR-0038).
	 */
	public static void runNow() {
		new InstallmentTopUpSchedulable().execute(null);
		new InstallmentSchedulable().execute(null);
		// Both are safe to repeat: a payment or donor already reminded for its date is skipped,
		// and each does nothing while its setting is off (G-29, G-30).
		new PledgeReminderScheduler().execute(null);
		new AskReminderSchedulable().execute(null);
	}

	/** Each of the five jobs by name: whether it is on, when it runs next and last started. */
	public static Map<String, JobStatus> statuses() {
		Map<String, JobStatus> byName = new Map<String, JobStatus>();
		Boolean runScheduled = NightlyJobs.isScheduled();
		for (NightlyStep step : steps()) {
			JobStatus status = new JobStatus();
			status.jobName = step.key;
			status.scheduled =
				runScheduled && NightlyJobs.isSwitchedOn(step.key, step.switchDefault);
			status.nextRunAt = status.scheduled ? NightlyJobs.nextRunAt(step) : null;
			status.previousFireTime = NightlyJobs.lastStarted(step.key);
			byName.put(step.key, status);
		}
		return byName;
	}

	private static List<String> jobNames() {
		return new List<String>{
			TOP_UP_JOB_NAME,
			OVERDUE_JOB_NAME,
			LEVELS_JOB_NAME,
			PLEDGE_JOB_NAME,
			ASK_JOB_NAME
		};
	}
}
