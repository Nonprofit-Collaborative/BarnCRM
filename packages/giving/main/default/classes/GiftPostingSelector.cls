/**
 * The reads behind the posting and closed period lock (G-20, ADR-0053).
 *
 * `selectLockStateByIds` runs in system mode for field and object access and keeps the running
 * user's sharing (the class is `with sharing`): it decides whether a save is refused, and a rule
 * that holds only for users granted read on Posted to Accounting is not a rule. It returns no
 * value to anyone; the lock reads it and refuses or allows (ADR-0021, reads that compute a
 * package decision). A person who can save an allocation can see its gift, because an
 * allocation's access comes from its gift.
 *
 * `selectForPosting` runs in user mode: the gifts it returns are the ones the user marks or
 * unposts, so a gift the user cannot see is never touched.
 *
 * `selectSwitchableAutomationNames` reads the shipped automation registry, which is package
 * metadata holding no organization data, as `AutomationRegistrySelector` does.
 *
 * The Health Check finding for unposted gifts in a closed period (G-20 follow-up) reads through
 * `HealthCheckGivingSelector` instead, `without sharing`: `WITH SYSTEM_MODE` here only lifts
 * field and object security, not sharing (the class keyword is what decides that), and every
 * method in this class deliberately keeps the running user's sharing (`with sharing`) because
 * each one answers a question about what that user may lock, save or post. A report on the
 * whole org's posting state is a different question, so it lives in its own selector rather
 * than bending this one's sharing for a single pair of methods.
 */
public with sharing class GiftPostingSelector {
	/**
	 * Gifts that name any of these records as donor or original and could be locked: posted, or
	 * dated on or before the close date. The lock decides which are. System mode for the reason
	 * above: a delete guard that holds only for users who can see the gift is not a guard.
	 */
	public static List<Gift__c> selectPossiblyLockedNaming(Set<Id> recordIds, Date closed) {
		// With no period closed, no date qualifies.
		Date latest = closed == null ? Date.newInstance(1700, 1, 1) : closed;
		return [
			SELECT
				Id,
				Status__c,
				Type__c,
				Gift_Date__c,
				Accounting_Posted_At__c,
				Donor_Contact__c,
				Donor_Contact__r.AccountId,
				Donor_Account__c,
				Original_Gift__c
			FROM Gift__c
			WHERE
				(Donor_Contact__c IN :recordIds
				OR Donor_Contact__r.AccountId IN :recordIds
				OR Donor_Account__c IN :recordIds
				OR Original_Gift__c IN :recordIds)
				AND (Accounting_Posted_At__c != NULL
				OR Gift_Date__c <= :latest)
			WITH SYSTEM_MODE
		];
	}

	public static List<Gift__c> selectLockStateByIds(Set<Id> giftIds) {
		return [
			SELECT Id, Status__c, Type__c, Gift_Date__c, Accounting_Posted_At__c
			FROM Gift__c
			WHERE Id IN :giftIds
			WITH SYSTEM_MODE
		];
	}

	public static List<Gift__c> selectForPosting(Set<Id> giftIds) {
		return [
			SELECT
				Id,
				Name,
				Status__c,
				Type__c,
				Gift_Date__c,
				Accounting_Posted_At__c,
				Accounting_Posted_By__r.Name
			FROM Gift__c
			WHERE Id IN :giftIds
			WITH USER_MODE
		];
	}

	public static List<String> selectSwitchableAutomationNames(String objectName) {
		List<String> names = new List<String>();
		for (Automation_Registry__mdt entry : [
			SELECT DeveloperName
			FROM Automation_Registry__mdt
			WHERE Object_Name__c = :objectName AND Always_Runs__c = FALSE
			WITH SYSTEM_MODE
		]) {
			names.add(entry.DeveloperName);
		}
		return names;
	}
}
