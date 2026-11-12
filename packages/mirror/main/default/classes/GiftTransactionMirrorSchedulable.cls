/**
 * The Gift Transaction mirror's nightly run (feature X-07, R-GT6), switched on and off from the
 * Gift Transaction mirror page in the shape ADR-0038 set for the Giving nightly jobs. It is a
 * step of Core's one nightly run (ADR-0166 nightly-job-dispatcher), which runs as the
 * administrator who scheduled it, whose access the run's user mode reads and writes use.
 *
 * 01:35 keeps it after the Opportunity mirror at 01:30 and before the rollups at 02:00.
 */
public with sharing class GiftTransactionMirrorSchedulable implements Schedulable {
	/** The name the run was scheduled under, now the step's key. */
	public static final String JOB_NAME = 'BarnCRM Mirror: Gift Transaction mirror';
	private static final Set<String> RUNNING_JOB_STATUSES = new Set<String>{
		'Queued',
		'Preparing',
		'Processing',
		'Holding'
	};

	/** Starts tonight's run, unless the mirror is off or a run is still going. */
	public void execute(SchedulableContext context) {
		if (!isRunning()) {
			GiftTransactionMirrorBatch.run();
		}
	}

	/** Switches the nightly run on, scheduling Core's nightly run when it is not. */
	public static Id schedule() {
		return NightlyJobs.turnOn(JOB_NAME);
	}

	/** Switches the nightly run off. */
	public static void stop() {
		NightlyJobs.turnOff(JOB_NAME);
	}

	/** True when the step is switched on and the nightly run is scheduled. */
	public static Boolean isScheduled() {
		return NightlyJobs.isStepScheduled(JOB_NAME, true);
	}

	/** The run as a step of the nightly run: only while the mirror is on. */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				System.Label.Mirror_GiftTransactionMirror_Title,
				1,
				35,
				new GiftTransactionMirrorSchedulable()
			)
			.withSwitch(true)
			.activeWhen(GiftTransactionMirrorService.isOn());
	}

	/** When the nightly run next starts, or null when it is not scheduled. */
	public static Datetime nextRunAt() {
		return isScheduled() ? NightlyJobs.nextRunAt(step()) : null;
	}

	/** When the nightly run was scheduled, or null when it is not, for Health Check. */
	public static Datetime scheduledAt() {
		return isScheduled() ? ScheduledJobSelector.startTime(NightlyJobs.jobName()) : null;
	}

	/** True while a run is queued or in progress, so only one runs at a time. */
	public static Boolean isRunning() {
		Set<String> statuses = RUNNING_JOB_STATUSES;
		return ![
				SELECT Id
				FROM AsyncApexJob
				WHERE
					ApexClass.Name = :GiftTransactionMirrorBatch.CLASS_NAME
					AND JobType = 'BatchApex'
					AND Status IN :statuses
				WITH USER_MODE
				LIMIT 1
			]
			.isEmpty();
	}
}
