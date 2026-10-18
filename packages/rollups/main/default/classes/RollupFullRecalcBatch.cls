/**
 * The full recalculation of BarnCRM's own rollup engine: the nightly run, Recalculate and
 * Recalculate all (rollup proposal, Part 2 section 4, "Full recalculation" and "Skew";
 * `decisions/0082-barncrm-owns-its-rollup-engine.md` decisions 5 and 6).
 *
 * One pass per target entity, in turn. A pass is a batch over every record of the entity in Id
 * order, and each chunk recalculates every definition that writes the entity together through
 * `RollupEngine`: a few aggregate queries, one write per record, only where a value changed, with
 * `Rollups_Last_Calculated__c` in the same write (R-R11, R-R13). When the last pass finishes,
 * every definition that ran everywhere is marked calculated, so the Rollups page never shows a
 * time before the totals are on the records (R-R13, bug 5).
 *
 * Chunk size follows the data. Each record's expected source rows are estimated from the counts
 * the last run stored on it (the largest total of every active COUNT on its entity, as
 * `RollupLargeParentBatch.estimate` does) times the source queries the pass runs. A chunk
 * takes records until the estimate reaches `rowBudget`, and holds the rest back for a follow-up
 * pass over just those records with a quarter of the chunk size. A record that has no COUNT
 * total to go by is estimated at one row.
 *
 * Large parents (R-RQ6): an aggregate query counts every row it aggregates towards the 50,000 a
 * transaction may read, so a record with tens of thousands of source rows cannot be calculated
 * in any chunk, even alone (the tier 1 scale test's fund of 30,000 allocations stopped its chunk
 * on "Too many query rows: 50001" every run). A record estimated at
 * `RollupLargeParentBatch.largeParentRows` or more goes to the Rollup Queue, which hands it to the
 * large parent batch. A stale count can still make a record look small, so each chunk's
 * recalculation runs under the queue's row ceiling: before a further query would pass it, the
 * recalculation stops with nothing written, and the chunk's records are held back for a pass
 * with smaller chunks, or, one record alone, go the large parent way too.
 *
 * Locks and failures: no `FOR UPDATE`; writes in Id order with partial success (`RollupWriter`);
 * a record the platform refused goes to the Rollup Queue to be tried again, Failed after five
 * attempts; a chunk that stopped on something it could not catch leaves its entity's definitions
 * unmarked and is counted in one Error Log summary per run (R-RQ4), and the platform's
 * `BatchApexErrorEvent` for it hands the chunk's records to the Rollup Queue
 * (`RollupRecalcErrorHandler`, R-R14). A run that saves a record a Failed queue entry holds takes
 * the entry off the list (R-RQ4).
 *
 * One full run at a time (R-R14): a start while another run is going starts nothing and answers
 * the running job.
 *
 * DOCUMENTED EXCEPTION to user mode reads (plan Section 4.13, ADR-0021, as in `RollupAggregator`
 * and `RollupQueue`): every record of a target entity is read and the queue is written in system
 * mode and without sharing, because a total must not depend on who scheduled the run.
 */
