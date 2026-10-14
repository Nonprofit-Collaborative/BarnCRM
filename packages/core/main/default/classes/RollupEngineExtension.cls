/**
 * The seam the BarnCRM Rollup Builder module uses to keep totals current when Core saves,
 * merges or loads records (ADR-NEXT, `NEXT-rollup-builder-module.md`), under the cross-package
 * mechanism ADR-0017 settled and in the shape of `HealthCheckExtension`.
 *
 * Core does not contain the rollup engine and may not name it. It looks up an implementation by
 * name (`RollupEngineExtensions`) and, where none is installed, skips the step: an org without
 * the module has no totals to keep current.
 */
@NamespaceAccessible
public interface RollupEngineExtension {
    /**
     * Recalculates the totals on the survivors of a merge, read off the deleted records the
     * `after delete` trigger has (their `MasterRecordId` names the survivor).
     */
    void afterMerge(String targetObject, List<SObject> mergedRecords);

    /** Recalculates the totals on these merge survivors of the named object. */
    void forSurvivors(String targetObject, Set<Id> survivorIds);

    /** Starts the queued recalculation for anything still pending, as a background job ends. */
    void startQueuedRecalculation();

    /** Starts the processor when entries wait, as automation resumes after a pause. */
    void processPending();

    /** When the totals were last calculated across every active definition, or null. */
    Datetime lastCalculated();

    /** True when the totals have not completed inside the freshness window. */
    Boolean isStale();

    /**
     * Every field a rollup writes, by the object it writes on, as the definitions name them
     * (active or not). Never null.
     */
    Map<String, Set<String>> targetFieldsByObject();
}
