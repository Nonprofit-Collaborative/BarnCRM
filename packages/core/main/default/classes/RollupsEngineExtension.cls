/**
 * The rollup engine's answer to Core's `RollupEngineExtension` (ADR-NEXT,
 * `NEXT-rollup-builder-module.md`). It only delegates: each method is the engine call Core made
 * directly before the engine became the BarnCRM Rollup Builder module.
 */
@NamespaceAccessible
public with sharing class RollupsEngineExtension implements RollupEngineExtension {
    @NamespaceAccessible
    public RollupsEngineExtension() {
        // Built by name from Core (RollupEngineExtensions), so it needs a public constructor.
    }

    public void afterMerge(String targetObject, List<SObject> mergedRecords) {
        RollupService.runAfterMerge(targetObject, mergedRecords);
    }

    public void forSurvivors(String targetObject, Set<Id> survivorIds) {
        RollupService.runForSurvivors(targetObject, survivorIds);
    }

    public void startQueuedRecalculation() {
        RollupService.startQueuedRecalculation();
    }

    public void processPending() {
        RollupQueue.processPending();
    }

    public Datetime lastCalculated() {
        return RollupService.lastCalculated();
    }

    public Boolean isStale() {
        return RollupService.isStale();
    }

    public Map<String, Set<String>> targetFieldsByObject() {
        Map<String, Set<String>> targets = new Map<String, Set<String>>();
        for (Rollup_Definition__c definition : RollupSelector.selectAll()) {
            if (
                String.isBlank(definition.Target_Object__c) ||
                String.isBlank(definition.Target_Field__c)
            ) {
                continue;
            }
            String target = definition.Target_Object__c.trim();
            if (!targets.containsKey(target)) {
                targets.put(target, new Set<String>());
            }
            targets.get(target).add(definition.Target_Field__c.trim());
        }
        return targets;
    }
}
