/**
 * The "Recalculate rollups" Flow action: real time for an administrator's own entity, which
 * BarnCRM ships no trigger for (canonical model R-R12, rollup proposal slice S10).
 *
 * A record-triggered Flow copied from `Recalculate_Rollups_Template` passes the saved record and
 * its prior values. The action works out which totals the save changed exactly as a packaged
 * trigger does (`RollupService.runForFlow`, R-R11), so every rollup that counts the entity is
 * kept current by one flow. The record is generic, so one action serves every entity; the Flow
 * Builder asks for the entity when the action is placed.
 *
 * The Flow runs one interview per record, and the platform hands the interviews of one save to
 * this action together, so a bulk save is still one call here, recalculated or queued as one.
 */
public with sharing class RollupRecalcAction {
    /** One record a Flow saw change. */
    public class Request {
        @InvocableVariable(
            label='Record'
            description='The record that was created, updated or is being deleted.'
            required=true
        )
        public SObject record;

        @InvocableVariable(
            label='Record before the change'
            description='The record as it was before an update, so a record moved to another parent leaves the old total. Leave empty for a new record.'
        )
        public SObject priorRecord;

        @InvocableVariable(
            label='Record is being deleted'
            description='True in a flow that starts when a record is deleted. Its totals are recalculated once the delete is done.'
        )
        public Boolean deleting;
    }

    /**
     * Recalculates, or queues, the totals these saves changed.
     *
     * @param requests one per record, of any entities
     */
    @InvocableMethod(
        label='Recalculate rollups'
        description='Keeps every BarnCRM rollup that counts this record up to date. Use it in a record-triggered flow on an object BarnCRM does not update by itself.'
        category='BarnCRM'
    )
    public static void recalculate(List<Request> requests) {
        Map<String, Batch> batches = new Map<String, Batch>();
        for (Request request : requests == null ? new List<Request>() : requests) {
            if (request == null || request.record == null) {
                continue;
            }
            String entity = String.valueOf(request.record.getSObjectType());
            Boolean deleting = request.deleting == true;
            String key = entity + '|' + deleting;
            if (!batches.containsKey(key)) {
                batches.put(key, new Batch(entity, deleting));
            }
            batches.get(key).add(request);
        }
        for (Batch batch : batches.values()) {
            try {
                RollupService.runForFlow(
                    batch.entity,
                    batch.records,
                    batch.priorById.isEmpty() ? null : batch.priorById,
                    batch.deleting
                );
            } catch (Exception failed) {
                // As for every rollup: never fail the administrator's save; the nightly run in
                // Both mode puts it right.
                ErrorLogger.log(failed, 'RollupRecalcAction');
            }
        }
    }

    /** The records of one entity, saved or being deleted, with their prior values. */
    private class Batch {
        final String entity;
        final Boolean deleting;
        final List<SObject> records = new List<SObject>();
        final Map<Id, SObject> priorById = new Map<Id, SObject>();

        Batch(String entity, Boolean deleting) {
            this.entity = entity;
            this.deleting = deleting;
        }

        void add(Request request) {
            this.records.add(request.record);
            if (request.priorRecord != null && request.record.Id != null) {
                this.priorById.put(request.record.Id, request.priorRecord);
            }
        }
    }
}
