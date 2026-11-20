/**
 * How much of the org's data and file storage and daily limits are used, read from `OrgLimits`
 * (no callout, no Tooling API): for the weekly admin digest (C-54) and for the Org Optimizer
 * module's Storage and Limits section, which reads them here so the two never disagree.
 */
@NamespaceAccessible
public with sharing class OrgLimitReader {
	/** The limits read, by their OrgLimits name. */
	private static final List<String> LIMIT_NAMES = new List<String>{
		'DataStorageMB',
		'FileStorageMB',
		'DailyApiRequests',
		'DailyAsyncApexExecutions',
		'SingleEmail'
	};

	/** Stands in for OrgLimits in tests, by limit name: { used, max }. */
	@TestVisible
	private static Map<String, List<Integer>> limitsOverride;

	/** Test seam for the Org Optimizer module's tests, where `@TestVisible` does not reach. */
	@NamespaceAccessible
	public static void useLimitsForTest(Map<String, List<Integer>> readings) {
		if (Test.isRunningTest()) {
			limitsOverride = readings;
		}
	}

	/** One org limit. */
	@NamespaceAccessible
	public class LimitUse {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Integer used;
		@AuraEnabled
		public Integer max;
		@AuraEnabled
		public Integer percent;

		@NamespaceAccessible
		public String getName() {
			return name;
		}

		@NamespaceAccessible
		public Integer getPercent() {
			return percent;
		}
	}

	/** Every limit read, in the order shown. */
	@NamespaceAccessible
	public static List<LimitUse> all() {
		return atOrAbove(0);
	}

	/**
	 * The limits at or above `threshold` percent, for the weekly admin digest. No permission
	 * check: the caller is the digest, which runs as an administrator, or a page that checked.
	 */
	@NamespaceAccessible
	public static List<LimitUse> atOrAbove(Integer threshold) {
		List<LimitUse> found = new List<LimitUse>();
		Map<String, List<Integer>> readings = readLimits();
		for (String name : LIMIT_NAMES) {
			if (readings.get(name) == null) {
				continue;
			}
			LimitUse use = limitUse(name, readings.get(name));
			if (use.percent >= threshold) {
				found.add(use);
			}
		}
		return found;
	}

	private static LimitUse limitUse(String name, List<Integer> reading) {
		LimitUse use = new LimitUse();
		use.name = name;
		use.used = reading[0];
		use.max = reading[1];
		use.percent = use.max == null ||
			use.max <= 0
			? 0
			: (Integer) Math.min(100, Math.round(100.0 * use.used / use.max));
		return use;
	}

	private static Map<String, List<Integer>> readLimits() {
		if (limitsOverride != null) {
			return limitsOverride;
		}
		Map<String, List<Integer>> result = new Map<String, List<Integer>>();
		Map<String, System.OrgLimit> everyLimit = OrgLimits.getMap();
		for (String name : LIMIT_NAMES) {
			System.OrgLimit orgLimit = everyLimit.get(name);
			if (orgLimit != null) {
				result.put(name, new List<Integer>{ orgLimit.getValue(), orgLimit.getLimit() });
			}
		}
		return result;
	}
}
