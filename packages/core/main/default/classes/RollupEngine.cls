/**
 * BarnCRM's own rollup engine: the entry point the instant path (slice S6), the full
 * recalculation batch (`RollupFullRecalcBatch`, S7) and `RollupService` (S8) call (rollup
 * proposal D1, D3, Part 2 section 4). Since S8 it is the only engine any run reaches.
 *
 * One pass per target entity: `RollupPlanner` turns every definition that writes it into a few
 * source queries, `RollupAggregator` recomputes each value from all its source rows, and
 * `RollupWriter` saves each record once, only when a value changed, with its freshness stamp.
 *
 * - Recompute, never add and subtract: running twice, or two runs racing, gives the same answer.
 * - A sum or count with nothing left to count is written as zero, not left behind.
 * - A definition writes only the records its target filter admits (R-R8, bug 2), so two
 *   definitions writing one attribute for different kinds of record never overwrite each other.
 * - A definition that cannot be planned or queried is logged and left out; the others still run.
 */
@NamespaceAccessible
public with sharing class RollupEngine {
    /** The chunk `RollupFullRecalcBatch` starts from, before it shrinks a chunk to fit its data. */
    @NamespaceAccessible
    public static final Integer RECORDS_PER_PASS = 200;

    private static final Set<String> EVERY_MODE = new Set<String>{
        RollupService.MODE_REAL_TIME,
        RollupService.MODE_SCHEDULED,
        RollupService.MODE_BOTH
    };

    /** What a recalculation did. */
    @NamespaceAccessible
    public class Result {
        /** The target records saved because a value changed. */
        @NamespaceAccessible
        public Set<Id> written = new Set<Id>();
        /** The target records the platform refused to save, with its message, for a retry. */
        @NamespaceAccessible
        public Map<Id, String> failed = new Map<Id, String>();
        /** The definitions calculated. */
        @NamespaceAccessible
        public List<Rollup_Definition__c> ran = new List<Rollup_Definition__c>();
        /** The definitions left out because they could not be planned or queried. */
        @NamespaceAccessible
        public List<Rollup_Definition__c> refused = new List<Rollup_Definition__c>();
    }

    /**
     * Recalculates every active definition, whatever its mode, that writes these records.
     *
     * @param parentIds the target records; ids of another entity are ignored
     * @param targetType the entity they belong to
     */
    @NamespaceAccessible
    public static Result recalculate(Set<Id> parentIds, Schema.SObjectType targetType) {
        if (targetType == null || parentIds == null || parentIds.isEmpty()) {
            return new Result();
        }
        return recalculate(
            parentIds,
            RollupSelector.selectActiveForTarget(String.valueOf(targetType), EVERY_MODE)
        );
    }

    /**
     * Recalculates these definitions for these records, one pass per target entity.
     *
     * @param parentIds the target records, of any of the definitions' target entities
     * @param definitions the definitions to calculate
     */
    @NamespaceAccessible
    public static Result recalculate(Set<Id> parentIds, List<Rollup_Definition__c> definitions) {
        Result result = new Result();
        if (parentIds == null || parentIds.isEmpty()) {
            return result;
        }
        for (RollupPlanner.Plan plan : plansFor(definitions, result)) {
            Set<Id> ofThisType = new Set<Id>();
            for (Id parentId : parentIds) {
                if (parentId != null && parentId.getSObjectType() == plan.targetType) {
                    ofThisType.add(parentId);
                }
            }
            runPass(plan, ofThisType, result);
        }
        return result;
    }

    /** One plan per target entity; a definition naming an entity the org lacks is refused. */
    private static List<RollupPlanner.Plan> plansFor(
        List<Rollup_Definition__c> definitions,
        Result result
    ) {
        Map<String, List<Rollup_Definition__c>> byTarget = new Map<String, List<Rollup_Definition__c>>();
        for (
            Rollup_Definition__c definition : definitions == null
                ? new List<Rollup_Definition__c>()
                : definitions
        ) {
            String target = String.isBlank(definition.Target_Object__c)
                ? ''
                : definition.Target_Object__c.toLowerCase();
            if (!byTarget.containsKey(target)) {
                byTarget.put(target, new List<Rollup_Definition__c>());
            }
            byTarget.get(target).add(definition);
        }
        List<RollupPlanner.Plan> plans = new List<RollupPlanner.Plan>();
        for (String target : byTarget.keySet()) {
            Schema.SObjectType targetType = SettingsService.typeByName(target);
            if (targetType == null) {
                result.refused.addAll(byTarget.get(target));
                continue;
            }
            RollupPlanner.Plan plan = RollupPlanner.plan(targetType, byTarget.get(target));
            result.refused.addAll(plan.refused);
            if (!plan.definitions.isEmpty()) {
                plans.add(plan);
            }
        }
        return plans;
    }

    /** What a draft rollup would write on one record, without saving anything (slice S12). */
    @NamespaceAccessible
    public class Preview {
        /** False when the definition cannot be planned or queried. */
        @NamespaceAccessible
        public Boolean planned = false;
        /** False when the record is not one the definition writes (its target filter). */
        @NamespaceAccessible
        public Boolean admitted = false;
        /** The value the definition would write. */
        @NamespaceAccessible
        public Object calculated;
        /** The value the record holds now. */
        @NamespaceAccessible
        public Object current;
    }

    /**
     * Calculates one definition, saved or not, for one record of its target entity and writes
     * nothing. The Builder shows it next to what the record holds now.
     *
     * @param definition the definition, which need not be saved
     * @param targetId a record of the definition's target entity
     */
    @NamespaceAccessible
    public static Preview preview(Rollup_Definition__c definition, Id targetId) {
        Preview preview = new Preview();
        Result result = new Result();
        List<RollupPlanner.Plan> plans = plansFor(
            new List<Rollup_Definition__c>{ definition },
            result
        );
        if (plans.isEmpty() || targetId == null) {
            return preview;
        }
        RollupPlanner.Plan plan = plans[0];
        if (targetId.getSObjectType() != plan.targetType) {
            return preview;
        }
        Computation computation = compute(plan, new Set<Id>{ targetId }, result);
        preview.planned = result.refused.isEmpty();
        Map<Schema.SObjectField, Object> values = computation.computed.get(targetId);
        if (preview.planned && values != null) {
            preview.admitted = true;
            preview.calculated = values.get(plan.targetFields[0]);
            preview.current = computation.stored.get(targetId).get(plan.targetFields[0]);
        }
        return preview;
    }

    /** The records read and the values calculated for them, before anything is written. */
    private class Computation {
        Map<Id, SObject> stored = new Map<Id, SObject>();
        Map<Id, Map<Schema.SObjectField, Object>> computed = new Map<Id, Map<Schema.SObjectField, Object>>();
    }

    /** Calculates and writes one plan for one set of records of its target entity. */
    private static void runPass(RollupPlanner.Plan plan, Set<Id> targetIds, Result result) {
        if (targetIds.isEmpty()) {
            return;
        }
        Computation computation = compute(plan, targetIds, result);
        RollupWriter.TotalsWrite write = RollupWriter.writeTotals(
            plan.targetType,
            computation.stored,
            computation.computed,
            Datetime.now()
        );
        result.written.addAll(write.written);
        result.failed.putAll(write.failed);
    }

    /** Calculates one plan for records of its target entity; ran and refused go on `result`. */
    private static Computation compute(RollupPlanner.Plan plan, Set<Id> targetIds, Result result) {
        Computation computation = new Computation();
        List<Set<Id>> admittedByDefinition = admitted(plan, targetIds);
        Set<Id> anyAdmitted = new Set<Id>();
        for (Set<Id> admittedIds : admittedByDefinition) {
            anyAdmitted.addAll(admittedIds);
        }
        RollupAggregator.Answer answer = RollupAggregator.calculate(plan, anyAdmitted);

        Boolean converts = RollupCurrency.isMultiCurrency();
        Set<String> columns = new Set<String>();
        for (Schema.SObjectField field : plan.targetFields) {
            columns.add(String.valueOf(field));
        }
        if (converts) {
            columns.add(RollupCurrency.ISO_FIELD);
        }
        Map<Id, SObject> stored = RollupAggregator.stored(plan.targetType, columns, anyAdmitted);
        computation.stored = stored;
        Map<Id, Map<Schema.SObjectField, Object>> computed = computation.computed;
        for (Integer i = 0; i < plan.definitions.size(); i++) {
            Rollup_Definition__c definition = plan.definitions[i];
            if (answer.failed.contains(i)) {
                result.refused.add(definition);
                continue;
            }
            result.ran.add(definition);
            String aggregate = definition.Aggregate__c.toUpperCase();
            // Read only for a text list, so a caller that queried a definition without the
            // delimiter still runs every other aggregate.
            String separator = aggregate.startsWith('TEXT_LIST')
                ? RollupPlanner.separatorFor(definition.Delimiter__c)
                : null;
            Schema.SObjectField field = plan.targetFields[i];
            Boolean toTargetCurrency =
                converts &&
                aggregate != 'COUNT' &&
                field.getDescribe().getType() == Schema.DisplayType.CURRENCY &&
                RollupCurrency.isCurrencyPath(
                    definition.Source_Object__c,
                    definition.Source_Field__c
                );
            Map<Id, RollupAggregator.Tally> tallies = answer.tallies.get(i);
            for (Id targetId : admittedByDefinition[i]) {
                SObject current = stored.get(targetId);
                if (current == null) {
                    continue;
                }
                RollupAggregator.Tally tally = tallies == null ? null : tallies.get(targetId);
                Object value = (tally == null ? new RollupAggregator.Tally() : tally)
                    .result(aggregate, separator);
                if (toTargetCurrency && value != null) {
                    value = RollupCurrency.fromCorporate(
                        RollupAggregator.toDecimal(value),
                        (String) current.get(RollupCurrency.ISO_FIELD)
                    );
                }
                if (!computed.containsKey(targetId)) {
                    computed.put(targetId, new Map<Schema.SObjectField, Object>());
                }
                computed.get(targetId).put(field, value);
            }
        }
        return computation;
    }

    /**
     * The records each definition may write: all of them, or those its target filter admits.
     * Definitions sharing a target filter share its query.
     */
    private static List<Set<Id>> admitted(RollupPlanner.Plan plan, Set<Id> targetIds) {
        Map<String, Set<Id>> passingByFilter = new Map<String, Set<Id>>();
        List<Set<Id>> result = new List<Set<Id>>();
        for (String targetFilter : plan.targetFilters) {
            if (String.isBlank(targetFilter)) {
                result.add(targetIds);
                continue;
            }
            if (!passingByFilter.containsKey(targetFilter)) {
                Set<Id> passing;
                try {
                    passing = RollupAggregator.passing(plan.targetType, targetFilter, targetIds);
                } catch (Exception refused) {
                    // A target filter the org cannot query writes nothing rather than everything.
                    ErrorLogger.log(refused, 'RollupEngine.admitted');
                    passing = new Set<Id>();
                }
                passingByFilter.put(targetFilter, passing);
            }
            result.add(passingByFilter.get(targetFilter));
        }
        return result;
    }
}
