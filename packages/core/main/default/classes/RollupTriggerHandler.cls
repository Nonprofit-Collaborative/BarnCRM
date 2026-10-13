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
 */
public with sharing class RollupTriggerHandler extends TriggerHandler {
    private static final String CONTEXT = 'RollupTriggerHandler';

    public override void afterInsert() {
        run(newRecords(), null);
    }

    public override void afterUpdate() {
        run(newRecords(), oldRecordsById());
    }

    public override void beforeDelete() {
        run(oldRecords(), null);
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
        run(newRecords(), null);
    }

    /**
     * Hands the records to the engine once per transaction per record, so a rollup that causes its
     * own source object to be updated again does not run twice over the same rows.
     */
    private void run(List<SObject> records, Map<Id, SObject> oldRecords) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            Set<Id> recordIds = new Set<Id>();
            for (SObject record : records) {
                if (record.Id != null) {
                    recordIds.add(record.Id);
                }
            }
            Set<Id> unclaimed = claimRunFor('rollup', recordIds);
            if (unclaimed.isEmpty()) {
                return;
            }
            List<SObject> toRun = new List<SObject>();
            for (SObject record : records) {
                if (unclaimed.contains(record.Id)) {
                    toRun.add(record);
                }
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
