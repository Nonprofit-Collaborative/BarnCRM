/**
 * Where a Backup Set run's or an archive's CSV parts go besides Files (canonical model R-SQ17,
 * ADR-NEXT `NEXT-automatic-backups-and-off-platform-destination.md`). A module implements it and
 * registers the class in its catalog row's `Extensions__c` (`ArchiveDestination: <Class>`), so
 * Core names no module class; `OffPlatformSendBatch` finds it through `ModuleExtensions`.
 *
 * Note for the integrator: AR-10 (archive rules with a destination picklist) may define a seam
 * of the same name; reconcile the two into one interface at merge.
 */
@NamespaceAccessible
public interface ArchiveDestination {
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
