/**
 * The Grant Finder tab (F-09, canonical model R-GN11): whether it is on, the search and Save to
 * Pipeline. Thin by design (plan Section 9.9): the work is in `GrantFinder`.
 */
public with sharing class GrantFinderController {
	private static final String CONTEXT = 'GrantFinderController';

	/** Whether the tab searches, and whether the person can save a grant. */
	@AuraEnabled
	public static Map<String, Object> getStatus() {
		return new Map<String, Object>{
			'enabled' => FundersSettings.grantFinderEnabled(),
			'canSave' => Schema.SObjectType.Grant__c.isCreateable()
		};
	}

	/** The listings matching the words, posted, forecasted or both. */
	@AuraEnabled
	public static List<GrantFinder.Listing> search(String keyword, List<String> statuses) {
		if (!FundersSettings.grantFinderEnabled()) {
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Finder_Off'));
		}
		try {
			return GrantFinder.search(keyword, statuses);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.search', null);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Finder_SearchFailed'));
		}
	}

	/** Save to Pipeline: the listing, as JSON from the tab, becomes a Prospect grant. */
	@AuraEnabled
	public static Id save(String listing) {
		try {
			return GrantFinder.save(
				(GrantFinder.Listing) JSON.deserialize(listing, GrantFinder.Listing.class)
			);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.save', null);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
		}
	}
}
