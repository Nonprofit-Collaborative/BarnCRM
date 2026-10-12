/**
 * Turns BarnCRM's rollup configuration into the shape the vendored engine understands.
 *
 * This class is the whole of ADR-0015's promise. `Rollup_Definition__c` is the system of record
 * and the only rollup configuration an administrator ever sees; the vendored engine's own
 * `Rollup__mdt` is built here, in memory, for the length of one call, and never written to a
 * subscriber org. There is no metadata deployment, no remote site setting, and no second rollup
 * console.
 *
 * The mapping, definition attribute to engine attribute:
 *
 * | Rollup Definition       | Engine                                                       |
 * | ----------------------- | ------------------------------------------------------------ |
 * | Source Entity           | `CalcItemText__c`                                             |
 * | Target Entity           | `LookupObjectText__c`                                         |
 * | Relationship Path, 1 hop| `LookupFieldOnCalcItemText__c`                                |
 * | Relationship Path, 2+   | `GrandparentRelationshipFieldPath__c`                         |
 * | Aggregate               | `RollupOperation__c`                                          |
 * | Source Attribute        | `RollupFieldOnCalcItemText__c`                                |
 * | Order By Attribute      | `OrderByFirstLast__c`                                         |
 * | Target Attribute        | `RollupFieldOnLookupObjectText__c`                            |
 * | Filter plus fiscal window | `CalcItemWhereClause__c`                                    |
 *
 * Every object and attribute goes in through the engine's `...Text__c` variants rather than its
 * `EntityDefinition` lookups, which makes this class the single place a namespace prefix would be
 * applied once one is registered, and which is what the upstream namespaced-package rule requires.
 */
