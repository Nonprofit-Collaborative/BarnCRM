/**
 * The reads behind the grant reminder run (F-02, R-GQ3): every open requirement in the reminder
 * window, whoever runs the job, and which of the people to remind are active users.
 * ADR-0021 (system mode for package owned data).
 *
 * `without sharing` and `WITH SYSTEM_MODE`, because the run is the organization's own morning
 * job, not a user's action: it must reach every requirement. Nothing here is shown to a user, and
 * nothing reaches a dynamic query.
 */
public without sharing class GrantReminderSelector {
	/**
	 * The open requirements due on or before `windowEnd` and on or after `oldest`. Whether each
	 * was already reminded for its due date is decided in Apex, since a query cannot compare two
	 * fields.
	 */
	public static Database.QueryLocator dueLocator(Date oldest, Date windowEnd) {
		return Database.getQueryLocator(
			[
				SELECT
					Id,
					Name,
					Type__c,
					Status__c,
					Due_Date__c,
					Reminder_Sent_For__c,
					Assigned_To__c,
					Grant__c,
					Grant__r.Name,
					Grant__r.OwnerId,
					Grant__r.Funder__r.Name
				FROM Grant_Requirement__c
				WHERE
					Status__c IN :GrantRequirementService.OPEN_STATUSES
					AND Due_Date__c >= :oldest
					AND Due_Date__c <= :windowEnd
				WITH SYSTEM_MODE
				ORDER BY Due_Date__c
			]
		);
	}

	/** Which of these record identifiers are active users (a queue or an inactive user is not). */
	public static Set<Id> activeUsers(Set<Id> candidates) {
		Set<Id> active = new Set<Id>();
		if (candidates == null || candidates.isEmpty()) {
			return active;
		}
		for (User person : [
			SELECT Id
			FROM User
			WHERE Id IN :candidates AND IsActive = TRUE
			WITH SYSTEM_MODE
		]) {
			active.add(person.Id);
		}
		return active;
	}
}
