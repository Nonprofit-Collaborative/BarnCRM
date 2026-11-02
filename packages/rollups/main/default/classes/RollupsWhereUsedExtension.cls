/**
 * The Rollup Builder's part of Where Used (C-59, ADR-0159 `0159-where-used-extension.md`): every
 * rollup definition that counts, filters, sorts on, travels through or writes to the target.
 * Core finds this class by name (`WhereUsedExtensions`) and adds its answer to the one list.
 *
 * Definitions are read in system mode: Core's controller has already checked Manage BarnCRM
 * Settings, and a definition is setup, not organization data. The relationship path (R-R1) is read
 * segment by segment from the counted object; a `{Household}` token stops the walk, because the
 * household is resolved by HouseholdService, not by a field.
 */
@NamespaceAccessible
public with sharing class RollupsWhereUsedExtension implements WhereUsedExtension {
    private static final String KIND = 'rollup';

    @NamespaceAccessible
    public RollupsWhereUsedExtension() {
        // Built by name from Core (WhereUsedExtensions), so it needs a public constructor.
    }

    public List<WhereUsedService.Reference> references(WhereUsedService.Target target) {
        List<WhereUsedService.Reference> found = new List<WhereUsedService.Reference>();
        for (Rollup_Definition__c definition : [
            SELECT
                Id,
                Name,
                Source_Object__c,
                Source_Field__c,
                Target_Object__c,
                Target_Field__c,
                Relationship_Path__c,
                Order_By_Field__c,
                Fiscal_Date_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c
            FROM Rollup_Definition__c
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 2000
        ]) {
            WhereUsedService.Reference reference = new WhereUsedService.Reference(
                KIND,
                System.Label.Core_RollupBuilder_WhereUsedKind,
                definition.Name,
                definition.Id
            );
            addSourceParts(target, definition, reference);
            addTargetParts(target, definition, reference);
            if (!reference.getParts().isEmpty()) {
                found.add(
                    reference.withBreaks(System.Label.Core_RollupBuilder_WhereUsedBreaks)
                        .withEdit('Rollup_Builder', null)
                );
            }
        }
        return found;
    }

    /**
     * What the rollup counts: for a whole object, one part when it counts that object; otherwise
     * its counted field, sort, fiscal date, filter and path.
     */
    private static void addSourceParts(
        WhereUsedService.Target target,
        Rollup_Definition__c definition,
        WhereUsedService.Reference reference
    ) {
        String source = definition.Source_Object__c;
        if (target.isObject() && target.isObject(source)) {
            reference.addPart(System.Label.Core_RollupBuilder_WhereUsedCounts);
            return;
        }
        if (
            target.matchesField(source, definition.Source_Field__c) ||
            target.matchesField(source, definition.Order_By_Field__c) ||
            target.matchesField(source, definition.Fiscal_Date_Field__c)
        ) {
            reference.addPart(System.Label.Core_RollupBuilder_WhereUsedSourceField);
        }
        if (target.matchesFilter(source, definition.Filter_JSON__c)) {
            reference.addPart(System.Label.Core_RollupBuilder_WhereUsedSourceFilter);
        }
        if (pathNames(target, source, definition.Relationship_Path__c)) {
            reference.addPart(System.Label.Core_RollupBuilder_WhereUsedPath);
        }
    }

    /** Where the rollup writes: the object, or its result field and target filter. */
    private static void addTargetParts(
        WhereUsedService.Target target,
        Rollup_Definition__c definition,
        WhereUsedService.Reference reference
    ) {
        String written = definition.Target_Object__c;
        if (target.isObject() && target.isObject(written)) {
            reference.addPart(System.Label.Core_RollupBuilder_WhereUsedWrites);
            return;
        }
        if (target.matchesField(written, definition.Target_Field__c)) {
            reference.addPart(System.Label.Core_RollupBuilder_WhereUsedTargetField);
        }
        if (target.matchesFilter(written, definition.Target_Filter_JSON__c)) {
            reference.addPart(System.Label.Core_RollupBuilder_WhereUsedTargetFilter);
        }
    }

    /** True when any lookup on any alternative of a relationship path (R-R1) is the target. */
    @TestVisible
    private static Boolean pathNames(WhereUsedService.Target target, String source, String path) {
        if (String.isBlank(path)) {
            return false;
        }
        for (String alternative : path.split('\\|')) {
            String current = source;
            for (String segment : alternative.split('>')) {
                String name = segment.trim();
                if (current == null || name.startsWith('{')) {
                    break;
                }
                if (!target.isObject() && target.matchesField(current, name)) {
                    return true;
                }
                current = target.objectOfLookup(current, name);
                if (target.isObject() && target.isObject(current)) {
                    return true;
                }
            }
        }
        return false;
    }
}
