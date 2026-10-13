/**
 * The Rollup Queue (canonical model Section 14A) and the one processor that works through it
 * (rollup proposal D4, Part 2 section 4, "Parent queue").
 *
 * A save writes the target records its change marked here with `add` and returns (R-R4): every
 * save by default, and with Rollup Processing set to In the save, a save whose totals are too
 * many to recalculate in it or that is already running in the background (ADR-NEXT async
 * rollups). The processor, a
 * Queueable, reads the due entries, merges and sorts their identifiers, recalculates a slice
 * through `RollupEngine`, deletes the entries it finished and runs again while entries remain
 * (R-RQ3). Records the platform refused to save come back as a new entry, tried later each time
 * and Failed after the fifth attempt (R-RQ4). A limit error the processor cannot catch is handled
 * by its finalizer, which charges the attempt to the entries it held and starts again with half
 * the slice.
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

    /** Target records one run recalculates per target entity, before a failure halves it. */
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

    /** Test seam: true or false stands in for `System.isQueueable()`; null reads the platform. */
    @TestVisible
    private static Boolean queueableForTest;

    private final Integer sliceSize;

    public RollupQueue() {
        this(defaultSliceSize);
    }

    public RollupQueue(Integer sliceSize) {
        this.sliceSize = sliceSize == null || sliceSize < 1 ? 1 : sliceSize;
    }

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
     * processor runs only those (ADR-NEXT `NEXT-rollups-recalculate-only-what-a-save-changed.md`).
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
    @TestVisible
    private static Datetime nextAttempt(Integer attempts) {
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
     * the queue: 2". The entries wait for the next processor: one a later save starts, one the
     * chain starts when it ends (`startProcessor`), or the nightly run.
     */
    private static void requestProcessor() {
        if (processorRequested || AutomationControl.isPaused() || inQueueable()) {
            return;
        }
        startProcessor();
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
        Drain drain = new Drain(this.sliceSize);
        System.attachFinalizer(drain);

        Slice slice = take(selectDue(entriesPerRun), this.sliceSize);
        drain.held.addAll(slice.entries);
        Integer failed = 0;
        for (String target : slice.idsByTarget.keySet()) {
            Set<Id> definitionIds = slice.definitionIdsFor(target);
            RollupEngine.Result result = definitionIds == null
                ? RollupEngine.recalculate(
                      slice.idsByTarget.get(target),
                      SettingsService.typeByName(target)
                  )
                : RollupEngine.recalculate(
                      slice.idsByTarget.get(target),
                      RollupSelector.selectActiveByIds(definitionIds)
                  );
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
        // A run that finished doubles a halved slice back towards the default (ROLLUPS-11), so
        // one heavy record does not leave the rest of the backlog draining one at a time.
        chainIfMoreDue(Math.min(defaultSliceSize, this.sliceSize * 2));
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
     * slice on its own, after a failure halved it, gives up only its first identifiers.
     */
    @TestVisible
    private static Slice take(List<Rollup_Queue__c> due, Integer sliceSize) {
        Slice slice = new Slice();
        for (Rollup_Queue__c entry : due) {
            String target = String.isBlank(entry.Target_Object__c) ? '' : entry.Target_Object__c;
            Set<Id> taken = slice.idsByTarget.containsKey(target)
                ? slice.idsByTarget.get(target)
                : new Set<Id>();
            List<Id> ids = idsOf(entry);
            Set<Id> merged = new Set<Id>(taken);
            merged.addAll(ids);
            if (!taken.isEmpty() && merged.size() > sliceSize) {
                continue;
            }
            if (merged.size() > sliceSize) {
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
        return slice;
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
    private static void chainIfMoreDue(Integer sliceSize) {
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
        enqueue(new RollupQueue(sliceSize), delay);
    }

    private static void enqueue(RollupQueue job, Integer delayMinutes) {
        if (Test.isRunningTest() && chainInTests != true) {
            return;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        System.enqueueJob(job, delayMinutes);
    }

    /**
     * What happens when a run dies of something it could not catch, such as a governor limit:
     * the entries it held are charged one attempt, with the reason, and a run with half the slice
     * starts, so a slice too heavy for one transaction is worked through in smaller ones.
     */
    public class Drain implements System.Finalizer {
        private final Integer sliceSize;
        public List<Rollup_Queue__c> held = new List<Rollup_Queue__c>();
        public Boolean finished = false;

        public Drain(Integer sliceSize) {
            this.sliceSize = sliceSize;
        }

        public void execute(System.FinalizerContext context) {
            if (
                this.finished ||
                this.held.isEmpty() ||
                context.getResult() == System.ParentJobResult.SUCCESS
            ) {
                return;
            }
            Exception thrown = context.getException();
            charge(this.held, thrown == null ? '' : thrown.getMessage());
            if (thrown != null) {
                ErrorLogger.log(thrown, LOG_CONTEXT);
            }
            enqueue(new RollupQueue(Math.max(1, this.sliceSize / 2)), 0);
        }
    }

    /** One more attempt on each entry, with why it stopped, and Failed after the fifth. */
    @TestVisible
    private static void charge(List<Rollup_Queue__c> entries, String reason) {
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
    }
}
