/**
 * The Sample Data package's side of Core's `SampleDataHost` seam (ADR-0233
 * `0233-org-optimizer-and-sample-data-modules.md`): Core's install check and the module sample
 * sets reach the loader, Core's removal stages and the finished notice through it, by the class
 * name in this package's catalog row (ADR-0057).
 */
@NamespaceAccessible
public with sharing class SampleDataPackageHost implements SampleDataHost {
	/** Built by name from Core (`ModuleExtensions`), so it needs a public constructor. */
	@NamespaceAccessible
	public SampleDataPackageHost() {
		// Stateless: every call goes to SampleDataLoader.
	}

	public void load() {
		SampleDataLoader.load();
	}

	public SampleDataStages coreRemoveStages() {
		return new SampleDataRemoveStages();
	}

	public void notifyLoadFinished() {
		SampleDataLoader.notifyLoadFinished();
	}
}
