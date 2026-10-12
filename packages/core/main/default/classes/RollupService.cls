/**
 * The rollup engine, as the rest of BarnCRM sees it.
 *
 * Everything a feature, a trigger, a batch or the console needs is here, and nothing outside this
 * package's `Rollup*` classes ever names the vendored engine (ADR-0015). Three things happen:
 *
 * - **Real time.** A trigger on a source entity calls `runRealTime`, which finds the active
 *   definitions for that entity in Real-time or Both mode, hands them to the engine as in-memory
 *   metadata, and stamps freshness when the run completes.
 * - **Scheduled.** `RollupScheduler` calls `startNightlyRun` for the definitions in Scheduled or
 *   Both mode, which is the nightly reconciliation R-R4 describes: `RollupBatch` on the vendored
 *   engine, `RollupFullRecalcBatch` on BarnCRM's own.
 * - **On demand.** `recalculate` runs one definition now, which is what the Recalculate action on
 *   the Rollups page does.
 *
 * Freshness is ours, not the engine's (ADR-0015, "Last Calculated"). The definition's own
 * `Last_Calculated__c` answers "when did this rollup last run" for the console, and the single
 * `Rollups_Last_Calculated__c` on each target entity answers "when was this record last
 * recalculated" on the record page (canonical model Section 26).
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

    /** Queued jobs a merge leaves room for, for the automation that runs after it. */
    private static final Integer QUEUEABLE_HEADROOM = 10;

    /** The one freshness attribute every target entity carries (canonical model Section 26). */
    @NamespaceAccessible
    public static final String FRESHNESS_FIELD = 'Rollups_Last_Calculated__c';

    /** The hours after which the Hub calls the nightly run overdue (plan Section 4.10). */
    @NamespaceAccessible
    public static final Integer STALE_AFTER_HOURS = 36;

    private static final String CONTEXT_REAL_TIME = 'RollupService.runRealTime';
    private static final String CONTEXT_RECALCULATE = 'RollupService.recalculate';
    private static final String CONTEXT_ENSURE_DEFAULTS = 'RollupService.ensureDefaults';

    private static final Set<String> REAL_TIME_MODES = new Set<String>{ MODE_REAL_TIME, MODE_BOTH };
    private static final Set<String> SCHEDULED_MODES = new Set<String>{ MODE_SCHEDULED, MODE_BOTH };

    /** Set by a test so a run can be asserted without the engine being reachable. */
    @TestVisible
    private static Boolean skipEngine = false;

    /** What the last call handed the engine, so a test can assert the mapping end to end. */
    @TestVisible
    private static List<Rollup__mdt> lastMetadata;

    /** The records the last recalculation was limited to, or null when it covered every record. */
    @TestVisible
    private static Set<Id> lastParentIds;

    /** How many separate engine calls the last recalculation made, one per source entity. */
    @TestVisible
    private static Integer lastEngineCalls;

    /**
     * True when every call below goes to BarnCRM's own engine (`RollupEngine`) rather than the
     * vendored one. Only a test can set it, through `useOwnEngineInTests`, so the regression
     * suite can judge the new engine before slice S8 swaps it in for everyone; S8 removes the
     * switch and the vendored calls together. Under the switch a save's changes are collected by
     * `RollupChanges` and recalculated now or through `RollupQueue` (slice S6).
     */
    private static Boolean useOwnEngine = false;

    /** Routes this test's rollups to BarnCRM's own engine. Does nothing outside a test. */
    @NamespaceAccessible
    public static void useOwnEngineInTests() {
        if (Test.isRunningTest()) {
            useOwnEngine = true;
        }
    }

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
     * Recalculates, in this transaction, every active real-time definition whose source entity is
     * the one that just changed.
     *
     * Called from a trigger handler, never directly, so that the automation is bypassable and
     * pausable like every other packaged automation (R-A1). A rollup that cannot be expressed is
     * logged and skipped: one broken definition must not fail the administrator's save.
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
        if (useOwnEngine) {
            runOwnEngine(sourceObject, changedRecords, oldRecords);
            return;
        }
        List<Rollup_Definition__c> definitions = vendoredRealTime(
            RollupSelector.selectActiveForSource(sourceObject, REAL_TIME_MODES)
        );
        if (definitions.isEmpty()) {
            return;
        }
        List<Rollup__mdt> metadata = new List<Rollup__mdt>();
        List<Rollup_Definition__c> ran = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : definitions) {
            try {
                metadata.addAll(
                    RollupAdapter.toMetadata(new List<Rollup_Definition__c>{ definition })
                );
                ran.add(definition);
            } catch (Exception refused) {
                ErrorLogger.log(refused, CONTEXT_REAL_TIME, definition.Id);
            }
        }
        if (metadata.isEmpty()) {
            return;
        }
        lastMetadata = metadata;
        if (skipEngine != true) {
            // Inside a trigger the engine reads the operation from the trigger context itself,
            // which is why this entry point is only ever called from a handler.
            Rollup.runFromApex(metadata, null, changedRecords, oldRecords)?.runCalc();
        }
        stampAfterRun(ran, targetIdsFor(ran, changedRecords));
    }

    /**
     * Recalculates the totals on the survivors of a merge (C-20).
     *
     * The platform's merge moves the merged-away record's children onto the survivor without
     * saving them, so no trigger on a child runs and a real-time total on the survivor would
     * not include them until the nightly run. By `after delete` the children already point at
     * the survivor, so this recalculates every active real-time definition that targets the
     * merged entity, whatever package declared it (Core names no child entity, ADR-0014), for
     * the survivors only: the engine counts and reads the survivors' children, not the whole
     * table, so a merge queues one small job per source entity and never a batch job while a
     * survivor has fewer children than the engine's batching threshold.
     *
     * The engine's own after-delete merge handling queued nothing in a test run, which is why
     * the survivors are handed to the recalculation the Rollups page uses instead. When the
     * transaction has too little room left for those jobs, nothing is queued, an Info entry
     * says so, and the nightly run brings a Both definition up to date.
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
     * only name the surviving account.
     *
     * @param targetObject the entity whose totals the merge changed
     * @param survivorIds the records of that entity that survived the merge
     */
    @NamespaceAccessible
    public static void runForSurvivors(String targetObject, Set<Id> survivorIds) {
        if (String.isBlank(targetObject) || survivorIds == null || survivorIds.isEmpty()) {
            return;
        }
        List<Rollup_Definition__c> definitions = RollupSelector.selectActiveForTarget(
            targetObject,
            REAL_TIME_MODES
        );
        if (definitions.isEmpty()) {
            return;
        }
        Integer jobsNeeded = sourcesOf(definitions).size();
        if (
            Limits.getQueueableJobs() + jobsNeeded + QUEUEABLE_HEADROOM >
            Limits.getLimitQueueableJobs()
        ) {
            ErrorLogger.logMessage(
                String.format(
                    System.Label.Core_Rollups_MergeRecalcDeferred,
                    new List<String>{ targetObject }
                ),
                CONTEXT_REAL_TIME,
                ErrorLogger.SEVERITY_INFO
            );
            return;
        }
        handToEngine(definitions, survivorIds, CONTEXT_REAL_TIME);
    }

    // -------------------------------------------------------------------------------- scheduled

    /**
     * A full recalculation of a set of definitions, in the engine's own batch context.
     *
     * This is the path R-R9 talks about: recalculating any set of records produces the same result
     * as calculating it the first time, so the nightly run reconciles whatever real time missed.
     *
     * The engine is called once per source entity. One call spanning definitions with different
     * source entities fails inside the vendored engine, so definitions are grouped by source
     * before they are handed over, and any mix of definitions is safe to pass.
     *
     * @param definitions the definitions to recalculate
     * @return how many were handed to the engine
     */
    @NamespaceAccessible
    public static Integer runFullRecalculation(List<Rollup_Definition__c> definitions) {
        if (definitions == null || definitions.isEmpty()) {
            return 0;
        }
        if (useOwnEngine) {
            // A batch over every record, one target entity at a time, that marks the definitions
            // calculated itself when its last pass finishes (R-R13, bug 5), never at hand-over.
            return RollupFullRecalcBatch.begin(definitions) == null ? 0 : definitions.size();
        }
        List<Rollup_Definition__c> ran = handToEngine(definitions, null, CONTEXT_RECALCULATE);
        if (ran.isEmpty()) {
            return 0;
        }
        stampAfterRun(ran, new Map<String, Set<Id>>());
        return ran.size();
    }

    /** One definition per chunk of `RollupBatch`: each is itself a job chain in the vendored engine. */
    private static final Integer VENDORED_BATCH_SIZE = 1;

    /**
     * Starts the nightly run now: every active Scheduled and Both definition, over every record
     * (R-R4). The scheduled job and the Recalculate all button both call this.
     *
     * @return the batch job started, or null when nothing started
     */
    public static Id startNightlyRun() {
        if (useOwnEngine) {
            return RollupFullRecalcBatch.begin(
                RollupSelector.selectActiveForModes(SCHEDULED_MODES)
            );
        }
        return Database.executeBatch(new RollupBatch(), VENDORED_BATCH_SIZE);
    }

    /**
     * Hands these definitions to the engine's full recalculation, one call per source entity,
     * limited to the given parent records when there are any. A definition that cannot be
     * expressed is logged and skipped. Answers the definitions that were handed over.
     */
    private static List<Rollup_Definition__c> handToEngine(
        List<Rollup_Definition__c> definitions,
        Set<Id> parentIds,
        String context
    ) {
        if (useOwnEngine) {
            // Only merge survivors arrive here: a full recalculation goes to the batch above.
            lastParentIds = parentIds;
            return RollupEngine.recalculate(parentIds, definitions).ran;
        }
        Map<String, List<Rollup__mdt>> metadataBySource = new Map<String, List<Rollup__mdt>>();
        List<Rollup__mdt> metadata = new List<Rollup__mdt>();
        List<Rollup_Definition__c> ran = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : definitions) {
            try {
                List<Rollup__mdt> converted = RollupAdapter.toMetadata(
                    new List<Rollup_Definition__c>{ definition }
                );
                String source = sourceOf(definition);
                if (!metadataBySource.containsKey(source)) {
                    metadataBySource.put(source, new List<Rollup__mdt>());
                }
                metadataBySource.get(source).addAll(converted);
                metadata.addAll(converted);
                ran.add(definition);
            } catch (Exception refused) {
                ErrorLogger.log(refused, context, definition.Id);
            }
        }
        if (metadata.isEmpty()) {
            return ran;
        }
        lastMetadata = metadata;
        lastParentIds = parentIds;
        lastEngineCalls = metadataBySource.size();
        if (skipEngine == true) {
            return ran;
        }
        List<String> parents = new List<String>();
        if (parentIds != null) {
            for (Id parentId : parentIds) {
                parents.add(String.valueOf(parentId));
            }
        }
        for (List<Rollup__mdt> sameSource : metadataBySource.values()) {
            if (parents.isEmpty()) {
                Rollup.performBulkFullRecalc(
                    sameSource,
                    Rollup.InvocationPoint.FROM_FULL_RECALC_APEX.name()
                );
            } else {
                Rollup.performBulkFullRecalcWithParentIds(
                    JSON.serialize(sameSource),
                    Rollup.InvocationPoint.FROM_FULL_RECALC_APEX.name(),
                    parents
                );
            }
        }
        return ran;
    }

    /**
     * The real-time definitions the vendored engine can run in a save. It refuses a definition
     * that reads an attribute through a relationship (`Gift__r.Status__c`) or reaches its target
     * through a household token, and one refusal stops every definition handed over in the same
     * call, which is why Gift Allocation and Soft Credit were not registered for real time. Those
     * definitions are left to the nightly run until slice S8 swaps in BarnCRM's own engine.
     */
    private static List<Rollup_Definition__c> vendoredRealTime(
        List<Rollup_Definition__c> definitions
    ) {
        List<Rollup_Definition__c> runnable = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : definitions) {
            Boolean readsThrough = false;
            Set<String> reads = RollupFilterParser.fieldsOf(definition.Filter_JSON__c);
            reads.add(String.valueOf(definition.Source_Field__c));
            reads.add(String.valueOf(definition.Order_By_Field__c));
            reads.add(String.valueOf(definition.Fiscal_Date_Field__c));
            for (String read : reads) {
                readsThrough = readsThrough || read.contains('.');
            }
            Boolean token = String.valueOf(definition.Relationship_Path__c).contains('{');
            if (!readsThrough && !token) {
                runnable.add(definition);
            }
        }
        return runnable;
    }

    // ------------------------------------------------------------------ BarnCRM's own engine

    /**
     * The target records a normal save recalculates itself (R-R4); a save that marks more goes
     * to the Rollup Queue.
     */
    @TestVisible
    private static Integer instantLimit = 50;

    /**
     * A save under the test switch (slice S6): `RollupChanges` works out which target records the
     * save marks (R-R11), and they are recalculated now or queued. A delete is collected in two
     * steps: before it, the rows the platform deletes with the record; after it, `runAfterDelete`.
     */
    private static void runOwnEngine(
        String sourceObject,
        List<SObject> changedRecords,
        Map<Id, SObject> oldRecords
    ) {
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
     * count (R-R11). BarnCRM's own engine only; the vendored one handled the delete before it.
     *
     * @param sourceObject the entity whose records were deleted
     * @param deletedRecords the records as they were
     */
    @NamespaceAccessible
    public static void runAfterDelete(String sourceObject, List<SObject> deletedRecords) {
        if (!useOwnEngine || String.isBlank(sourceObject) || deletedRecords == null) {
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
     * R-R4: a normal save that marks a few records recalculates them in the same save; a bulk
     * change, or a save already running in the background, queues them. A record the platform
     * refuses to save is queued to be tried again, and anything that stops the recalculation
     * queues the lot, so nothing marked is lost.
     */
    private static void recalculateNowOrQueue(RollupChanges.Marked marked) {
        if (marked.isEmpty()) {
            return;
        }
        Map<String, Set<Id>> idsByTarget = new Map<String, Set<Id>>();
        for (String target : marked.idsByTarget.keySet()) {
            Schema.SObjectType targetType = SettingsService.typeByName(target);
            if (targetType != null) {
                idsByTarget.put(String.valueOf(targetType), marked.idsByTarget.get(target));
            }
        }
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

    private static Set<String> sourcesOf(List<Rollup_Definition__c> definitions) {
        Set<String> sources = new Set<String>();
        for (Rollup_Definition__c definition : definitions) {
            sources.add(sourceOf(definition));
        }
        return sources;
    }

    private static String sourceOf(Rollup_Definition__c definition) {
        return String.isBlank(definition.Source_Object__c)
            ? ''
            : definition.Source_Object__c.toLowerCase();
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

    /**
     * Stamps the definitions that ran and, where the caller worked them out, the target records.
     *
     * The definition stamp lands once per call rather than once per chunk, which is what makes
     * "last calculated" mean the end of a run rather than the end of a batch.
     */
    private static void stampAfterRun(
        List<Rollup_Definition__c> ran,
        Map<String, Set<Id>> targetIdsByObject
    ) {
        if (ran.isEmpty()) {
            return;
        }
        Datetime completedAt = Datetime.now();
        Map<Id, Datetime> completedAtById = new Map<Id, Datetime>();
        for (Rollup_Definition__c definition : ran) {
            if (definition.Id != null) {
                completedAtById.put(definition.Id, completedAt);
            }
        }
        RollupWriter.stampDefinitions(completedAtById);
        for (String targetObject : targetIdsByObject.keySet()) {
            RollupWriter.stampTargets(
                targetObject,
                targetIdsByObject.get(targetObject),
                completedAt
            );
        }
    }

    /**
     * The target records a real-time run touched, grouped by entity, so their freshness attribute
     * can be stamped. Only paths the engine walks itself are resolved here; a household path is
     * resolved through `HouseholdService` by `RollupPath`, which is the same answer.
     */
    private static Map<String, Set<Id>> targetIdsFor(
        List<Rollup_Definition__c> ran,
        List<SObject> changedRecords
    ) {
        Map<String, Set<Id>> targetIdsByObject = new Map<String, Set<Id>>();
        for (Rollup_Definition__c definition : ran) {
            RollupPath.Parsed path;
            try {
                path = RollupPath.parse(definition.Relationship_Path__c);
            } catch (Exception ignored) {
                continue;
            }
            Set<Id> targetIds = new Set<Id>();
            if (path.needsHouseholdResolution()) {
                for (Set<Id> resolved : RollupPath.resolveTargets(path, changedRecords).values()) {
                    targetIds.addAll(resolved);
                }
            } else {
                RollupPath.Branch branch = path.branches[0];
                if (branch.segments.size() == 1) {
                    for (SObject changed : changedRecords) {
                        Object value = changed.get(branch.segments[0]);
                        if (value != null) {
                            targetIds.add((Id) value);
                        }
                    }
                }
            }
            if (targetIds.isEmpty()) {
                continue;
            }
            if (!targetIdsByObject.containsKey(definition.Target_Object__c)) {
                targetIdsByObject.put(definition.Target_Object__c, new Set<Id>());
            }
            targetIdsByObject.get(definition.Target_Object__c).addAll(targetIds);
        }
        return targetIdsByObject;
    }
}
