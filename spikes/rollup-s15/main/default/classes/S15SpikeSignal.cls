/**
 * SPIKE (rollup slice S15). The packaged entry point a generated trigger calls. In the product this
 * would enqueue dirty parents through the rollup queue (and be `global` once a namespace exists);
 * in the spike it only records that it ran.
 */
public with sharing class S15SpikeSignal {
    public static Boolean invoked = false;
    public static String lastOutcome;

    /** The single line every generated trigger runs. Reads Trigger context itself. */
    public static void handle() {
        invoked = true;
    }

    /**
     * Used by every generated test. The insert fires the generated before-insert trigger, which runs
     * before required-field checks and custom validation rules, so the trigger line is covered even
     * when the admin's org rejects the dummy record. Only an error raised before the trigger ran
     * fails the test (the DLRS RollupService.testHandler pattern).
     */
    public static void testHandler(SObject dummyRecord) {
        try {
            Database.insert(dummyRecord, AccessLevel.SYSTEM_MODE);
        } catch (DmlException e) {
            if (!invoked) {
                throw e;
            }
        }
    }
}
