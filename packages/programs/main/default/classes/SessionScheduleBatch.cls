/**
 * The nightly run of every active session schedule (R-SS3), and the run a large save hands its
 * schedules to. Ten schedules per transaction: a schedule on every weekday creates at most 56
 * sessions to the eight-week horizon, so a chunk stays far inside the DML limits however many
 * schedules the org has.
 *
 * As a Schedulable it is the Programs step of the nightly run (`ProgramsNightlyJobProvider`).
 * One chunk that fails is logged and the rest still run; its schedules are tried again the next
 * night, and the lock each run takes means a retry never creates a day twice.
 */
public with sharing class SessionScheduleBatch implements Database.Batchable<SObject>, Schedulable {
	/** Schedules per transaction. */
	public static final Integer CHUNK_SIZE = 10;
	/** The nightly step's key. */
	public static final String JOB_NAME = 'BarnCRM Session Schedules';

	private static final String LOG_CONTEXT = 'SessionScheduleBatch';

	/** Null for the nightly run of every runnable schedule. */
	private final Set<Id> onlyIds;

	public SessionScheduleBatch() {
		this(null);
	}

	public SessionScheduleBatch(Set<Id> onlyIds) {
		this.onlyIds = onlyIds;
	}

	/** The nightly step (ADR-0166): 3:10 AM, after the Volunteers schedules. */
	public static NightlyStep step() {
		return new NightlyStep(
			JOB_NAME,
			BarnHelp.text('Programs', 'Programs_NightlyJobs_SchedulesName'),
			3,
			10,
			new SessionScheduleBatch()
		);
	}

	/** Starts the nightly run; nothing while Programs is turned off. */
	public void execute(SchedulableContext context) {
		if (!SessionScheduleService.isTurnedOff()) {
			AsyncStarter.batch(new SessionScheduleBatch(), CHUNK_SIZE, 'SessionScheduleBatch');
		}
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return SessionScheduleSelector.runnableLocator(onlyIds, SessionScheduleService.today());
	}

	public void execute(Database.BatchableContext context, List<Session_Schedule__c> scope) {
		try {
			SessionScheduleService.run(new Map<Id, Session_Schedule__c>(scope).keySet());
		} catch (Exception chunkFailure) {
			ErrorLogger.log(chunkFailure, LOG_CONTEXT);
		}
	}

	public void finish(Database.BatchableContext context) {
		return;
	}
}
