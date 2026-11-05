/**
 * The read behind the shift reminder run (V-10, R-VU6): every booking due a reminder, whoever
 * runs the job. ADR-0021 (system mode for package owned data).
 *
 * `without sharing` and `SYSTEM_MODE`, because the run is the organization's own morning job,
 * not a user's action: it must reach every booking and every person's email address. Nothing
 * here is shown to a user, and no user input reaches the query.
 *
 * The query is built as text because, in an org that stores people as accounts, it also reads
 * the person account's own name, email and opt out, fields that exist only in such an org
 * (ADR-0013: no Person Account dependency). The Sign-ups panel books a person account on
 * `Account__c` with no Contact (QA-F3).
 */
public without sharing class VolunteerReminderSelector {
	private static final String CONTACT_FIELDS = 'Id, Contact__c, Contact__r.FirstName, Contact__r.Email, Volunteer_Shift__r.Start_Time__c, Volunteer_Shift__r.End_Time__c, Volunteer_Shift__r.Location__c, Volunteer_Shift__r.Volunteer_Job__r.Name';
	private static final String PERSON_ACCOUNT_FIELDS = ', Account__c, Account__r.FirstName, Account__r.PersonEmail'; // detection-only: read only after isPersonAccountOrg found person accounts
	private static final String CONTACT_CAN_BE_EMAILED = '(Contact__c != NULL AND Contact__r.Email != NULL AND Contact__r.HasOptedOutOfEmail = FALSE)';
	private static final String PERSON_ACCOUNT_CAN_BE_EMAILED = ' OR (Contact__c = NULL AND Account__c != NULL AND Account__r.PersonEmail != NULL AND Account__r.PersonHasOptedOutOfEmail = FALSE)'; // detection-only: read only after isPersonAccountOrg found person accounts

	/** The person account email field, read by name: it exists only where people are accounts. */
	public static final String PERSON_EMAIL = 'PersonEmail'; // detection-only: read only from a record the person account query returned

	/**
	 * The bookings due a reminder: not yet reminded, still Signed up or Confirmed, for an open
	 * shift that starts after `now` and before `windowEnd`, for a Contact, or in an org that
	 * stores people as accounts a person account booked with no Contact, with an email address
	 * and email not opted out.
	 */
	public static Database.QueryLocator dueLocator(Datetime now, Datetime windowEnd) {
		return Database.getQueryLocatorWithBinds(
			dueQuery(HouseholdService.isPersonAccountOrg()),
			new Map<String, Object>{ 'now' => now, 'windowEnd' => windowEnd },
			AccessLevel.SYSTEM_MODE
		);
	}

	/** The query text; in an org with person accounts it adds their fields and branch. */
	@TestVisible
	private static String dueQuery(Boolean personAccounts) {
		return 'SELECT ' +
			CONTACT_FIELDS +
			(personAccounts ? PERSON_ACCOUNT_FIELDS : '') +
			' FROM Volunteer_Signup__c WHERE Reminder_Sent_On__c = NULL' +
			' AND Status__c IN (\'Signed up\', \'Confirmed\')' +
			' AND (' +
			CONTACT_CAN_BE_EMAILED +
			(personAccounts ? PERSON_ACCOUNT_CAN_BE_EMAILED : '') +
			')' +
			' AND Volunteer_Shift__r.Status__c = \'Open\'' +
			' AND Volunteer_Shift__r.Start_Time__c > :now' +
			' AND Volunteer_Shift__r.Start_Time__c < :windowEnd' +
			' ORDER BY Volunteer_Shift__r.Start_Time__c';
	}
}
