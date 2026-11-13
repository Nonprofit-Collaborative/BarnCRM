/**
 * The rollup engine's answer to Core's `RollupEngineExtension` (ADR-0125,
 * `0125-rollup-builder-module.md`). It only delegates: each method is the engine call Core made
 * directly before the engine became the BarnCRM Rollup Builder module, plus the calls Core's
 * Module Manager makes on Turn on (decision 9) and its settings service after a save (ADR-0136).
 */
@NamespaceAccessible
public with sharing class RollupsEngineExtension implements RollupEngineExtension {
	@NamespaceAccessible
	public RollupsEngineExtension() {
		// Built by name from Core (RollupEngineExtensions), so it needs a public constructor.
	}

	public void afterModuleTurnedOn(String moduleName) {
		if (RollupService.MODULE_NAME.equalsIgnoreCase(moduleName)) {
			// Core's Turn on also queues the module's access sync from its catalog row (D2).
			RollupService.catchUpAfterTurnedOn();
		}
	}

	/**
	 * Nothing to do: the nightly rollup step reads its hour every night (ADR-0166
	 * nightly-job-dispatcher), so a new hour needs no schedule moved (Section 14B).
	 */
	public void afterSettingsSaved(String settingsObject, Set<String> changedKeys) {
		return;
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
