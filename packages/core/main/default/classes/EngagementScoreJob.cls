/**
 * The nightly engagement score step (C-64, canonical model R-ES1 and R-ES5, ADR-0166
 * nightly-job-dispatcher): at 2:30, while scoring is on, every person is scored and the people
 * whose score changed are saved with today as Scored On. A person whose score is unchanged is
 * not written, so the run does not touch every person's Last Modified date each night.
 *
 * System mode (ADR-0021): the score is a fact about the organization, written by package upkeep
 * into two fields no user edits. A chunk whose signals cannot answer is logged and skipped
 * (R-ES4); a person whose save is refused is logged and the rest are saved.
 */
public with sharing class EngagementScoreJob implements Database.Batchable<SObject>, Schedulable {
	/** The step's key. */
	public static final String JOB_NAME = 'BarnCRM Engagement Score';

	/** People per chunk: one query per installed signal and one save. */
	public static final Integer CHUNK_SIZE = 200;

	private static final String LOG_CONTEXT = 'EngagementScoreJob';

	/** The score as a step of the nightly run, half past two, active while scoring is on. */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				Schema.SObjectType.Contact.fields.Engagement_Score__c.getLabel(),
				2,
				30,
				new EngagementScoreJob()
			)
			.activeWhen(EngagementScore.isOn());
	}

	public void execute(SchedulableContext context) {
		Database.executeBatch(new EngagementScoreJob(), CHUNK_SIZE);
	}

	/** Every person, or none while scoring is off. */
	public Database.QueryLocator start(Database.BatchableContext context) {
		if (!EngagementScore.isOn()) {
			return Database.getQueryLocator(
				[SELECT Id FROM Contact WHERE Id = NULL WITH SYSTEM_MODE]
			);
		}
		return Database.getQueryLocator(
			[SELECT Id, LastActivityDate, Engagement_Score__c FROM Contact WITH SYSTEM_MODE]
		);
	}

	public void execute(Database.BatchableContext context, List<Contact> scope) {
		try {
			save(scope, Date.today());
		} catch (Exception chunkFailure) {
			ErrorLogger.log(chunkFailure, LOG_CONTEXT);
		}
	}

	public void finish(Database.BatchableContext context) {
		return;
	}

	/** Scores these people and saves the changed ones; returns how many were saved. */
	@TestVisible
	private static Integer save(List<Contact> people, Date today) {
		Map<Id, Integer> scores = new EngagementScore().scores(people, today);
		List<Contact> changed = new List<Contact>();
		for (Contact person : people) {
			Integer score = scores.get(person.Id);
			if (
				person.Engagement_Score__c == null ||
				person.Engagement_Score__c.intValue() != score
			) {
				changed.add(
					new Contact(
						Id = person.Id,
						Engagement_Score__c = score,
						Engagement_Scored_On__c = today
					)
				);
			}
		}
		List<String> failures = new List<String>();
		Integer saved = 0;
		List<Database.SaveResult> results = Database.update(
			changed,
			false,
			AccessLevel.SYSTEM_MODE
		);
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				saved++;
			} else {
				failures.add(changed[i].Id + ': ' + results[i].getErrors()[0].getMessage());
			}
		}
		if (!failures.isEmpty()) {
			ErrorLogger.logMessages(failures, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
		}
		return saved;
	}
}
