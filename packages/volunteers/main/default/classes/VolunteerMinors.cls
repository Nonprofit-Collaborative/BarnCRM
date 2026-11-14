/**
 * Minors and guardian consent (V-15, canonical model R-VU11). With Guardian Consent Required on,
 * a sign-up that is new, or whose person changes, for a Contact younger than Minor Age on the
 * shift's day with no current Guardian consent requirement is saved with Consent Needed checked,
 * and a Guardian consent requirement, Not started, is created for them unless an unfinished one
 * is open. Nothing is refused: the coordinator decides (R-VQ3). A person with no Birthdate, or
 * named by an Account, is not checked.
 *
 * Reads and the requirement insert run in system mode: requirements are kept to coordinators
 * (R-VQ4), and a booking from the portal or a public form must still raise the step.
 */
public inherited sharing class VolunteerMinors {
	public static final String TYPE_CONSENT = 'Guardian consent';
	private static final Set<String> UNFINISHED = new Set<String>{ 'Not started', 'In progress' };
	private static final String LOG_CONTEXT = 'VolunteerMinors.requestConsent';

	/**
	 * The guardian a public form named for a person (record key `guardian`), by the person's
	 * Contact Id; read when the consent requirement is created in the same transaction.
	 */
	public static Map<Id, Id> guardianByPerson = new Map<Id, Id>();

	/** Before save: checks Consent Needed on the sign-ups of minors without current consent. */
	public static void flag(
		List<Volunteer_Signup__c> signups,
		Map<Id, Volunteer_Signup__c> previousById
	) {
		if (!VolunteerSettings.minorConsentRequired()) {
			return;
		}
		List<Volunteer_Signup__c> checked = new List<Volunteer_Signup__c>();
		Set<Id> contactIds = new Set<Id>();
		Set<Id> shiftIds = new Set<Id>();
		for (Volunteer_Signup__c signup : signups) {
			Volunteer_Signup__c previous = previousById == null
				? null
				: previousById.get(signup.Id);
			if (
				signup.Contact__c != null &&
				(previous == null ||
				previous.Contact__c != signup.Contact__c)
			) {
				checked.add(signup);
				contactIds.add(signup.Contact__c);
				shiftIds.add(signup.Volunteer_Shift__c);
			}
		}
		if (checked.isEmpty()) {
			return;
		}
		Map<Id, Contact> people = new Map<Id, Contact>(
			[
				SELECT Id, Birthdate
				FROM Contact
				WHERE Id IN :contactIds AND Birthdate != NULL
				WITH SYSTEM_MODE
			]
		);
		if (people.isEmpty()) {
			return;
		}
		Map<Id, Volunteer_Shift__c> shifts = new Map<Id, Volunteer_Shift__c>(
			[
				SELECT Id, Start_Time__c
				FROM Volunteer_Shift__c
				WHERE Id IN :shiftIds
				WITH SYSTEM_MODE
			]
		);
		Set<Id> consented = withCurrentConsent(people.keySet());
		Integer minorAge = VolunteerSettings.minorAge();
		for (Volunteer_Signup__c signup : checked) {
			Contact person = people.get(signup.Contact__c);
			Volunteer_Shift__c shift = shifts.get(signup.Volunteer_Shift__c);
			Date onTheDay = shift == null ||
				shift.Start_Time__c == null
				? Date.today()
				: shift.Start_Time__c.date();
			if (
				person != null &&
				!consented.contains(person.Id) &&
				person.Birthdate.addYears(minorAge) > onTheDay
			) {
				signup.Consent_Needed__c = true;
			}
		}
	}

	/**
	 * After save: a Guardian consent requirement, Not started, for each flagged person whose sign-up
	 * is new or changed person, unless an unfinished one is open. Returns how many were created.
	 */
	public static Integer requestConsent(
		List<Volunteer_Signup__c> signups,
		Map<Id, Volunteer_Signup__c> previousById
	) {
		Set<Id> contactIds = new Set<Id>();
		for (Volunteer_Signup__c signup : signups) {
			Volunteer_Signup__c previous = previousById == null
				? null
				: previousById.get(signup.Id);
			if (
				signup.Consent_Needed__c == true &&
				signup.Contact__c != null &&
				(previous == null ||
				previous.Contact__c != signup.Contact__c)
			) {
				contactIds.add(signup.Contact__c);
			}
		}
		if (contactIds.isEmpty()) {
			return 0;
		}
		for (Volunteer_Requirement__c open : [
			SELECT Contact__c
			FROM Volunteer_Requirement__c
			WHERE Contact__c IN :contactIds AND Type__c = :TYPE_CONSENT AND Status__c IN :UNFINISHED
			WITH SYSTEM_MODE
		]) {
			contactIds.remove(open.Contact__c);
		}
		List<Volunteer_Requirement__c> steps = new List<Volunteer_Requirement__c>();
		for (Id contactId : contactIds) {
			steps.add(
				new Volunteer_Requirement__c(
					Contact__c = contactId,
					Type__c = TYPE_CONSENT,
					Status__c = 'Not started',
					Guardian__c = guardianByPerson.get(contactId)
				)
			);
		}
		Integer made = 0;
		List<Database.SaveResult> results = Database.insert(steps, false, AccessLevel.SYSTEM_MODE);
		for (Database.SaveResult result : results) {
			made += result.isSuccess() ? 1 : 0;
		}
		ErrorLogger.logFailures(results, null, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
		return made;
	}

	private static Set<Id> withCurrentConsent(Set<Id> contactIds) {
		Set<Id> found = new Set<Id>();
		for (Volunteer_Requirement__c current : [
			SELECT Contact__c
			FROM Volunteer_Requirement__c
			WHERE Contact__c IN :contactIds AND Type__c = :TYPE_CONSENT AND Is_Current__c = TRUE
			WITH SYSTEM_MODE
		]) {
			found.add(current.Contact__c);
		}
		return found;
	}
}
