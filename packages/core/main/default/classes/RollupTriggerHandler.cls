/**
 * Real-time rollups, on whichever entity the trigger that invoked this handler is for.
 *
 * One handler serves every source entity, because a rollup's source is configuration, not code:
 * a package registers this class against its object in `Automation_Registry__mdt` and its rollups
 * become real time, without Core naming that object anywhere (R-R7, ADR-0014).
 *
 * Core registers it against Contact and Household Member. That is not decoration: in contact mode
 * a household total reaches its household through the contact, so a person who moves household
 * has to mark both households for recalculation (R-R11). In junction mode the membership row is
 * the reparenting event, so the same is true there.
 *
 * The recursion guard is kept per event, never shared between events, and an update is not
 * guarded at all. A save often updates the record it is saving: a gift on a pledge is inserted,
 * and a handler earlier in the same save links it to its installment with a nested update. A
 * guard shared by every event let that nested update claim the gift first, so the insert, the
 * event that moves the donor, household, appeal and pledge totals, was skipped (rollup review
 * ROLLUPS-1). Every update carries its own `Trigger.old`, `RollupChanges` marks nothing when no
 * field a rollup reads changed, and recalculation recomputes (ADR-0082), so running each update
 * is never wrong and costs nothing when nothing a rollup reads moved.
 */
public with sharing class RollupTriggerHandler extends TriggerHandler {
    private static final String CONTEXT = 'RollupTriggerHandler';

    /** One claim per event: each event of a record runs once per transaction. */
    private static final String PHASE_INSERT = 'rollup.afterInsert';
    private static final String PHASE_DELETE = 'rollup.beforeDelete';
    private static final String PHASE_UNDELETE = 'rollup.afterUndelete';

    public override void afterInsert() {
        run(PHASE_INSERT, newRecords(), null);
    }

    /** Not claimed: every update of a record is its own change (see the class comment). */
    public override void afterUpdate() {
        run(null, newRecords(), oldRecordsById());
    }

    public override void beforeDelete() {
        run(PHASE_DELETE, oldRecords(), null);
    }

    /**
     * After a delete, the totals the deleted records counted towards no longer include them
     * (`RollupService.runAfterDelete`; `beforeDelete` collected the rows the platform deletes
     * with them). A merge: the records deleted with `MasterRecordId` filled name the survivors,
     * whose totals are recalculated so they include what the merge moved onto them.
     */
    public override void afterDelete() {
        List<SObject> deleted = oldRecords();
        List<SObject> merged = new List<SObject>();
        for (SObject record : deleted == null ? new List<SObject>() : deleted) {
            if (record.getPopulatedFieldsAsMap().get('MasterRecordId') != null) {
                merged.add(record);
            }
        }
        try {
            if (deleted != null && !deleted.isEmpty()) {
                RollupService.runAfterDelete(objectNameOf(deleted), deleted);
            }
            if (merged.isEmpty()) {
                return;
            }
            RollupService.runAfterMerge(objectNameOf(merged), merged);
        } catch (Exception failed) {
            // As for every rollup: never fail the save, and the nightly run puts it right.
            ErrorLogger.log(failed, CONTEXT);
        }
    }

    public override void afterUndelete() {
        run(PHASE_UNDELETE, newRecords(), null);
    }

    /**
     * Hands the records to the engine. With a phase, once per record per transaction for that
     * event, so the second 200 of a 400 record load still run while a repeat of the same event
     * does not; without one (an update), every time.
     */
    private void run(String phase, List<SObject> records, Map<Id, SObject> oldRecords) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            List<SObject> toRun = records;
            if (phase != null) {
                Set<Id> recordIds = new Set<Id>();
                for (SObject record : records) {
                    if (record.Id != null) {
                        recordIds.add(record.Id);
                    }
                }
                Set<Id> unclaimed = claimRunFor(phase, recordIds);
                toRun = new List<SObject>();
                for (SObject record : records) {
                    if (unclaimed.contains(record.Id)) {
                        toRun.add(record);
                    }
                }
            }
            if (toRun.isEmpty()) {
                return;
            }
            RollupService.runRealTime(objectNameOf(toRun), toRun, oldRecords);
        } catch (Exception failed) {
            // A rollup must never fail an administrator's save. The failure is logged and the
            // nightly reconciliation puts the number right (R-R4).
            ErrorLogger.log(failed, CONTEXT);
        }
    }

    private String objectNameOf(List<SObject> records) {
        if (records.isEmpty()) {
            return null;
        }
        return String.valueOf(records[0].getSObjectType());
    }
}
