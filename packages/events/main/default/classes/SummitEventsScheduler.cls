/**
 * The Summit Events import step (EV-10): at 7:15 AM, before the event reminders, it starts
 * `SummitEventsBatch`. `EventsNightlyJobProvider` adds it to the nightly run only when Summit
 * Events is installed.
 *
 * A separate class from the batch, so a change to the batch deploys while the job is scheduled.
 */
public with sharing class SummitEventsScheduler implements Schedulable {
	/** The step's key in the nightly run. */
	public static final String JOB_NAME = 'BarnCRM Summit Events Import';

	public void execute(SchedulableContext context) {
		SummitEventsBatch.startMorning();
	}

	/** The import as a step of the nightly run (ADR-0166). */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				System.Label.Events_NightlyJobs_SummitName,
				7,
				15,
				new SummitEventsScheduler()
			)
			.activeWhen(SummitEventsAdapter.isActive());
	}
}
