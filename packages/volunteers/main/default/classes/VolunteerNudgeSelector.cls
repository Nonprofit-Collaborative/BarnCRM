/**
 * The reads behind the "still need you" run (V-10b): the shifts due a nudge and the people to
 * send it to, whoever runs the job. ADR-0021 (system mode for package owned data).
 *
 * `without sharing` and `SYSTEM_MODE`, because the run is the organization's own morning job,
 * not a user's action: it must reach every shift and every volunteer's email address. Nothing
 * here is shown to a user, and no user input reaches a query.
 */
public without sharing class VolunteerNudgeSelector {
	/**
	 * The shifts due a nudge: open, not yet nudged, still short of volunteers, starting after
	 * `now` and before `windowEnd`.
	 */
	public static Database.QueryLocator dueLocator(Datetime now, Datetime windowEnd) {
		return Database.getQueryLocatorWithBinds(
			'SELECT Id, Start_Time__c, End_Time__c, Location__c, Volunteer_Job__c, Volunteer_Job__r.Name, Slots_Remaining__c' +
				' FROM Volunteer_Shift__c WHERE Nudge_Sent_On__c = NULL AND Status__c = \'Open\'' +
				' AND Slots_Remaining__c > 0 AND Start_Time__c > :now AND Start_Time__c < :windowEnd' +
				' ORDER BY Start_Time__c',
			new Map<String, Object>{ 'now' => now, 'windowEnd' => windowEnd },
			AccessLevel.SYSTEM_MODE
		);
	}

	/**
	 * Active volunteers with approved hours on the shift's job, an email address and email not
	 * opted out, with no sign-up of any status on this shift, the most hours first, at most `max`.
	 */
	public static List<Contact> candidates(Id shiftId, Id jobId, Integer max) {
		return [
			SELECT Id, FirstName, Email
			FROM Contact
			WHERE
				Volunteer_Status__c = 'Active'
				AND Email != NULL
				AND HasOptedOutOfEmail = FALSE
				AND Id IN (
					SELECT Contact__c
					FROM Volunteer_Hours__c
					WHERE Volunteer_Job__c = :jobId AND Status__c = 'Approved'
				)
				AND Id NOT IN (
					SELECT Contact__c
					FROM Volunteer_Signup__c
					WHERE Volunteer_Shift__c = :shiftId AND Contact__c != NULL
				)
			WITH SYSTEM_MODE
			ORDER BY Volunteer_Hours_Total__c DESC NULLS LAST, Name ASC
			LIMIT :max
		];
	}
}
