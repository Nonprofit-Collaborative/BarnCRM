/**
 * The lookups a gift import makes within the importing user's sharing: funds and appeals (R-GI3,
 * R-GI4), the open installments a gift may pay (R-DM2) and the credits on the gifts it just
 * made. What already exists in the org is read by GiftImportIntegritySelector.
 */
public with sharing class GiftImportSelector {
	/**
	 * The funds a file could mean by these words: by identifier, by name or by accounting code.
	 * Inactive funds are included, because a migration names funds that have closed (R-GI4).
	 * Read in the user's own mode: a fund the user cannot see is one they cannot allocate to.
	 */
	public static List<Fund__c> selectFundsNamed(Set<String> words) {
		Set<Id> ids = idsAmong(words);
		return [
			SELECT Id, Name, Accounting_Code__c
			FROM Fund__c
			WHERE Id IN :ids OR Name IN :words OR Accounting_Code__c IN :words
			WITH USER_MODE
			LIMIT 2000
		];
	}

	/** The appeals a file could mean by these words: by identifier or by name. */
	public static List<Appeal__c> selectAppealsNamed(Set<String> words) {
		Set<Id> ids = idsAmong(words);
		return [
			SELECT Id, Name
			FROM Appeal__c
			WHERE Id IN :ids OR Name IN :words
			WITH USER_MODE
			LIMIT 2000
		];
	}

	/**
	 * The soft credits already on these gifts, the automatic household ones included. The
	 * gifts are the ones this import just made and soft credits share their gift's access, so
	 * the importing user sees every one: the read runs in user mode (D-13).
	 */
	public static List<Soft_Credit__c> selectCreditsOnGifts(Set<Id> giftIds) {
		return [
			SELECT Id, Gift__c, Contact__c, Account__c, Role__c
			FROM Soft_Credit__c
			WHERE Gift__c IN :giftIds
			WITH USER_MODE
		];
	}

	/**
	 * The open installments of these donors or households due between these dates (R-DM2).
	 * Read in the user's own mode: a pledge the user cannot see is not one they may pay.
	 */
	public static List<Installment__c> selectOpenInstallments(
		Set<Id> donorIds,
		Set<Id> householdIds,
		Date earliest,
		Date latest
	) {
		return [
			SELECT
				Id,
				Name,
				Due_Date__c,
				Expected_Amount__c,
				Commitment__c,
				Commitment__r.Donor_Contact__c,
				Commitment__r.Donor_Account__c,
				Commitment__r.Household__c
			FROM Installment__c
			WHERE
				Status__c IN ('Scheduled', 'Overdue', 'Partially paid')
				AND Commitment__r.Status__c IN ('Active', 'Paused')
				AND Due_Date__c >= :earliest
				AND Due_Date__c <= :latest
				AND (Commitment__r.Donor_Contact__c IN :donorIds
				OR Commitment__r.Donor_Account__c IN :donorIds
				OR Commitment__r.Household__c IN :householdIds)
			WITH USER_MODE
			ORDER BY Due_Date__c, Name
			LIMIT 5000
		];
	}

	/** The words that are record identifiers; a word that is not one is simply not an id. */
	private static Set<Id> idsAmong(Set<String> words) {
		Set<Id> ids = new Set<Id>();
		for (String word : words) {
			if (word != null && (word.length() == 15 || word.length() == 18)) {
				try {
					ids.add(Id.valueOf(word));
				} catch (Exception notAnId) {
					continue;
				}
			}
		}
		return ids;
	}
}
