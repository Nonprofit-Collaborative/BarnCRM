/**
 * The rollup engine, as the rest of BarnCRM sees it.
 *
 * Everything a feature, a trigger, a batch or the console needs is here, and the engine behind it
 * is BarnCRM's own (`decisions/0082-barncrm-owns-its-rollup-engine.md`, slice S8). Three things
 * happen:
 *
 * - **Real time.** A trigger on a source entity calls `runRealTime`. `RollupChanges` works out
 *   which target records the save marks (R-R11), and they are recalculated in the same save or,
 *   for a bulk or background save, written to the Rollup Queue (R-R4, Section 14A).
 * - **Scheduled.** `RollupScheduler` calls `startNightlyRun` for the definitions in Scheduled or
 *   Both mode, which is the nightly reconciliation R-R4 describes: `RollupFullRecalcBatch`.
 * - **On demand.** `recalculate` runs one definition over every record now, which is what the
 *   Recalculate action on the Rollups page does.
 *
 * Freshness is the engine's own: `RollupWriter` stamps `Rollups_Last_Calculated__c` on a record
 * in the same write as its totals, and the full recalculation marks a definition calculated when
 * its run has finished (R-R13).
 *
 * The vendored apex-rollup tree and `RollupAdapter` are no longer reached from here. They stay in
 * the repository only for `RollupEngineComparison`, until the comparison run the ADR requires.
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

    /** The records the last merge recalculated, so a test can see only survivors were. */
    @TestVisible
    private static Set<Id> lastParentIds;

    /**
     * The target records a normal save recalculates itself (R-R4); a save that marks more goes
     * to the Rollup Queue.
     */
    @TestVisible
    private static Integer instantLimit = 50;

    /** The modes a nightly run covers. */
    @NamespaceAccessible
    public static Set<String> scheduledModes() {
        return new Set<String>(SCHEDULED_MODES);
    }

    /** The mode a new definition starts in, from the org's default. */
    @NamespaceAccessible
    public static String defaultMode() {
        Object stored = SettingsService.getValue('Rollup_Mode_Default__c');
        String mode = stored == null ? null : String.valueOf(stored);
        return REAL_TIME_MODES.contains(mode) || MODE_SCHEDULED.equals(mode) ? mode : MODE_BOTH;
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
        if (String.isBlank(sourceObject) || changedRecords == null || changedRecords.isEmpty()) {
            return;
        }
        List<Rollup_Definition__c> definitions = RollupSelector.selectActiveForModes(
            REAL_TIME_MODES
        );
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
        if (String.isBlank(sourceObject) || deletedRecords == null) {
            return;
        }
        List<Rollup_Definition__c> definitions = RollupSelector.selectActiveForModes(
            REAL_TIME_MODES
        );
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
        if (targetType == null || survivorIds == null || survivorIds.isEmpty()) {
            return;
        }
        List<Rollup_Definition__c> definitions = RollupSelector.selectActiveForTarget(
            targetObject,
            REAL_TIME_MODES
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
            RollupQueue.add(new Map<String, Set<Id>>{ target => survivorIds });
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
            try {
                RollupQueue.retryLater(
                    target,
                    RollupEngine.recalculate(survivorIds, definitions).failed,
                    0
                );
            } catch (Exception stopped) {
                ErrorLogger.log(stopped, CONTEXT_REAL_TIME);
                RollupQueue.add(new Map<String, Set<Id>>{ target => survivorIds });
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
        if (
            String.isBlank(sourceObject) ||
            records == null ||
            records.isEmpty() ||
            AutomationControl.isPaused()
        ) {
            return;
        }
        List<Rollup_Definition__c> definitions = RollupSelector.selectActiveForModes(
            REAL_TIME_MODES
        );
        if (definitions.isEmpty()) {
            return;
        }
        if (deleting == true) {
            RollupQueue.add(
                idsByTargetOf(RollupChanges.afterDelete(sourceObject, records, definitions))
            );
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
     * R-R4: a normal save that marks a few records recalculates them in the same save; a bulk
     * change, or a save already running in the background, queues them. A record the platform
     * refuses to save is queued to be tried again, and anything that stops the recalculation
     * queues the lot, so nothing marked is lost.
     */
    private static void recalculateNowOrQueue(RollupChanges.Marked marked) {
        if (marked.isEmpty()) {
            return;
        }
        Map<String, Set<Id>> idsByTarget = idsByTargetOf(marked);
        if (!canRecalculateNow(marked.size())) {
            RollupQueue.add(idsByTarget);
            return;
        }
        try {
            for (String target : idsByTarget.keySet()) {
                RollupEngine.Result result = RollupEngine.recalculate(
                    idsByTarget.get(target),
                    SettingsService.typeByName(target)
                );
                RollupQueue.retryLater(target, result.failed, 0);
            }
        } catch (Exception stopped) {
            ErrorLogger.log(stopped, CONTEXT_REAL_TIME);
            RollupQueue.add(idsByTarget);
        }
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
            Limits.getCpuTime() * 2 < Limits.getLimitCpuTime();
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
     * (R-R4). The scheduled job and the Recalculate all button both call this.
     *
     * @return the batch job started, the full run still going when there is one (R-R14), or
     *         null when nothing started
     */
    public static Id startNightlyRun() {
        return RollupFullRecalcBatch.begin(RollupSelector.selectActiveForModes(SCHEDULED_MODES));
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
