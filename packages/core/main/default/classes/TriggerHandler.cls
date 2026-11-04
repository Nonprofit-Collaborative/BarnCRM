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
 * A handler never reads `Trigger.new` and its companions directly: when a handler fails, the
 * dispatcher runs the handlers again over part of the records to find which record the failure
 * belongs to, and only these accessors see that part (ADR-NEXT dispatcher error contract).
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
        Scope narrowed = currentScope();
        if (narrowed != null) {
            return narrowed.newRecords;
        }
        return useTestOverrides() && testNew != null ? testNew : Trigger.new;
    }

    @NamespaceAccessible
    public Map<Id, SObject> newRecordsById() {
        Scope narrowed = currentScope();
        if (narrowed != null) {
            return narrowed.newRecordsById;
        }
        return useTestOverrides() && testNewMap != null ? testNewMap : Trigger.newMap;
    }

    @NamespaceAccessible
    public List<SObject> oldRecords() {
        Scope narrowed = currentScope();
        if (narrowed != null) {
            return narrowed.oldRecords;
        }
        return useTestOverrides() && testOld != null ? testOld : Trigger.old;
    }

    @NamespaceAccessible
    public Map<Id, SObject> oldRecordsById() {
        Scope narrowed = currentScope();
        if (narrowed != null) {
            return narrowed.oldRecordsById;
        }
        return useTestOverrides() && testOldMap != null ? testOldMap : Trigger.oldMap;
    }

    /**
     * Part of a trigger's records, which the dispatcher hands its handlers while it finds out
     * which record a failure belongs to (ADR-NEXT dispatcher error contract). The four
     * accessors above return it in place of the trigger collections. This is why a handler
     * reads its records through them and never through `Trigger.new` itself: a handler that
     * did would be handed all the records again, and the failure could never be pinned on one.
     */
    @NamespaceAccessible
    public class Scope {
        public List<SObject> newRecords { get; private set; }
        public Map<Id, SObject> newRecordsById { get; private set; }
        public List<SObject> oldRecords { get; private set; }
        public Map<Id, SObject> oldRecordsById { get; private set; }

        @NamespaceAccessible
        public Scope(
            List<SObject> newRecords,
            Map<Id, SObject> newRecordsById,
            List<SObject> oldRecords,
            Map<Id, SObject> oldRecordsById
        ) {
            this.newRecords = newRecords;
            this.newRecordsById = newRecordsById;
            this.oldRecords = oldRecords;
            this.oldRecordsById = oldRecordsById;
        }
    }

    /**
     * One entry per dispatcher run under way, the innermost last: the part of the records that
     * run is narrowed to, or null for all of them. A save a handler makes fires its own trigger,
     * whose run pushes its own entry, so a narrowed run never narrows the records of another
     * trigger.
     */
    private static final List<Scope> SCOPES = new List<Scope>();

    /** Called by the dispatcher as a trigger run starts: its handlers see every record. */
    @NamespaceAccessible
    public static void enterRun() {
        SCOPES.add(null);
    }

    /** Called by the dispatcher as a trigger run ends, however it ends. */
    @NamespaceAccessible
    public static void leaveRun() {
        if (!SCOPES.isEmpty()) {
            SCOPES.remove(SCOPES.size() - 1);
        }
    }

    /** Narrows the run under way to part of its records, or back to all of them with null. */
    @NamespaceAccessible
    public static void narrowRun(Scope narrowed) {
        if (!SCOPES.isEmpty()) {
            SCOPES[SCOPES.size() - 1] = narrowed;
        }
    }

    private static Scope currentScope() {
        return SCOPES.isEmpty() ? null : SCOPES[SCOPES.size() - 1];
    }

    /**
     * Every claim, copied, so the dispatcher can put them back when it undoes a failed attempt:
     * the records that attempt claimed were never processed for good.
     */
    @NamespaceAccessible
    public static Map<String, Set<Id>> copyRunClaims() {
        Map<String, Set<Id>> copied = new Map<String, Set<Id>>();
        for (String key : CLAIMED_RECORDS.keySet()) {
            copied.put(key, CLAIMED_RECORDS.get(key).clone());
        }
        return copied;
    }

    /** Puts back the claims `copyRunClaims` copied. */
    @NamespaceAccessible
    public static void restoreRunClaims(Map<String, Set<Id>> copied) {
        CLAIMED_RECORDS.clear();
        if (copied != null) {
            for (String key : copied.keySet()) {
                CLAIMED_RECORDS.put(key, copied.get(key).clone());
            }
        }
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
     *
     * Namespace accessible for a module's own trigger entry point, which dispatches one handler
     * without a registry row and marks progress the same way (`RollupInstantTrigger`, ADR-0138).
     */
    @NamespaceAccessible
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
