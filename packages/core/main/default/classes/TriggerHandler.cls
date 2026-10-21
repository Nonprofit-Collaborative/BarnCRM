/**
 * Base class for every packaged trigger handler.
 *
 * A handler subclasses this, overrides only the contexts it cares about, and is invoked by
 * `TriggerDispatcher`. Nothing else calls a handler directly, so every packaged automation is
 * bypassable and pausable (plan Section 7.2, canonical model rule R-A1).
 *
 * THE CONTRACT. Every context method takes no arguments, and a handler body reads the records
 * through `newRecords()`, `newRecordsById()`, `oldRecords()`, and `oldRecordsById()`, which
 * return the trigger context collections. That is what every feature module is written
 * against, so it is fixed here.
 *
 *     public class ContactTriggerHandler extends TriggerHandler {
 *         public override void beforeInsert() {
 *             for (Contact person : (List<Contact>) newRecords()) {
 *                 person.Description = 'Seen by BarnCRM';
 *             }
 *         }
 *     }
 *
 * Outside a trigger there is no `Trigger.new` to read, so a unit test that wants to drive a
 * handler without inserting records sets the `testNew`, `testNewMap`, `testOld`, and `testOldMap`
 * overrides below, which those four accessors return in place of the trigger collections.
 *
 * The recursion guard is per transaction, per handler, per phase, and per record: `claimRunFor`
 * takes the record ids in front of it and hands back the ones this handler has not already
 * processed, so a handler that causes its own object to be updated again does its work once per
 * record while a 400 record load still gets all 400 processed. Every claim of the transaction is
 * cleared when a partial save is retried (`noteTriggerProgress`), so a claim never stops a
 * workflow or flow re-fire across a partial save: a handler that must not run twice for a
 * record needs work that is safe to repeat, or its own check of saved state.
 */
