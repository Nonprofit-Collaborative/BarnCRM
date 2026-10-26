/**
 * The Rollup Builder's Apex entry point for developers, the counterpart of DLRS's
 * `RollupService` (canonical model Section 14, R-R12 note, ADR-0136). Two calls:
 *
 * - `recalculate`: the totals on these records, every active rollup on their objects, as the
 *   Recalculate totals on this record Flow action does.
 * - `recalculateChanges`: the totals that changed source records affect, as a packaged trigger
 *   and the Recalculate rollups Flow action do (`RollupService.runForFlow`, R-R11), for code that
 *   saves records of an object BarnCRM ships no trigger for.
 *
 * Both recalculate in the same transaction when it has room and queue otherwise (R-R4), and
 * never throw for a total: a failure is written to the Error Log and the nightly run puts it
 * right, so a caller's save is never failed by its totals.
 *
 * Global is permanent once a managed version is released: the class and both methods can then
 * never be removed or change signature, so nothing more is added here without an ADR.
 */
global with sharing class RollupApi {
    private static final String CONTEXT = 'RollupApi';

    /**
     * Recalculates the totals on these records: every active rollup on their objects, whatever
     * its mode. A Bypass Permission does not apply: this is a request for the totals, not a save.
     *
     * @param recordIds the records that show the totals, of any objects
     */
    global static void recalculate(Set<Id> recordIds) {
        try {
            RollupService.recalculateTargets(recordIds, null);
        } catch (Exception failed) {
            ErrorLogger.log(failed, CONTEXT);
        }
    }

    /**
     * Recalculates the totals that a save of these records changed, for every active rollup in
     * Instantly or Both mode that counts them. Call it after the records are saved, or before
     * they are deleted with `deleting` true (their totals are then queued for after the delete).
     * Rollups whose Bypass Permission the running user holds are left out (R-R4a).
     *
     * @param records the saved records, or the records being deleted, of any objects
     * @param oldRecords the same records before an update, by Id, or null for new records
     * @param deleting true when the records are being deleted
     */
    global static void recalculateChanges(
        List<SObject> records,
        Map<Id, SObject> oldRecords,
        Boolean deleting
    ) {
        Map<Schema.SObjectType, List<SObject>> recordsByType = new Map<Schema.SObjectType, List<SObject>>();
        for (SObject record : records == null ? new List<SObject>() : records) {
            if (record == null) {
                continue;
            }
            Schema.SObjectType type = record.getSObjectType();
            if (!recordsByType.containsKey(type)) {
                recordsByType.put(type, new List<SObject>());
            }
            recordsByType.get(type).add(record);
        }
        for (Schema.SObjectType type : recordsByType.keySet()) {
            try {
                RollupService.runForFlow(
                    String.valueOf(type),
                    recordsByType.get(type),
                    oldRecords == null || oldRecords.isEmpty() ? null : oldRecords,
                    deleting == true
                );
            } catch (Exception failed) {
                ErrorLogger.log(failed, CONTEXT);
            }
        }
    }
}
