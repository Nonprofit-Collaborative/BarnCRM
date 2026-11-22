/**
 * Finds the destination an archive rule names (canonical model R-SQ18, ADR-0240 archive rules and
 * big object archive). All three are Core's: Files (`ArchiveToFiles`), BigObject
 * (`ArchiveToBigObject`) and OffPlatform (`OffPlatformArchiveDestination`, which sends the file
 * through the backup destination a module installs and is refused with a reason while none is).
 */
@NamespaceAccessible
public with sharing class ArchiveDestinations {
	/** The Off Platform destination's class name. Kept for the API surface; Core names it directly. */
	@NamespaceAccessible
	public static final String OFF_PLATFORM_CLASS = 'OffPlatformArchiveDestination';

	/** Injected by tests in place of the real destination, by key. */
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
			return new OffPlatformArchiveDestination();
		}
		if (wanted == ArchiveRules.BIG_OBJECT) {
			return new ArchiveToBigObject();
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
}
