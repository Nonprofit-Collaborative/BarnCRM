/**
 * Finds the destination an archive rule names (canonical model R-SQ16, ADR-NEXT archive rules and
 * big object archive). Files and BigObject are Core's; OffPlatform is the class
 * `OffPlatformArchiveDestination`, looked up by name in the package namespace and then without
 * one, as `PersonErasureExtensions` does, so it may live in Core or a module.
 */
@NamespaceAccessible
public with sharing class ArchiveDestinations {
	/** The off-platform destination's class name, which its builder implements. */
	@NamespaceAccessible
	public static final String OFF_PLATFORM_CLASS = 'OffPlatformArchiveDestination';

	/** Injected by tests in place of the class lookup, by key. */
	@TestVisible
	private static Map<String, ArchiveDestination> overrides = new Map<String, ArchiveDestination>();

	/** One destination as the rule panel offers it. */
	public class Choice {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String label;
		/** Null when it can be used; otherwise why not. */
		@AuraEnabled
		public String unavailableReason;
	}

	/** The destination for a rule's key; an empty or unknown key reads as Files. */
	@NamespaceAccessible
	public static ArchiveDestination forKey(String key) {
		String wanted = ArchiveRules.destinationOf(key);
		if (overrides.containsKey(wanted)) {
			return overrides.get(wanted);
		}
		if (wanted == ArchiveRules.OFF_PLATFORM) {
			ArchiveDestination found = offPlatform();
			return found == null ? new Missing() : found;
		}
		return new ArchiveToFiles();
	}

	/** Every destination, in the order the panel lists them, with why one cannot be used. */
	public static List<Choice> choices() {
		List<Choice> result = new List<Choice>();
		for (String key : ArchiveRules.DESTINATIONS) {
			Choice choice = new Choice();
			choice.key = key;
			choice.label = labelOf(key);
			choice.unavailableReason = forKey(key).unavailableReason();
			result.add(choice);
		}
		return result;
	}

	/** The destination's name as the panel shows it. */
	public static String labelOf(String key) {
		String wanted = ArchiveRules.destinationOf(key);
		if (wanted == ArchiveRules.BIG_OBJECT) {
			return BarnHelp.text('Core', 'Core_ArchiveRules_DestinationBigObject');
		}
		if (wanted == ArchiveRules.OFF_PLATFORM) {
			return BarnHelp.text('Core', 'Core_ArchiveRules_DestinationOffPlatform');
		}
		return BarnHelp.text('Core', 'Core_ArchiveRules_DestinationFiles');
	}

	private static ArchiveDestination offPlatform() {
		String prefix = NamespaceUtil.prefix();
		Type found = Type.forName(String.isBlank(prefix) ? null : prefix.removeEnd('__'), OFF_PLATFORM_CLASS);
		if (found == null) {
			found = Type.forName(OFF_PLATFORM_CLASS);
		}
		if (found == null) {
			return null;
		}
		try {
			Object candidate = found.newInstance();
			return candidate instanceof ArchiveDestination ? (ArchiveDestination) candidate : null;
		} catch (Exception cannotBuild) {
			ErrorLogger.log(cannotBuild, 'ArchiveDestinations.offPlatform');
			return null;
		}
	}

	/** The off-platform destination while none is installed: offered, refused with a reason. */
	@TestVisible
	private class Missing implements ArchiveDestination {
		public String key() {
			return ArchiveRules.OFF_PLATFORM;
		}

		public String unavailableReason() {
			return BarnHelp.text('Core', 'Core_ArchiveRules_OffPlatformMissing');
		}

		public Import_Batch__c start(ArchiveRun run) {
			throw new ArchiveRules.ArchiveRuleException(unavailableReason());
		}
	}
}
