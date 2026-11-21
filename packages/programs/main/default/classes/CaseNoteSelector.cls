/**
 * Reads case notes (canonical model 29ZA1). Erasure (R-CN4) must find every note about a person,
 * whoever wrote it, so these reads run in system mode (ADR-0021); what is done with them runs as
 * the user.
 */
public without sharing class CaseNoteSelector {
	/**
	 * Every case note on any enrollment of this person (a contact or a person account). For a
	 * person account, enrollments made on its own contact count too: erasure only reaches an
	 * account that is a person record (`PersonErasure`), so its contacts are that person.
	 */
	public static List<Case_Note__c> selectAllAbout(Id personId) {
		Set<Id> contactIds = contactsOf(personId);
		return [
			SELECT Id
			FROM Case_Note__c
			WHERE Enrollment__r.Contact__c IN :contactIds OR Enrollment__r.Account__c = :personId
			WITH SYSTEM_MODE
			LIMIT 10000
		];
	}

	/**
	 * Every goal on any enrollment of this person (R-GL6), whoever can see it, found as
	 * `selectAllAbout` finds notes. Their steps are details and go with them.
	 */
	public static List<Goal__c> selectGoalsAbout(Id personId) {
		Set<Id> contactIds = contactsOf(personId);
		return [
			SELECT Id
			FROM Goal__c
			WHERE Enrollment__r.Contact__c IN :contactIds OR Enrollment__r.Account__c = :personId
			WITH SYSTEM_MODE
			LIMIT 10000
		];
	}

	/** How many enrollments this person has, any stage, whoever can see them. */
	public static Integer countEnrollmentsOf(Id personId) {
		Set<Id> contactIds = contactsOf(personId);
		return [
			SELECT COUNT()
			FROM Enrollment__c
			WHERE Contact__c IN :contactIds OR Account__c = :personId
			WITH SYSTEM_MODE
		];
	}

	/** The contact ids that are this person: itself, or a person account's own contact. */
	private static Set<Id> contactsOf(Id personId) {
		Set<Id> contactIds = new Set<Id>{ personId };
		if (personId != null && personId.getSObjectType() == Account.SObjectType) {
			for (Contact own : [
				SELECT Id
				FROM Contact
				WHERE AccountId = :personId
				WITH SYSTEM_MODE
				LIMIT 200
			]) {
				contactIds.add(own.Id);
			}
		}
		return contactIds;
	}
}