public without sharing class RollupFullRecalcBatch implements Database.Batchable<SObject>, Database.Stateful, Database.RaisesPlatformEvents {
    private static final String LOG_CONTEXT = 'RollupFullRecalcBatch';
    /** The class name the platform records on each pass's job, read by the error handler. */
    public static final String CLASS_NAME = 'RollupFullRecalcBatch';
    private static final Set<String> RUNNING = new Set<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };

    /** The largest chunk the platform gives a batch over a query. */
    private static final Integer LARGEST_SCOPE = 2000;

    /** How much smaller each follow-up pass's chunks are. */
    private static final Integer SHRINK_BY = 4;

    /**
     * Source rows a chunk may expect to read: the platform allows 50,000 per transaction, and the
     * rest is left for the stored values, target filters and automation on the records saved.
     */
    @TestVisible
    private static Integer rowBudget = 30000;

    /** Records held back for a follow-up pass at most; any more go to the Rollup Queue. */
    @TestVisible
    private static Integer holdBackLimit = 10000;

    /** Records the run remembers as refused at most, to clear Failed queue entries (R-RQ4). */
    private static final Integer FAILED_IDS_LIMIT = 10000;

    /**
     * The runs this transaction started. A test sees only these as running: the org a test runs
     * in may have its own nightly run going, which a test can neither see past nor stop.
     */
    private static Set<Id> startedHere = new Set<Id>();

    /** Thrown by a chunk a test asks to stop, as a governor limit would stop it. */
    @TestVisible
    private class ChunkStoppedException extends Exception {
    }

    /** Set by a test to stop the next chunk with an error the run does not catch. */
    @TestVisible
    private static Boolean stopNextChunk = false;

    /** One target entity: the definitions planned for it, and what estimates a record's weight. */
    @TestVisible
    private class Target {
        public String name;
        public List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>();
        /** The COUNT totals stored on the entity, which say how many rows the last run counted. */
        public List<String> countFields = new List<String>();
        public Integer queries = 1;
        public Boolean stopped = false;
    }

    /** What the whole run has done, carried from pass to pass. */
    @TestVisible
    private class Run {
        public List<Target> targets = new List<Target>();
        public Datetime startedAt = Datetime.now();
        public Integer written = 0;
        public Integer failed = 0;
        public Integer stoppedChunks = 0;
        public Set<Id> refused = new Set<Id>();
        public Set<Id> failedIds = new Set<Id>();
        public Boolean failedIdsComplete = true;
        /** Who started the run from a page, told when it ends; null for the nightly run (Q-04). */
        public Id notifyUserId = JobNotifier.starter();
    }

    @TestVisible
    private final Run run;
    private final Integer targetIndex;
    /** The records of a follow-up pass, or null for every record of the entity. */
    private final Set<Id> onlyIds;
    @TestVisible
    private final Integer scope;
    /** Records that did not fit a chunk's budget, for a follow-up pass. */
    @TestVisible
    private Set<Id> later = new Set<Id>();
    /** Records this pass sent to the large parent route, for tests to read. */
    @TestVisible
    private Set<Id> large = new Set<Id>();

    private RollupFullRecalcBatch(Run run, Integer targetIndex, Set<Id> onlyIds, Integer scope) {
        this.run = run;
        this.targetIndex = targetIndex;
        this.onlyIds = onlyIds;
        this.scope = Math.max(1, scope);
    }

    // --------------------------------------------------------------------------------- starting

    /**
     * Starts a full recalculation of these definitions over every record they write. Does nothing
     * while the module is turned off (ADR-0125 decision 9; Turn on recalculates every rollup)
     * or all automation is paused (R-RQ5; the next run catches up), and an Info entry says so.
     * Starts nothing while another full run is going (R-R14): that run's job is answered and an
     * Info entry says so.
     *
     * @param definitions the definitions to recalculate, of any target entities
     * @return the first pass's job, the running job, or null when nothing started
     */
    public static Id begin(List<Rollup_Definition__c> definitions) {
        if (RollupService.isTurnedOff()) {
            ErrorLogger.logMessage(
                System.Label.Core_Rollups_FullRunTurnedOff,
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_INFO
            );
            return null;
        }
        if (AutomationControl.isPaused()) {
            ErrorLogger.logMessage(
                System.Label.Core_Rollups_FullRunPaused,
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_INFO
            );
            return null;
        }
        Id running = runningJobId();
        if (running != null) {
            ErrorLogger.logMessage(
                String.format(
                    System.Label.Core_Rollups_FullRunAlreadyRunningLog,
                    new List<String>{ String.valueOf(running) }
                ),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_INFO
            );
            return running;
        }
        RollupFullRecalcBatch first = firstPass(definitions);
        if (first == null) {
            return null;
        }
        Id started = Database.executeBatch(first, first.scope);
        startedHere.add(started);
        return started;
    }

    /**
     * The job of the full run going now, or null when none is (R-R14). Between two passes of a
     * run the finishing pass is still Processing when it starts the next, so a run in progress
     * always has a job in one of the running states.
     */
    public static Id runningJobId() {
        for (AsyncApexJob job : [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex' AND ApexClass.Name = :CLASS_NAME AND Status IN :RUNNING
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 50
        ]) {
            if (!Test.isRunningTest() || startedHere.contains(job.Id)) {
                return job.Id;
            }
        }
        return null;
    }

    /**
     * The first pass of a run, planned once: a definition that cannot be planned is logged once
     * here, left out, and never marked calculated. Null when nothing can run.
     */
    @TestVisible
    private static RollupFullRecalcBatch firstPass(List<Rollup_Definition__c> definitions) {
        Map<String, List<Rollup_Definition__c>> byTarget = new Map<String, List<Rollup_Definition__c>>();
        for (
            Rollup_Definition__c definition : definitions == null
                ? new List<Rollup_Definition__c>()
                : definitions
        ) {
            Schema.SObjectType targetType = SettingsService.typeByName(definition.Target_Object__c);
            if (targetType == null) {
                continue;
            }
            String name = String.valueOf(targetType);
            if (!byTarget.containsKey(name)) {
                byTarget.put(name, new List<Rollup_Definition__c>());
            }
            byTarget.get(name).add(definition);
        }
        List<String> names = new List<String>(byTarget.keySet());
        names.sort();
        Run run = new Run();
        for (String name : names) {
            Target target = targetFor(name, byTarget.get(name));
            if (!target.definitions.isEmpty()) {
                run.targets.add(target);
            }
        }
        return run.targets.isEmpty() ? null : new RollupFullRecalcBatch(run, 0, null, firstScope());
    }

    private static Target targetFor(String name, List<Rollup_Definition__c> definitions) {
        Schema.SObjectType targetType = SettingsService.typeByName(name);
        RollupPlanner.Plan plan = RollupPlanner.plan(targetType, definitions);
        Target target = new Target();
        target.name = name;
        target.definitions.addAll(plan.definitions);
        target.queries = Math.max(1, plan.queries.size());
        // Every active COUNT on the entity, not only those planned: Recalculate on a fund's SUM
        // alone must still see the fund's 30,000 allocations (R-RQ6).
        target.countFields.addAll(RollupLargeParentBatch.storedCountFields(targetType));
        return target;
    }

    /** A test method runs one chunk only, so a test reads every record in one. */
    private static Integer firstScope() {
        return Test.isRunningTest() ? LARGEST_SCOPE : RollupEngine.RECORDS_PER_PASS;
    }

    // ------------------------------------------------------------------------------- one pass

    private Target currentTarget() {
        return this.run.targets[this.targetIndex];
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocatorWithBinds(query(), binds(), AccessLevel.SYSTEM_MODE);
    }

    private String query() {
        Set<String> columns = new Set<String>{ 'Id' };
        columns.addAll(currentTarget().countFields);
        return 'SELECT ' +
            String.join(new List<String>(columns), ', ') +
            ' FROM ' +
            currentTarget().name +
            (this.onlyIds == null ? '' : ' WHERE Id IN :onlyIds') +
            ' ORDER BY Id';
    }

    private Map<String, Object> binds() {
        return this.onlyIds == null
            ? new Map<String, Object>()
            : new Map<String, Object>{ 'onlyIds' => this.onlyIds };
    }

    /** Takes the records that fit this chunk's budget, holds back the rest, and recalculates. */
    public void execute(Database.BatchableContext context, List<SObject> records) {
        if (stopNextChunk) {
            stopNextChunk = false;
            throw new ChunkStoppedException(LOG_CONTEXT);
        }
        Target target = currentTarget();
        Set<Id> taken = new Set<Id>();
        Set<Id> overflow = new Set<Id>();
        Set<Id> large = new Set<Id>();
        Integer expected = 0;
        for (SObject record : records) {
            Integer weight = weightOf(record, target);
            if (weight >= RollupLargeParentBatch.largeParentRows()) {
                large.add(record.Id);
            } else if (!taken.isEmpty() && expected + weight > rowBudget) {
                holdBack(record.Id, overflow);
            } else {
                taken.add(record.Id);
                expected += weight;
            }
        }
        if (!overflow.isEmpty()) {
            RollupQueue.add(new Map<String, Set<Id>>{ target.name => overflow });
        }
        toLargeParentRoute(target, large);
        recalculate(target, taken);
    }

    /** Holds a record back for a follow-up pass, or, past the hold back limit, queues it. */
    private void holdBack(Id recordId, Set<Id> overflow) {
        if (this.later.size() < holdBackLimit) {
            this.later.add(recordId);
        } else {
            overflow.add(recordId);
        }
    }

    /**
     * R-RQ6: queues records too large for any chunk, naming the pass's definitions. The queue
     * estimates them as this pass did and hands them to `RollupLargeParentBatch`, which reads
     * their source rows in chunks; a stale count is caught by the queue's own row ceiling.
     */
    private void toLargeParentRoute(Target target, Set<Id> ids) {
        if (ids.isEmpty()) {
            return;
        }
        this.large.addAll(ids);
        Set<Id> definitionIds = new Set<Id>();
        for (Rollup_Definition__c definition : target.definitions) {
            if (definition.Id != null) {
                definitionIds.add(definition.Id);
            }
        }
        RollupQueue.add(
            new Map<String, Set<Id>>{ target.name => ids },
            definitionIds.isEmpty()
                ? null
                : new Map<String, Set<Id>>{ target.name => definitionIds }
        );
    }

    /** The source rows a record is expected to read: its largest stored count, per query. */
    private static Integer weightOf(SObject record, Target target) {
        Decimal largest = 1;
        for (String field : target.countFields) {
            Object counted = record.get(field);
            if (counted != null) {
                largest = Math.max(largest, RollupAggregator.toDecimal(counted));
            }
        }
        Decimal weight = largest * target.queries;
        return weight > 2000000000 ? 2000000000 : weight.intValue();
    }

    private void recalculate(Target target, Set<Id> ids) {
        if (ids.isEmpty()) {
            return;
        }
        Map<Id, String> refused;
        RollupAggregator.limitQueryRows(RollupLargeParentBatch.queueRowCeiling());
        try {
            RollupEngine.Result result = RollupEngine.recalculate(ids, target.definitions);
            this.run.written += result.written.size();
            for (Rollup_Definition__c definition : result.refused) {
                this.run.refused.add(definition.Id);
            }
            refused = result.failed;
        } catch (RollupAggregator.RowCeilingException tooLarge) {
            // R-RQ6: a stale count took a record as small, and the next query would have stopped
            // the chunk. Nothing was written: smaller chunks, or the large parent route alone.
            if (ids.size() == 1) {
                toLargeParentRoute(target, ids);
            } else {
                Set<Id> overflow = new Set<Id>();
                for (Id recordId : ids) {
                    holdBack(recordId, overflow);
                }
                if (!overflow.isEmpty()) {
                    RollupQueue.add(new Map<String, Set<Id>>{ target.name => overflow });
                }
            }
            return;
        } catch (Exception stopped) {
            // Nothing was written: the write is the engine's last step. The records wait in the
            // queue rather than until tomorrow night.
            ErrorLogger.log(stopped, LOG_CONTEXT);
            refused = new Map<Id, String>();
            for (Id recordId : ids) {
                refused.put(recordId, stopped.getMessage());
            }
        } finally {
            RollupAggregator.limitQueryRows(null);
        }
        if (refused.isEmpty()) {
            return;
        }
        RollupQueue.retryLater(target.name, refused, 0);
        this.run.failed += refused.size();
        if (this.run.failedIds.size() + refused.size() > FAILED_IDS_LIMIT) {
            this.run.failedIdsComplete = false;
        } else {
            this.run.failedIds.addAll(refused.keySet());
        }
    }

    /**
     * Follows up the held back records, then the next entity, then ends.
     * Chains nothing once the module is turned off (ADR-0125 decision 9): the run stops there,
     * unstamped, and Turn on recalculates every rollup.
     */
    public void finish(Database.BatchableContext context) {
        Integer stopped = stoppedChunks(context);
        if (stopped > 0) {
            this.run.stoppedChunks += stopped;
            currentTarget().stopped = true;
        }
        RollupFullRecalcBatch next = nextPass();
        if (next == null) {
            complete();
        } else if (RollupService.isTurnedOff()) {
            ErrorLogger.logMessage(
                System.Label.Core_Rollups_RunStoppedTurnedOff,
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_INFO
            );
        } else if (Test.isRunningTest()) {
            // A test cannot chain batch jobs, so the rest of the run happens here.
            next.runInline();
        } else {
            Database.executeBatch(next, next.scope);
        }
    }

    private RollupFullRecalcBatch nextPass() {
        if (!this.later.isEmpty()) {
            return new RollupFullRecalcBatch(
                this.run,
                this.targetIndex,
                this.later,
                this.scope / SHRINK_BY
            );
        }
        clearResolvedEntries(currentTarget());
        if (this.targetIndex + 1 < this.run.targets.size()) {
            return new RollupFullRecalcBatch(this.run, this.targetIndex + 1, null, firstScope());
        }
        return null;
    }

    /** What a pass does in a test: every chunk, then its finish, in this transaction. */
    @TestVisible
    private void runInline() {
        List<SObject> records = Database.queryWithBinds(
            query() + ' LIMIT ' + LARGEST_SCOPE * 5,
            binds(),
            AccessLevel.SYSTEM_MODE
        );
        for (Integer first = 0; first < records.size(); first += this.scope) {
            List<SObject> chunk = new List<SObject>();
            for (Integer i = first; i < Math.min(first + this.scope, records.size()); i++) {
                chunk.add(records[i]);
            }
            execute(null, chunk);
        }
        finish(null);
    }

    private static Integer stoppedChunks(Database.BatchableContext context) {
        if (context == null) {
            return 0;
        }
        Id jobId = context.getJobId();
        List<AsyncApexJob> jobs = [
            SELECT NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            WITH SYSTEM_MODE
        ];
        return jobs.isEmpty() || jobs[0].NumberOfErrors == null ? 0 : jobs[0].NumberOfErrors;
    }

    /**
     * R-RQ4: a Failed queue entry from before this run whose records this run saved, or found
     * already right, is done. Skipped when a chunk of the entity stopped or the run lost count of
     * the records it could not save, because then it cannot tell.
     */
    private void clearResolvedEntries(Target target) {
        if (target.stopped || !this.run.failedIdsComplete) {
            return;
        }
        List<Rollup_Queue__c> resolved = new List<Rollup_Queue__c>();
        for (Rollup_Queue__c entry : [
            SELECT Id, Record_Ids__c
            FROM Rollup_Queue__c
            WHERE
                Status__c = :RollupQueue.STATUS_FAILED
                AND Target_Object__c = :target.name
                AND LastModifiedDate < :this.run.startedAt
            WITH SYSTEM_MODE
            LIMIT 2000
        ]) {
            Set<Id> ids = new Set<Id>(RollupQueue.idsOf(entry));
            ids.retainAll(this.run.failedIds);
            if (ids.isEmpty()) {
                resolved.add(entry);
            }
        }
        Database.delete(resolved, false, AccessLevel.SYSTEM_MODE);
    }

    /** The end of the run: the definitions that ran everywhere are marked calculated now. */
    private void complete() {
        Datetime finishedAt = Datetime.now();
        Map<Id, Datetime> stamps = new Map<Id, Datetime>();
        for (Target target : this.run.targets) {
            for (Rollup_Definition__c definition : target.definitions) {
                if (
                    definition.Id != null &&
                    !target.stopped &&
                    !this.run.refused.contains(definition.Id)
                ) {
                    stamps.put(definition.Id, finishedAt);
                }
            }
        }
        try {
            RollupWriter.stampDefinitions(stamps);
        } catch (Exception notStamped) {
            // A definition deleted while the run was going; the totals are written either way.
            ErrorLogger.log(notStamped, LOG_CONTEXT);
        }
        if (this.run.failed > 0 || this.run.stoppedChunks > 0) {
            ErrorLogger.logMessage(
                String.format(
                    System.Label.Core_Rollups_FullRunSummary,
                    new List<String>{
                        String.valueOf(this.run.failed),
                        String.valueOf(this.run.stoppedChunks)
                    }
                ),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
        JobNotifier.aboutSettings(
            this.run.notifyUserId,
            System.Label.Core_JobNotice_Rollups,
            this.run.stoppedChunks > 0,
            String.format(
                System.Label.Core_JobNotice_RollupsBody,
                new List<Object>{
                    this.run.written.format(),
                    this.run.failed.format(),
                    this.run.stoppedChunks.format()
                }
            ),
            JobNotifier.SECTION_ROLLUPS
        );
    }

    // -------------------------------------------------------------------------------- progress

    /**
     * How the latest full recalculation is getting on, for the Rollup Builder to show (slices
     * S12 and S13). It describes the pass now running, or the last one: a run is one pass per
     * target entity, plus a short follow-up pass for the records held back.
     */
    public class Progress {
        public Id jobId;
        public Boolean running = false;
        public String status;
        public Integer chunksDone = 0;
        public Integer chunksTotal = 0;
        public Integer chunksStopped = 0;
        public Datetime startedAt;
        public Datetime finishedAt;
    }

    /** The latest pass's progress, or an empty answer when no run has ever started. */
    public static Progress progress() {
        Progress answer = new Progress();
        for (AsyncApexJob job : [
            SELECT
                Id,
                Status,
                JobItemsProcessed,
                TotalJobItems,
                NumberOfErrors,
                CreatedDate,
                CompletedDate
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex' AND ApexClass.Name = :CLASS_NAME
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ]) {
            answer.jobId = job.Id;
            answer.status = job.Status;
            answer.running = RUNNING.contains(job.Status);
            answer.chunksDone = job.JobItemsProcessed == null ? 0 : job.JobItemsProcessed;
            answer.chunksTotal = job.TotalJobItems == null ? 0 : job.TotalJobItems;
            answer.chunksStopped = job.NumberOfErrors == null ? 0 : job.NumberOfErrors;
            answer.startedAt = job.CreatedDate;
            answer.finishedAt = job.CompletedDate;
        }
        return answer;
    }
}
