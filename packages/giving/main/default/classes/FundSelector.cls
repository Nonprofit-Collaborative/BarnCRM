/**
 * All SOQL against Fund__c.
 */
public with sharing class FundSelector {
	/**
	 * The funds with the given identifiers.
	 */
	public static List<Fund__c> selectById(Set<Id> fundIds) {
		return [
			SELECT Id, Name, Active__c, Restricted__c, Is_Default__c, Accounting_Code__c
			FROM Fund__c
			WHERE Id IN :fundIds
			WITH USER_MODE
		];
	}

	/**
	 * The active fund marked as the default, or null when the organization has not picked one
	 * yet. At most one fund carries the flag (R-F1), and the oldest wins if data predates the
	 * rule, so the answer never changes between two transactions.
	 */
	public static Fund__c selectDefaultFund() {
		List<Fund__c> funds = [
			SELECT Id, Name, Active__c, Is_Default__c
			FROM Fund__c
			WHERE Is_Default__c = TRUE AND Active__c = TRUE
			WITH USER_MODE
			ORDER BY CreatedDate ASC
			LIMIT 1
		];
		return funds.isEmpty() ? null : funds[0];
	}

	/**
	 * The funds other than these that still carry the default flag, so saving a new default
	 * clears the old one (R-F1).
	 */
	public static List<Fund__c> selectOtherDefaults(Set<Id> excludedFundIds) {
		return [
			SELECT Id, Is_Default__c
			FROM Fund__c
			WHERE Is_Default__c = TRUE AND Id NOT IN :excludedFundIds
			WITH USER_MODE
		];
	}
}
