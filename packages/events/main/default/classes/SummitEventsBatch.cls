/**
 * The morning Summit Events import (EV-10): Summit's registrations, a few per transaction because
 * each one runs Core's matcher and the registration service. A chunk that fails is logged and the
 * rest still run.
 */
public with sharing class SummitEventsBatch implements Database.Batchable<SObject> {
	public static final Integer CHUNK_SIZE = 5;
	private static final String LOG_CONTEXT = 'SummitEventsBatch';

	/** Starts the import; null when Event Management is off or Summit Events is not installed. */
	public static Id startMorning() {
		if (!SummitEventsAdapter.isActive()) {
			return null;
		}
		return AsyncStarter.batch(new SummitEventsBatch(), CHUNK_SIZE, 'SummitEventsBatch');
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return SummitEventsAdapter.locator();
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		try {
			SummitEventsAdapter.importRecords(scope);
		} catch (Exception chunkFailure) {
			ErrorLogger.log(chunkFailure, LOG_CONTEXT);
		}
	}

	public void finish(Database.BatchableContext context) {
		// Nothing follows: the reminder step runs at its own time.
		return;
	}
}
