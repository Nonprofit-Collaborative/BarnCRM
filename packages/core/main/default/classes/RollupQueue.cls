/**
 * The Rollup Queue (canonical model Section 14A) and the one processor that works through it
 * (rollup proposal D4, Part 2 section 4, "Parent queue").
 *
 * A save writes the target records its change marked here with `add` and returns (R-R4): every
 * save by default, and with Rollup Processing set to In the save, a save whose totals are too
 * many to recalculate in it or that is already running in the background (ADR-0098 async
 * rollups). The processor, a
 * Queueable, reads the due entries, merges and sorts their identifiers, recalculates a slice
 * through `RollupEngine`, deletes the entries it finished and runs again while entries remain
 * (R-RQ3). Records the platform refused to save come back as a new entry, tried later each time
 * and Failed after the fifth attempt (R-RQ4). A run takes records up to a row budget estimated
 * from their stored counts and leaves the rest for the next run. A run that stops on an error it
 * cannot catch has the records it held charged by its finalizer, which retries them alone and a
 * quarter as many at a time, so only a record that stops every run reaches Failed. Records whose
 * source rows are more than a Queueable may read go to `RollupLargeParentBatch` instead (R-RQ6,
 * ADR-0116): those whose stored counts say so before the run, and a lone record that stopped its
 * run on the query row limit.
 *
 * Recalculation recomputes (R-R11), so an entry processed twice, or two processors racing, give
 * the same totals; that is what lets this class stay this small.
 *
 * DOCUMENTED EXCEPTION to user mode DML (plan Section 4.13, ADR-0021, R-RQ5): entries are the
 * engine's own bookkeeping and are written and read in system mode, so a gift saved by someone who
 * cannot see the queue still queues its totals.
 */
