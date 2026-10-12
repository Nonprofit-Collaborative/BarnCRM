/**
 * Base class for every packaged trigger handler.
 *
 * A handler subclasses this, overrides only the contexts it cares about, and is invoked by
 * `TriggerDispatcher`. Nothing else calls a handler directly, so every packaged automation is
 * bypassable and pausable (plan Section 7.2, canonical model rule R-A1).
 *
 * THE CONTRACT. Every context method takes no arguments, and a handler body reads the records
 * from the trigger context itself: `Trigger.new`, `Trigger.old`, `Trigger.newMap`,
 * `Trigger.oldMap`. That is what every feature module is written against, so it is fixed here.
 *
 *     public class ContactTriggerHandler extends TriggerHandler {
 *         public override void beforeInsert() {
 *             for (Contact person : (List<Contact>) Trigger.new) {
 *                 person.Description = 'Seen by BarnCRM';
 *             }
 *         }
 *     }
 *
 * Outside a trigger there is no `Trigger.new` to read, so a unit test that wants to drive a
 * handler without inserting records sets the `testNew`, `testNewMap`, `testOld`, and `testOldMap`
 * overrides below and has the handler read them through `newRecords()`, `newRecordsById()`,
 * `oldRecords()`, and `oldRecordsById()`, which return the override when there is one and the
 * trigger collection otherwise.
 *
 * The recursion guard is per transaction, per handler, per phase, and per record: `claimRunFor`
 * takes the record ids in front of it and hands back the ones this handler has not already
 * processed, so a handler that causes its own object to be updated again does its work once per
 * record while a 400 record load still gets all 400 processed.
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

    @NamespaceAccessible
    public Boolean hasRunFor(String phase, Id recordId) {
        return recordId != null && claimedFor(phase).contains(recordId);
    }

    /**
     * Forgets what this handler has claimed for a phase, for the rare operation that means to run
     * it again over the same records in one transaction.
     */
    @NamespaceAccessible
    public void releaseRunFor(String phase) {
        CLAIMED_RECORDS.remove(phaseKey(phase));
    }

    /**
     * Clears every claim. Used by tests and by bulk operations that deliberately re-run a
     * handler in the same transaction.
     */
    @NamespaceAccessible
    public static void clearRunClaims() {
        CLAIMED_RECORDS.clear();
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
