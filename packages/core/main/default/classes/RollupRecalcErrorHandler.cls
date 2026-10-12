/**
 * Puts the records of a full recalculation chunk the platform stopped into the Rollup Queue
 * (canonical model R-R14, `decisions/0082-barncrm-owns-its-rollup-engine.md`).
 *
 * `RollupFullRecalcBatch` catches what it can, but a governor limit ends a chunk with nothing
 * caught and nothing saved. A `System.Finalizer` cannot be attached to a batch job, so the batch
 * raises `BatchApexErrorEvent` instead (`Database.RaisesPlatformEvents`), and this handler, run
 * by its trigger, hands the chunk's record Ids to the queue, whose processor recalculates them in
 * slices within minutes and retries with its own finalizer and backoff. Without it those records
 * would wait for the next night.
 *
 * Only events from the full recalculation's own jobs, in their execute phase, are read: every
 * batch class in the org that raises platform events publishes to the same channel.
 *
 * Not routed through `TriggerDispatcher`, like `ErrorLogEventTrigger`: this is the engine's own
 * bookkeeping. The engine's pause still applies, because the queue starts no processor while
 * automation is paused (R-RQ5).
 *
 * DOCUMENTED EXCEPTION to user mode reads (plan Section 4.13, ADR-0021, as in `RollupQueue`): the
 * job is read and the queue written in system mode, because the event runs as the Automated
 * Process user.
 */
public without sharing class RollupRecalcErrorHandler {
    private static final String LOG_CONTEXT = 'RollupRecalcErrorHandler';
    private static final String EXECUTE_PHASE = 'EXECUTE';
    private static final String SEPARATOR = ',';

    /**
     * Queues the records of every stopped full recalculation chunk among these events.
     *
     * @param events the events the trigger received
     */
    public static void handle(List<BatchApexErrorEvent> events) {
        Set<Id> jobIds = new Set<Id>();
        for (BatchApexErrorEvent event : events) {
            if (event.AsyncApexJobId != null && event.Phase == EXECUTE_PHASE) {
                jobIds.add(event.AsyncApexJobId);
            }
        }
        if (jobIds.isEmpty()) {
            return;
        }
        Set<Id> ours = new Map<Id, AsyncApexJob>(
                [
                    SELECT Id
                    FROM AsyncApexJob
                    WHERE Id IN :jobIds AND ApexClass.Name = :RollupFullRecalcBatch.CLASS_NAME
                    WITH SYSTEM_MODE
                ]
            )
            .keySet();
        Map<String, Set<Id>> idsByTarget = new Map<String, Set<Id>>();
        Integer queued = 0;
        for (BatchApexErrorEvent event : events) {
            if (!ours.contains(event.AsyncApexJobId) || event.Phase != EXECUTE_PHASE) {
                continue;
            }
            for (Id recordId : idsIn(event.JobScope)) {
                String target = String.valueOf(recordId.getSObjectType());
                if (!idsByTarget.containsKey(target)) {
                    idsByTarget.put(target, new Set<Id>());
                }
                if (idsByTarget.get(target).add(recordId)) {
                    queued++;
                }
            }
        }
        if (queued == 0) {
            return;
        }
        RollupQueue.add(idsByTarget);
        ErrorLogger.logMessage(
            String.format(
                System.Label.Core_Rollups_FullRunChunkQueued,
                new List<String>{ String.valueOf(queued) }
            ),
            LOG_CONTEXT,
            ErrorLogger.SEVERITY_WARNING
        );
    }

    /** The record Ids in an event's job scope; anything that is not an Id is skipped. */
    private static List<Id> idsIn(String jobScope) {
        List<Id> ids = new List<Id>();
        if (String.isBlank(jobScope)) {
            return ids;
        }
        for (String part : jobScope.split(SEPARATOR)) {
            try {
                ids.add(Id.valueOf(part.trim()));
            } catch (StringException notAnId) {
                continue;
            }
        }
        return ids;
    }
}
