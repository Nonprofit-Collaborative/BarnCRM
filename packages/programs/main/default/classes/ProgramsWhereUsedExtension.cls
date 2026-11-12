/**
 * Programs' part of Where Used (C-59, ADR-0159 `0159-where-used-extension.md`): every program
 * whose eligibility rules (P-14, R-EN8) read an enrollment field, or a person's field through the
 * enrollment's Contact lookup (P-14b, `Contact__r.Birthdate`). Core finds this class by name
 * (`WhereUsedExtensions`) and adds its answer to the one list.
 *
 * Programs are read in system mode: Core's controller has already checked Manage BarnCRM
 * Settings, and rules are setup, not organization data. A rule names an Enrollment field by its
 * API name, or a person field by its path, in each condition's `field` (format in
 * `EligibilityRules`).
 */
@NamespaceAccessible
public with sharing class ProgramsWhereUsedExtension implements WhereUsedExtension {
	private static final String KIND = 'eligibilityRules';
	private static final String RULES_OBJECT = 'Enrollment__c';

	@NamespaceAccessible
	public ProgramsWhereUsedExtension() {
		// Built by name from Core (WhereUsedExtensions), so it needs a public constructor.
	}

	public List<WhereUsedService.Reference> references(WhereUsedService.Target target) {
		List<WhereUsedService.Reference> found = new List<WhereUsedService.Reference>();
		if (target.isObject()) {
			// Rules read only Programs' own Enrollment object, which only the module removes.
			return found;
		}
		for (Program__c program : [
			SELECT Id, Name, Eligibility_Rules__c
			FROM Program__c
			WITH SYSTEM_MODE
			ORDER BY Name
			LIMIT 2000
		]) {
			if (rulesName(target, program.Eligibility_Rules__c)) {
				found.add(
					new WhereUsedService.Reference(
							KIND,
							Schema.SObjectType.Program__c.getLabelPlural(),
							program.Name,
							program.Id
						)
						.addPart(
							Schema.SObjectType.Program__c.fields.Eligibility_Rules__c.getLabel()
						)
						.withBreaks(System.Label.Core_WhereUsed_BreaksModuleRecord)
						.withRecordEdit(program.Id)
				);
			}
		}
		return found;
	}

	/** True when any condition of any rule reads the target field. */
	@TestVisible
	private static Boolean rulesName(WhereUsedService.Target target, String rules) {
		for (Object rule : WhereUsedService.listOf(WhereUsedService.parsed(rules).get('rules'))) {
			if (!(rule instanceof Map<String, Object>)) {
				continue;
			}
			for (
				Object condition : WhereUsedService.listOf(((Map<String, Object>) rule).get('all'))
			) {
				Object field = condition instanceof Map<String, Object>
					? ((Map<String, Object>) condition).get('field')
					: null;
				if (field instanceof String && target.matchesPath(RULES_OBJECT, (String) field)) {
					return true;
				}
			}
		}
		return false;
	}
}