public without sharing class RollupQueue implements Queueable {
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_FAILED = 'Failed';

    /** Identifiers per entry at most (R-RQ1). */
    public static final Integer IDS_PER_ENTRY = 200;

    /** Attempts before an entry is Failed and waits for Retry (R-RQ3). */
    public static final Integer MAX_ATTEMPTS = 5;

    private static final String LOG_CONTEXT = 'RollupQueue';
    private static final String CLASS_NAME = 'RollupQueue';
    private static final String SEPARATOR = ',';
    private static final Integer LAST_ERROR_LENGTH = 32768;
    private static final Integer DEFINITION_IDS_LENGTH = 32768;

    /** The longest delay the platform accepts for a queued job, in minutes. */
    private static final Integer LONGEST_DELAY_MINUTES = 10;

    /** The shortest chain of queued jobs any org allows: Developer Edition, trial, scratch. */
    private static final Integer LOWEST_CHAIN_DEPTH = 5;

    /** Test seam: stands in for this job's depth in its chain; null reads the platform. */
    @TestVisible
    private static Integer stackDepthForTest;

    /** Target records one run recalculates per target entity. */
    @TestVisible
    private static Integer defaultSliceSize = 200;

    /** Entries one run reads at most. */
    @TestVisible
    private static Integer entriesPerRun = 500;

    /** A test cannot chain queued jobs, so a run only says it would have; a test may allow it. */
    @TestVisible
    private static Boolean chainInTests = false;

    /** The delay, in minutes, of the follow-on run the last run asked for, or null for none. */
    @TestVisible
    private static Integer lastChainDelay;

    /** Set once a processor is queued, or is this job, so one transaction asks for one only. */
    private static Boolean processorRequested = false;

    /** How many Rollup_Queue_Ready__e this transaction published: one at most. */
    @TestVisible
    private static Integer readyEventsPublished = 0;

    /** Test seam: true or false stands in for `System.isQueueable()`; null reads the platform. */
    @TestVisible
    private static Boolean queueableForTest;

    // ------------------------------------------------------------------------------- writers

    /**
     * Appends entries for these target records, one per target entity and 200 identifiers, and
     * makes sure a processor will run (R-RQ1). Never updates an entry, so two saves never
     * contend for one.
     *
     * @param idsByTarget the target records, by target entity API name
     */
    public static void add(Map<String, Set<Id>> idsByTarget) {
        add(idsByTarget, null);
    }

    /**
     * As above, naming the definitions to recalculate for each target entity's records, so the
     * processor runs only those (ADR-0099 `0099-rollups-recalculate-only-what-a-save-changed.md`).
     *
     * @param idsByTarget the target records, by target entity API name
     * @param definitionIdsByTarget the definitions, by the same names; a missing or empty set
     *        means every active definition on the entity
     */
    public static void add(
        Map<String, Set<Id>> idsByTarget,
        Map<String, Set<Id>> definitionIdsByTarget
    ) {
        List<Rollup_Queue__c> entries = new List<Rollup_Queue__c>();
        for (String target : idsByTarget == null ? new Set<String>() : idsByTarget.keySet()) {
            entries.addAll(
                entriesFor(
                    target,
                    idsByTarget.get(target),
                    0,
                    null,
                    definitionIdsByTarget == null ? null : definitionIdsByTarget.get(target)
                )
            );
        }
        insertEntries(entries);
    }

    /**
     * Queues the records the platform refused to save, to be tried again later, or marks them
     * Failed when this was their fifth attempt (R-RQ3).
     *
     * @param targetObject the entity of the records
     * @param messageById the platform's message for each record
     * @param attemptsSoFar the attempts already made before this one
     */
    public static void retryLater(
        String targetObject,
        Map<Id, String> messageById,
        Integer attemptsSoFar
    ) {
        retryLater(targetObject, messageById, attemptsSoFar, null);
    }

    /**
     * As above, for these definitions only; null means every active definition on the entity.
     */
    public static void retryLater(
        String targetObject,
        Map<Id, String> messageById,
        Integer attemptsSoFar,
        Set<Id> definitionIds
    ) {
        if (messageById == null || messageById.isEmpty()) {
            return;
        }
        String message = String.format(
            System.Label.Core_Rollups_QueueSaveFailed,
            new List<String>{ messageById.values()[0] }
        );
        insertEntries(
            entriesFor(
                targetObject,
                messageById.keySet(),
                (attemptsSoFar == null ? 0 : attemptsSoFar) + 1,
                message,
                definitionIds
            )
        );
    }

    private static List<Rollup_Queue__c> entriesFor(
        String targetObject,
        Set<Id> ids,
        Integer attempts,
        String lastError,
        Set<Id> definitionIds
    ) {
        List<Rollup_Queue__c> entries = new List<Rollup_Queue__c>();
        if (String.isBlank(targetObject) || ids == null) {
            return entries;
        }
        List<String> sorted = new List<String>();
        for (Id recordId : ids) {
            if (recordId != null) {
                sorted.add(String.valueOf(recordId));
            }
        }
        sorted.sort();
        String definitions = joinedDefinitionIds(definitionIds);
        for (Integer start = 0; start < sorted.size(); start += IDS_PER_ENTRY) {
            List<String> chunk = new List<String>();
            for (Integer i = start; i < Math.min(start + IDS_PER_ENTRY, sorted.size()); i++) {
                chunk.add(sorted[i]);
            }
            entries.add(entry(targetObject, chunk, attempts, lastError, definitions));
        }
        return entries;
    }

    /**
     * The definitions as an entry holds them, or null for every definition: none named, or
     * more than the attribute holds.
     */
    private static String joinedDefinitionIds(Set<Id> definitionIds) {
        if (definitionIds == null || definitionIds.isEmpty() || definitionIds.contains(null)) {
            return null;
        }
        List<String> sorted = new List<String>();
        for (Id definitionId : definitionIds) {
            sorted.add(String.valueOf(definitionId));
        }
        sorted.sort();
        String joined = String.join(sorted, SEPARATOR);
        return joined.length() > DEFINITION_IDS_LENGTH ? null : joined;
    }

    private static Rollup_Queue__c entry(
        String targetObject,
        List<String> ids,
        Integer attempts,
        String lastError,
        String definitionIds
    ) {
        return new Rollup_Queue__c(
            Target_Object__c = targetObject,
            Record_Ids__c = String.join(ids, SEPARATOR),
            Definition_Ids__c = definitionIds,
            Record_Count__c = ids.size(),
            Attempts__c = attempts,
            Status__c = attempts >= MAX_ATTEMPTS ? STATUS_FAILED : STATUS_PENDING,
            Next_Attempt__c = attempts > 0 ? nextAttempt(attempts) : null,
            Last_Error__c = lastError == null ? null : lastError.left(LAST_ERROR_LENGTH)
        );
    }

    /** Later each time: two minutes after the first failure, then four, eight and sixteen. */
    public static Datetime nextAttempt(Integer attempts) {
        Integer power = Math.max(1, Math.min(attempts, MAX_ATTEMPTS - 1));
        Integer minutes = Math.pow(2, power).intValue();
        return Datetime.now().addMinutes(minutes);
    }

    /**
     * Retry from the Rollup Builder's Needs attention list (R-RQ4, slice S13): Failed entries
     * go back to Pending with no attempts and are tried within minutes.
     *
     * @param entryIds the entries to retry, or null for every Failed entry
     * @return how many entries went back in the queue
     */
    public static Integer retry(Set<Id> entryIds) {
        List<Rollup_Queue__c> failed = entryIds == null
            ? [
                  SELECT Id
                  FROM Rollup_Queue__c
                  WHERE Status__c = :STATUS_FAILED
                  WITH SYSTEM_MODE
                  LIMIT 10000
              ]
            : [
                  SELECT Id
                  FROM Rollup_Queue__c
                  WHERE Status__c = :STATUS_FAILED AND Id IN :entryIds
                  WITH SYSTEM_MODE
              ];
        for (Rollup_Queue__c entry : failed) {
            entry.Status__c = STATUS_PENDING;
            entry.Attempts__c = 0;
            entry.Next_Attempt__c = null;
        }
        if (!failed.isEmpty()) {
            Database.update(failed, AccessLevel.SYSTEM_MODE);
        }
        // Retry also starts entries still Pending that no processor is coming for.
        processPending();
        return failed.size();
    }

    /**
     * Starts a processor when Pending entries wait and none is queued (ROLLUPS-7). A save that
     * could not queue a job (its allowance used, or automation paused) leaves its entries for the
     * next save that does; the nightly run, the end of a pause and Retry call this so they never
     * wait for one.
     *
     * @return true when Pending entries were found
     */
    public static Boolean processPending() {
        Boolean pending =
            [
                SELECT Id
                FROM Rollup_Queue__c
                WHERE Status__c = :STATUS_PENDING
                WITH SYSTEM_MODE
                LIMIT 1
            ]
            .size() > 0;
        if (pending) {
            requestProcessor();
        }
        return pending;
    }

    private static void insertEntries(List<Rollup_Queue__c> entries) {
        if (entries.isEmpty()) {
            return;
        }
        Database.insert(entries, AccessLevel.SYSTEM_MODE);
        requestProcessor();
    }

    /**
     * Queues a processor unless one already waits to start: a waiting one reads every entry
     * committed by the time it starts. When the transaction can queue no more jobs, the entries
     * wait for the next save that queues one, or for the nightly run.
     *
     * Never from inside a Queueable (R-RQ3). A Queueable may queue one job, and the job running
     * may need that one job for its own next step: the sample data load and the household soft
     * credit recompute chain themselves after saving gifts and people, and so may a subscriber's
     * integration. Taking it stopped the sample data load with "Too many queueable jobs added to
     * the queue: 2". There the transaction publishes one Rollup_Queue_Ready__e instead, after
     * commit, and its subscriber starts the processor (ADR-0100).
     */
    private static void requestProcessor() {
        if (processorRequested || AutomationControl.isPaused()) {
            return;
        }
        if (inQueueable()) {
            announceReady();
            return;
        }
        startProcessor();
    }

    /**
     * Publishes one Rollup_Queue_Ready__e per transaction. It is published after commit, so a
     * job that rolls back announces nothing, and it takes no queueable job. If it cannot be
     * published the entries wait for a later processor or the nightly run, as before.
     */
    private static void announceReady() {
        if (readyEventsPublished > 0) {
            return;
        }
        readyEventsPublished++;
        Database.SaveResult result = EventBus.publish(new Rollup_Queue_Ready__e());
        if (!result.isSuccess()) {
            ErrorLogger.logMessage(
                result.getErrors()[0].getMessage(),
                'RollupQueue.announceReady',
                'Warning'
            );
        }
    }

    /** Whether this transaction is a Queueable job, whose one chained job is not the engine's. */
    private static Boolean inQueueable() {
        return queueableForTest == null ? System.isQueueable() : queueableForTest;
    }

    /**
     * Starts a processor now when entries are pending and none waits to start. For a background
     * job that saved records the engine queued, called when the job has no next step of its own,
     * so its totals catch up within minutes instead of waiting for the nightly run.
     */
    public static void startProcessor() {
        if (processorRequested || AutomationControl.isPaused()) {
            return;
        }
        processorRequested = true;
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        Integer pending = [
            SELECT COUNT()
            FROM Rollup_Queue__c
            WHERE Status__c = :STATUS_PENDING
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (pending == 0) {
            return;
        }
        Integer waiting = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE
                JobType = 'Queueable'
                AND ApexClass.Name = :CLASS_NAME
                AND Status IN ('Queued', 'Holding')
            WITH SYSTEM_MODE
        ];
        if (waiting == 0) {
            System.enqueueJob(new RollupQueue());
        }
    }

    // ----------------------------------------------------------------------------- processor

    /** One run: a slice of the due entries, recalculated, then the next run if more are due. */
    public void execute(QueueableContext context) {
        processorRequested = true;
        if (AutomationControl.isPaused()) {
            // R-RQ5: the entries wait; the nightly run puts Both totals right after the pause.
            return;
        }
        Drain drain = new Drain();
        System.attachFinalizer(drain);

        Slice slice = take(selectDue(entriesPerRun), defaultSliceSize);
        drain.held.addAll(slice.entries);
        List<Rollup_Queue__c> large = new List<Rollup_Queue__c>();
        List<Rollup_Queue__c> deferred = new List<Rollup_Queue__c>();
        Integer budget = RollupLargeParentBatch.sliceRowBudget();
        Boolean anyTaken = false;
        Integer failed = 0;
        for (String target : slice.idsByTarget.keySet()) {
            Set<Id> definitionIds = slice.definitionIdsFor(target);
            Schema.SObjectType targetType = SettingsService.typeByName(target);
            List<Rollup_Definition__c> definitions = definitionIds != null
                ? RollupSelector.selectActiveByIds(definitionIds)
                : targetType == null
                      ? new List<Rollup_Definition__c>()
                      : RollupSelector.selectActiveForTarget(
                            String.valueOf(targetType),
                            RollupService.everyMode()
                        );
            // Until the split below, every record is charged if the run stops (R-RQ3).
            drain.takenIds.addAll(slice.idsByTarget.get(target));
            // R-RQ6: a record whose source rows would stop this run goes to the batch route, and
            // records past the run's row budget wait for the next run.
            Map<Id, Integer> rowsById = RollupLargeParentBatch.estimate(
                targetType,
                definitions,
                slice.idsByTarget.get(target)
            );
            Set<Id> ids = new Set<Id>();
            Set<Id> oversized = new Set<Id>();
            Set<Id> later = new Set<Id>();
            for (Id recordId : slice.idsByTarget.get(target)) {
                Integer rows = rowsById.get(recordId);
                if (rows >= RollupLargeParentBatch.largeParentRows()) {
                    oversized.add(recordId);
                } else if (rows > budget && anyTaken) {
                    later.add(recordId);
                } else {
                    // The first record always runs, so a run never takes nothing.
                    budget -= rows;
                    anyTaken = true;
                    ids.add(recordId);
                }
            }
            Integer attempts = slice.attemptsByTarget.get(target);
            large.addAll(entriesFor(target, oversized, attempts, null, definitionIds));
            deferred.addAll(entriesFor(target, later, attempts, null, definitionIds));
            drain.takenIds.removeAll(oversized);
            drain.takenIds.removeAll(later);
            RollupEngine.Result result = RollupEngine.recalculate(ids, definitions);
            if (!result.failed.isEmpty()) {
                retryLater(
                    target,
                    result.failed,
                    slice.attemptsByTarget.get(target),
                    definitionIds
                );
                failed += result.failed.size();
            }
        }
        // Partial success: an entry another run already finished is simply gone.
        Database.update(slice.remainders, false, AccessLevel.SYSTEM_MODE);
        Database.delete(slice.finished, false, AccessLevel.SYSTEM_MODE);
        if (!deferred.isEmpty()) {
            Database.insert(deferred, AccessLevel.SYSTEM_MODE);
        }
        if (!large.isEmpty()) {
            Database.insert(large, AccessLevel.SYSTEM_MODE);
            RollupLargeParentBatch.begin(large, true);
        }
        if (failed > 0) {
            ErrorLogger.logMessage(
                String.format(
                    System.Label.Core_Rollups_QueueRunSummary,
                    new List<String>{ String.valueOf(failed) }
                ),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
        drain.finished = true;
        chainIfMoreDue();
    }

    /** What one run takes: the identifiers by target entity, and what becomes of each entry. */
    @TestVisible
    private class Slice {
        public Map<String, Set<Id>> idsByTarget = new Map<String, Set<Id>>();
        public Map<String, Integer> attemptsByTarget = new Map<String, Integer>();
        /** Every entry the run holds, for the finalizer. */
        public List<Rollup_Queue__c> entries = new List<Rollup_Queue__c>();
        /** Entries whose identifiers are all taken: deleted when the run finishes. */
        public List<Rollup_Queue__c> finished = new List<Rollup_Queue__c>();
        /** Entries larger than the slice: rewritten with the identifiers left over. */
        public List<Rollup_Queue__c> remainders = new List<Rollup_Queue__c>();
        /** The definitions the entries taken name, by target entity. */
        public Map<String, Set<Id>> definitionIdsByTarget = new Map<String, Set<Id>>();
        /** Target entities with an entry that names none, so every definition runs. */
        public Set<String> everyDefinition = new Set<String>();

        /** The definitions to run for this target entity, or null for every one. */
        public Set<Id> definitionIdsFor(String target) {
            return this.everyDefinition.contains(target)
                ? null
                : this.definitionIdsByTarget.get(target);
        }

        public void addDefinitions(String target, Rollup_Queue__c entry) {
            List<Id> named = idsIn(entry.Definition_Ids__c);
            if (named.isEmpty()) {
                this.everyDefinition.add(target);
                return;
            }
            if (!this.definitionIdsByTarget.containsKey(target)) {
                this.definitionIdsByTarget.put(target, new Set<Id>());
            }
            this.definitionIdsByTarget.get(target).addAll(named);
        }
    }

    /**
     * Merges entries per target entity while the merged set stays within the slice, so a load that
     * touches one household 5,000 times is one small recalculation. An entry larger than the
     * slice on its own gives up only its first identifiers.
     *
     * An entry with attempts (a run stopped while holding its records, or the platform refused to
     * save one) is never merged: a run takes it alone, and only a quarter as many of its
     * identifiers per attempt (50, 12, 3, then 1 of a 200 slice), so a record that stops every run
     * holding it is narrowed down to itself and only it reaches Failed (R-RQ3).
     */
    @TestVisible
    private static Slice take(List<Rollup_Queue__c> due, Integer sliceSize) {
        Slice slice = new Slice();
        for (Rollup_Queue__c entry : due) {
            Integer attempts = entry.Attempts__c == null ? 0 : entry.Attempts__c.intValue();
            if (attempts > 0) {
                if (slice.entries.isEmpty()) {
                    takeEntry(slice, entry, retrySlice(attempts, sliceSize));
                    return slice;
                }
                continue;
            }
            String target = String.isBlank(entry.Target_Object__c) ? '' : entry.Target_Object__c;
            Set<Id> taken = slice.idsByTarget.containsKey(target)
                ? slice.idsByTarget.get(target)
                : new Set<Id>();
            Set<Id> merged = new Set<Id>(taken);
            merged.addAll(idsOf(entry));
            if (!taken.isEmpty() && merged.size() > sliceSize) {
                continue;
            }
            takeEntry(slice, entry, sliceSize);
        }
        return slice;
    }

    /** The identifiers a retried entry gives one run: a quarter as many per attempt, at least 1. */
    @TestVisible
    private static Integer retrySlice(Integer attempts, Integer sliceSize) {
        return Math.max(1, sliceSize >> (2 * Math.min(attempts, 8)));
    }

    /** Adds an entry's identifiers to the slice, splitting off what the limit leaves over. */
    private static void takeEntry(Slice slice, Rollup_Queue__c entry, Integer sliceSize) {
        String target = String.isBlank(entry.Target_Object__c) ? '' : entry.Target_Object__c;
        Set<Id> taken = slice.idsByTarget.containsKey(target)
            ? slice.idsByTarget.get(target)
            : new Set<Id>();
        List<Id> ids = idsOf(entry);
        Set<Id> merged = new Set<Id>(taken);
        merged.addAll(ids);
        if (merged.size() > sliceSize) {
            // Only an entry taken first for its entity gets here: the merge skips the others.
            merged = new Set<Id>();
            List<String> rest = new List<String>();
            for (Id recordId : ids) {
                if (merged.size() < sliceSize) {
                    merged.add(recordId);
                } else {
                    rest.add(String.valueOf(recordId));
                }
            }
            slice.remainders.add(
                new Rollup_Queue__c(
                    Id = entry.Id,
                    Record_Ids__c = String.join(rest, SEPARATOR),
                    Record_Count__c = rest.size()
                )
            );
        } else {
            slice.finished.add(entry);
        }
        slice.entries.add(entry);
        slice.idsByTarget.put(target, merged);
        slice.addDefinitions(target, entry);
        Integer attempts = entry.Attempts__c == null ? 0 : entry.Attempts__c.intValue();
        Integer highest = slice.attemptsByTarget.get(target);
        slice.attemptsByTarget.put(
            target,
            highest == null ? attempts : Math.max(highest, attempts)
        );
    }

    /** The identifiers an entry holds; anything that is not one is dropped. */
    public static List<Id> idsOf(Rollup_Queue__c entry) {
        return idsIn(entry.Record_Ids__c);
    }

    private static List<Id> idsIn(String joined) {
        List<Id> ids = new List<Id>();
        if (String.isBlank(joined)) {
            return ids;
        }
        for (String part : joined.split(SEPARATOR)) {
            try {
                ids.add(Id.valueOf(part.trim()));
            } catch (Exception notAnId) {
                continue;
            }
        }
        return ids;
    }

    private static List<Rollup_Queue__c> selectDue(Integer maxEntries) {
        Datetime now = Datetime.now();
        return [
            SELECT Id, Target_Object__c, Record_Ids__c, Definition_Ids__c, Attempts__c
            FROM Rollup_Queue__c
            WHERE
                Status__c = :STATUS_PENDING
                AND (Next_Attempt__c = NULL
                OR Next_Attempt__c <= :now)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate, Id
            LIMIT :maxEntries
        ];
    }

    /**
     * Runs again while Pending entries remain: now when one is due, or when the earliest one
     * becomes due, up to the platform's ten minute limit on a delay.
     */
    private static void chainIfMoreDue() {
        List<Rollup_Queue__c> next = [
            SELECT Next_Attempt__c
            FROM Rollup_Queue__c
            WHERE Status__c = :STATUS_PENDING
            WITH SYSTEM_MODE
            ORDER BY Next_Attempt__c ASC NULLS FIRST
            LIMIT 1
        ];
        if (next.isEmpty()) {
            lastChainDelay = null;
            return;
        }
        Integer delay = 0;
        if (next[0].Next_Attempt__c != null) {
            Long millis = next[0].Next_Attempt__c.getTime() - Datetime.now().getTime();
            Integer minutes = Math.ceil(millis / 60000.0).intValue();
            delay = Math.min(LONGEST_DELAY_MINUTES, Math.max(0, minutes));
        }
        lastChainDelay = delay;
        enqueue(new RollupQueue(), delay);
    }

    private static void enqueue(RollupQueue job, Integer delayMinutes) {
        if (atChainDepthLimit()) {
            // The platform would refuse the next link, the refusal kills this run, and the
            // entries would stay Pending with nothing to process them. The Ready event starts a
            // fresh chain after this run commits instead (ADR-0100's doorbell).
            announceReady();
            ErrorLogger.logMessage(
                System.Label.Core_Rollups_QueueHandedOff,
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_INFO
            );
            return;
        }
        if (Test.isRunningTest() && chainInTests != true) {
            return;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        System.enqueueJob(job, delayMinutes);
    }

    /**
     * Whether this job is as deep in its chain as the platform lets a chain go, so the job it
     * queued would be refused. A chain given no depth of its own is held to the lowest depth the
     * platform sets on any org (five, in Developer Edition, trial and scratch orgs), so the same
     * code stays safe everywhere at the cost of one Ready event per five runs.
     */
    private static Boolean atChainDepthLimit() {
        Integer depth = stackDepthForTest != null
            ? stackDepthForTest
            : AsyncInfo.getCurrentQueueableStackDepth();
        if (depth == null) {
            return false;
        }
        Integer limitDepth = AsyncInfo.hasMaxStackDepth()
            ? AsyncInfo.getMaximumQueueableStackDepth()
            : LOWEST_CHAIN_DEPTH;
        return depth >= limitDepth;
    }

    /**
     * What happens when a run dies of something it could not catch, such as a governor limit
     * (R-RQ3, R-RQ6). Only the records the run was recalculating are charged: they move to a new
     * entry with one more attempt and the reason, Failed after the fifth, and the rest of each
     * entry it held stays as it was. A retried entry runs alone and a quarter as large each
     * attempt (`take`), so a record that stops every run narrows down to itself and only it
     * reaches Failed. A run of one record that stopped on the query row limit hands that record to
     * `RollupLargeParentBatch` instead, which reads its source rows in chunks however many there
     * are.
     *
     * The queue carries on in a fresh processor started by the Ready event, never by a job this
     * finalizer queues: the platform stops re-queuing from finalizers after five failed jobs in a
     * row and refuses a link past the chain depth limit, and on the tier 1 scale test that left
     * 826 entries Pending with nothing to process them.
     */
    public class Drain implements System.Finalizer {
        public List<Rollup_Queue__c> held = new List<Rollup_Queue__c>();
        /** The records the run was recalculating when it stopped. */
        public Set<Id> takenIds = new Set<Id>();
        public Boolean finished = false;

        public void execute(System.FinalizerContext context) {
            if (
                this.finished ||
                this.held.isEmpty() ||
                context.getResult() == System.ParentJobResult.SUCCESS
            ) {
                return;
            }
            Exception thrown = context.getException();
            if (thrown != null) {
                ErrorLogger.log(thrown, LOG_CONTEXT);
            }
            stopped(this.held, this.takenIds, thrown == null ? '' : thrown.getMessage());
        }
    }

    /** The message the platform gives when a transaction reads more rows than it may. */
    private static final String ROW_LIMIT = 'Too many query rows';

    /**
     * The entries of a run that stopped: the records it was recalculating charged (or, a lone
     * record over the row limit, handed to the large parent batch), the rest left as they were,
     * and a fresh processor announced.
     *
     * @param held the entries the run held, as they were before it
     * @param takenIds the records it was recalculating; empty charges every record held
     * @param reason why it stopped
     */
    @TestVisible
    private static void stopped(List<Rollup_Queue__c> held, Set<Id> takenIds, String reason) {
        String message = String.format(
                System.Label.Core_Rollups_QueueRunStopped,
                new List<String>{ reason }
            )
            .left(LAST_ERROR_LENGTH);
        Set<Id> charging = new Set<Id>(takenIds);
        if (charging.isEmpty()) {
            for (Rollup_Queue__c entry : held) {
                charging.addAll(idsOf(entry));
            }
        }
        Boolean toBatch = charging.size() == 1 && reason.contains(ROW_LIMIT);
        List<Rollup_Queue__c> rest = new List<Rollup_Queue__c>();
        List<Rollup_Queue__c> emptied = new List<Rollup_Queue__c>();
        List<Rollup_Queue__c> charged = new List<Rollup_Queue__c>();
        for (Rollup_Queue__c entry : held) {
            Set<Id> hit = new Set<Id>();
            List<String> left = new List<String>();
            for (Id recordId : idsOf(entry)) {
                if (charging.contains(recordId)) {
                    hit.add(recordId);
                } else {
                    left.add(String.valueOf(recordId));
                }
            }
            if (hit.isEmpty()) {
                continue;
            }
            if (left.isEmpty()) {
                emptied.add(new Rollup_Queue__c(Id = entry.Id));
            } else {
                rest.add(
                    new Rollup_Queue__c(
                        Id = entry.Id,
                        Record_Ids__c = String.join(left, SEPARATOR),
                        Record_Count__c = left.size()
                    )
                );
            }
            Integer attempts = entry.Attempts__c == null ? 0 : entry.Attempts__c.intValue();
            List<Id> named = definitionIdsOf(entry);
            charged.addAll(
                entriesFor(
                    entry.Target_Object__c,
                    hit,
                    attempts + 1,
                    message,
                    named.isEmpty() ? null : new Set<Id>(named)
                )
            );
        }
        Database.update(rest, false, AccessLevel.SYSTEM_MODE);
        Database.delete(emptied, false, AccessLevel.SYSTEM_MODE);
        Database.insert(charged, false, AccessLevel.SYSTEM_MODE);
        if (toBatch) {
            // Already charged above: the batch only holds it.
            RollupLargeParentBatch.begin(charged, false);
        }
        announceReady();
    }

    /** The definitions an entry names; none means every active definition on its entity. */
    public static List<Id> definitionIdsOf(Rollup_Queue__c entry) {
        return idsIn(entry.Definition_Ids__c);
    }

    /**
     * One more attempt on each entry, with why it stopped, and Failed after the fifth.
     *
     * @return the entries as charged
     */
    public static List<Rollup_Queue__c> charge(List<Rollup_Queue__c> entries, String reason) {
        String message = String.format(
                System.Label.Core_Rollups_QueueRunStopped,
                new List<String>{ reason }
            )
            .left(LAST_ERROR_LENGTH);
        List<Rollup_Queue__c> charged = new List<Rollup_Queue__c>();
        for (Rollup_Queue__c entry : entries) {
            Integer attempts = (entry.Attempts__c == null ? 0 : entry.Attempts__c.intValue()) + 1;
            charged.add(
                new Rollup_Queue__c(
                    Id = entry.Id,
                    Attempts__c = attempts,
                    Status__c = attempts >= MAX_ATTEMPTS ? STATUS_FAILED : STATUS_PENDING,
                    Next_Attempt__c = nextAttempt(attempts),
                    Last_Error__c = message
                )
            );
        }
        Database.update(charged, false, AccessLevel.SYSTEM_MODE);
        return charged;
    }
}
