/**
 * Where a Backup Set run's or an archive's CSV parts go besides Files (canonical model R-SQ17,
 * ADR-NEXT `NEXT-automatic-backups-and-off-platform-destination.md`). A module implements it and
 * registers the class in its catalog row's `Extensions__c` (`OffPlatformDestination: <Class>`),
 * so Core names no module class; `OffPlatformSendBatch` finds it through `ModuleExtensions`.
 *
 * It sends one file. AR-10's `ArchiveDestination` (an archive rule's Files, BigObject or
 * OffPlatform choice, which starts a whole run) is a different seam: its OffPlatform choice
 * writes the parts to Files and sends them through this one.
 */
@NamespaceAccessible
public interface OffPlatformDestination {
	/** The destination's key as a set or an archive stores it, such as `offPlatform`. */
	String key();

	/** Null when the running user can send now; otherwise why not, in plain words. */
	String notReady();

	/**
	 * Sends one file, making at most one callout and no DML. Returns null when the destination
	 * answered with success, otherwise the failure in plain words (never a secret).
	 */
	String send(String fileName, Blob body);
}
