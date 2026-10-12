/**
 * Runs BarnCRM's own rollup engine and the vendored apex-rollup engine over the same records and
 * reports where their answers differ (`decisions/0082-barncrm-owns-its-rollup-engine.md`, the
 * comparison the vendored tree's deletion waits for). How to run it, and what a difference
 * means: `docs/contributor-guide/rollup-engine-comparison.md`.
 *
 * Nothing is saved. Each definition is calculated by one engine, the value read back, and the
 * transaction rolled back to a savepoint before the other engine runs, so both start from the
 * stored data. Every registered automation is bypassed for the run, so a save made by either
 * engine starts nothing else. If the vendored engine starts a background job anyway, which a
 * rollback does not take back, the run throws with the report as its message, so the whole
 * transaction, the job included, is discarded.
 *
 * A developer tool, run as Anonymous Apex on a test org. Anonymous Apex already needs Author
 * Apex, so the class adds no permission of its own. Reads and writes are system mode: it
 * compares the engines, not the running user's access.
 */
public with sharing class RollupEngineComparison {
    /** The records a run samples per definition when none are named. */
    public static final Integer DEFAULT_SAMPLE = 50;
    /** The most records one definition is compared over in one run. */
    public static final Integer LARGEST_SAMPLE = 200;

    // Headroom kept so a run always finishes with its report: below these, it stops early and
    // names the definitions it did not reach.
    private static final Integer QUERY_CEILING = 70;
    private static final Integer DML_CEILING = 100;
    private static final Integer CPU_CEILING_MS = 7000;

    /** Thrown to discard a run in which the vendored engine started a background job. */
    public class ComparisonException extends Exception {
    }

    /** One record and attribute where the two engines disagree. */
    public class Difference {
        public String definitionKey;
        public String targetField;
        public Id recordId;
        /** The value on the record before either engine ran. */
        public Object stored;
        /** BarnCRM's own engine. */
        public Object barncrm;
        /** The vendored engine. */
        public Object vendored;
    }

    /** What a run found. */
    public class Report {
        public Integer definitionsCompared = 0;
        public Integer valuesCompared = 0;
        public List<Difference> differences = new List<Difference>();
        /** Definitions that were not compared, by key, with the reason. */
        public Map<String, String> notCompared = new Map<String, String>();
        /** Definitions the run stopped before, to run again. */
        public List<String> notReached = new List<String>();
        /** True when the vendored engine started a background job. */
        public Boolean startedBackgroundWork = false;

        /** The report as plain text, one line per finding. */
        public String summary() {
            List<String> lines = new List<String>{
                String.format(
                    System.Label.Core_RollupComparison_Summary,
                    new List<String>{
                        String.valueOf(definitionsCompared),
                        String.valueOf(valuesCompared),
                        String.valueOf(differences.size())
                    }
                )
            };
            for (Difference difference : differences) {
                lines.add(
                    String.format(
                        System.Label.Core_RollupComparison_Difference,
                        new List<String>{
                            difference.definitionKey,
                            difference.targetField,
                            String.valueOf(difference.recordId),
                            String.valueOf(difference.stored),
                            String.valueOf(difference.barncrm),
                            String.valueOf(difference.vendored)
                        }
                    )
                );
            }
            for (String key : notCompared.keySet()) {
                lines.add(
                    String.format(
                        System.Label.Core_RollupComparison_NotCompared,
                        new List<String>{ key, notCompared.get(key) }
                    )
                );
            }
            if (!notReached.isEmpty()) {
                lines.add(
                    String.format(
                        System.Label.Core_RollupComparison_NotReached,
                        new List<String>{ String.join(notReached, ', ') }
                    )
                );
            }
            return String.join(lines, '\n');
        }
    }

    /**
     * Compares the engines for these definitions over a sample of each one's target records.
     *
     * @param definitionKeys the definitions' keys; null or empty compares every active definition
     * @param samplePerTarget how many target records per definition, at most `LARGEST_SAMPLE`;
     *        null takes `DEFAULT_SAMPLE`
     */
    public static Report run(Set<String> definitionKeys, Integer samplePerTarget) {
        Integer sample = samplePerTarget == null ||
            samplePerTarget < 1
            ? DEFAULT_SAMPLE
            : Math.min(samplePerTarget, LARGEST_SAMPLE);
        return compareAll(definitionKeys, null, sample);
    }

    /**
     * Compares the engines for these definitions over these records. Each definition is compared
     * over the records of its own target entity that its target filter admits.
     *
     * @param targetIds the records to compare, at most `LARGEST_SAMPLE` per definition
     * @param definitionKeys the definitions' keys; null or empty compares every active definition
     */
    public static Report compare(Set<Id> targetIds, Set<String> definitionKeys) {
        return compareAll(
            definitionKeys,
            targetIds == null ? new Set<Id>() : targetIds,
            LARGEST_SAMPLE
        );
    }

    private static Report compareAll(Set<String> keys, Set<Id> named, Integer sample) {
        Report report = new Report();
        List<Rollup_Definition__c> definitions = definitionsFor(keys, report);
        for (Automation_Registry__mdt entry : AutomationRegistrySelector.selectAll()) {
            AutomationControl.bypass(entry.DeveloperName);
        }
        try {
            for (Integer i = 0; i < definitions.size(); i++) {
                if (nearTheLimits()) {
                    for (Integer j = i; j < definitions.size(); j++) {
                        report.notReached.add(definitions[j].Definition_Key__c);
                    }
                    break;
                }
                compareOne(definitions[i], named, sample, report);
            }
        } finally {
            AutomationControl.clearAllBypasses();
        }
        if (report.startedBackgroundWork) {
            throw new ComparisonException(
                String.format(
                    System.Label.Core_RollupComparison_BackgroundWork,
                    new List<String>{ report.summary() }
                )
            );
        }
        return report;
    }

    private static List<Rollup_Definition__c> definitionsFor(Set<String> keys, Report report) {
        Boolean every = keys == null || keys.isEmpty();
        Set<String> missing = every ? new Set<String>() : new Set<String>(keys);
        List<Rollup_Definition__c> chosen = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : RollupSelector.selectAll()) {
            if (definition.Active__c != true) {
                continue;
            }
            if (every || keys.contains(definition.Definition_Key__c)) {
                chosen.add(definition);
                missing.remove(definition.Definition_Key__c);
            }
        }
        for (String key : missing) {
            report.notCompared.put(key, System.Label.Core_RollupComparison_NoDefinition);
        }
        return chosen;
    }

    private static Boolean nearTheLimits() {
        return Limits.getQueries() > QUERY_CEILING ||
            Limits.getDmlStatements() > DML_CEILING ||
            Limits.getCpuTime() > CPU_CEILING_MS;
    }

    private static void compareOne(
        Rollup_Definition__c definition,
        Set<Id> named,
        Integer sample,
        Report report
    ) {
        String key = definition.Definition_Key__c;
        try {
            Schema.SObjectType targetType = Schema.getGlobalDescribe()
                .get(definition.Target_Object__c);
            Set<Id> targetIds = targetsFor(definition, targetType, named, sample);
            if (targetIds.isEmpty()) {
                report.notCompared.put(key, System.Label.Core_RollupComparison_NoRecords);
                return;
            }
            String field = definition.Target_Field__c;
            Map<Id, SObject> stored = read(targetType, field, targetIds);
            Map<Id, SObject> ours = runOurs(definition, targetType, targetIds, report);
            if (ours == null) {
                return;
            }
            Map<Id, SObject> theirs = runVendored(definition, targetType, targetIds, report);
            if (theirs == null) {
                return;
            }
            report.definitionsCompared++;
            for (Id recordId : targetIds) {
                Object before = stored.get(recordId)?.get(field);
                Object barncrm = ours.get(recordId)?.get(field);
                Object vendored = theirs.get(recordId)?.get(field);
                report.valuesCompared++;
                if (!same(barncrm, vendored)) {
                    Difference difference = new Difference();
                    difference.definitionKey = key;
                    difference.targetField = field;
                    difference.recordId = recordId;
                    difference.stored = before;
                    difference.barncrm = barncrm;
                    difference.vendored = vendored;
                    report.differences.add(difference);
                }
            }
        } catch (Exception failed) {
            report.notCompared.put(key, describe(failed));
        }
    }

    /** The target records a definition is compared over: named ones, or a sample. */
    private static Set<Id> targetsFor(
        Rollup_Definition__c definition,
        Schema.SObjectType targetType,
        Set<Id> named,
        Integer sample
    ) {
        String targetFilter = RollupFilterParser.toWhereClause(definition.Target_Filter_JSON__c);
        Boolean filtered = String.isNotBlank(targetFilter);
        Set<Id> ids = new Set<Id>();
        if (named != null) {
            for (Id recordId : named) {
                if (recordId.getSObjectType() == targetType && ids.size() < sample) {
                    ids.add(recordId);
                }
            }
            return filtered && !ids.isEmpty()
                ? RollupAggregator.passing(targetType, targetFilter, ids)
                : ids;
        }
        String soql =
            'SELECT Id FROM ' +
            String.valueOf(targetType) +
            (filtered ? ' WHERE (' + targetFilter + ')' : '') +
            ' ORDER BY Id LIMIT :sample';
        return new Map<Id, SObject>(
                Database.queryWithBinds(
                    soql,
                    new Map<String, Object>{ 'sample' => sample },
                    AccessLevel.SYSTEM_MODE
                )
            )
            .keySet();
    }

    /** BarnCRM's answer for these records, read back, with the save taken back. */
    private static Map<Id, SObject> runOurs(
        Rollup_Definition__c definition,
        Schema.SObjectType targetType,
        Set<Id> targetIds,
        Report report
    ) {
        Savepoint before = Database.setSavepoint();
        try {
            RollupEngine.Result result = RollupEngine.recalculate(
                targetIds,
                new List<Rollup_Definition__c>{ definition }
            );
            if (!result.refused.isEmpty()) {
                report.notCompared.put(
                    definition.Definition_Key__c,
                    System.Label.Core_RollupComparison_RefusedByBarnCrm
                );
                return null;
            }
            return read(targetType, definition.Target_Field__c, targetIds);
        } finally {
            Database.rollback(before);
        }
    }

    /** The vendored engine's answer for these records, read back, with the save taken back. */
    private static Map<Id, SObject> runVendored(
        Rollup_Definition__c definition,
        Schema.SObjectType targetType,
        Set<Id> targetIds,
        Report report
    ) {
        Integer queueablesBefore = Limits.getQueueableJobs();
        Integer futuresBefore = Limits.getFutureCalls();
        List<String> parentIds = new List<String>();
        for (Id targetId : targetIds) {
            parentIds.add(String.valueOf(targetId));
        }
        Savepoint before = Database.setSavepoint();
        try {
            // The singular parent invocation point runs the calculation synchronously, in this
            // transaction, as the vendored "recalculate this record" button does.
            Rollup.performBulkFullRecalcWithParentIds(
                JSON.serialize(
                    RollupAdapter.toMetadata(new List<Rollup_Definition__c>{ definition })
                ),
                Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name(),
                parentIds
            );
            return read(targetType, definition.Target_Field__c, targetIds);
        } catch (Exception failed) {
            report.notCompared.put(
                definition.Definition_Key__c,
                String.format(
                    System.Label.Core_RollupComparison_VendoredFailed,
                    new List<String>{ describe(failed) }
                )
            );
            return null;
        } finally {
            Database.rollback(before);
            if (
                Limits.getQueueableJobs() > queueablesBefore ||
                Limits.getFutureCalls() > futuresBefore
            ) {
                report.startedBackgroundWork = true;
            }
        }
    }

    private static Map<Id, SObject> read(
        Schema.SObjectType targetType,
        String field,
        Set<Id> targetIds
    ) {
        return RollupAggregator.stored(targetType, new Set<String>{ field }, targetIds);
    }

    /** Equal values; numbers of any Apex type are compared as numbers. */
    @TestVisible
    private static Boolean same(Object left, Object right) {
        if (left == null || right == null) {
            return left == right;
        }
        if (isNumber(left) && isNumber(right)) {
            return RollupAggregator.toDecimal(left) == RollupAggregator.toDecimal(right);
        }
        return left == right;
    }

    private static Boolean isNumber(Object value) {
        return value instanceof Decimal ||
            value instanceof Integer ||
            value instanceof Long ||
            value instanceof Double;
    }

    private static String describe(Exception failed) {
        return failed.getTypeName() + ': ' + failed.getMessage();
    }
}
