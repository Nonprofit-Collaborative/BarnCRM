/**
 * The rollup engine, as the rest of BarnCRM sees it.
 *
 * Everything a feature, a trigger, a batch or the console needs is here, and the engine behind it
 * is BarnCRM's own (`decisions/0082-barncrm-owns-its-rollup-engine.md`, slice S8). Three things
 * happen:
 *
 * - **Real time.** A trigger on a source entity calls `runRealTime`. `RollupChanges` works out
 *   which target records the save marks (R-R11). By default they are written to the Rollup Queue
 *   and recalculated just after the save, so the save itself only marks and queues; an org that
 *   sets Rollup Processing to In the save recalculates a normal save's totals in it, and a bulk
 *   or background save still queues (R-R4, Section 14A, ADR-0098 async rollups).
 * - **Scheduled.** `RollupScheduler` calls `startNightlyRun` for the definitions in Scheduled or
 *   Both mode, which is the nightly reconciliation R-R4 describes: `RollupFullRecalcBatch`.
 * - **On demand.** `recalculate` runs one definition over every record now, which is what the
 *   Recalculate action on the Rollups page does.
 *
 * Freshness is the engine's own: `RollupWriter` stamps `Rollups_Last_Calculated__c` on a record
 * in the same write as its totals, and the full recalculation marks a definition calculated when
 * its run has finished (R-R13).
 */
