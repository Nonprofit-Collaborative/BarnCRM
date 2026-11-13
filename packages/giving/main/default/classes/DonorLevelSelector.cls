/**
 * Every query donor levels need (plan Section 9.3).
 *
 * The ladder read that assignment uses runs in system mode, for the same reason the tribute rules
 * read a deceased flag that way: a level that quietly stopped being assigned because the person
 * saving a gift cannot see the level records would be worse than no levels at all. The reads the
 * Donor Levels page shows to somebody run in user mode.
 */
public with sharing class DonorLevelSelector {
	/**
	 * The active rungs, lowest first. Ordering here rather than in the service keeps the ladder
	 * in one shape wherever it is read.
	 */
	public static List<Donor_Level__c> selectActiveLevels() {
		return [
			SELECT Id, Name, Minimum_Amount__c, Maximum_Amount__c, Active__c
			FROM Donor_Level__c
			WHERE Active__c = TRUE
			WITH SYSTEM_MODE
			ORDER BY Minimum_Amount__c ASC, Name ASC
			LIMIT 500
		];
	}

	/** Every rung, active or not, for the page that lists the ladder. */
	public static List<Donor_Level__c> selectAllLevels() {
		return [
			SELECT Id, Name, Description__c, Minimum_Amount__c, Maximum_Amount__c, Active__c
			FROM Donor_Level__c
			WITH USER_MODE
			ORDER BY Minimum_Amount__c ASC, Name ASC
			LIMIT 500
		];
	}

	/**
	 * How many donors sit on each rung, counting accounts and contacts together, so the page can
	 * say whether a ladder is doing anything at all.
	 */
	public static Map<Id, Integer> countDonorsByLevel() {
		Map<Id, Integer> counts = new Map<Id, Integer>();
		for (AggregateResult row : [
			SELECT Donor_Level__c levelId, COUNT(Id) donors
			FROM Account
			WHERE Donor_Level__c != NULL
			WITH USER_MODE
			GROUP BY Donor_Level__c
			LIMIT 500
		]) {
			add(counts, (Id) row.get('levelId'), (Integer) row.get('donors'));
		}
		for (AggregateResult row : [
			SELECT Donor_Level__c levelId, COUNT(Id) donors
			FROM Contact
			WHERE Donor_Level__c != NULL
			WITH USER_MODE
			GROUP BY Donor_Level__c
			LIMIT 500
		]) {
			add(counts, (Id) row.get('levelId'), (Integer) row.get('donors'));
		}
		return counts;
	}

	private static void add(Map<Id, Integer> counts, Id levelId, Integer donors) {
		if (levelId == null) {
			return;
		}
		Integer running = counts.containsKey(levelId) ? counts.get(levelId) : 0;
		counts.put(levelId, running + (donors == null ? 0 : donors));
	}

	/**
	 * The accounts a recalculation walks: anybody who has a giving total of any kind, plus
	 * anybody already holding a level, so that a donor whose totals have gone back to nothing is
	 * still re-placed rather than left on a rung they no longer earn.
	 */
	public static Database.QueryLocator accountLocator() {
		return Database.getQueryLocator(
			[
				SELECT
					Id,
					Total_Giving__c,
					Giving_This_Year__c,
					Giving_Last_Year__c,
					Largest_Gift__c,
					Donor_Level__c,
					Previous_Donor_Level__c,
					Donor_Level_Changed_Date__c,
					Last_Gift_Date__c,
					Recent_Gift_Count__c,
					Recent_Giving__c,
					RFM_Recency_Score__c,
					RFM_Frequency_Score__c,
					RFM_Monetary_Score__c,
					RFM_Score__c,
					RFM_Segment__c
				FROM Account
				WHERE
					Last_Gift_Date__c != NULL
					OR RFM_Segment__c != NULL
					OR Total_Giving__c != NULL
					OR Giving_This_Year__c != NULL
					OR Giving_Last_Year__c != NULL
					OR Largest_Gift__c != NULL
					OR Donor_Level__c != NULL
				WITH SYSTEM_MODE
			]
		);
	}

	/** The people a recalculation walks, on the same terms as the accounts. */
	public static Database.QueryLocator contactLocator() {
		return Database.getQueryLocator(
			[
				SELECT
					Id,
					Total_Giving__c,
					Giving_This_Year__c,
					Giving_Last_Year__c,
					Largest_Gift__c,
					Donor_Level__c,
					Previous_Donor_Level__c,
					Donor_Level_Changed_Date__c,
					Last_Gift_Date__c,
					Recent_Gift_Count__c,
					Recent_Giving__c,
					RFM_Recency_Score__c,
					RFM_Frequency_Score__c,
					RFM_Monetary_Score__c,
					RFM_Score__c,
					RFM_Segment__c
				FROM Contact
				WHERE
					Last_Gift_Date__c != NULL
					OR RFM_Segment__c != NULL
					OR Total_Giving__c != NULL
					OR Giving_This_Year__c != NULL
					OR Giving_Last_Year__c != NULL
					OR Largest_Gift__c != NULL
					OR Donor_Level__c != NULL
				WITH SYSTEM_MODE
			]
		);
	}

	/** The attributes the passes read, as `accountLocator` and `contactLocator` select them. */
	private static final List<String> DONOR_FIELDS = new List<String>{
		'Id',
		'Total_Giving__c',
		'Giving_This_Year__c',
		'Giving_Last_Year__c',
		'Largest_Gift__c',
		'Donor_Level__c',
		'Previous_Donor_Level__c',
		'Donor_Level_Changed_Date__c',
		'Last_Gift_Date__c',
		'Recent_Gift_Count__c',
		'Recent_Giving__c',
		'RFM_Recency_Score__c',
		'RFM_Frequency_Score__c',
		'RFM_Monetary_Score__c',
		'RFM_Score__c',
		'RFM_Segment__c'
	};

	/**
	 * The donors of `Account` or `Contact` whose last gift date lies in one of these ranges, for
	 * the nightly pass that only rescores donors crossing a recency cutoff (D-200 P1).
	 *
	 * @param objectName `Account` or `Contact`
	 * @param edges start and end dates, inclusive, in pairs
	 */
	public static Database.QueryLocator recencyEdgeLocator(String objectName, List<Date> edges) {
		List<String> ranges = new List<String>();
		Map<String, Object> binds = new Map<String, Object>();
		for (Integer i = 0; i + 1 < edges.size(); i += 2) {
			ranges.add(
				'(Last_Gift_Date__c >= :from' + i + ' AND Last_Gift_Date__c <= :to' + i + ')'
			);
			binds.put('from' + i, edges[i]);
			binds.put('to' + i, edges[i + 1]);
		}
		return Database.getQueryLocatorWithBinds(
			'SELECT ' +
				String.join(DONOR_FIELDS, ', ') +
				' FROM ' +
				(objectName == 'Contact' ? 'Contact' : 'Account') +
				' WHERE ' +
				(ranges.isEmpty() ? 'Id = null' : String.join(ranges, ' OR ')),
			binds,
			AccessLevel.SYSTEM_MODE
		);
	}
}
