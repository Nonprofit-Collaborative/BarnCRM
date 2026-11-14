/**
 * The morning "still need you" run (V-10b): emails the people for every unfilled shift due a
 * nudge, 4 shifts per transaction so one email call (at most 25 people per shift) stays inside
 * the platform's per call recipient limit. One chunk that fails is logged and the rest still run.
 */
public with sharing class VolunteerNudgeBatch implements Database.Batchable<SObject> {
	/** Shifts per transaction: 4 shifts of at most 25 people is one email call of 100. */
	public static final Integer CHUNK_SIZE = 4;

	private static final String LOG_CONTEXT = 'VolunteerNudgeBatch';

	/** Starts the run; null when the module or the nudges setting is off. */
	public static Id startMorning() {
		if (!VolunteerNudgeService.isActive()) {
			return null;
		}
		return AsyncStarter.batch(new VolunteerNudgeBatch(), CHUNK_SIZE, 'VolunteerNudgeBatch');
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return VolunteerNudgeSelector.dueLocator(
			ShiftScheduleService.now(),
			VolunteerReminderService.windowEnd(VolunteerSettings.nudgeLeadDays())
		);
	}

	public void execute(Database.BatchableContext context, List<Volunteer_Shift__c> scope) {
		try {
			VolunteerNudgeService.nudge(scope);
		} catch (Exception chunkFailure) {
			ErrorLogger.log(chunkFailure, LOG_CONTEXT);
		}
	}

	public void finish(Database.BatchableContext context) {
		return;
	}
}
