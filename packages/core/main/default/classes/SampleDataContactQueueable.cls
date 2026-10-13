/**
 * Stage two of the C-10 sample data load: inserts one chunk of contacts, then enqueues
 * itself for the next chunk until every member in the payload has been inserted.
 *
 * The last chunk hands over to SampleDataConnectionQueueable, which loads the connections
 * between the people and starts any module sample set.
 *
 * Only the household key to Id map and the chunk index travel from one job to the next.
 * The payload itself is re-read from the static resource in each job, so a several
 * hundred kilobyte JSON body is never serialized into the queue.
 */
public with sharing class SampleDataContactQueueable implements Queueable {
    private final Map<String, Id> householdIdsByKey;
    private final Integer chunkIndex;

    public SampleDataContactQueueable(Map<String, Id> householdIdsByKey, Integer chunkIndex) {
        this.householdIdsByKey = householdIdsByKey;
        this.chunkIndex = chunkIndex;
    }

    public void execute(QueueableContext context) {
        // A stage that throws rolls back everything it did, a notification included, so the
        // person who loaded the data is told by the finalizer, which runs afterwards (Q-04).
        System.attachFinalizer(new SampleDataLoadFinalizer());
        try {
            SampleDataSet data = SampleDataSet.parse(SampleDataLoader.getSampleDataJson());
            data.householdIdsByKey = householdIdsByKey;
            SampleDataLoadQueueable.loadContactChunk(data, chunkIndex);
            if (!SampleDataLoader.mayQueueNextStage()) {
                return;
            }
            if (chunkIndex + 1 < data.chunkCount()) {
                System.enqueueJob(
                    new SampleDataContactQueueable(householdIdsByKey, chunkIndex + 1)
                );
            } else {
                // Every person now exists, so the connections between them, and any module
                // sample set that points at them, can be loaded.
                System.enqueueJob(new SampleDataConnectionQueueable());
            }
        } catch (Exception e) {
            // Logged here because nothing else sees an async failure; the synchronous
            // entry points leave logging to SampleDataController.
            ErrorLogger.log(e, 'SampleDataContactQueueable');
            throw e;
        }
    }
}
