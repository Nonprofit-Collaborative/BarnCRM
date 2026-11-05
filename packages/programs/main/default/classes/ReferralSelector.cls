/**
 * Reads referrals (canonical model 29ZA2). Erasure (R-RF4) must find every referral about a
 * person, whoever owns it, so this read runs in system mode (ADR-0021); what is done with the
 * result runs as the user.
 */
public without sharing class ReferralSelector {
	/**
	 * Every referral about this person (a contact or a person account). For a person account,
	 * referrals made on its own contact count too: erasure only reaches an account that is a
	 * person record, so its contacts are that person.
	 */
	public static List<Referral__c> selectAllAbout(Id personId) {
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
		return [
			SELECT Id
			FROM Referral__c
			WHERE Contact__c IN :contactIds OR Account__c = :personId
			WITH SYSTEM_MODE
			LIMIT 10000
		];
	}
}
