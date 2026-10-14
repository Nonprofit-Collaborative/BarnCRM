/**
 * Runs a sample data removal's stages (SampleDataRemoveStages, and each module's own) the way
 * SampleDataStageBatch runs a load's: one stage per transaction, in order, with no cap on how
 * many batches follow each other (ADMIN-3).
 *
 * It is a subclass only so that its AsyncApexJob row carries its own class name. The status
 * card and the load and remove guards read that name to tell a load from a removal, which one
 * shared class name could not say. Everything else is SampleDataStageBatch.
 */
@NamespaceAccessible
public with sharing class SampleDataRemoveBatch extends SampleDataStageBatch {
    @NamespaceAccessible
    public SampleDataRemoveBatch(SampleDataStages stages) {
        super(stages);
    }

    /** Starts a batch that runs the given removal's stages, and returns its job Id. */
    @NamespaceAccessible
    public static Id startRemoval(SampleDataStages stages) {
        SampleDataStageBatch.noteStarted(stages);
        return Database.executeBatch(
            new SampleDataRemoveBatch(stages),
            SampleDataStageBatch.SCOPE_SIZE
        );
    }

    protected override void notifyStopped() {
        SampleDataLoader.notifyRemoveStopped();
    }
}
