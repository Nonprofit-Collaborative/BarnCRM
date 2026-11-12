/**
 * The Event Management morning step (EV-14): at 7:30 AM it starts `EventEmailBatch`, which sends
 * reminders and follow-ups and marks No-Show as Events Settings ask. It stays in the nightly run
 * while every setting is off and does nothing then, so turning a setting on needs no other step.
 *
 * A separate class from the batch, so a change to the batch deploys while the job is scheduled.
 */
public with sharing class EventEmailScheduler implements Schedulable {
	/** The step's key in the nightly run. */
	public static final String JOB_NAME = 'BarnCRM Event Emails';

	public void execute(SchedulableContext context) {
		EventEmailBatch.startMorning();
		// Sweeps up Unpaid Pending Payment registrations whose checkout job never ran.
		if (EventsSettings.onlinePayments()) {
			EventPayments.queueCheckouts();
		}
	}

	/** The job as a step of the nightly run (ADR-0166), before the working day. */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				System.Label.Events_NightlyJobs_EmailsName,
				7,
				30,
				new EventEmailScheduler()
			)
			.activeWhen(
				EventEmailService.nextActive(null) != null || EventsSettings.onlinePayments()
			);
	}
}