@NamespaceAccessible
public with sharing class RollupService {
    /** Raised when a rollup cannot be run. */
    @NamespaceAccessible
    public class RollupServiceException extends Exception {
    }

    @NamespaceAccessible
    public static final String MODE_REAL_TIME = 'Real-time';
    @NamespaceAccessible
    public static final String MODE_SCHEDULED = 'Scheduled';
    @NamespaceAccessible
    public static final String MODE_BOTH = 'Both';

    /** The field the platform fills on a record deleted by a merge, naming the survivor. */
    private static final String MERGE_SURVIVOR_FIELD = 'MasterRecordId';

    /** The one freshness attribute every target entity carries (canonical model Section 26). */
    @NamespaceAccessible
    public static final String FRESHNESS_FIELD = 'Rollups_Last_Calculated__c';

    /** The hours after which the Hub calls the nightly run overdue (plan Section 4.10). */
    @NamespaceAccessible
    public static final Integer STALE_AFTER_HOURS = 36;

    private static final String CONTEXT_REAL_TIME = 'RollupService.runRealTime';
    private static final String CONTEXT_ENSURE_DEFAULTS = 'RollupService.ensureDefaults';

    private static final Set<String> REAL_TIME_MODES = new Set<String>{ MODE_REAL_TIME, MODE_BOTH };
    private static final Set<String> SCHEDULED_MODES = new Set<String>{ MODE_SCHEDULED, MODE_BOTH };
    private static final Set<String> EVERY_MODE = new Set<String>{
        MODE_REAL_TIME,
        MODE_SCHEDULED,
        MODE_BOTH
    };

    /** The records the last merge recalculated, so a test can see only survivors were. */
    @TestVisible
    private static Set<Id> lastParentIds;

    /**
     * The target records a normal save recalculates itself (R-R4); a save that marks more goes
     * to the Rollup Queue.
     */
    @TestVisible
    private static Integer instantLimit = 50;

    /** The module's own settings object (canonical model Section 14B, ADR-0125 decision 6). */
    @NamespaceAccessible
    public static final String SETTINGS_OBJECT = 'Rollup_Settings__c';
    /** The setting that says when real-time totals are recalculated (R-R4, ADR-0098). */
    @NamespaceAccessible
    public static final String PROCESSING_SETTING = 'Rollup_Processing__c';
    /** The setting that says which mode a new definition starts in (R-R4). */
    @NamespaceAccessible
    public static final String MODE_DEFAULT_SETTING = 'Rollup_Mode_Default__c';
    /** Queued and recalculated just after the save: the default. */
    @NamespaceAccessible
    public static final String PROCESSING_BACKGROUND = 'Background';
    /** Recalculated in the save itself when it is small enough, as before ADR-0098. */
    @NamespaceAccessible
    public static final String PROCESSING_IN_SAVE = 'In_Save';

    /**
     * Queries a recalculation in the save spends on top of its planned aggregate queries for one
     * target entity: the stored values, the target filter and the write's own automation.
     */
    private static final Integer QUERIES_PER_TARGET = 4;

    /** The module's name on the Module Manager (ADR-0125 D7). */
    @NamespaceAccessible
    public static final String MODULE_NAME = 'Rollups';

    /**
     * Whether BarnCRM Rollup Builder is turned off on the Module Manager (ADR-0125 decision 9).
     * While it is, every entry point of the engine returns without doing anything: the trigger
     * handler on every object that registers it (Giving's rows too), the Flow action, Core's
     * merge and queue calls, the Rollup Queue processor, the nightly and full runs (and the
     * passes they chain) and the scheduler. Nothing is processed and queued entries wait; Turn
     * on drains them and recalculates every active rollup (`catchUpAfterTurnedOn`).
     */
    @NamespaceAccessible
    public static Boolean isTurnedOff() {
        return ModuleManagerService.turnedOff().contains(MODULE_NAME.toLowerCase());
    }

    /** Whether the engine must not run now: automation paused, or the module turned off. */
    @NamespaceAccessible
    public static Boolean isStopped() {
        return AutomationControl.isPaused() || isTurnedOff();
    }

    /**
     * Puts every total right after the module is turned on again (ADR-0125 decision 9, owner
     * decision: totals are right after Turn on): starts the processor for the entries that
     * waited, and a full recalculation of every active rollup, since nothing recorded the saves
     * made while it was off. Core's Module Manager calls this through the engine seam.
     */
    @NamespaceAccessible
    public static void catchUpAfterTurnedOn() {
        if (isTurnedOff()) {
            return;
        }
        RollupQueue.processPending();
        startFullRunOfEveryDefinition();
    }

    /**
     * Whether a normal save recalculates its real-time totals itself. Anything but In the save,
     * including a setting never saved, means just after the save.
     */
    @NamespaceAccessible
    public static Boolean recalculatesInTheSave() {
        Object stored = SettingsService.getValue(SETTINGS_OBJECT, PROCESSING_SETTING);
        return stored != null && PROCESSING_IN_SAVE.equals(String.valueOf(stored));
    }

    /** The modes a nightly run covers. */
    @NamespaceAccessible
    public static Set<String> scheduledModes() {
        return new Set<String>(SCHEDULED_MODES);
    }

    /** The mode a new definition starts in, from the org's default. */
    @NamespaceAccessible
    public static String defaultMode() {
        Object stored = SettingsService.getValue(SETTINGS_OBJECT, MODE_DEFAULT_SETTING);
        String mode = stored == null ? null : String.valueOf(stored);
        return REAL_TIME_MODES.contains(mode) || MODE_SCHEDULED.equals(mode) ? mode : MODE_BOTH;
    }

    // ---------------------------------------------------------------------------------- bypass

    /** Whether the running user holds each Bypass Permission asked about, for this transaction. */
    private static Map<String, Boolean> bypassHeld = new Map<String, Boolean>();

    /** The active Real-time and Both definitions a save by the running user runs (R-R4a). */
    private static List<Rollup_Definition__c> realTimeForThisUser() {
        return withoutBypassed(RollupSelector.selectActiveForModes(REAL_TIME_MODES));
    }

    /**
     * These definitions without the ones whose Bypass Permission the running user holds
     * (R-R4a, ADR-0136): a data migration user's saves neither recalculate nor queue them, and
     * the nightly run and Recalculate, which never call this, still cover them.
     */
    private static List<Rollup_Definition__c> withoutBypassed(
        List<Rollup_Definition__c> definitions
    ) {
        List<Rollup_Definition__c> kept = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : definitions) {
            if (!isBypassed(definition.Bypass_Permission__c)) {
                kept.add(definition);
            }
        }
        return kept;
    }

    /**
     * Whether the running user holds this custom permission, asked once per user and name in a
     * transaction. A name the platform does not know bypasses nobody: the definition's save
     * refuses one, so this only meets a permission deleted since.
     */
    private static Boolean isBypassed(String permission) {
        if (String.isBlank(permission)) {
            return false;
        }
        String name = permission.trim();
        String key = UserInfo.getUserId() + '|' + name.toLowerCase();
        if (!bypassHeld.containsKey(key)) {
            Boolean held = false;
            try {
                held = FeatureManagement.checkPermission(name);
            } catch (Exception unknown) {
                held = false;
            }
            bypassHeld.put(key, held == true);
        }
        return bypassHeld.get(key);
    }

    // ------------------------------------------------------------------------------- real time

    /**
     * Recalculates the totals a save of these records changed, for every active definition in
     * Real-time or Both mode (R-R4, R-R11).
     *
     * Called from a trigger handler, never directly, so that the automation is bypassable and
     * pausable like every other packaged automation (R-A1). A delete is collected in two steps:
     * before it, the rows the platform deletes with the record (`RollupDependents`); after it,
     * `runAfterDelete`. A definition that cannot be planned is logged and left out by the
     * engine: one broken definition must not fail the administrator's save.
     *
     * @param sourceObject the entity whose records changed
     * @param changedRecords the records in front of the trigger
     * @param oldRecords the same records as they were, or null outside an update
     */
    @NamespaceAccessible
    public static void runRealTime(
        String sourceObject,
        List<SObject> changedRecords,
        Map<Id, SObject> oldRecords
    ) {
        if (
            String.isBlank(sourceObject) ||
            changedRecords == null ||
            changedRecords.isEmpty() ||
            isTurnedOff()
        ) {
            return;
        }
        List<Rollup_Definition__c> definitions = realTimeForThisUser();
        if (definitions.isEmpty()) {
            return;
        }
        if (Trigger.isExecuting && Trigger.isDelete) {
            RollupDependents.beforeDelete(
                SettingsService.typeByName(sourceObject),
                changedRecords,
                definitions
            );
            return;
        }
        recalculateNowOrQueue(
            RollupChanges.forSave(
                sourceObject,
                changedRecords,
                oldRecords,
                Trigger.isExecuting && Trigger.isUndelete,
                definitions
            )
        );
    }

    /**
     * After records are deleted: recalculates the targets they reached, now that they no longer
     * count (R-R11).
     *
     * @param sourceObject the entity whose records were deleted
     * @param deletedRecords the records as they were
     */
    @NamespaceAccessible
    public static void runAfterDelete(String sourceObject, List<SObject> deletedRecords) {
        if (String.isBlank(sourceObject) || deletedRecords == null || isTurnedOff()) {
            return;
        }
        List<Rollup_Definition__c> definitions = realTimeForThisUser();
        if (!definitions.isEmpty()) {
            recalculateNowOrQueue(
                RollupChanges.afterDelete(sourceObject, deletedRecords, definitions)
            );
        }
    }

    /**
     * Recalculates the totals on the survivors of a merge (C-20).
     *
     * The platform's merge moves the merged-away record's children onto the survivor without
     * saving them, so no trigger on a child runs. By `after delete` the children already point
     * at the survivor, so this recalculates every active real-time definition that targets the
     * merged entity, whatever package declared it (Core names no child entity, ADR-0014), for the
     * survivors only.
     *
     * @param targetObject the entity whose records were merged
     * @param mergedRecords the deleted records, as the `after delete` trigger has them; only
     *        those with `MasterRecordId` filled were merged, and it names the survivor
     */
    @NamespaceAccessible
    public static void runAfterMerge(String targetObject, List<SObject> mergedRecords) {
        if (String.isBlank(targetObject) || mergedRecords == null) {
            return;
        }
        Set<Id> survivorIds = new Set<Id>();
        for (SObject record : mergedRecords) {
            Object survivorId = record.getPopulatedFieldsAsMap().get(MERGE_SURVIVOR_FIELD);
            if (survivorId != null) {
                survivorIds.add((Id) survivorId);
            }
        }
        runForSurvivors(targetObject, survivorIds);
    }

    /**
     * Recalculates the real-time totals on these merge survivors, as `runAfterMerge` does
     * once it has read the survivors off the deleted records. A person stored as an account
     * has a second record behind it, its person contact, whose own totals the merge also
     * changes; `AccountTriggerHandler` names those here, since the deleted account records
     * only name the surviving account. Run just after the save, not in it (R-R4): the platform
     * refuses a trigger's write to a record while it is in a merge, so a recalculation in the
     * same save would fail and wait minutes for a retry. A save that cannot start a job, or has
     * many survivors, hands them to the Rollup Queue instead.
     *
     * @param targetObject the entity whose totals the merge changed
     * @param survivorIds the records of that entity that survived the merge
     */
    @NamespaceAccessible
    public static void runForSurvivors(String targetObject, Set<Id> survivorIds) {
        Schema.SObjectType targetType = SettingsService.typeByName(targetObject);
        if (targetType == null || survivorIds == null || survivorIds.isEmpty() || isTurnedOff()) {
            return;
        }
        List<Rollup_Definition__c> definitions = withoutBypassed(
            RollupSelector.selectActiveForTarget(targetObject, REAL_TIME_MODES)
        );
        if (definitions.isEmpty()) {
            return;
        }
        lastParentIds = survivorIds;
        String target = String.valueOf(targetType);
        // Inside a Queueable the one job it may queue belongs to its own next step, never to
        // the engine (`RollupQueue.requestProcessor`), so survivors go to the queue there too.
        if (
            survivorIds.size() > instantLimit ||
            System.isQueueable() ||
            Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()
        ) {
            queue(
                new Map<String, Set<Id>>{ target => survivorIds },
                new Map<String, List<Rollup_Definition__c>>{ target => definitions }
            );
            return;
        }
        System.enqueueJob(new SurvivorRecalculation(target, survivorIds, definitions));
    }

    /**
     * Starts the Rollup Queue's processor when entries are pending. A background job that saved
     * records calls this when it has no next step of its own: inside a Queueable the engine
     * never takes the job's one chained job, so the totals it queued would otherwise wait for a
     * later save or the nightly run.
     */
    @NamespaceAccessible
    public static void startQueuedRecalculation() {
        RollupQueue.startProcessor();
    }

    /**
     * The real-time totals on merge survivors, recalculated once the merge is saved. Only the
     * definitions the merge asked for: the Rollup Queue would also run the nightly ones. A
     * record the platform still refuses is queued to be tried again, and anything that stops
     * the run queues the lot, as in a save.
     */
    private class SurvivorRecalculation implements Queueable {
        private final String target;
        private final Set<Id> survivorIds;
        private final List<Rollup_Definition__c> definitions;

        SurvivorRecalculation(
            String target,
            Set<Id> survivorIds,
            List<Rollup_Definition__c> definitions
        ) {
            this.target = target;
            this.survivorIds = survivorIds;
            this.definitions = definitions;
        }

        public void execute(QueueableContext context) {
            if (isTurnedOff()) {
                // Turned off since the merge (ADR-0125 decision 9): the survivors wait in the
                // queue, which Turn on drains.
                ErrorLogger.logMessage(
                    System.Label.Core_Rollups_RunStoppedTurnedOff,
                    CONTEXT_REAL_TIME,
                    ErrorLogger.SEVERITY_INFO
                );
                queue(
                    new Map<String, Set<Id>>{ target => survivorIds },
                    new Map<String, List<Rollup_Definition__c>>{ target => definitions }
                );
                return;
            }
            try {
                RollupQueue.retryLater(
                    target,
                    RollupEngine.recalculate(survivorIds, definitions).failed,
                    0,
                    idsOf(definitions)
                );
            } catch (Exception stopped) {
                ErrorLogger.log(stopped, CONTEXT_REAL_TIME);
                queue(
                    new Map<String, Set<Id>>{ target => survivorIds },
                    new Map<String, List<Rollup_Definition__c>>{ target => definitions }
                );
            }
        }
    }

    /**
     * Recalculates the totals a save of these records changed, for an entity BarnCRM ships no
     * trigger for. The Recalculate rollups Flow action calls this (R-R12, `RollupRecalcAction`):
     * the same marking as a packaged trigger (R-R11), in the same save or queued (R-R4).
     *
     * A record-triggered Flow on delete runs before the record is gone, so a recalculation then
     * would still count it: the targets of a record being deleted are queued instead, and the
     * processor runs after the delete is committed.
     *
     * @param sourceObject the entity whose records changed
     * @param records the records as saved, or as they are before a delete
     * @param oldRecords the same records before an update, or null
     * @param deleting true when the records are about to be deleted
     */
    @NamespaceAccessible
    public static void runForFlow(
        String sourceObject,
        List<SObject> records,
        Map<Id, SObject> oldRecords,
        Boolean deleting
    ) {
        if (String.isBlank(sourceObject) || records == null || records.isEmpty() || isStopped()) {
            return;
        }
        List<Rollup_Definition__c> definitions = realTimeForThisUser();
        if (definitions.isEmpty()) {
            return;
        }
        if (deleting == true) {
            RollupChanges.Marked marked = RollupChanges.afterDelete(
                sourceObject,
                records,
                definitions
            );
            Map<String, Set<Id>> idsByTarget = idsByTargetOf(marked);
            queue(idsByTarget, definitionsByTargetOf(marked, idsByTarget.keySet()));
            return;
        }
        recalculateNowOrQueue(
            RollupChanges.forSave(sourceObject, records, oldRecords, false, definitions)
        );
    }

    /** Marked records keyed by each target entity's own API name; unknown entities are dropped. */
    private static Map<String, Set<Id>> idsByTargetOf(RollupChanges.Marked marked) {
        Map<String, Set<Id>> idsByTarget = new Map<String, Set<Id>>();
        for (String target : marked.idsByTarget.keySet()) {
            Schema.SObjectType targetType = SettingsService.typeByName(target);
            if (targetType != null) {
                idsByTarget.put(String.valueOf(targetType), marked.idsByTarget.get(target));
            }
        }
        return idsByTarget;
    }

    /**
     * The definitions that marked each target entity's records, which are the ones recalculated
     * (ADR-0099 `0099-rollups-recalculate-only-what-a-save-changed.md`): a gift save does not
     * run the soft credit totals on the donor. When one of them has no record id to name it,
     * every active definition on the entity runs, as before.
     */
    private static Map<String, List<Rollup_Definition__c>> definitionsByTargetOf(
        RollupChanges.Marked marked,
        Set<String> targets
    ) {
        Map<String, List<Rollup_Definition__c>> definitionsByTarget = new Map<String, List<Rollup_Definition__c>>();
        for (String target : targets) {
            List<Rollup_Definition__c> definitions = marked.definitionsFor(target);
            definitionsByTarget.put(
                target,
                definitions == null
                    ? withoutBypassed(RollupSelector.selectActiveForTarget(target, EVERY_MODE))
                    : definitions
            );
        }
        return definitionsByTarget;
    }

    /**
     * Queues the records with the definitions to recalculate for them. A target entity left
     * with an empty list has nothing to run (every definition on it bypassed for this user,
     * R-R4a) and is not queued, since an entry naming no definition runs every one.
     */
    private static void queue(
        Map<String, Set<Id>> idsByTarget,
        Map<String, List<Rollup_Definition__c>> definitionsByTarget
    ) {
        Map<String, Set<Id>> queuedIds = new Map<String, Set<Id>>();
        Map<String, Set<Id>> definitionIdsByTarget = new Map<String, Set<Id>>();
        for (String target : idsByTarget.keySet()) {
            List<Rollup_Definition__c> definitions = definitionsByTarget.get(target);
            if (definitions != null && definitions.isEmpty()) {
                continue;
            }
            queuedIds.put(target, idsByTarget.get(target));
            definitionIdsByTarget.put(target, idsOf(definitions));
        }
        RollupQueue.add(queuedIds, definitionIdsByTarget);
    }

    /** The definitions' ids; a definition with none leaves a null in, which queues every one. */
    private static Set<Id> idsOf(List<Rollup_Definition__c> definitions) {
        if (definitions == null) {
            return null;
        }
        Set<Id> ids = new Set<Id>();
        for (Rollup_Definition__c definition : definitions) {
            ids.add(definition.Id);
        }
        return ids;
    }

    /**
     * R-R4: by default every save queues the records it marked, and the Rollup Queue
     * recalculates them just after the save (ADR-0098 async rollups), so a save pays for marking
     * and one insert, never for the aggregate queries. With Rollup Processing set to In the
     * save, a normal save that marks a few records recalculates them in the same save when the
     * transaction has room for it; a bulk change, a save already running in the background, or
     * one without the room queues them. A record the platform refuses to save is queued to be
     * tried again, and anything that stops the recalculation queues the lot, so nothing marked
     * is lost.
     */
    private static void recalculateNowOrQueue(RollupChanges.Marked marked) {
        if (marked.isEmpty()) {
            return;
        }
        Map<String, Set<Id>> idsByTarget = idsByTargetOf(marked);
        recalculateNowOrQueue(
            idsByTarget,
            definitionsByTargetOf(marked, idsByTarget.keySet()),
            marked.size(),
            recalculatesInTheSave()
        );
    }

    /**
     * Recalculates these records now when `now` is asked for and the transaction has room,
     * otherwise queues them; a refused record is queued to be tried again and anything that
     * stops the recalculation queues the lot.
     */
    private static void recalculateNowOrQueue(
        Map<String, Set<Id>> idsByTarget,
        Map<String, List<Rollup_Definition__c>> definitionsByTarget,
        Integer targetCount,
        Boolean now
    ) {
        if (!now || !canRecalculateNow(targetCount, definitionsByTarget)) {
            queue(idsByTarget, definitionsByTarget);
            return;
        }
        try {
            for (String target : idsByTarget.keySet()) {
                List<Rollup_Definition__c> definitions = definitionsByTarget.get(target);
                RollupEngine.Result result = RollupEngine.recalculate(
                    idsByTarget.get(target),
                    definitions
                );
                RollupQueue.retryLater(target, result.failed, 0, idsOf(definitions));
            }
        } catch (Exception stopped) {
            ErrorLogger.log(stopped, CONTEXT_REAL_TIME);
            queue(idsByTarget, definitionsByTarget);
        }
    }

    // ------------------------------------------------------------------------- named records

    /**
     * Recalculates the totals on these target records (R-R12 note, ADR-0136): every active
     * definition targeting each record's entity, whatever its mode, or only the one named. The
     * Recalculate totals on this record Flow action and `RollupApi.recalculate` call this. It is
     * a request for these totals, not a save, so a Bypass Permission does not apply (R-R4a) and
     * the records are recalculated in this transaction whenever it has room, whatever Rollup
     * Processing says; a bulk request, a background transaction or one without the room queues
     * them. Nothing happens while the module is turned off: Turn on recalculates every total.
     *
     * @param targetIds the records whose totals to recalculate, of any entities
     * @param rollup a definition's Definition Key or name, or blank for every one
     * @return the target entities that had something to recalculate
     */
    @NamespaceAccessible
    public static Set<String> recalculateTargets(Set<Id> targetIds, String rollup) {
        Map<String, Set<Id>> idsByTarget = new Map<String, Set<Id>>();
        Map<String, List<Rollup_Definition__c>> definitionsByTarget = new Map<String, List<Rollup_Definition__c>>();
        if (targetIds == null || isTurnedOff()) {
            return idsByTarget.keySet();
        }
        Integer count = 0;
        for (Id targetId : targetIds) {
            if (targetId == null) {
                continue;
            }
            String target = String.valueOf(targetId.getSObjectType());
            if (!definitionsByTarget.containsKey(target)) {
                definitionsByTarget.put(target, named(target, rollup));
            }
            if (definitionsByTarget.get(target).isEmpty()) {
                continue;
            }
            if (!idsByTarget.containsKey(target)) {
                idsByTarget.put(target, new Set<Id>());
            }
            idsByTarget.get(target).add(targetId);
            count++;
        }
        if (!idsByTarget.isEmpty()) {
            recalculateNowOrQueue(idsByTarget, definitionsByTarget, count, true);
        }
        return idsByTarget.keySet();
    }

    /** The active definitions on this target entity, or only the one with this key or name. */
    private static List<Rollup_Definition__c> named(String target, String rollup) {
        List<Rollup_Definition__c> definitions = RollupSelector.selectActiveForTarget(
            target,
            EVERY_MODE
        );
        if (String.isBlank(rollup)) {
            return definitions;
        }
        String wanted = rollup.trim();
        List<Rollup_Definition__c> matching = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : definitions) {
            if (
                wanted.equalsIgnoreCase(definition.Definition_Key__c) ||
                wanted.equalsIgnoreCase(definition.Name)
            ) {
                matching.add(definition);
            }
        }
        return matching;
    }

    /** Whether this transaction recalculates now: few records, not async, room to spare. */
    @TestVisible
    private static Boolean canRecalculateNow(Integer targetCount) {
        return targetCount <= instantLimit &&
            !System.isBatch() &&
            !System.isFuture() &&
            !System.isQueueable() &&
            !System.isScheduled() &&
            Limits.getQueries() * 2 < Limits.getLimitQueries() &&
            Limits.getDmlStatements() * 2 < Limits.getLimitDmlStatements() &&
            Limits.getCpuTime() * 2 < Limits.getLimitCpuTime() &&
            Limits.getQueryRows() * 2 < Limits.getLimitQueryRows();
    }

    /**
     * As above, and the queries the recalculation is planned to spend fit in what the
     * transaction has left (ROLLUPS-2): a save that reaches the rollups with 45 queries used
     * must queue, since a limit error there would fail the person's save and no catch can stop
     * it. The estimate costs no query: definitions come from the transaction's cache.
     */
    @TestVisible
    private static Boolean canRecalculateNow(
        Integer targetCount,
        Map<String, List<Rollup_Definition__c>> definitionsByTarget
    ) {
        if (!canRecalculateNow(targetCount)) {
            return false;
        }
        return plannedQueries(definitionsByTarget) <=
            Limits.getLimitQueries() - Limits.getQueries();
    }

    /**
     * The queries a recalculation of these definitions spends at most: one per definition (the
     * planner folds some together, never splits one), one more for a path through a household
     * token, and the fixed cost of each target entity. Counted, not planned, so a definition
     * that cannot be planned is not logged twice. A pure count with no side effects, so it is
     * shared rather than test visible: Giving's save cost test budgets against it.
     */
    @NamespaceAccessible
    public static Integer plannedQueries(
        Map<String, List<Rollup_Definition__c>> definitionsByTarget
    ) {
        Integer planned = 0;
        for (List<Rollup_Definition__c> definitions : definitionsByTarget.values()) {
            if (definitions == null || definitions.isEmpty()) {
                continue;
            }
            planned += QUERIES_PER_TARGET;
            for (Rollup_Definition__c definition : definitions) {
                String path = definition.Relationship_Path__c;
                planned += String.isNotBlank(path) && path.contains('{') ? 2 : 1;
            }
        }
        return planned;
    }

    // ---------------------------------------------------------------------------- full runs

    /**
     * A full recalculation of a set of definitions over every record they write: one batch pass
     * per target entity, which marks the definitions calculated itself when its last pass
     * finishes (R-R13), never at hand-over. This is the path R-R9 talks about: recalculating any
     * set of records produces the same result as calculating it the first time, so the nightly
     * run reconciles whatever real time missed.
     *
     * @param definitions the definitions to recalculate, of any source and target entities
     * @return how many were handed to the run, or zero when nothing started, including when
     *         another full run is still going (R-R14)
     */
    @NamespaceAccessible
    public static Integer runFullRecalculation(List<Rollup_Definition__c> definitions) {
        if (definitions == null || definitions.isEmpty()) {
            return 0;
        }
        Id running = RollupFullRecalcBatch.runningJobId();
        Id started = RollupFullRecalcBatch.begin(definitions);
        return started == null || started == running ? 0 : definitions.size();
    }

    /**
     * Starts the nightly run now: every active Scheduled and Both definition, over every record
     * (R-R4). The nightly job calls this.
     *
     * @return the batch job started, the full run still going when there is one (R-R14), or
     *         null when nothing started
     */
    public static Id startNightlyRun() {
        return RollupFullRecalcBatch.begin(RollupSelector.selectActiveForModes(SCHEDULED_MODES));
    }

    /**
     * Recalculate all: every active definition whatever its mode, Instantly ones too, over every
     * record. An administrator who clicks it expects every total rebuilt (owner decision on
     * ROLLUPS-8), which the nightly run's Scheduled and Both scope does not do.
     *
     * @return the batch job started, the full run still going when there is one (R-R14), or
     *         null when nothing started
     */
    public static Id startFullRunOfEveryDefinition() {
        return RollupFullRecalcBatch.begin(RollupSelector.selectActiveForModes(EVERY_MODE));
    }

    /** The modes Recalculate all covers: every one. */
    @NamespaceAccessible
    public static Set<String> everyMode() {
        return new Set<String>(EVERY_MODE);
    }

    /**
     * Recalculates one definition now. This is the Recalculate action on the Rollups page.
     *
     * @param definitionId the definition to recalculate
     */
    @NamespaceAccessible
    public static void recalculate(Id definitionId) {
        Rollup_Definition__c definition = RollupSelector.selectById(definitionId);
        if (definition == null) {
            throw new RollupServiceException(System.Label.Core_Rollups_ErrorUnknownDefinition);
        }
        runFullRecalculation(new List<Rollup_Definition__c>{ definition });
    }

    // ---------------------------------------------------------------------------- materializing

    /**
     * Creates a Rollup Definition for every shipped default that does not have one yet, and leaves
     * every existing definition exactly as the administrator left it (R-R6). Safe on every install,
     * every upgrade, and twice in a row. Returns how many it created.
     *
     * A shipped default whose target field an active definition of the administrator's own
     * already writes is not created (C-21, ADR-0048): two definitions writing one field would
     * overwrite each other's total, and the one already here is her choice. Only her own
     * definitions count: shipped pairs such as the household and the organization giving total
     * write the same field for different accounts by design. `skippedDefaultNames` names them.
     *
     * This is called from a post-install script as well as from the Rollups page (ADR-0029), so it
     * is written for that context: one query for the shipped rows, one for the existing ones, one
     * describe per distinct entity name however many rows mention it, and a single insert.
     */
    @NamespaceAccessible
    public static Integer ensureDefaults() {
        List<Rollup_Definition__c> toCreate = planDefaults().toCreate;
        RollupWriter.insertDefinitions(toCreate);
        return toCreate.size();
    }

    /**
     * The names of the shipped defaults this org does not have yet, without creating them, so
     * Health Check can say what restoring them would add (C-21, ADR-0048).
     */
    @NamespaceAccessible
    public static List<String> missingDefaultNames() {
        List<String> names = new List<String>();
        for (Rollup_Definition__c definition : planDefaults().toCreate) {
            names.add(definition.Name);
        }
        return names;
    }

    /**
     * The names of the shipped defaults this org does not have and that restoring leaves out,
     * because an active definition the administrator made already writes the same target field
     * (C-21, ADR-0048).
     */
    @NamespaceAccessible
    public static List<String> skippedDefaultNames() {
        return planDefaults().skippedNames;
    }

    /** What ensureDefaults would do: the definitions it creates, and the ones it leaves out. */
    private class DefaultsPlan {
        List<Rollup_Definition__c> toCreate = new List<Rollup_Definition__c>();
        List<String> skippedNames = new List<String>();
    }

    private static DefaultsPlan planDefaults() {
        DefaultsPlan plan = new DefaultsPlan();
        List<Rollup_Definition_Default__mdt> shipped = RollupSelector.selectShippedDefaults();
        if (shipped.isEmpty()) {
            return plan;
        }
        Set<String> existingKeys = new Set<String>();
        Set<String> writtenTargets = new Set<String>();
        for (Rollup_Definition__c definition : RollupSelector.selectAll()) {
            if (String.isNotBlank(definition.Definition_Key__c)) {
                existingKeys.add(definition.Definition_Key__c.toLowerCase());
            }
            if (definition.Active__c == true && definition.Is_Package_Default__c != true) {
                writtenTargets.add(
                    targetKey(definition.Target_Object__c, definition.Target_Field__c)
                );
            }
        }
        Map<String, Boolean> presentByName = new Map<String, Boolean>();
        for (Rollup_Definition_Default__mdt shippedDefault : shipped) {
            String key = shippedDefault.Definition_Key__c;
            if (String.isBlank(key) || existingKeys.contains(key.toLowerCase())) {
                continue;
            }
            if (!isShippableHere(shippedDefault, presentByName)) {
                continue;
            }
            existingKeys.add(key.toLowerCase());
            Rollup_Definition__c definition = materialize(shippedDefault);
            if (
                writtenTargets.contains(
                    targetKey(shippedDefault.Target_Object__c, shippedDefault.Target_Field__c)
                )
            ) {
                plan.skippedNames.add(definition.Name);
                continue;
            }
            plan.toCreate.add(definition);
        }
        return plan;
    }

    /** One target field, compared without regard to case. */
    private static String targetKey(String targetObject, String targetField) {
        return (String.isBlank(targetObject) ? '' : targetObject.toLowerCase()) +
            '.' +
            (String.isBlank(targetField) ? '' : targetField.toLowerCase());
    }

    /**
     * The same thing, called from a post-install script, where nothing may throw (ADR-0029).
     *
     * A package's install must not fail because its totals could not be created: an org with
     * blank totals is recoverable from the Rollups page in two clicks, and an install that the
     * platform rolled back is not. So a failure is written to the Error Log and the caller is
     * told nothing was created.
     *
     * @param context the calling script, so the Error Log entry names it
     * @return how many definitions were created, and zero when the step failed
     */
    @NamespaceAccessible
    public static Integer ensureDefaultsDuringInstall(String context) {
        try {
            return ensureDefaults();
        } catch (Exception failed) {
            ErrorLogger.log(failed, String.isBlank(context) ? CONTEXT_ENSURE_DEFAULTS : context);
            return 0;
        }
    }

    /**
     * Whether a shipped default can be materialized in this org. A row shipped by a module that is
     * not installed has neither its source nor its target entity here, so it is skipped rather
     * than creating a definition that names objects nobody has (R-R6, plan Principle 3). Asking
     * the org what exists is the general answer: it needs no list of package names, and it is
     * right for a module Core has never heard of.
     */
    private static Boolean isShippableHere(
        Rollup_Definition_Default__mdt shippedDefault,
        Map<String, Boolean> presentByName
    ) {
        return isPresent(shippedDefault.Source_Object__c, presentByName) &&
            isPresent(shippedDefault.Target_Object__c, presentByName);
    }

    /**
     * Whether the org has an entity with this name, answered once per name.
     *
     * The answer is remembered because the shipped rows name a handful of entities between them
     * (every giving total on a donor names Gift and Account), and each miss walks the org's whole
     * describe. Forty rows asking twice each is eighty walks in a post-install transaction that
     * has no user to wait for it.
     */
    private static Boolean isPresent(String apiName, Map<String, Boolean> presentByName) {
        if (String.isBlank(apiName)) {
            return false;
        }
        if (!presentByName.containsKey(apiName)) {
            presentByName.put(apiName, SettingsService.typeByName(apiName) != null);
        }
        return presentByName.get(apiName);
    }

    private static Rollup_Definition__c materialize(Rollup_Definition_Default__mdt shippedDefault) {
        return new Rollup_Definition__c(
            Name = String.isBlank(shippedDefault.MasterLabel)
                ? shippedDefault.Definition_Key__c
                : shippedDefault.MasterLabel,
            Description__c = shippedDefault.Description__c,
            Definition_Key__c = shippedDefault.Definition_Key__c,
            Source_Object__c = shippedDefault.Source_Object__c,
            Target_Object__c = shippedDefault.Target_Object__c,
            Relationship_Path__c = shippedDefault.Relationship_Path__c,
            Aggregate__c = shippedDefault.Aggregate__c,
            Source_Field__c = shippedDefault.Source_Field__c,
            Order_By_Field__c = shippedDefault.Order_By_Field__c,
            Target_Field__c = shippedDefault.Target_Field__c,
            Filter_JSON__c = shippedDefault.Filter_JSON__c,
            Target_Filter_JSON__c = shippedDefault.Target_Filter_JSON__c,
            Fiscal_Year_Aware__c = shippedDefault.Fiscal_Year_Aware__c == true,
            Fiscal_Year_Offset__c = shippedDefault.Fiscal_Year_Offset__c,
            Fiscal_Date_Field__c = shippedDefault.Fiscal_Date_Field__c,
            Mode__c = String.isBlank(shippedDefault.Mode__c)
                ? defaultMode()
                : shippedDefault.Mode__c,
            Is_Package_Default__c = true,
            Active__c = shippedDefault.Default_Active__c == true
        );
    }

    // ------------------------------------------------------------------------------- freshness

    /** When the rollups were last calculated across every active definition. */
    @NamespaceAccessible
    public static Datetime lastCalculated() {
        return RollupSelector.lastCalculatedAcrossActive();
    }

    /** True when the rollups have not completed inside the freshness window. */
    @NamespaceAccessible
    public static Boolean isStale() {
        Datetime latest = lastCalculated();
        return latest == null || latest < Datetime.now().addHours(-STALE_AFTER_HOURS);
    }
}
