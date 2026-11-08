/**
 * The backfill (ADR-0176 contact point sync module, decision 10): syncs every person in the org,
 * 200 at a time, exactly as a save would, then records when it finished and what it did on the
 * module's settings for the Contact Point Sync page.
 *
 * Without sharing: an org job over every person, started only from the page by someone holding
 * Contact Point Sync Admin and Manage BarnCRM Settings.
 */
public without sharing class ContactPointBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
	public static final String CLASS_NAME = 'ContactPointBackfillBatch';
	@TestVisible
	private static final Integer CHUNK_SIZE = 200;

	private final ContactPointSyncService.Result totals = new ContactPointSyncService.Result();

	/** Starts the backfill and returns its job ID. */
	public static Id start() {
		return Database.executeBatch(new ContactPointBackfillBatch(), CHUNK_SIZE);
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return Database.getQueryLocator(
			'SELECT Id FROM Contact ORDER BY Id',
			AccessLevel.SYSTEM_MODE
		);
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		totals.add(ContactPointSyncService.syncPeople(new Map<Id, SObject>(scope).keySet(), null));
	}

	public void finish(Database.BatchableContext context) {
		record(totals);
	}

	/**
	 * Writes the last backfill's time and summary. Only those two keys are saved, so the
	 * switches keep what they read, also on an org that never saved them (ADR-0035).
	 */
	@TestVisible
	private static void record(ContactPointSyncService.Result done) {
		try {
			OrgSettingsSystemWriter.save(
				Contact_Point_Sync_Settings__c.SObjectType,
				new Map<Schema.SObjectField, Object>{
					Contact_Point_Sync_Settings__c.Last_Backfill__c => System.now(),
					Contact_Point_Sync_Settings__c.Last_Backfill_Summary__c => BarnHelp.text(
						'ContactPoints',
						'ContactPoints_Backfill_Summary',
						new List<Object>{ done.created, done.updated, done.deleted, done.failed }
					)
				}
			);
		} catch (Exception unexpected) {
			ErrorLogger.log(unexpected, ContactPointSyncService.CONTEXT);
		}
	}
}
