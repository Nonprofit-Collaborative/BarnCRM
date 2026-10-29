/**
 * A trigger handler the shipped registry can name, used only by the trigger framework's tests.
 *
 * It is a top-level public class with a no-argument constructor because that is what
 * `Type.forName` needs in order to build a handler a registry record names (ADR-0017). It records
 * what it did on statics, since the dispatcher builds the instance and the test never sees it, and
 * it uses the base class recursion guard the way a real handler is meant to. It reads its records
 * through `newRecordsById()` rather than `Trigger.newMap` so that the tests can drive it without
 * a real trigger.
 */
@IsTest
public class TestRegisteredHandler extends TriggerHandler {
    public static Integer runCount = 0;
    public static Set<Id> handledIds = new Set<Id>();
    /** Handed to TriggerDispatcher.afterHandlers on each run, when set. */
    public static TriggerDispatcher.Deferred toDefer;

    public static void reset() {
        runCount = 0;
        handledIds = new Set<Id>();
        toDefer = null;
        TriggerHandler.clearRunClaims();
    }

    public override void afterInsert() {
        runCount++;
        if (toDefer != null) {
            TriggerDispatcher.afterHandlers(toDefer);
        }
        Map<Id, SObject> records = newRecordsById();
        if (records != null) {
            handledIds.addAll(claimRunFor('afterInsert', records.keySet()));
        }
    }
}