@NamespaceAccessible
public virtual with sharing class TriggerHandler {
    private static final Map<String, Set<Id>> CLAIMED_RECORDS = new Map<String, Set<Id>>();

    /**
     * Stand-ins for the four trigger context collections, for a unit test driving a handler
     * outside a trigger. Nothing in production ever sets them.
     */
    @TestVisible
    private static List<SObject> testNew;
    @TestVisible
    private static Map<Id, SObject> testNewMap;
    @TestVisible
    private static List<SObject> testOld;
    @TestVisible
    private static Map<Id, SObject> testOldMap;

    /**
     * Sets `testNew` and `testOldMap` from a module's test, where `@TestVisible` does not reach
     * once the packages are separate. Does nothing outside a test.
     */
    @NamespaceAccessible
    public static void setTestRecords(List<SObject> newRecords, Map<Id, SObject> oldRecordsById) {
        if (Test.isRunningTest()) {
            testNew = newRecords;
            testOldMap = oldRecordsById;
        }
    }

    @NamespaceAccessible
    public virtual void beforeInsert() {
        return;
    }

    @NamespaceAccessible
    public virtual void afterInsert() {
        return;
    }

    @NamespaceAccessible
    public virtual void beforeUpdate() {
        return;
    }

    @NamespaceAccessible
    public virtual void afterUpdate() {
        return;
    }

    @NamespaceAccessible
    public virtual void beforeDelete() {
        return;
    }

    @NamespaceAccessible
    public virtual void afterDelete() {
        return;
    }

    @NamespaceAccessible
    public virtual void afterUndelete() {
        return;
    }

    /**
     * The records in front of this handler. Identical to `Trigger.new` and its companions inside
     * a trigger, and equal to the test overrides outside one, so the same handler body works in
     * both places.
     */
    @NamespaceAccessible
    public List<SObject> newRecords() {
        return useTestOverrides() && testNew != null ? testNew : Trigger.new;
    }

    @NamespaceAccessible
    public Map<Id, SObject> newRecordsById() {
        return useTestOverrides() && testNewMap != null ? testNewMap : Trigger.newMap;
    }

    @NamespaceAccessible
    public List<SObject> oldRecords() {
        return useTestOverrides() && testOld != null ? testOld : Trigger.old;
    }

    @NamespaceAccessible
    public Map<Id, SObject> oldRecordsById() {
        return useTestOverrides() && testOldMap != null ? testOldMap : Trigger.oldMap;
    }

    /**
     * The overrides stand in for a trigger only where there is none. A handler a test drives
     * directly can save records, and the triggers that save fires are real: were the overrides
     * read there too, a contact trigger would be handed the affiliations the test put in front of
     * the first handler, and fail on them.
     */
    private static Boolean useTestOverrides() {
        return !Trigger.isExecuting;
    }

    /**
     * Records a failure in the Error Log (R-E1) and puts the given message on every record
     * that does not already carry one: a record already refused with a message that tells the
     * person what to change keeps it, and a second message would bury it.
     */
    protected void reportFailure(
        Exception thrown,
        List<SObject> records,
        String context,
        String message
    ) {
        ErrorLogger.log(thrown, context);
        if (records == null) {
            return;
        }
        for (SObject record : records) {
            if (!record.hasErrors()) {
                record.addError(message);
            }
        }
    }

    /**
     * The stable name of this automation, matching its Automation Setting row and its entry in
     * the shipped registry. A handler may override it; by default it is the class name.
     *
     * The namespace is stripped. Inside a managed package the class reports itself as
     * `Namespace.ContactTriggerHandler`, while every consumer of this value (the automation row,
     * the bypass, the recursion guard) keys on the bare name the registry ships.
     */
    @NamespaceAccessible
    public virtual String getName() {
        String qualifiedName = String.valueOf(this).substringBefore(':');
        return qualifiedName.contains('.') ? qualifiedName.substringAfterLast('.') : qualifiedName;
    }

    /**
     * Claims records for a phase and returns the ones this handler has not seen yet in this
     * transaction.
     *
     * The guard is per record, not per phase, and that matters: one DML of 400 records fires the
     * trigger twice in the same transaction with statics preserved, so a guard that claimed the
     * whole phase would let a handler process the first 200 records and silently skip the rest
     * (plan Principle 2). Records already claimed come back out of the set, everything else is
     * claimed and returned.
     *
     * Claims reset when a partial save (allOrNone false) is retried: `noteTriggerProgress` clears
     * every claim of the transaction, not only the rolled-back attempt's. Do not rely on a claim
     * to stop a workflow or flow re-fire across a partial save.
     */
    @NamespaceAccessible
    public Set<Id> claimRunFor(String phase, Set<Id> recordIds) {
        Set<Id> unclaimed = new Set<Id>();
        if (recordIds == null || recordIds.isEmpty()) {
            return unclaimed;
        }
        Set<Id> claimed = claimedFor(phase);
        for (Id recordId : recordIds) {
            if (recordId != null && !claimed.contains(recordId)) {
                unclaimed.add(recordId);
            }
        }
        claimed.addAll(unclaimed);
        return unclaimed;
    }

    /**
     * Clears every claim. Used by tests and by bulk operations that deliberately re-run a
     * handler in the same transaction.
     */
    @NamespaceAccessible
    public static void clearRunClaims() {
        CLAIMED_RECORDS.clear();
    }

    /** Queries plus DML statements spent when a trigger last started or ended. */
    private static Integer workAtLastTrigger = 0;

    /**
     * Called by the dispatcher as each trigger starts and ends. A partial save (allOrNone false,
     * as the Bulk API, Data Loader and `Database.delete(records, false)` save) whose records
     * partly fail is rolled back and its triggers run again for the records that passed, with
     * static variables kept, so the claims of the rolled-back attempt would make the retry skip
     * every record: what a handler did for them went with the rollback. The platform puts
     * governor limits back where they were before the attempt, so less work counted than when
     * the last trigger ended means a rollback, and the claims are cleared. A test's startTest and
     * stopTest move the count too, which only clears claims a test would clear itself.
     */
    public static void noteTriggerProgress() {
        Integer work = Limits.getQueries() + Limits.getDmlStatements();
        if (work < workAtLastTrigger) {
            CLAIMED_RECORDS.clear();
        }
        workAtLastTrigger = work;
    }

    private Set<Id> claimedFor(String phase) {
        String key = phaseKey(phase);
        if (!CLAIMED_RECORDS.containsKey(key)) {
            CLAIMED_RECORDS.put(key, new Set<Id>());
        }
        return CLAIMED_RECORDS.get(key);
    }

    private String phaseKey(String phase) {
        return getName() + '.' + (phase == null ? '' : phase);
    }
}
