/**
 * The Giving sample data load chain (C-10): one job per stage, each enqueuing the next.
 *
 * Stage -1 inserts the funds, appeals and commitments; stages 0 and up insert one chunk of
 * gifts each; the chain ends by settling overdue installments and handing back to Core, so
 * a module that loads after Giving would start there.
 *
 * Only the reference key to Id map (about forty entries) and the chunk index travel between
 * jobs. The payload is re-read from the static resource in each job, so a two hundred
 * kilobyte JSON body is never serialized into the queue.
 */
public with sharing class GivingSampleDataQueueable implements Queueable {
    /** The stage index that inserts funds, appeals and commitments. */
    public static final Integer STAGE_REFERENCE_DATA = -1;

    private final Integer stage;
    private final Map<String, Id> referenceIdsByKey;

    public GivingSampleDataQueueable(Integer stage, Map<String, Id> referenceIdsByKey) {
        this.stage = stage;
        this.referenceIdsByKey = referenceIdsByKey;
    }

    public void execute(QueueableContext context) {
        // Core's finalizer tells the person who loaded the data when a stage stops (Q-04): a
        // stage that throws rolls back, a notification sent from its catch included.
        System.attachFinalizer(new SampleDataLoadFinalizer());
        try {
            GivingSampleDataSet data = GivingSampleDataSet.parse(
                GivingSampleData.getSampleDataJson()
            );
            if (stage == STAGE_REFERENCE_DATA) {
                Map<String, Id> loaded = GivingSampleDataLoader.loadReferenceData(data);
                enqueueNext(0, loaded, data);
                return;
            }
            GivingSampleDataLoader.loadGiftChunk(data, stage, referenceIdsByKey);
            enqueueNext(stage + 1, referenceIdsByKey, data);
        } catch (Exception failed) {
            // Logged here because nothing else sees an asynchronous failure.
            ErrorLogger.log(failed, 'GivingSampleDataQueueable');
            throw failed;
        }
    }

    /**
     * Queues the next chunk, or ends the chain: the installments that are already past due
     * are settled, and Core is told Giving has finished so the module after it can start.
     */
    private void enqueueNext(
        Integer nextStage,
        Map<String, Id> idsByKey,
        GivingSampleDataSet data
    ) {
        if (nextStage < data.chunkCount()) {
            System.enqueueJob(new GivingSampleDataQueueable(nextStage, idsByKey));
            return;
        }
        GivingSampleDataLoader.finish();
        SampleDataModules.startAfter(GivingSampleData.MODULE_NAME);
    }
}
