/**
 * All SOQL against the receipting objects.
 *
 * Reads that reach a person run `WITH USER_MODE`, so a user only sees the receipts their sharing
 * lets them see (plan Section 4.13). The reads the year end run depends on say `WITH SYSTEM_MODE`
 * instead, out loud rather than by omission: `numbersInSeries`, so that
 * `ReceiptNumberSequence.reconcile` can account for a consumed number even when the receipt that
 * consumed it belongs to a donor the running user cannot see, and `giftsForReceipting`,
 * `donorLocator`, `issuedKeys` and `activeTemplate`, which the batch uses to build documents for
 * the whole org. ADR-0021 allows a read whose only purpose is to compute a package owned value to
 * run in system mode alongside the write it feeds, provided the class says which reads are which.
 * These are those. Record level sharing still applies to every one of them: this class is
 * `with sharing`, and `WITH SYSTEM_MODE` waives object and field permissions, not who may see
 * which record.
 */
public with sharing class ReceiptSelector {
	private static final String STATUS_RECEIVED = 'Received';

	/** One receipt, everything about it, for a screen. */
	public static Receipt__c byId(Id receiptId) {
		List<Receipt__c> receipts = [
			SELECT
				Id,
				Name,
				Receipt_Number__c,
				Type__c,
				Status__c,
				Statement_Year__c,
				Gift__c,
				Donor_Contact__c,
				Donor_Account__c,
				Household__c,
				Total_Amount__c,
				Issue_Date__c,
				Content_Document_Id__c,
				Void_Reason__c,
				Voided_On__c,
				Replaces__c,
				Replaced_By__c,
				Series_Key__c,
				Donor_Year_Key__c
			FROM Receipt__c
			WHERE Id = :receiptId
			WITH USER_MODE
			LIMIT 1
		];
		return receipts.isEmpty() ? null : receipts[0];
	}

	/** Every receipt raised against one gift, newest first, so a screen can show the history. */
	public static List<Receipt__c> forGift(Id giftId) {
		return [
			SELECT
				Id,
				Receipt_Number__c,
				Type__c,
				Status__c,
				Statement_Year__c,
				Total_Amount__c,
				Issue_Date__c,
				Content_Document_Id__c,
				Void_Reason__c,
				Voided_On__c,
				Replaces__c,
				Replaced_By__c
			FROM Receipt__c
			WHERE Gift__c = :giftId
			WITH USER_MODE
			ORDER BY CreatedDate DESC
		];
	}

	/**
	 * The receipt numbers a series has actually produced. Upkeep, not display: system mode, for
	 * the reason in the class comment.
	 */
	public static List<Receipt__c> numbersInSeries(String seriesKey) {
		return [
			SELECT Id, Receipt_Number__c
			FROM Receipt__c
			WHERE Series_Key__c = :seriesKey
			WITH SYSTEM_MODE
		];
	}

	/**
	 * The gifts a statement covers for one set of donor accounts, which are households and
	 * organizations: everything in the statement year that a receipt can be raised against. A
	 * household's gifts are found through the household reference the package derives (R-G2), so a
	 * statement covers what the household gave rather than what one member of it gave. Upkeep, not display: the batch composes documents for donors
	 * the running user has no reason to be able to see.
	 *
	 * Pending and Cancelled gifts are left out because the money has not arrived, and a receipt
	 * says it has.
	 * Refunded and written off gifts are kept, because a statement that silently dropped them
	 * would not reconcile with what the donor believes they gave; R-RC8 puts the status on the
	 * line instead.
	 */
	public static List<Gift__c> giftsForReceipting(Set<Id> donorIds, Integer statementYear) {
		Date firstDay = Date.newInstance(statementYear, 1, 1);
		Date firstDayAfter = Date.newInstance(statementYear + 1, 1, 1);
		return [
			SELECT
				Id,
				Name,
				Donor_Contact__c,
				Donor_Account__c,
				Household__c,
				Gift_Date__c,
				Amount__c,
				Type__c,
				Status__c,
				Receipt_Number__c,
				In_Kind_Description__c,
				Fair_Market_Value__c,
				Benefit_Description__c,
				Benefit_Value__c,
				Intangible_Religious_Benefits__c,
				Brand__c
			FROM Gift__c
			WHERE
				Gift_Date__c >= :firstDay
				AND Gift_Date__c < :firstDayAfter
				AND Status__c NOT IN ('Pending', 'Cancelled')
				AND (Household__c IN :donorIds
				OR Donor_Account__c IN :donorIds)
			WITH SYSTEM_MODE
			ORDER BY Gift_Date__c ASC
		];
	}

	/** One gift, with everything the receipt language reads. */
	public static Gift__c giftForReceipting(Id giftId) {
		List<Gift__c> gifts = [
			SELECT
				Id,
				Name,
				Donor_Contact__c,
				Donor_Account__c,
				Household__c,
				Gift_Date__c,
				Amount__c,
				Type__c,
				Status__c,
				Receipt_Number__c,
				In_Kind_Description__c,
				Fair_Market_Value__c,
				Benefit_Description__c,
				Benefit_Value__c,
				Intangible_Religious_Benefits__c,
				Brand__c
			FROM Gift__c
			WHERE Id = :giftId
			WITH USER_MODE
			LIMIT 1
		];
		return gifts.isEmpty() ? null : gifts[0];
	}

	/**
	 * The donors a year end run covers: every household or organization account that received at
	 * least one qualifying gift in the statement year. The batch iterates accounts rather than
	 * gifts so that one donor produces one document.
	 *
	 * The donor ids are collected first and the locator reads them back, because SOQL does not
	 * allow a semi join inside an `OR`, and a gift can name its donor through either the household
	 * or the donor account.
	 */
	public static Database.QueryLocator donorLocator(Integer statementYear) {
		Date firstDay = Date.newInstance(statementYear, 1, 1);
		Date firstDayAfter = Date.newInstance(statementYear + 1, 1, 1);
		Set<Id> donorIds = new Set<Id>();
		for (Gift__c gift : [
			SELECT Household__c, Donor_Account__c
			FROM Gift__c
			WHERE
				Gift_Date__c >= :firstDay
				AND Gift_Date__c < :firstDayAfter
				AND Status__c = :STATUS_RECEIVED
				AND (Household__c != NULL
				OR Donor_Account__c != NULL)
			WITH SYSTEM_MODE
		]) {
			if (gift.Household__c != null) {
				donorIds.add(gift.Household__c);
			}
			if (gift.Donor_Account__c != null) {
				donorIds.add(gift.Donor_Account__c);
			}
		}
		return Database.getQueryLocator(
			[
				SELECT Id, Name
				FROM Account
				WHERE Id IN :donorIds
				WITH SYSTEM_MODE
				ORDER BY Id
			]
		);
	}

	/** The receipts these donors already hold for this year and type, so a rerun skips them. */
	public static List<Receipt__c> issuedKeys(Set<String> donorYearKeys) {
		return [
			SELECT Id, Donor_Year_Key__c
			FROM Receipt__c
			WHERE Donor_Year_Key__c IN :donorYearKeys AND Status__c = 'Issued'
			WITH SYSTEM_MODE
		];
	}

	/** The most recent runs, for the console. */
	public static List<Receipt_Run__c> recentRuns(Integer howMany) {
		return [
			SELECT
				Id,
				Name,
				Type__c,
				Statement_Year__c,
				Status__c,
				Started__c,
				Finished__c,
				Donors_Processed__c,
				Receipts_Issued__c,
				Errors__c
			FROM Receipt_Run__c
			WITH USER_MODE
			ORDER BY CreatedDate DESC
			LIMIT :howMany
		];
	}

	/** Every template, for the settings console. */
	public static List<Receipt_Template__c> allTemplates() {
		return [
			SELECT Id, Name, Type__c, Body__c, Active__c
			FROM Receipt_Template__c
			WITH USER_MODE
			ORDER BY Type__c, Name
			LIMIT 2000
		];
	}

	/**
	 * The active template for one receipt type. System mode: the batch needs the letter whether or
	 * not the person who scheduled the run can read the template list.
	 */
	public static Receipt_Template__c activeTemplate(String receiptType) {
		List<Receipt_Template__c> templates = [
			SELECT Id, Name, Type__c, Body__c, Active__c
			FROM Receipt_Template__c
			WHERE Type__c = :receiptType AND Active__c = TRUE
			WITH SYSTEM_MODE
			ORDER BY LastModifiedDate DESC
			LIMIT 1
		];
		return templates.isEmpty() ? null : templates[0];
	}
}
