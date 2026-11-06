/**
 * Queries for session schedules (canonical model 29ZA7). The run reads and locks schedules in
 * system mode: it is the schedule's own bookkeeping, done for whoever saved it or scheduled the
 * nightly run; the sessions it creates are inserted in user mode.
 */
public with sharing class SessionScheduleSelector {
	/** The schedules to run, locked so two runs never create the same day (R-SS3). */
	public static List<Session_Schedule__c> lockForRun(Set<Id> scheduleIds) {
		return [
			SELECT
				Id,
				Name,
				Service__c,
				Service__r.Name,
				Cohort__c,
				Weekdays__c,
				Every_N_Weeks__c,
				Start_Time__c,
				End_Time__c,
				Start_Date__c,
				End_Date__c,
				Active__c,
				Created_Through__c
			FROM Session_Schedule__c
			WHERE Id IN :scheduleIds
			WITH SYSTEM_MODE
			FOR UPDATE
		];
	}

	/** One schedule for its page's panel, or null when the user cannot see it. */
	public static Session_Schedule__c forPreview(Id scheduleId) {
		List<Session_Schedule__c> found = [
			SELECT
				Id,
				Service__c,
				Cohort__c,
				Weekdays__c,
				Every_N_Weeks__c,
				Start_Time__c,
				End_Time__c,
				Start_Date__c,
				End_Date__c,
				Active__c,
				Created_Through__c
			FROM Session_Schedule__c
			WHERE Id = :scheduleId
			WITH USER_MODE
			LIMIT 1
		];
		return found.isEmpty() ? null : found[0];
	}

	/** The nightly run's schedules: every active one that has not ended. */
	public static Database.QueryLocator runnableLocator(Set<Id> onlyIds, Date today) {
		if (onlyIds != null) {
			return Database.getQueryLocator(
				[SELECT Id FROM Session_Schedule__c WHERE Id IN :onlyIds WITH SYSTEM_MODE]
			);
		}
		return Database.getQueryLocator(
			[
				SELECT Id
				FROM Session_Schedule__c
				WHERE Active__c = TRUE AND (End_Date__c = NULL OR End_Date__c >= :today)
				WITH SYSTEM_MODE
			]
		);
	}

	/**
	 * The sessions from `fromDay` on that take a day from these schedules (R-SS2): the
	 * schedules' own, of any status, and those of the same services, not Cancelled, which are
	 * matched to a schedule by service and cohort.
	 */
	public static List<Session__c> sessionsFrom(
		Set<Id> scheduleIds,
		Set<Id> serviceIds,
		Date fromDay
	) {
		return [
			SELECT Id, Session_Schedule__c, Service__c, Cohort__c, Session_Date__c, Status__c
			FROM Session__c
			WHERE
				Session_Date__c >= :fromDay
				AND (Session_Schedule__c IN :scheduleIds
				OR (Service__c IN :serviceIds
				AND Status__c != :SessionAttendance.CANCELLED))
			WITH SYSTEM_MODE
			LIMIT 10000
		];
	}

	/**
	 * R-SS5: the schedule's Scheduled sessions after this day with no service delivery. Read in
	 * system mode, so a delivery the user cannot see still keeps its session; the user deletes
	 * them in user mode.
	 */
	public static List<Session__c> removableAfter(Id scheduleId, Date day) {
		return [
			SELECT Id
			FROM Session__c
			WHERE
				Session_Schedule__c = :scheduleId
				AND Session_Date__c > :day
				AND Status__c = :SessionAttendance.SCHEDULED
				AND Id NOT IN (SELECT Session__c FROM Service_Delivery__c WHERE Session__c != NULL)
			WITH SYSTEM_MODE
			LIMIT 2000
		];
	}
}
