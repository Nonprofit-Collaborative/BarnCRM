/**
 * Where an archive rule moves its records (canonical model R-SQ18, ADR-0240 archive rules and big
 * object archive). Core ships Files (`ArchiveToFiles`) and BigObject (`ArchiveToBigObject`); the
 * off-platform store is the class `OffPlatformArchiveDestination`, found by name in
 * `ArchiveDestinations`, so it can live in Core or a module without the rule's shape changing.
 *
 * The caller has already checked the person's permissions, the object (R-BD4) and the count
 * (R-BD2) before `start` is asked. A destination checks what only it knows.
 */
@NamespaceAccessible
public interface ArchiveDestination {
	/** The destination's value in the rule's `destination` key: Files, BigObject or OffPlatform. */
	String key();

	/**
	 * Why this destination cannot be used in this org now, as a sentence for the person, or null
	 * when it can. Asked before a rule is saved or run.
	 */
	String unavailableReason();

	/**
	 * Starts moving the run's records and returns its data job (`Import_Batch__c`), already saved.
	 * Throws an exception whose message is for the person when it refuses.
	 */
	Import_Batch__c start(ArchiveRun run);
}
