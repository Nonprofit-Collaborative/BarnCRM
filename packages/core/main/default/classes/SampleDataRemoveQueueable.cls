/**
 * The C-10 sample data remove chain: each job deletes one chunk of sample records
 * (SampleDataLoader.removeNextChunk) and queues the next until nothing flagged is left.
 * Chunked like the load, because the whole set with Giving's gifts is more automation than
 * one transaction can run (ADMIN-3). It carries no state: each job reads what is left.
 */
public with sharing class SampleDataRemoveQueueable implements Queueable {
    public void execute(QueueableContext context) {
        try {
            if (SampleDataLoader.removeNextChunk() && SampleDataLoader.mayQueueNextStage()) {
                System.enqueueJob(new SampleDataRemoveQueueable());
            }
        } catch (Exception e) {
            // Logged here because nothing else sees an async failure.
            ErrorLogger.log(e, 'SampleDataRemoveQueueable');
            throw e;
        }
    }
}
