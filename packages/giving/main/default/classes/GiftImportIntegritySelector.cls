/**
 * The reads a gift import makes about what already exists in the org, whoever is importing
 * (R-DM1, R-GI9). ADR-0021 (system mode for package owned data) and ADR-0052.
 *
 * `without sharing` and `WITH SYSTEM_MODE`, because each answer is a fact about the org, not
 * about what the importing user may see: a gift already loaded under this external ID that the
 * user cannot see must still stop a second copy (the platform refuses the duplicate anyway, and
 * the row would fail with a message naming nothing), and a receipt the user cannot see must still
 * keep its gift when an import is undone. What the importing user can learn from them is
 * limited to what the platform's own duplicate refusal would tell: a row that repeats a hidden
 * gift's external ID is Matched and its row carries that gift's ID, and an undo that keeps a
 * gift says so. No field of a hidden record is shown. The inputs are values from the staged rows
 * or identifiers the import itself made; nothing reaches a dynamic query.
 */
public without sharing class GiftImportIntegritySelector {
	/** The gifts already carrying these external identifiers (R-DM1). */
	public static List<Gift__c> selectByExternalIds(Set<String> externalIds) {
		return [
			SELECT Id, External_Id__c, Created_By_Import_Batch__c
			FROM Gift__c
			WHERE External_Id__c IN :externalIds
			WITH SYSTEM_MODE
		];
	}

	// The undo's questions (R-GI9): a receipt the undoing user cannot see must still keep its
	// gift, and a gift that stays must still keep its donor.

	/**
	 * The gifts with their receipt number, whether any receipt names them, and what the posting
	 * lock reads.
	 */
	public static List<Gift__c> selectForUndo(Set<Id> giftIds) {
		return [
			SELECT
				Id,
				Receipt_Number__c,
				Donor_Contact__c,
				Donor_Account__c,
				Gift_Date__c,
				Status__c,
				Type__c,
				Accounting_Posted_At__c,
				(SELECT Id FROM Receipts__r LIMIT 1)
			FROM Gift__c
			WHERE Id IN :giftIds
			WITH SYSTEM_MODE
		];
	}

	/** The issued year-end statements of these donors for these years. */
	public static List<Receipt__c> selectIssuedStatements(Set<Id> donorIds, Set<Integer> years) {
		return [
			SELECT Donor_Contact__c, Donor_Account__c, Statement_Year__c
			FROM Receipt__c
			WHERE
				Type__c = 'Consolidated statement'
				AND Status__c = 'Issued'
				AND Statement_Year__c IN :years
				AND (Donor_Contact__c IN :donorIds
				OR Donor_Account__c IN :donorIds)
			WITH SYSTEM_MODE
		];
	}

	/** The gifts this import made that still exist and name any of these records. */
	public static List<Gift__c> selectImportedGiftsNaming(Id batchId, Set<Id> recordIds) {
		return [
			SELECT Donor_Contact__c, Donor_Account__c, Household__c
			FROM Gift__c
			WHERE
				Created_By_Import_Batch__c = :batchId
				AND (Donor_Contact__c IN :recordIds
				OR Donor_Account__c IN :recordIds
				OR Household__c IN :recordIds)
			WITH SYSTEM_MODE
		];
	}

	/** The soft credits on gifts this import made that credit any of these records. */
	public static List<Soft_Credit__c> selectImportedCreditsNaming(Id batchId, Set<Id> recordIds) {
		return [
			SELECT Contact__c, Account__c
			FROM Soft_Credit__c
			WHERE
				Gift__r.Created_By_Import_Batch__c = :batchId
				AND (Contact__c IN :recordIds
				OR Account__c IN :recordIds)
			WITH SYSTEM_MODE
		];
	}
}
