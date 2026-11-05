/**
 * Every query against Tribute, and the one Contact query the tribute rules need (plan Section 9.3).
 *
 * The deceased test reads in system mode. Whether a memorial would notify the person it
 * remembers cannot depend on whether the person saving the gift happens to have access to the
 * Deceased field: a rule that quietly stops applying is worse than no rule.
 */
public with sharing class TributeSelector {
	public static List<Tribute__c> selectForGifts(Set<Id> giftIds) {
		if (giftIds == null || giftIds.isEmpty()) {
			return new List<Tribute__c>();
		}
		return [
			SELECT
				Id,
				Name,
				Gift__c,
				Type__c,
				Honoree_Name__c,
				Honoree_Contact__c,
				Honoree_Contact__r.Name,
				Honoree_Account__c,
				Honoree_Account__r.Name,
				Notification_Recipient_Contact__c,
				Notification_Recipient_Contact__r.Name,
				Notification_Recipient_Account__c,
				Notification_Recipient_Account__r.Name,
				Notification_Recipient_Name__c,
				Notification_Sent__c,
				Notification_Sent_Date__c,
				Message__c
			FROM Tribute__c
			WHERE Gift__c IN :giftIds
			WITH USER_MODE
			ORDER BY Name
			LIMIT 1000
		];
	}

	public static List<Tribute__c> selectByIds(Set<Id> tributeIds) {
		if (tributeIds == null || tributeIds.isEmpty()) {
			return new List<Tribute__c>();
		}
		return [
			SELECT Id, Gift__c, Type__c, Notification_Sent__c, Notification_Sent_Date__c
			FROM Tribute__c
			WHERE Id IN :tributeIds
			WITH USER_MODE
			LIMIT 200
		];
	}

	/**
	 * The gifts among these that already carry a tribute, so that a second one is refused
	 * (R-TR1). Read in system mode for the same reason the deceased test is.
	 */
	public static List<Tribute__c> selectExistingForGifts(Set<Id> giftIds) {
		if (giftIds == null || giftIds.isEmpty()) {
			return new List<Tribute__c>();
		}
		return [
			SELECT Id, Gift__c
			FROM Tribute__c
			WHERE Gift__c IN :giftIds
			WITH SYSTEM_MODE
			LIMIT 10000
		];
	}

	/**
	 * Which of these people, stored as accounts, are recorded as having died. Read in system
	 * mode for the same reason as the contact query below.
	 */
	public static Set<Id> selectDeceasedAccountIds(Set<Id> accountIds) {
		Set<Id> deceased = new Set<Id>();
		if (accountIds == null || accountIds.isEmpty()) {
			return deceased;
		}
		for (Account person : [
			SELECT Id
			FROM Account
			WHERE Id IN :accountIds AND Deceased__c = TRUE
			WITH SYSTEM_MODE
			LIMIT 10000
		]) {
			deceased.add(person.Id);
		}
		return deceased;
	}

	/**
	 * Which of these people are recorded as having died.
	 */
	public static Set<Id> selectDeceasedContactIds(Set<Id> contactIds) {
		Set<Id> deceased = new Set<Id>();
		if (contactIds == null || contactIds.isEmpty()) {
			return deceased;
		}
		for (Contact person : [
			SELECT Id
			FROM Contact
			WHERE Id IN :contactIds AND Deceased__c = TRUE
			WITH SYSTEM_MODE
			LIMIT 10000
		]) {
			deceased.add(person.Id);
		}
		return deceased;
	}
}
