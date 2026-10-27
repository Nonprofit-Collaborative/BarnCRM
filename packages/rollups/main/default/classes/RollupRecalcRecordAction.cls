/**
 * The "Recalculate totals on this record" Flow action (canonical model Section 14, R-R12 note,
 * ADR-0136): recalculates the totals a record carries, every active rollup on its object or only
 * the one named, for a screen flow button, a scheduled flow or any flow that knows the record
 * rather than what changed under it. `RollupService.recalculateTargets` does the work, now when
 * the transaction has room and queued otherwise.
 *
 * The Flow runs one interview per record and hands them to this action together, so a bulk
 * call is still one recalculation, or one queue write, per object.
 *
 * Global, with its request: in a managed package only a global invocable action appears in a
 * subscriber's Flow Builder. Global is permanent once a managed version is released: the class,
 * `Request`, its two variables and `recalculate` can then never be removed or change signature.
 */
global with sharing class RollupRecalcRecordAction {
    /** One record whose totals to recalculate. */
    global class Request {
        @InvocableVariable(
            label='Record ID'
            description='The record that shows the totals, for example a household or a contact.'
            required=true
        )
        global Id recordId;

        @InvocableVariable(
            label='Rollup (optional)'
            description='The Definition Key or name of one rollup to recalculate. Leave empty to recalculate every active rollup on the record.'
        )
        global String rollup;
    }

    /**
     * Recalculates, or queues, the totals on these records. A rollup name that matches no
     * active rollup on a record's object is written to the Error Log; the flow is never failed.
     *
     * @param requests one per record, of any objects
     */
    @InvocableMethod(
        label='Recalculate totals on this record'
        description='Recalculates the BarnCRM rollup totals on a record: every active rollup on its object, or the one you name.'
        category='BarnCRM'
    )
    global static void recalculate(List<Request> requests) {
        Map<String, Set<Id>> idsByRollup = new Map<String, Set<Id>>();
        for (Request request : requests == null ? new List<Request>() : requests) {
            if (request == null || request.recordId == null) {
                continue;
            }
            String rollup = String.isBlank(request.rollup) ? '' : request.rollup.trim();
            if (!idsByRollup.containsKey(rollup)) {
                idsByRollup.put(rollup, new Set<Id>());
            }
            idsByRollup.get(rollup).add(request.recordId);
        }
        for (String rollup : idsByRollup.keySet()) {
            try {
                Set<Id> recordIds = idsByRollup.get(rollup);
                Set<String> recalculated = RollupService.recalculateTargets(recordIds, rollup);
                if (String.isNotBlank(rollup) && recalculated.isEmpty()) {
                    ErrorLogger.logMessage(
                        String.format(
                            System.Label.Core_Rollups_ErrorNoRollupNamed,
                            new List<String>{ rollup }
                        ),
                        'RollupRecalcRecordAction',
                        ErrorLogger.SEVERITY_WARNING
                    );
                }
            } catch (Exception failed) {
                ErrorLogger.log(failed, 'RollupRecalcRecordAction');
            }
        }
    }
}
