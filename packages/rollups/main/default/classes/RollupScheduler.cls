/**
 * The nightly rollup run, and the two buttons on the Rollups page that turn it on and off.
 *
 * The run is a step of Core's one nightly run (ADR-0166 nightly-job-dispatcher) at the hour the
 * Time of the Nightly Run setting holds; the buttons switch the step on and off. The switch is an
 * administrator's, not Setup's: it lives in the BarnCRM Settings console.
 */
public with sharing class RollupScheduler implements Schedulable {
	/** The name the scheduled job carries, so the console can find it again. */
	public static final String JOB_NAME = 'BarnCRM Rollups';

	/**
	 * The name used for the job. A test gives it a name of its own, because the org a test runs
	 * in may already have the nightly run, which a test can neither see past nor stop.
	 */
	@TestVisible
	private static String jobNameInUse = JOB_NAME;

	/** The name the nightly job is scheduled and found under. */
	public static String jobName() {
		return jobNameInUse;
	}

	/** The setting that holds the hour the nightly run starts (Section 14B, ADR-0136). */
	public static final String HOUR_SETTING = 'Nightly_Run_Hour__c';

	/**
	 * Two in the morning, after the day's data entry and before the day's reporting: the hour
	 * when the setting is blank or out of range.
	 */
	public static final Integer DEFAULT_HOUR = 2;

	/** The hour the nightly run starts, 0 to 23, in the scheduling user's time zone. */
	public static Integer nightlyHour() {
		Decimal hour = SettingsService.number(RollupService.SETTINGS_OBJECT, HOUR_SETTING);
		return hour == null || hour < 0 || hour > 23 ? DEFAULT_HOUR : hour.intValue();
	}

	/** The nightly run's hour as the person reading it writes a time, for example 2:00 AM. */
	public static String nightlyTime() {
		return Datetime.newInstance(Date.today(), Time.newInstance(nightlyHour(), 0, 0, 0))
			.format('h:mm a');
	}

	/**
	 * True for the one run Recalculate all sets up for tonight, which covers every definition;
	 * the nightly job covers Scheduled and Both only. Null on a job scheduled before this field.
	 */
	private Boolean everyDefinition = false;

	/** The nightly job. */
	public RollupScheduler() {
		this(false);
	}

	/** The nightly job, or with `everyDefinition` the one run Recalculate all sets up tonight. */
	public RollupScheduler(Boolean everyDefinition) {
		this.everyDefinition = everyDefinition == true;
	}

	/**
	 * The nightly run, and a processor for Rollup Queue entries no save started one for
	 * (ROLLUPS-7), so a queued total never waits longer than a night. Nothing while the module
	 * is turned off (ADR-0125 decision 9), a one-off Run tonight included, and an Info entry
	 * says the run was skipped; the schedule stays, so it runs again once it is on.
	 * The nightly run also gives the Rollup Builder sets to anyone given a BarnCRM role since
	 * (`ModuleAccessSyncs`, D2).
	 */
	public void execute(SchedulableContext context) {
		if (RollupService.isTurnedOff()) {
			ErrorLogger.logMessage(
				BarnHelp.text('Rollups', 'Core_Rollups_ScheduledRunTurnedOff'),
				'RollupScheduler',
				ErrorLogger.SEVERITY_INFO
			);
			return;
		}
		if (this.everyDefinition == true) {
			RollupService.startFullRunOfEveryDefinition();
		} else {
			RollupService.startNightlyRun();
			ModuleAccessSyncs.requestFor(RollupService.MODULE_NAME);
		}
		RollupQueue.processPending();
	}

	/** Switches the nightly step on, scheduling Core's nightly run when it is not. */
	public static Id start() {
		return NightlyJobs.turnOn(jobNameInUse);
	}

	/** Switches the nightly step off. */
	public static void stop() {
		NightlyJobs.turnOff(jobNameInUse);
	}

	/**
	 * The rollup run as a step of the nightly run, at the hour the setting holds. Read every
	 * night, so saving a new hour needs nothing moved.
	 */
	public static NightlyStep step() {
		return new NightlyStep(
				jobNameInUse,
				System.Label.Core_JobNotice_Rollups,
				nightlyHour(),
				0,
				new RollupScheduler()
			)
			.withSwitch(true);
	}

	/** Runs the nightly work now, without waiting for tonight; null when nothing started. */
	public static Id runNow() {
		return RollupService.startNightlyRun();
	}

	/**
	 * Sets up one run for the coming nightly hour (2:00 AM unless the setting says otherwise)
	 * in the running user's time zone, for Recalculate all when the nightly run is not
	 * scheduled (slice S12). Like Recalculate all, it covers every active definition. The job
	 * carries the night's date in its name, so asking twice sets up one run.
	 */
	public static Id scheduleTonight() {
		Integer hour = nightlyHour();
		Date night = Integer.valueOf(Datetime.now().format('H')) < hour
			? Date.today()
			: Date.today().addDays(1);
		String name = jobNameInUse + ' ' + String.valueOf(night);
		String cron = String.join(
			new List<Object>{ '0 0', hour, night.day(), night.month(), '?', night.year() },
			' '
		);
		return ScheduledJobSelector.ensure(name, cron, new RollupScheduler(true));
	}

	/** True when the step is switched on and the nightly run is scheduled. */
	public static Boolean isScheduled() {
		return NightlyJobs.isStepScheduled(jobNameInUse, true);
	}

	/** When the nightly rollup run is next due, or null when it is not scheduled. */
	public static Datetime nextRunAt() {
		return isScheduled() ? NightlyJobs.nextRunAt(step()) : null;
	}
}
