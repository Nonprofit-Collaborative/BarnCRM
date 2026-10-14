/**
 * One sample data load, Core's own or a module's, cut into stages that SampleDataStageBatch
 * runs one per transaction, in order (C-10).
 *
 * The stages run from Batch Apex rather than a chain of queueables because Developer Edition,
 * trial and scratch orgs stop a queueable chain after five jobs, and a full load is more stages
 * than that. A batch has no such cap, and the batch that finishes one load starts the next.
 *
 * The implementation is kept between stages (the batch is stateful), so a map built by one
 * stage, such as the household keys and Ids, is there for the next. Keep that state small: it
 * is serialized after every stage. Re-read a large payload in each stage instead.
 */
@NamespaceAccessible
public interface SampleDataStages {
    /** Names this load in the error log, for example 'Core sample data'. */
    String name();

    /** How many stages this load has. Stage numbers run from zero to this less one. */
    Integer stageCount();

    /**
     * Runs one stage. A stage that throws is rolled back, logged, and ends the load: no later
     * stage runs and finish() is not called.
     */
    void runStage(Integer stage);

    /** Runs once after every stage succeeded, and starts whatever loads next. */
    void finish();
}
