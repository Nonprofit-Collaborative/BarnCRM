/**
 * The BarnCRM Sample Data package, as Core reaches it (ADR-0233
 * `0233-org-optimizer-and-sample-data-modules.md`). Core keeps the sample data framework every
 * module's set runs on (SampleDataModules, SampleDataStageBatch, SampleDataFile); the package
 * holds Core's own sample set, its loader and the Sample Data page, and names its class for
 * this seam in its catalog row (`SampleDataHost: <class>`, ADR-0057). Without the package there
 * is none, and Core says so instead of loading.
 */
@NamespaceAccessible
public interface SampleDataHost {
	/** Starts the load; throws SampleDataException when it is already loaded or running. */
	void load();

	/** The removal stages for Core's own sample records, which run after every module's. */
	SampleDataStages coreRemoveStages();

	/** Tells the person who loaded the set that the whole load, every module's included, is in. */
	void notifyLoadFinished();
}
