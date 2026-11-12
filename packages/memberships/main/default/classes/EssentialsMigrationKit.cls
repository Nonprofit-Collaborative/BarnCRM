/**
 * The Memberships Essentials kit's rows (canonical model R-MEM9; ADR-0206
 * `0206-memberships-module.md`, decision 8), named by the kit `Memberships_Essentials`. Essentials
 * keeps a membership product's term as a number and a unit, and a membership's state in its own
 * formulas, so this class works out the two columns the templates map that no one field holds:
 * `Months` for a level and `Ends` and `Status` for a membership. Essentials is read by describe
 * only: its field names are text here. Core builds this class by name, so it and its constructor
 * are namespace-accessible (ADR-0017).
 */
@NamespaceAccessible
public with sharing class EssentialsMigrationKit implements MigrationKitExtension {
	@TestVisible
	private static final String KIT = 'Memberships_Essentials';
	@TestVisible
	private static final String LEVELS = 'levels';
	@TestVisible
	private static final String TERMS = 'terms';

	@NamespaceAccessible
	public EssentialsMigrationKit() {
		// Built by name from the kit's Extension Class; holds no state.
		return;
	}

	@NamespaceAccessible
	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		if (stepKey != LEVELS && stepKey != TERMS) {
			return null;
		}
		MigrationKitService.Source source = new MigrationKitService.Source(
			MigrationKitService.stepNamed(MigrationKitService.kitNamed(KIT), stepKey)
		);
		List<Map<String, Object>> rows = source.rows(records);
		Date today = MembershipService.today();
		for (Map<String, Object> row : rows) {
			if (stepKey == LEVELS) {
				row.put(
					'Months',
					months((String) row.get('Term__c'), (String) row.get('Term_Unit__c'))
				);
			} else {
				Boolean forever = (String) row.get('Does_Not_Expire__c') == 'true';
				String ends = forever ? '' : (String) row.get('End_Date__c');
				row.put('Ends', ends);
				row.put('Status', statusOf(ends, today));
			}
		}
		return rows;
	}

	@NamespaceAccessible
	public MigrationCheck verify(String stepKey) {
		return null;
	}

	/** An Essentials term as whole months: 0 (never ends) when it has none, at least 1 otherwise. */
	@TestVisible
	private static String months(String term, String unit) {
		Decimal count;
		try {
			count = String.isBlank(term) ? 0 : Decimal.valueOf(term);
		} catch (TypeException e) {
			count = 0;
		}
		if (count <= 0) {
			return '0';
		}
		Decimal result;
		switch on (unit == null ? 'Month' : unit) {
			when 'Day' {
				result = (count / 30).round(System.RoundingMode.HALF_UP);
			}
			when 'Week' {
				result = (count * 7 / 30).round(System.RoundingMode.HALF_UP);
			}
			when 'Year' {
				result = count * 12;
			}
			when else {
				result = count;
			}
		}
		return String.valueOf(Math.max(result.intValue(), 1));
	}

	/** Current when the membership has no end or has not ended, else Lapsed. */
	@TestVisible
	private static String statusOf(String ends, Date today) {
		if (String.isBlank(ends) || Date.valueOf(ends) >= today) {
			return MembershipService.CURRENT;
		}
		return MembershipService.LAPSED;
	}
}
