/**
 * Logic Models' part of Where Used (C-59, ADR-0159 `0159-where-used-extension.md`): every
 * computed indicator (L-03, ADR-0158, R-IN4) whose source counts by a date field, or sums or
 * counts the distinct values of a field, that is the target. The saved Find query it reads is
 * already in Core's own list (its object and filter); only the fields kept in the indicator's
 * Source Definition are this module's to report. Core finds this class by name
 * (`WhereUsedExtensions`).
 *
 * Indicators are read in system mode: Core's controller has already checked Manage BarnCRM
 * Settings, and a source is setup, not organization data.
 */
@NamespaceAccessible
public with sharing class LogicModelsWhereUsedExtension implements WhereUsedExtension {
    private static final String KIND = 'computedIndicator';

    @NamespaceAccessible
    public LogicModelsWhereUsedExtension() {
        // Built by name from Core (WhereUsedExtensions), so it needs a public constructor.
    }

    public List<WhereUsedService.Reference> references(WhereUsedService.Target target) {
        List<WhereUsedService.Reference> found = new List<WhereUsedService.Reference>();
        if (target.isObject()) {
            // The object a computed indicator counts is its saved query's, which Core lists.
            return found;
        }
        for (Indicator__c indicator : [
            SELECT
                Id,
                Name,
                Source_Definition__c,
                Source_Query__r.Object_Name__c,
                Element__r.Logic_Model__c
            FROM Indicator__c
            WHERE Source__c = :IndicatorSourceService.COMPUTED AND Source_Query__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 2000
        ]) {
            if (sourceNames(target, indicator)) {
                found.add(
                    new WhereUsedService.Reference(
                            KIND,
                            Schema.SObjectType.Indicator__c.getLabelPlural(),
                            indicator.Name,
                            indicator.Id
                        )
                        .addPart(
                            Schema.SObjectType.Indicator__c.fields.Source_Definition__c.getLabel()
                        )
                        .withBreaks(System.Label.Core_WhereUsed_BreaksModuleRecord)
                        .withRecordEdit(indicator.Element__r?.Logic_Model__c)
                );
            }
        }
        return found;
    }

    /** True when the source's date field or counted field, read from its query's object, is the target. */
    @TestVisible
    private static Boolean sourceNames(WhereUsedService.Target target, Indicator__c indicator) {
        IndicatorSourceService.Definition definition = IndicatorSourceService.parse(
            indicator.Source_Definition__c
        );
        String objectName = indicator.Source_Query__r?.Object_Name__c;
        if (definition == null || String.isBlank(objectName)) {
            return false;
        }
        return target.matchesPath(objectName, definition.dateField) ||
            target.matchesPath(objectName, definition.field);
    }
}
