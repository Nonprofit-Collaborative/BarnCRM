/**
 * The Volunteers "still need you" job (V-10b): at 7:15 AM it starts `VolunteerNudgeBatch`, which
 * emails the nudges due. Health Check's "Schedule all nightly jobs" fix schedules it through
 * `VolunteersNightlyJobProvider`.
 *
 * It stays scheduled while nudges are off and does nothing until the Send Unfilled Shift Nudges
 * setting is turned on, so turning the setting on needs no other step.
 */
public with sharing class VolunteerNudgeScheduler implements Schedulable {
	/** The name the scheduled job carries, so it can be found again. */
	public static final String JOB_NAME = 'BarnCRM Volunteer Shift Nudges';

	/** A test gives it a name of its own, because the org a test runs in may already have it. */
	@TestVisible
	private static String jobNameInUse = JOB_NAME;

	public void execute(SchedulableContext context) {
		VolunteerNudgeBatch.startMorning();
	}

	/** The job as a step of the nightly run: a quarter past seven, after the shift reminders. */
	public static NightlyStep step() {
		return new NightlyStep(
			jobNameInUse,
			System.Label.Volunteers_NightlyJobs_NudgesName,
			7,
			15,
			new VolunteerNudgeScheduler()
		);
	}
}
