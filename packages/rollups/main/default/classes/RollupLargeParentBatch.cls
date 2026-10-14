/**
 * The large parent route of the Rollup Queue (ADR-0116, canonical model R-RQ6): totals for target
 * records whose source rows are more than one background job may read.
 *
 * An aggregate query counts every row it aggregates towards the platform's 50,000 query rows a
 * transaction may read, and no catch stops that limit. A fund every gift is allocated to, or an
 * organization with tens of thousands of gifts, therefore cannot be recalculated in the Rollup
 * Queue's Queueable at all: on the tier 1 scale test the default fund's 28,739 allocations
 * stopped every run that held it. This batch reads the source rows of each planned query in
 * chunks instead, runs that query over each chunk's rows only (`RollupAggregator.calculateRows`),
 * and folds the partial answers together, which merge exactly as the alternatives of a path
 * already do (R-R1). When every query of an entity is read it writes the totals once, through
 * the same target filters, currency handling and write as any other recalculation
 * (`RollupEngine.writeCalculated`).
 *
 * The queue sends it two kinds of target record only: those whose stored COUNT totals say they
 * read at least `largeParentRows` (`estimate`), and a record that stopped a run of its own on the
 * query row limit. Any other failure stays with the queue, which narrows it down to the one
 * record that causes it (R-RQ3). The batch owns the entries it was given: they are charged one
 * attempt when it takes them (so a run that keeps dying still ends Failed after the fifth), held
 * with Next Attempt an hour ahead, renewed with every chunk, deleted when their totals are
 * written, and released to be tried again, with the reason, when a chunk stopped. The write
 * saves each record on its own (partial success), so one record the platform refuses never
 * stops the others; it is queued again as any refused save is.
 *
 * One run at a time (`lockRuns`): while one is going, the entries routed here wait two minutes
 * and are routed again, so a fund touched by every gift is not read by a pile of runs at once.
 *
 * DOCUMENTED EXCEPTION to user mode reads and writes (plan Section 4.13, ADR-0021, as in
 * `RollupQueue` and `RollupAggregator`): a total must not depend on who saved the gift.
 */
