/**
 * The large parent route of the Rollup Queue (ADR-NEXT, canonical model R-RQ6): totals for target
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
 * The queue sends it two kinds of target record: those whose stored COUNT totals say they read
 * more than `largeParentRows` (`oversized`), and those of an entry a run already failed on, for
 * whatever reason (any entry with an attempt). The batch owns the entries it was given: it
 * deletes them when their totals are written, charges them one attempt when a chunk stopped
 * (Failed after the fifth, R-RQ3), and until it ends they wait with a Next Attempt an hour away,
 * so a run that never ends leaves them to be tried again rather than lost.
 *
 * One run at a time: while one is going, the entries routed here wait two minutes and are routed
 * again, so a fund touched by every gift is not read by a pile of runs at once.
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

    /** The source rows above which a record's totals are calculated here. */
    public static Integer largeParentRows() {
        return largeParentRowsForTest != null
            ? largeParentRowsForTest
            : Limits.getLimitQueryRows() / 5;
    }

    /**
     * The records among these whose source rows are expected to exceed `largeParentRows`: the
     * largest COUNT total each one stores, times the queries the definitions plan to, as the
     * full run estimates a record's weight. A record with no COUNT total to go by is not sent
     * here by this estimate; if it is too large its run fails and the entry comes here anyway.
     *
     * @param targetType the entity of the records
     * @param definitions the definitions to calculate for them
     * @param ids the records
     */
    public static Set<Id> oversized(
        Schema.SObjectType targetType,
        List<Rollup_Definition__c> definitions,
        Set<Id> ids
    ) {
        Set<Id> large = new Set<Id>();
        if (targetType == null || ids == null || ids.isEmpty() || definitions.isEmpty()) {
            return large;
        }
        RollupPlanner.Plan plan = RollupPlanner.plan(targetType, definitions);
        Set<String> countFields = new Set<String>();
        for (Integer i = 0; i < plan.definitions.size(); i++) {
            if ('COUNT'.equalsIgnoreCase(plan.definitions[i].Aggregate__c)) {
                countFields.add(String.valueOf(plan.targetFields[i]));
            }
        }
        if (countFields.isEmpty() || plan.queries.isEmpty()) {
            return large;
        }
        Integer queries = plan.queries.size();
        Integer threshold = largeParentRows();
        for (SObject record : RollupAggregator.stored(targetType, countFields, ids).values()) {
            Decimal largest = 0;
            for (String field : countFields) {
                Object counted = record.get(field);
                if (counted != null) {
                    largest = Math.max(largest, RollupAggregator.toDecimal(counted));
                }
            }
            if (largest * queries >= threshold) {
                large.add(record.Id);
            }
        }
        return large;
    }

    /**
     * Starts a run over these queue entries, which then wait an hour while it holds them, or,
     * when a run is already going or none can start, leaves them to wait two minutes and be
     * routed again.
     *
     * @param entries Pending entries, with their target, records, definitions and attempts
     * @return true when a run started
     */
    public static Boolean begin(List<Rollup_Queue__c> entries) {
        if (entries == null || entries.isEmpty()) {
            return false;
        }
        Boolean started = false;
        List<Target> targets = targetsFor(entries);
        if (runningJobId() == null && !targets.isEmpty()) {
            try {
                Id jobId = Test.isRunningTest()
                    ? null
                    : Database.executeBatch(new RollupLargeParentBatch(targets), CHUNK_SIZE);
                if (jobId != null) {
                    startedHere.add(jobId);
                }
                started = true;
            } catch (Exception refused) {
                // The flex queue is full or the transaction has no async call left: try later.
                ErrorLogger.log(refused, LOG_CONTEXT);
            }
        }
        startedForTest = started;
        Datetime later = Datetime.now().addMinutes(started ? LEASE_MINUTES : BUSY_MINUTES);
        List<Rollup_Queue__c> waiting = new List<Rollup_Queue__c>();
        for (Rollup_Queue__c entry : entries) {
            waiting.add(new Rollup_Queue__c(Id = entry.Id, Next_Attempt__c = later));
        }
        Database.update(waiting, false, AccessLevel.SYSTEM_MODE);
        return started;
    }

    /** The run going now, or null when none is. */
    @TestVisible
    private static Id runningJobId() {
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
     * and charges its entries one attempt, so they are tried again and Failed after the fifth.
     */
    private void settle(Target target, RollupPlanner.Plan plan) {
        if (target.stoppedReason != null) {
            RollupQueue.charge(target.entries, target.stoppedReason);
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
