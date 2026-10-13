/**
 * Runs a sample data load's stages one per transaction, in order (C-10).
 *
 * Each stage is one scope item at a scope size of one, so every stage gets a full
 * asynchronous transaction of its own, as a queueable did. Batch Apex replaces the old
 * queueable chain because Developer Edition, trial and scratch orgs cap a chain at five jobs,
 * and a full load (accounts, five contact chunks, connections, then Giving's reference data,
 * gift chunks and settling) is about fifteen. A batch's finish() may start the next batch with
 * no depth cap, so Core's load hands over to each module's load here, and the last module hands
 * back to Core through SampleDataModules.startAfter.
 *
 * A stage that throws is rolled back to the point before it, logged, and stops the load: the
 * stages after it are skipped and nothing further is started, as when a queueable in the old
 * chain failed. The status card then shows what did load, and Remove Sample Data clears it.
 *
 * An Apex test may run only one execute of a batch, so inside a test start() returns the first
 * stage alone (SampleDataLoader.mayQueueNextStage), and finish() then starts nothing because
 * not every stage ran. A limit the platform cannot catch (CPU time) fails that stage's
 * transaction outright; the later stages still run, but that stage never counts as done, so
 * finish() starts nothing after it either. Tests drive the
 * stages and the hand-off by calling runStage, start, execute and finish directly.
 */
@NamespaceAccessible
public with sharing class SampleDataStageBatch implements Database.Batchable<Integer>, Database.Stateful {
    /** One stage per transaction. */
    public static final Integer SCOPE_SIZE = 1;

    /** The load each start() call handed to a new batch this transaction, for the tests. */
    @TestVisible
    private static List<SampleDataStages> started = new List<SampleDataStages>();

    /** Set by a test that calls start() directly to read the whole stage order. */
    @TestVisible
    private static Boolean everyStageInTest = false;

    private final SampleDataStages stages;
    private Integer stageTotal = 0;
    private Integer stagesDone = 0;
    @TestVisible
    private Boolean stopped = false;

    @NamespaceAccessible
    public SampleDataStageBatch(SampleDataStages stages) {
        this.stages = stages;
    }

    /** Starts a batch that runs the given load's stages, and returns its job Id. */
    @NamespaceAccessible
    public static Id start(SampleDataStages stages) {
        started.add(stages);
        return Database.executeBatch(new SampleDataStageBatch(stages), SCOPE_SIZE);
    }

    public Iterable<Integer> start(Database.BatchableContext context) {
        List<Integer> order = new List<Integer>();
        try {
            stageTotal = stages.stageCount();
        } catch (Exception failed) {
            stop(failed, null);
            return order;
        }
        for (Integer stage = 0; stage < stageTotal; stage++) {
            order.add(stage);
        }
        if (!SampleDataLoader.mayQueueNextStage() && !everyStageInTest && order.size() > 1) {
            return new List<Integer>{ order[0] };
        }
        return order;
    }

    public void execute(Database.BatchableContext context, List<Integer> scope) {
        for (Integer stage : scope) {
            runStage(stage);
        }
    }

    /** Runs one stage unless an earlier one stopped the load. */
    @TestVisible
    private void runStage(Integer stage) {
        if (stopped) {
            return;
        }
        Savepoint beforeStage = Database.setSavepoint();
        try {
            stages.runStage(stage);
            stagesDone++;
        } catch (Exception failed) {
            Database.rollback(beforeStage);
            stop(failed, stage);
        }
    }

    /**
     * Hands over to whatever loads next, once every stage has run. A load that stopped part way
     * starts nothing, so a module never loads against people that are not there.
     */
    public void finish(Database.BatchableContext context) {
        if (stopped || stagesDone < stageTotal) {
            return;
        }
        try {
            stages.finish();
        } catch (Exception failed) {
            stop(failed, null);
        }
    }

    private void stop(Exception failed, Integer stage) {
        stopped = true;
        // Logged here because nothing else sees an asynchronous failure; the synchronous entry
        // points leave logging to SampleDataController.
        ErrorLogger.log(failed, stages.name() + (stage == null ? '' : ', stage ' + stage));
    }
}
