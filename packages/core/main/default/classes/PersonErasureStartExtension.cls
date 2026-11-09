/**
 * An optional second seam for a module that also implements `PersonErasureExtension` and needs to
 * know an erasure is under way before Core changes anything (ADR-NEXT erasure start seam,
 * canonical model R-ER8). Contact Point Sync uses it to hold off its address copies while Core
 * deletes the person's addresses and ends their memberships, then copies once.
 *
 * Asked only after every check has passed and only for the real run or the preview, never for a
 * refused erasure. `afterErase` is always asked once the run ends, whether it succeeded or not,
 * so nothing held stays held for the rest of the transaction.
 */
@NamespaceAccessible
public interface PersonErasureStartExtension {
	/** Core is about to change the person's records. */
	void beforeErase(Id personId);

	/** The run has ended, after every module's `erase`, or because it failed. Never throws. */
	void afterErase(Id personId);
}
