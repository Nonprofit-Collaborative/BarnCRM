/**
 * Runs after each stage of the sample data load and, when the stage stopped on an error, tells
 * the person who loaded the data (Q-04). A finalizer rather than the stage's own catch, because a
 * stage that throws rolls back its whole transaction, and a notification sent in it with it.
 */
@NamespaceAccessible
public with sharing class SampleDataLoadFinalizer implements Finalizer {
    /** Attached by each module's sample data stages too, so Giving's stages report the same way. */
    @NamespaceAccessible
    public SampleDataLoadFinalizer() {
        // Nothing to hold: the finalizer reads everything it needs from the stage's result.
    }

    public void execute(FinalizerContext context) {
        handle(context == null ? null : context.getResult());
    }

    /** What the finalizer does with the stage's result; a test cannot build a context. */
    @TestVisible
    private static void handle(ParentJobResult result) {
        if (result == ParentJobResult.UNHANDLED_EXCEPTION) {
            SampleDataLoader.notifyLoadStopped();
        }
    }
}