public with sharing class RollupAdapter {
    /** Raised when a definition cannot be expressed to the engine. */
    public class RollupAdapterException extends Exception {
    }

    private static final Map<String, String> ENGINE_OPERATION_BY_AGGREGATE = new Map<String, String>{
        'SUM' => 'SUM',
        'COUNT' => 'COUNT',
        'MIN' => 'MIN',
        'MAX' => 'MAX',
        'FIRST' => 'FIRST',
        'LAST' => 'LAST',
        'AVG' => 'AVERAGE'
    };

    /** Aggregates that do not read an attribute off the source record. */
    private static final Set<String> COUNTING_AGGREGATES = new Set<String>{ 'COUNT' };

    /** Aggregates that need an Order By attribute to mean anything (R-R10). */
    private static final Set<String> ORDERED_AGGREGATES = new Set<String>{ 'FIRST', 'LAST' };

    /**
     * One definition as the engine's in-memory metadata.
     *
     * @param definition the administrator's rollup
     * @return the engine metadata for it
     */
    public static Rollup__mdt toMetadata(Rollup_Definition__c definition) {
        validate(definition);
        RollupPath.Parsed path = RollupPath.parse(definition.Relationship_Path__c);
        RollupPath.Branch branch = path.onlyBranch();

        Rollup__mdt meta = new Rollup__mdt();
        meta.DeveloperName = developerNameFor(definition);
        meta.MasterLabel = definition.Name;
        meta.CalcItemText__c = definition.Source_Object__c;
        meta.LookupObjectText__c = definition.Target_Object__c;
        meta.LookupFieldOnLookupObjectText__c = 'Id';
        meta.RollupFieldOnLookupObjectText__c = definition.Target_Field__c;
        meta.RollupFieldOnCalcItemText__c = aggregatedFieldFor(definition);
        meta.RollupOperation__c = ENGINE_OPERATION_BY_AGGREGATE.get(
            definition.Aggregate__c.toUpperCase()
        );
        if (definition.Aggregate__c.toUpperCase() == 'SUM') {
            // The engine hands back a rollup's default in place of a sum of exactly zero, and
            // with no default set that is blank, which it then declines to write over a blank
            // field. A donor whose only gift was refunded in full has a total of zero, not an
            // empty one (canonical model Section 26, ADR-0022), so a sum defaults to zero. Only
            // a sum: a count, a minimum or a maximum of nothing has no value to report.
            meta.FullRecalculationDefaultNumberValue__c = 0;
        }
        meta.CalcItemWhereClause__c = whereClauseFor(definition);
        meta.IsDisabled__c = definition.Active__c != true;
        // BarnCRM's own Active checkbox is the switch an administrator uses, so the engine's
        // separate custom setting is never in the way of a definition this package is running.
        meta.ShouldRunWithoutCustomSettingEnabled__c = true;

        if (ORDERED_AGGREGATES.contains(definition.Aggregate__c.toUpperCase())) {
            meta.OrderByFirstLast__c = definition.Order_By_Field__c;
        }

        if (path.needsHouseholdResolution()) {
            // The household abstraction has no single relationship in junction mode, so the
            // engine is handed resolved parent ids instead of a path to walk (ADR-0015).
            meta.IsRollupStartedFromParent__c = true;
            meta.LookupFieldOnCalcItemText__c = 'Id';
        } else if (branch != null && branch.segments.size() == 1) {
            meta.LookupFieldOnCalcItemText__c = branch.segments[0];
        } else if (branch != null) {
            meta.GrandparentRelationshipFieldPath__c = RollupPath.toGrandparentFieldPath(branch);
            meta.LookupFieldOnCalcItemText__c = branch.segments[0];
        } else {
            // Alternatives with no token are more than one relationship to walk, and the engine
            // walks one. Each alternative therefore becomes its own metadata record, which
            // `toMetadata(List)` below does.
            throw new RollupAdapterException(System.Label.Core_Rollups_ErrorInvalidFilter);
        }
        return withEngineNames(meta);
    }

    /**
     * Copies each `...Text__c` value onto the attribute the engine actually reads.
     *
     * The engine reads `CalcItem__c`, `LookupObject__c`, `LookupFieldOnCalcItem__c` and the rest
     * everywhere it runs. Only its own custom metadata query fills those from the `...Text__c`
     * variants (`RollupRepository`), and metadata built here in memory never goes through that
     * query, so without this the engine was handed a rollup with no source object, no target and
     * no attributes: a real-time run failed and was logged, and a full recalculation wrote
     * nothing. The `...Text__c` values stay the ones this class sets, so a namespace prefix is
     * still applied in one place.
     */
    private static Rollup__mdt withEngineNames(Rollup__mdt meta) {
        meta.CalcItem__c = meta.CalcItemText__c;
        meta.LookupObject__c = meta.LookupObjectText__c;
        meta.LookupFieldOnCalcItem__c = meta.LookupFieldOnCalcItemText__c;
        meta.LookupFieldOnLookupObject__c = meta.LookupFieldOnLookupObjectText__c;
        meta.RollupFieldOnCalcItem__c = meta.RollupFieldOnCalcItemText__c;
        meta.RollupFieldOnLookupObject__c = meta.RollupFieldOnLookupObjectText__c;
        return meta;
    }

    /**
     * A whole set of definitions as engine metadata.
     *
     * A path with alternatives and no mode-resolved token becomes one metadata record per
     * alternative, because the engine walks one relationship at a time and R-R1 says the first
     * alternative that resolves wins. The alternatives are emitted in order, so the engine sees
     * them in the order the administrator wrote them.
     */
    public static List<Rollup__mdt> toMetadata(List<Rollup_Definition__c> definitions) {
        List<Rollup__mdt> metadata = new List<Rollup__mdt>();
        if (definitions == null) {
            return metadata;
        }
        for (Rollup_Definition__c definition : definitions) {
            RollupPath.Parsed path = RollupPath.parse(definition.Relationship_Path__c);
            if (path.needsHouseholdResolution() || path.branches.size() == 1) {
                metadata.add(toMetadata(definition));
                continue;
            }
            for (RollupPath.Branch branch : path.branches) {
                Rollup_Definition__c single = definition.clone(true, true, true, true);
                single.Relationship_Path__c = String.join(branch.segments, ' > ');
                metadata.add(toMetadata(single));
            }
        }
        return metadata;
    }

    /**
     * The where clause the engine applies to the source records: the definition's own filter
     * document, and the fiscal year window when it is fiscal-year aware.
     */
    public static String whereClauseFor(Rollup_Definition__c definition) {
        List<String> fragments = new List<String>();
        String filterClause = RollupFilterParser.toWhereClause(definition.Filter_JSON__c);
        if (String.isNotBlank(filterClause)) {
            fragments.add('(' + filterClause + ')');
        }
        String windowClause = RollupDateWindow.toWhereClause(
            definition.Fiscal_Year_Aware__c,
            definition.Fiscal_Year_Offset__c == null
                ? 0
                : definition.Fiscal_Year_Offset__c.intValue(),
            fiscalDateFieldFor(definition)
        );
        if (String.isNotBlank(windowClause)) {
            fragments.add('(' + windowClause + ')');
        }
        return String.join(fragments, ' AND ');
    }

    /**
     * The date attribute a fiscal window is measured on. A definition may name one; when it does
     * not, and the attribute being aggregated is itself the date, that is the one meant.
     */
    private static String fiscalDateFieldFor(Rollup_Definition__c definition) {
        if (String.isNotBlank(definition.Fiscal_Date_Field__c)) {
            return definition.Fiscal_Date_Field__c;
        }
        return definition.Source_Field__c;
    }

    /**
     * What the engine reads off each source record. A COUNT reads nothing in particular, so it is
     * pointed at the record's own id, which is never blank and never changes the count.
     */
    private static String aggregatedFieldFor(Rollup_Definition__c definition) {
        return COUNTING_AGGREGATES.contains(definition.Aggregate__c.toUpperCase())
            ? 'Id'
            : definition.Source_Field__c;
    }

    /**
     * R-R10, before anything reaches the engine: an aggregate it knows, a source attribute for
     * every aggregate that reads one, and an order by attribute for first and last.
     */
    @TestVisible
    private static void validate(Rollup_Definition__c definition) {
        if (definition == null) {
            throw new RollupAdapterException(System.Label.Core_Rollups_ErrorUnknownDefinition);
        }
        if (
            String.isBlank(definition.Source_Object__c) ||
            String.isBlank(definition.Target_Object__c)
        ) {
            throw new RollupAdapterException(System.Label.Core_Rollups_ErrorUnknownObject);
        }
        if (String.isBlank(definition.Target_Field__c)) {
            throw new RollupAdapterException(System.Label.Core_Rollups_ErrorUnknownObject);
        }
        String aggregate = String.isBlank(definition.Aggregate__c)
            ? ''
            : definition.Aggregate__c.toUpperCase();
        if (!ENGINE_OPERATION_BY_AGGREGATE.containsKey(aggregate)) {
            throw new RollupAdapterException(System.Label.Core_Rollups_ErrorInvalidOperator);
        }
        if (
            !COUNTING_AGGREGATES.contains(aggregate) && String.isBlank(definition.Source_Field__c)
        ) {
            throw new RollupAdapterException(System.Label.Core_Rollups_ErrorInvalidOperator);
        }
        if (
            ORDERED_AGGREGATES.contains(aggregate) && String.isBlank(definition.Order_By_Field__c)
        ) {
            throw new RollupAdapterException(System.Label.Core_Rollups_ErrorInvalidOperator);
        }
    }

    /**
     * A name for the engine's log lines. The engine never stores this: it exists so that a person
     * reading the rollup log sees the definition key they know from the console.
     */
    private static String developerNameFor(Rollup_Definition__c definition) {
        return String.isBlank(definition.Definition_Key__c)
            ? 'BarnCRM_Rollup'
            : definition.Definition_Key__c;
    }
}
