/**
 * Keeps each address's `Match_Key__c` in step with its street and postal code (D-200 P6), so
 * the duplicate scan and import matching read the Address match sources through an index
 * instead of a LIKE over every street. Registry row `Address_Match_Key`, which always runs:
 * a key left stale by a pause or a bypass would hide a duplicate.
 *
 * The key is MatchSourceService.matchKey of the address's normalized form: the postal code and
 * the first street word normalization leaves as written. An address with a street and a postal
 * code that normalize to nothing gets NO_KEY, so it is never read as still to be filled.
 */
public with sharing class AddressMatchKeyHandler extends TriggerHandler {
	/** Held by an address that has a street and postal code but no key; matches nothing. */
	public static final String NO_KEY = '|';

	public override void beforeInsert() {
		stamp((List<Address__c>) newRecords());
	}

	public override void beforeUpdate() {
		stamp((List<Address__c>) newRecords());
	}

	/** Sets each address's key from its street and postal code. */
	public static void stamp(List<Address__c> records) {
		for (Address__c record : records) {
			record.Match_Key__c = keyFor(record.Street__c, record.Postal_Code__c);
		}
	}

	/** The key an address with this street and postal code holds, or null when either is blank. */
	public static String keyFor(String street, String postal) {
		if (String.isBlank(street) || String.isBlank(postal)) {
			return null;
		}
		String key = MatchSourceService.matchKey(MatchSourceService.address(street, postal));
		return key == null ? NO_KEY : key;
	}

	/** Health Check: Match Keys Not Filled, with a button that fills them (D-200 P6). */
	public class FilledCheck implements HealthCheckService.Check {
		public HealthCheckService.Finding run() {
			List<String> scope = HealthCheckService.fixScope(
				HealthCheckService.FIX_KEY_FILL_MATCH_KEYS
			);
			if (scope.isEmpty()) {
				return null;
			}
			return new HealthCheckService.Finding(
					'match_keys_not_filled',
					BarnHelp.text('Core', 'Core_HealthCheck_MatchKeysTitle'),
					BarnHelp.text('Core', 'Core_HealthCheck_MatchKeysDetail'),
					HealthCheckService.SEVERITY_INFO,
					HealthCheckService.CATEGORY_SETTINGS
				)
				.withFix(
					BarnHelp.text('Core', 'Core_HealthCheck_MatchKeysFix'),
					HealthCheckService.FIX_ACTION_PREFIX +
					HealthCheckService.FIX_KEY_FILL_MATCH_KEYS
				)
				.withScope(scope);
		}
	}

	/** What the fill fixes: the one job, while the keys are not filled. */
	public static List<String> unfilledScope() {
		return SettingsService.getSettings().Match_Keys_Filled__c == true
			? new List<String>()
			: new List<String>{ BarnHelp.text('Core', 'Core_HealthCheck_MatchKeysFix') };
	}

	/**
	 * Whether the duplicate scan and import matching may read this source by its keys: it is
	 * an Address source over the street and postal code the key is built from, and every
	 * address has been given its key.
	 */
	public static Boolean usable(MatchSourceService.Source source) {
		Schema.DescribeSObjectResult described = Address__c.SObjectType.getDescribe(
			SObjectDescribeOptions.DEFERRED
		);
		return source.normalization == MatchSourceService.ADDRESS &&
			source.objectName == described.getName() &&
			source.valueField == Address__c.Street__c.getDescribe().getName() &&
			source.postalField == Address__c.Postal_Code__c.getDescribe().getName() &&
			SettingsService.getSettings().Match_Keys_Filled__c == true;
	}
}
