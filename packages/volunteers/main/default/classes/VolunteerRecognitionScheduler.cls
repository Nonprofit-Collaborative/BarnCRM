/**
 * The Volunteers thank-you job (V-13, R-VP4): at 7:30 AM it starts `VolunteerRecognitionJob`.
 * Health Check's "Schedule all nightly jobs" fix schedules it through
 * `VolunteersNightlyJobProvider`. It stays scheduled while Send Thank-You Tasks is off and does
 * nothing until it is turned on.
 *
 * A separate class from the batch, so a change to the batch deploys while the job is scheduled.
 */
public with sharing class VolunteerRecognitionScheduler implements Schedulable {
	public static final String JOB_NAME = 'BarnCRM Volunteer Thank-Yous';

	@TestVisible
	private static String jobNameInUse = JOB_NAME;

	public void execute(SchedulableContext context) {
		VolunteerRecognitionJob.startMorning();
	}

	/** The job as a step of the nightly run (ADR-0166): half past seven, after the reminders. */
	public static NightlyStep step() {
		return new NightlyStep(
			jobNameInUse,
			System.Label.Volunteers_NightlyJobs_RecognitionName,
			7,
			30,
			new VolunteerRecognitionScheduler()
		);
	}
}