public without sharing class RollupLargeParentBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String CLASS_NAME = 'RollupLargeParentBatch';
    private static final String LOG_CONTEXT = CLASS_NAME;
    private static final Set<String> RUNNING = new Set<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };

    /** How long the entries a run holds wait before the queue may try them again. */
    @TestVisible
    private static final Integer LEASE_MINUTES = 60;

    /** How long entries routed here wait while another run is going. */
    @TestVisible
    private static final Integer BUSY_MINUTES = 2;

    /** Source rows one chunk reads: the most a batch over a query gives at once. */
    private static final Integer CHUNK_SIZE = 2000;

    /**
     * Test seam: the source rows above which a record is sent here; null means a fifth of the
     * rows a transaction may read, so the rest of a queue run's slice still fits beside it.
     */
    @TestVisible
    private static Integer largeParentRowsForTest;

    /** Test seam: stands in for the stopped chunks the platform counts on a pass. */
    @TestVisible
    private static Integer stoppedChunksForTest;

    /** Test seam: true stands in for a run already going. */
    @TestVisible
    private static Boolean runningForTest = false;

    /**
     * Source rows each query is taken to read per record when nothing stored says how many: a
     * full slice of such records then uses about half a run's row budget.
     */
    @TestVisible
    private static final Integer UNKNOWN_ROWS_PER_QUERY = 10;

    /** The runs this transaction started: a test sees only these as running. */
    private static Set<Id> startedHere = new Set<Id>();

    /** Whether the last call to `begin` started a run, for tests that cannot run it. */
    @TestVisible
    private static Boolean startedForTest = false;

    /** One target entity: its records, the definitions to run and the entries holding them. */
    @TestVisible
    private class Target {
        public String name;
        public Set<Id> parentIds = new Set<Id>();
        /** The definitions the entries name, or null when one names none: every definition. */
        public Set<Id> definitionIds = new Set<Id>();
        public List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>();
        public List<Rollup_Queue__c> entries = new List<Rollup_Queue__c>();
        public Integer attempts = 0;
        public String stoppedReason;
    }

    @TestVisible
    private final List<Target> targets;
    @TestVisible
    private Integer targetIndex = 0;
    @TestVisible
    private Integer queryIndex = 0;
    private RollupAggregator.Answer answer = new RollupAggregator.Answer();
    /** True when a test has the next pass to run itself. */
    @TestVisible
    private Boolean passWaiting = false;

    private RollupLargeParentBatch(List<Target> targets) {
        this.targets = targets;
    }

    // ---------------------------------------------------------------------------- the route

    /**
     * The source rows from which a record's totals are calculated here: two fifths of what a
     * transaction may read. A record below it fits a run on its own (the first record a run takes
     * always runs, within the run budget of three fifths), with the rest left for the queue's own
     * queries and the target records' triggers and flows, and for a filtered or stale COUNT that
     * makes the estimate low. A record at or above it comes here. An estimate that still falls
     * short is caught by the run's row ceiling (`queueRowCeiling`), or when the record stops a
     * run of its own (R-RQ6).
     */
    public static Integer largeParentRows() {
        return largeParentRowsForTest != null
            ? largeParentRowsForTest
            : Limits.getLimitQueryRows() * 2 / 5;
    }

    /** The source rows one queue run may expect to read across its whole slice. */
    public static Integer sliceRowBudget() {
        return sliceRowBudgetForTest != null
            ? sliceRowBudgetForTest
            : Limits.getLimitQueryRows() * 3 / 5;
    }

    /** Test seam: stands in for `sliceRowBudget`; null reads the platform's limit. */
    @TestVisible
    private static Integer sliceRowBudgetForTest;

    /**
     * The query rows a queue run may have read before its recalculation starts a further query:
     * four fifths of what a transaction may read, leaving the rest for the target records' write
     * and its triggers and flows. Stored counts go stale while a load adds children faster than
     * the queue recalculates (the 25,000 row scale test's fund stored 3,200 of its 26,102
     * allocations), so a record estimated small can still read more than a run may. The
     * recalculation measures what each of its queries read and, before one would pass this
     * ceiling, stops and the run sends the entity's records here, rather than the platform
     * stopping the run (`RollupAggregator.limitQueryRows`, R-RQ6).
     */
    public static Integer queueRowCeiling() {
        return queueRowCeilingForTest != null
            ? queueRowCeilingForTest
            : Limits.getLimitQueryRows() * 4 / 5;
    }

    /** Test seam: stands in for `queueRowCeiling`; null reads the platform's limit. */
    @TestVisible
    private static Integer queueRowCeilingForTest;

    /**
     * The source rows each record is expected to read: the largest COUNT total it stores (of every
     * active COUNT on its entity, not only those being calculated), times the queries the given
     * definitions plan to, as the full run estimates a record's weight. A COUNT
     * with a filter or fiscal window counts only part of the rows, so it is a floor, not the
     * answer. A record with no COUNT total to go by (none defined, or never calculated) is
     * unknown, not small: `UNKNOWN_ROWS_PER_QUERY` per query.
     *
     * @param targetType the entity of the records
     * @param definitions the definitions to calculate for them
     * @param ids the records
     * @return the expected rows of every record given
     */
    public static Map<Id, Integer> estimate(
        Schema.SObjectType targetType,
        List<Rollup_Definition__c> definitions,
        Set<Id> ids
    ) {
        Map<Id, Integer> rowsById = new Map<Id, Integer>();
        Integer queries = 1;
        Set<String> countFields = new Set<String>();
        if (targetType != null && !definitions.isEmpty()) {
            RollupPlanner.Plan plan = RollupPlanner.plan(targetType, definitions);
            queries = Math.max(1, plan.queries.size());
            countFields = storedCountFields(targetType);
        }
        Integer unknown = queries * UNKNOWN_ROWS_PER_QUERY;
        for (Id recordId : ids) {
            rowsById.put(recordId, unknown);
        }
        if (countFields.isEmpty()) {
            return rowsById;
        }
        for (SObject record : RollupAggregator.stored(targetType, countFields, ids).values()) {
            Decimal largest;
            for (String field : countFields) {
                Object counted = record.get(field);
                if (counted != null) {
                    Decimal value = RollupAggregator.toDecimal(counted);
                    largest = largest == null ? value : Math.max(largest, value);
                }
            }
            if (largest != null) {
                Decimal rows = Math.max(1, largest) * queries;
                rowsById.put(record.Id, rows > 2000000000 ? 2000000000 : rows.intValue());
            }
        }
        return rowsById;
    }

    /**
     * Where the entity's active COUNT definitions store their totals, whichever definitions a
     * run calculates. A save that changed only what a SUM or MAX reads queues only those
     * (ADR-0099), and the record's rows are no fewer for it: going by the counts of the queued
     * definitions alone took a fund with 25,000 allocations as unknown (ten rows a query)
     * whenever its entries named no COUNT, and its queries stopped the run on the query row
     * limit. A COUNT over a different source, path or filter than the named SUM or MAX is
     * only a guide to that query's rows: at best a floor, never the answer.
     */
    private static Set<String> storedCountFields(Schema.SObjectType targetType) {
        Map<String, Schema.SObjectField> fieldMap = targetType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .fields.getMap();
        Set<String> countFields = new Set<String>();
        for (
            Rollup_Definition__c definition : RollupSelector.selectActiveForTarget(
                String.valueOf(targetType),
                RollupService.everyMode()
            )
        ) {
            Schema.SObjectField field = String.isBlank(definition.Target_Field__c)
                ? null
                : fieldMap.get(definition.Target_Field__c);
            if (field != null && 'COUNT'.equalsIgnoreCase(definition.Aggregate__c)) {
                countFields.add(String.valueOf(field));
            }
        }
        return countFields;
    }

    /**
     * Takes the run lock until this transaction ends: the org-level `Rollup_Run_Lock__c` record,
     * created the first time. Two processors routing records here at the same moment both found
     * no run going and both started one (the scale rerun had two or three at once); with the
     * lock the second waits for the first to commit, then sees its run. Only the start is
     * locked, never a save, and the processor commits soon after.
     *
     * @return false when the lock could not be taken in time, so the entries wait as when busy
     */
    @TestVisible
    private static Boolean lockRuns() {
        Id org = UserInfo.getOrganizationId();
        try {
            if (lockedRow(org).isEmpty()) {
                try {
                    if (competingLockForTest) {
                        Database.insert(
                            new Rollup_Run_Lock__c(SetupOwnerId = org),
                            AccessLevel.SYSTEM_MODE
                        );
                    }
                    Database.insert(
                        new Rollup_Run_Lock__c(SetupOwnerId = org),
                        AccessLevel.SYSTEM_MODE
                    );
                } catch (DmlException collided) {
                    // Another run created it first: wait for it as for any holder.
                    lockedRow(org);
                }
            }
            return true;
        } catch (QueryException unavailable) {
            ErrorLogger.log(unavailable, LOG_CONTEXT);
            return false;
        }
    }

    private static List<Rollup_Run_Lock__c> lockedRow(Id org) {
        return [
            SELECT Id
            FROM Rollup_Run_Lock__c
            WHERE SetupOwnerId = :org
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
    }

    /** Test seam: another run creates the lock record just before this one's first insert. */
    @TestVisible
    private static Boolean competingLockForTest = false;

    /**
     * Starts a run over these queue entries, which then wait an hour while it holds them, or,
     * when a run is already going or none can start, leaves them to wait two minutes and be
     * routed again.
     *
     * @param entries Pending entries, with their target, records, definitions and attempts
     * @param charge true to charge each entry one attempt as the run takes it; false when the
     *        caller already charged it
     * @return true when a run started
     */
    public static Boolean begin(List<Rollup_Queue__c> entries, Boolean charge) {
        startedForTest = false;
        if (entries == null || entries.isEmpty()) {
            return false;
        }
        Boolean started = false;
        // Locked first, so a second processor deciding at the same moment waits for this one to
        // commit and then sees the run it started.
        if (lockRuns() && runningJobId() == null) {
            List<Rollup_Queue__c> held = hold(entries, charge);
            List<Target> targets = targetsFor(held);
            try {
                Id jobId = Test.isRunningTest() || targets.isEmpty()
                    ? null
                    : Database.executeBatch(new RollupLargeParentBatch(targets), CHUNK_SIZE);
                if (jobId != null) {
                    startedHere.add(jobId);
                }
                started = !targets.isEmpty();
            } catch (Exception refused) {
                // The flex queue is full or the transaction has no async call left: try later.
                ErrorLogger.log(refused, LOG_CONTEXT);
            }
            if (started) {
                startedForTest = true;
                return true;
            }
        }
        List<Rollup_Queue__c> waiting = new List<Rollup_Queue__c>();
        for (Rollup_Queue__c entry : entries) {
            waiting.add(
                new Rollup_Queue__c(
                    Id = entry.Id,
                    Next_Attempt__c = Datetime.now().addMinutes(BUSY_MINUTES)
                )
            );
        }
        Database.update(waiting, false, AccessLevel.SYSTEM_MODE);
        return false;
    }

    /**
     * The entries as a run holds them: charged one attempt when asked (Failed after the fifth),
     * saying why they wait, and with Next Attempt an hour ahead.
     */
    private static List<Rollup_Queue__c> hold(List<Rollup_Queue__c> entries, Boolean charge) {
        List<Rollup_Queue__c> held = new List<Rollup_Queue__c>();
        List<Rollup_Queue__c> changes = new List<Rollup_Queue__c>();
        for (Rollup_Queue__c entry : entries) {
            Integer attempts =
                (entry.Attempts__c == null ? 0 : entry.Attempts__c.intValue()) + (charge ? 1 : 0);
            Rollup_Queue__c change = new Rollup_Queue__c(
                Id = entry.Id,
                Attempts__c = attempts,
                Next_Attempt__c = Datetime.now().addMinutes(LEASE_MINUTES),
                Last_Error__c = System.Label.Core_Rollups_QueueHeldByBatch
            );
            if (attempts >= RollupQueue.MAX_ATTEMPTS) {
                change.Status__c = RollupQueue.STATUS_FAILED;
            }
            changes.add(change);
            Rollup_Queue__c copy = entry.clone(true, false, false, false);
            copy.Attempts__c = attempts;
            held.add(copy);
        }
        Database.update(changes, false, AccessLevel.SYSTEM_MODE);
        return held;
    }

    /** Keeps the entries held while the run is still reading their rows. */
    private static void renew(List<Rollup_Queue__c> entries) {
        List<Rollup_Queue__c> changes = new List<Rollup_Queue__c>();
        for (Rollup_Queue__c entry : entries) {
            changes.add(
                new Rollup_Queue__c(
                    Id = entry.Id,
                    Next_Attempt__c = Datetime.now().addMinutes(LEASE_MINUTES)
                )
            );
        }
        Database.update(changes, false, AccessLevel.SYSTEM_MODE);
    }

    /** The run going now, or null when none is. */
    @TestVisible
    private static Id runningJobId() {
        if (runningForTest) {
            // Any Id stands for the run going.
            return UserInfo.getUserId();
        }
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

    /** The entries grouped by target entity, with the definitions each one runs. */
    @TestVisible
    private static List<Target> targetsFor(List<Rollup_Queue__c> entries) {
        Map<String, Target> byName = new Map<String, Target>();
        for (Rollup_Queue__c entry : entries) {
            Schema.SObjectType targetType = SettingsService.typeByName(entry.Target_Object__c);
            if (targetType == null) {
                continue;
            }
            String name = String.valueOf(targetType);
            if (!byName.containsKey(name)) {
                Target target = new Target();
                target.name = name;
                byName.put(name, target);
            }
            Target target = byName.get(name);
            target.entries.add(entry);
            target.parentIds.addAll(RollupQueue.idsOf(entry));
            target.attempts = Math.max(
                target.attempts,
                entry.Attempts__c == null ? 0 : entry.Attempts__c.intValue()
            );
            List<Id> named = RollupQueue.definitionIdsOf(entry);
            if (named.isEmpty()) {
                target.definitionIds = null;
            } else if (target.definitionIds != null) {
                target.definitionIds.addAll(named);
            }
        }
        List<Target> targets = new List<Target>();
        for (Target target : byName.values()) {
            target.definitions = target.definitionIds == null
                ? RollupSelector.selectActiveForTarget(target.name, RollupService.everyMode())
                : RollupSelector.selectActiveByIds(target.definitionIds);
            targets.add(target);
        }
        return targets;
    }

    // ------------------------------------------------------------------------------ one pass

    private Target currentTarget() {
        return this.targets[this.targetIndex];
    }

    private RollupPlanner.Plan currentPlan() {
        Target target = currentTarget();
        return RollupPlanner.plan(SettingsService.typeByName(target.name), target.definitions);
    }

    /** The source rows of the current query, by Id only. */
    public Database.QueryLocator start(Database.BatchableContext context) {
        try {
            return RollupAggregator.sourceRows(
                currentPlan(),
                this.queryIndex,
                currentTarget().parentIds
            );
        } catch (Exception refused) {
            ErrorLogger.log(refused, LOG_CONTEXT);
            currentTarget().stoppedReason = refused.getMessage();
            return Database.getQueryLocator(
                [SELECT Id FROM Rollup_Queue__c WHERE Id = NULL WITH SYSTEM_MODE]
            );
        }
    }

    /** One chunk of source rows, folded into the answer. */
    public void execute(Database.BatchableContext context, List<SObject> rows) {
        if (currentTarget().stoppedReason != null) {
            return;
        }
        // Held for as long as the run makes progress, however long that is.
        renew(currentTarget().entries);
        RollupAggregator.calculateRows(
            currentPlan(),
            this.queryIndex,
            currentTarget().parentIds,
            new Map<Id, SObject>(rows).keySet(),
            this.answer
        );
    }

    /** The next query, or the write and the next entity, or the end of the run. */
    public void finish(Database.BatchableContext context) {
        String stopped = stoppedReason(context);
        if (stopped != null && currentTarget().stoppedReason == null) {
            currentTarget().stoppedReason = stopped;
        }
        this.queryIndex++;
        proceed();
    }

    /** Runs the next pass, writing each entity whose queries are all read on the way. */
    @TestVisible
    private void proceed() {
        while (this.targetIndex < this.targets.size()) {
            RollupPlanner.Plan plan = currentPlan();
            if (currentTarget().stoppedReason == null && this.queryIndex < plan.queries.size()) {
                if (Test.isRunningTest()) {
                    this.passWaiting = true;
                } else {
                    Database.executeBatch(this, CHUNK_SIZE);
                }
                return;
            }
            settle(currentTarget(), plan);
            this.targetIndex++;
            this.queryIndex = 0;
            this.answer = new RollupAggregator.Answer();
        }
        RollupQueue.processPending();
    }

    /**
     * Writes an entity's totals and deletes its entries, or, when a chunk stopped, writes nothing
     * and releases its entries to be tried again with the reason: the attempt was charged when
     * the run took them, so they are Failed after the fifth.
     */
    private void settle(Target target, RollupPlanner.Plan plan) {
        if (target.stoppedReason != null) {
            String message = String.format(
                    System.Label.Core_Rollups_QueueRunStopped,
                    new List<String>{ target.stoppedReason }
                )
                .left(32768);
            List<Rollup_Queue__c> released = new List<Rollup_Queue__c>();
            for (Rollup_Queue__c entry : target.entries) {
                Integer attempts = entry.Attempts__c == null ? 0 : entry.Attempts__c.intValue();
                released.add(
                    new Rollup_Queue__c(
                        Id = entry.Id,
                        Next_Attempt__c = RollupQueue.nextAttempt(Math.max(1, attempts)),
                        Last_Error__c = message
                    )
                );
            }
            Database.update(released, false, AccessLevel.SYSTEM_MODE);
            return;
        }
        RollupEngine.Result result = RollupEngine.writeCalculated(
            plan,
            target.parentIds,
            this.answer
        );
        if (!result.failed.isEmpty()) {
            RollupQueue.retryLater(
                target.name,
                result.failed,
                target.attempts,
                target.definitionIds
            );
        }
        Database.delete(target.entries, false, AccessLevel.SYSTEM_MODE);
    }

    /** Why a chunk of this pass stopped, or null when none did. */
    private static String stoppedReason(Database.BatchableContext context) {
        if (stoppedChunksForTest != null) {
            return stoppedChunksForTest > 0 ? 'Too many query rows: 50001' : null;
        }
        if (context == null) {
            return null;
        }
        Id jobId = context.getJobId();
        for (AsyncApexJob job : [
            SELECT NumberOfErrors, ExtendedStatus
            FROM AsyncApexJob
            WHERE Id = :jobId
            WITH SYSTEM_MODE
        ]) {
            if (job.NumberOfErrors != null && job.NumberOfErrors > 0) {
                return String.isBlank(job.ExtendedStatus) ? CLASS_NAME : job.ExtendedStatus;
            }
        }
        return null;
    }

    /**
     * Test seam: a test cannot run a chained batch, so it runs every pass here, in this
     * transaction, a chunk at a time.
     */
    @TestVisible
    private void runInline(Integer chunkSize) {
        this.passWaiting = true;
        while (this.passWaiting) {
            this.passWaiting = false;
            Database.QueryLocatorIterator rows = start(null).iterator();
            List<SObject> chunk = new List<SObject>();
            while (rows.hasNext()) {
                chunk.add(rows.next());
                if (chunk.size() == chunkSize) {
                    execute(null, chunk);
                    chunk = new List<SObject>();
                }
            }
            if (!chunk.isEmpty()) {
                execute(null, chunk);
            }
            finish(null);
        }
    }

    /** Test seam: a run over these entries, as `begin` would start it. */
    @TestVisible
    private static RollupLargeParentBatch forEntries(List<Rollup_Queue__c> entries) {
        return new RollupLargeParentBatch(targetsFor(entries));
    }
}
