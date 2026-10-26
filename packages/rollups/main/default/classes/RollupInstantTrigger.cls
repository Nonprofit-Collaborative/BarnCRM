/**
 * What a rollup trigger the administrator deployed from the Rollup Builder runs: instant totals
 * on an object BarnCRM ships no trigger for (a standard object, another package's object, the
 * organization's own), canonical model R-R12, ADR-0137.
 *
 * The generated trigger is one line, `RollupInstantTrigger.run();`, so editing a rollup never
 * changes code: which totals a save moves is worked out by `RollupTriggerHandler`, exactly as
 * for BarnCRM's own objects. The handler is dispatched through `TriggerDispatcher`, so pausing
 * all automation and a transaction bypass stop it like any packaged trigger, and a failure is
 * logged and never fails the save. The object's own switch, an Automation Setting named after
 * its trigger, turns it off without a deploy.
 *
 * The names live here too, because `run` finds the switch by them: the same object gives the
 * same trigger, test and switch names in every org, so a sandbox's change set lands exactly what
 * production's Builder expects to find.
 *
 * Global, with `run` and `hasRun`: the trigger and its test are code in the subscriber's org,
 * which can call only global Apex of a managed package. Global is permanent once a managed
 * version is released: the class, `run` and `hasRun` can then never be removed or change
 * signature. The name methods are public, for the Builder only.
 */
global with sharing class RollupInstantTrigger {
    private static final String NAME_PREFIX = 'BarnRollup_';
    private static final String TEST_SUFFIX = '_Test';
    /** Apex class and trigger names are at most 40 characters. */
    private static final Integer NAME_LIMIT = 40;

    private static Boolean reached = false;

    /** The line every generated trigger runs. Reads the trigger context itself. */
    global static void run() {
        reached = true;
        if (Trigger.isExecuting) {
            handle(Trigger.operationType, Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap);
        }
    }

    /**
     * True once a generated trigger has called `run` in this transaction, switched off or not.
     * The generated test asserts it after its insert, which the org's own required fields or
     * validation rules may refuse after the before insert trigger has run.
     */
    global static Boolean hasRun() {
        return reached;
    }

    /**
     * `BarnRollup_` and the object's API name, every run of other characters one underscore:
     * `Shift__c` gives `BarnRollup_Shift_c`. A name that would leave its test class over 40
     * characters is cut and ends in six characters of the API name's MD5 hash, so two long
     * names that start alike still differ. It is also the name of the object's switch.
     */
    public static String triggerNameFor(String objectApiName) {
        String base = objectApiName.replaceAll('[^A-Za-z0-9]+', '_').removeEnd('_');
        String name = NAME_PREFIX + base;
        if (name.length() + TEST_SUFFIX.length() > NAME_LIMIT) {
            String hash = EncodingUtil.convertToHex(
                    Crypto.generateDigest('MD5', Blob.valueOf(objectApiName))
                )
                .left(6);
            name = name.left(NAME_LIMIT - TEST_SUFFIX.length() - 7).removeEnd('_') + '_' + hash;
        }
        return name;
    }

    public static String testClassNameFor(String objectApiName) {
        return triggerNameFor(objectApiName) + TEST_SUFFIX;
    }

    /** The prefix every generated trigger's name starts with. */
    public static String namePrefix() {
        return NAME_PREFIX;
    }

    /** The trigger context, handed to the rollup handler when the object's switch is on. */
    @TestVisible
    private static void handle(
        System.TriggerOperation operation,
        List<SObject> newRecords,
        Map<Id, SObject> newRecordsById,
        List<SObject> oldRecords,
        Map<Id, SObject> oldRecordsById
    ) {
        List<SObject> records = newRecords != null ? newRecords : oldRecords;
        if (records == null || records.isEmpty()) {
            return;
        }
        String objectName = String.valueOf(records[0].getSObjectType());
        if (!AutomationControl.isEnabled(triggerNameFor(objectName))) {
            return;
        }
        // As TriggerDispatcher.run does for a registered trigger: a partial save's retry is told
        // apart from the attempt it repeats, so its records are not skipped as already done.
        TriggerHandler.noteTriggerProgress();
        TriggerDispatcher.run(
            new RollupTriggerHandler(),
            new TriggerDispatcher.Context(
                operation,
                newRecords,
                newRecordsById,
                oldRecords,
                oldRecordsById
            )
        );
        TriggerHandler.noteTriggerProgress();
    }
}
