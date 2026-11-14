/**
 * The morning event email run (EV-14): reminders, then follow-ups, then No-Show, each phase a
 * batch of 100 attendees per transaction (one email call per chunk) that starts the next active
 * phase when it finishes. A chunk that fails is logged and the rest still run.
 */
public with sharing class EventEmailBatch implements Database.Batchable<SObject> {
	public static final Integer CHUNK_SIZE = 100;
	private static final String LOG_CONTEXT = 'EventEmailBatch';
	/** A test calling `finish` itself (outside a running batch) sets this to see it chain. */
	@TestVisible
	private static Boolean chainInTests = false;

	private final String phase;

	public EventEmailBatch(String phase) {
		this.phase = phase;
	}

	/** Starts the first active phase; null when the module or every setting is off. */
	public static Id startMorning() {
		return startPhase(EventEmailService.nextActive(null));
	}

	private static Id startPhase(String phase) {
		if (phase == null) {
			return null;
		}
		return AsyncStarter.batch(new EventEmailBatch(phase), CHUNK_SIZE, 'EventEmailBatch');
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return EventEmailService.locator(phase);
	}

	public void execute(Database.BatchableContext context, List<Event_Attendee__c> scope) {
		try {
			EventEmailService.run(phase, scope);
		} catch (Exception chunkFailure) {
			ErrorLogger.log(chunkFailure, LOG_CONTEXT);
		}
	}

	public void finish(Database.BatchableContext context) {
		if (Test.isRunningTest() && !chainInTests) {
			// A test cannot start a batch from a batch's finish.
			return;
		}
		try {
			startPhase(EventEmailService.nextActive(phase));
		} catch (Exception cannotChain) {
			ErrorLogger.log(cannotChain, LOG_CONTEXT);
		}
	}
}
