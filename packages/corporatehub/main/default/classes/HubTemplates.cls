/**
 * The shipped templates (CH-04 to CH-07; canonical model R-CT1; ADR-0006 decision 3): the JSON
 * static resource `BarnCorporateHubTemplates` loaded as ordinary records, once per template key.
 * Obligations arrive Off, policies and processing activities (the CH-05 GDPR set) Draft; a record
 * that already carries a key is never touched, so an upgrade only adds new templates.
 */
public with sharing class HubTemplates {
	@TestVisible
	private static final String RESOURCE = 'BarnCorporateHubTemplates';

	/** Set by a test to stand in for the static resource. */
	@TestVisible
	private static String bodyOverride;

	/** A self-assessment template (`assessments`, R-BA1): its title and questions, or null. */
	public static Map<String, Object> assessment(String key) {
		Map<String, Object> templates = (Map<String, Object>) JSON.deserializeUntyped(body());
		for (Object item : entries(templates, 'assessments')) {
			Map<String, Object> template = (Map<String, Object>) item;
			if (text(template, 'key') == key) {
				return template;
			}
		}
		return null;
	}

	/**
	 * Creates a record for each template key the org does not have.
	 *
	 * @param ownerId who owns the new records; null means the running user
	 * @param asSystem true at install (the package's own setup, system mode); false from the
	 *   page (user mode)
	 * @return how many records were created
	 */
	public static Integer loadMissing(Id ownerId, Boolean asSystem) {
		Map<String, Object> templates = (Map<String, Object>) JSON.deserializeUntyped(body());
		Set<String> have = new Set<String>();
		for (SObject row : keyed(asSystem)) {
			have.add(((String) row.get('Template_Key__c')).toLowerCase());
		}
		List<SObject> rows = new List<SObject>();
		for (Object item : entries(templates, 'obligations')) {
			Map<String, Object> t = (Map<String, Object>) item;
			if (!have.contains(text(t, 'key').toLowerCase())) {
				rows.add(
					owned(
						new Compliance_Obligation__c(
							Name = text(t, 'name'),
							Template_Key__c = text(t, 'key'),
							Category__c = text(t, 'category'),
							Jurisdiction__c = text(t, 'jurisdiction'),
							Recurrence__c = text(t, 'recurrence'),
							Instructions__c = text(t, 'instructions'),
							Reference_Url__c = text(t, 'referenceUrl'),
							Status__c = 'Off'
						),
						ownerId
					)
				);
			}
		}
		for (Object item : entries(templates, 'policies')) {
			Map<String, Object> t = (Map<String, Object>) item;
			if (!have.contains(text(t, 'key').toLowerCase())) {
				rows.add(
					owned(
						new Hub_Document__c(
							Name = text(t, 'name'),
							Template_Key__c = text(t, 'key'),
							Type__c = 'Policy',
							Status__c = 'Draft',
							Requires_Acknowledgment__c = t.get('requiresAcknowledgment') == true,
							Review_Months__c = t.get('reviewMonths') == null
								? 12
								: Decimal.valueOf(text(t, 'reviewMonths')),
							Summary__c = text(t, 'summary')
						),
						ownerId
					)
				);
			}
		}
		for (Object item : entries(templates, 'processingActivities')) {
			Map<String, Object> t = (Map<String, Object>) item;
			if (!have.contains(text(t, 'key').toLowerCase())) {
				rows.add(
					owned(
						new Processing_Activity__c(
							Name = text(t, 'name'),
							Template_Key__c = text(t, 'key'),
							Status__c = 'Draft',
							Purpose__c = text(t, 'purpose'),
							Lawful_Basis__c = text(t, 'lawfulBasis'),
							Data_Subjects__c = text(t, 'dataSubjects'),
							Data_Categories__c = text(t, 'dataCategories'),
							Recipients__c = text(t, 'recipients'),
							Retention__c = text(t, 'retention')
						),
						ownerId
					)
				);
			}
		}
		if (asSystem == true) {
			insert as system rows;
		} else {
			insert as user rows;
		}
		return rows.size();
	}

	/** The obligations and documents that came from a template. */
	private static List<SObject> keyed(Boolean asSystem) {
		List<SObject> rows = new List<SObject>();
		if (asSystem == true) {
			rows.addAll(
				[
					SELECT Template_Key__c
					FROM Compliance_Obligation__c
					WHERE Template_Key__c != NULL
					WITH SYSTEM_MODE
				]
			);
			rows.addAll(
				[
					SELECT Template_Key__c
					FROM Hub_Document__c
					WHERE Template_Key__c != NULL
					WITH SYSTEM_MODE
				]
			);
			rows.addAll(
				[
					SELECT Template_Key__c
					FROM Processing_Activity__c
					WHERE Template_Key__c != NULL
					WITH SYSTEM_MODE
				]
			);
		} else {
			rows.addAll(
				[
					SELECT Template_Key__c
					FROM Compliance_Obligation__c
					WHERE Template_Key__c != NULL
					WITH USER_MODE
				]
			);
			rows.addAll(
				[
					SELECT Template_Key__c
					FROM Hub_Document__c
					WHERE Template_Key__c != NULL
					WITH USER_MODE
				]
			);
			rows.addAll(
				[
					SELECT Template_Key__c
					FROM Processing_Activity__c
					WHERE Template_Key__c != NULL
					WITH USER_MODE
				]
			);
		}
		return rows;
	}

	private static SObject owned(SObject row, Id ownerId) {
		if (ownerId != null) {
			row.put('OwnerId', ownerId);
		}
		return row;
	}

	private static String body() {
		if (bodyOverride != null) {
			return bodyOverride;
		}
		String prefix = NamespaceUtil.prefix().removeEnd('__');
		String namespace = String.isBlank(prefix) ? null : prefix;
		// System mode, as BarnHelp reads its catalogs: packaged data, never a same-named resource
		// of the org's own.
		List<StaticResource> found = [
			SELECT Body
			FROM StaticResource
			WHERE Name = :RESOURCE AND NamespacePrefix = :namespace
			WITH SYSTEM_MODE
			LIMIT 1
		];
		return found.isEmpty() ? '{}' : found[0].Body.toString();
	}

	private static List<Object> entries(Map<String, Object> templates, String name) {
		Object items = templates.get(name);
		return items instanceof List<Object> ? (List<Object>) items : new List<Object>();
	}

	private static String text(Map<String, Object> template, String name) {
		Object value = template.get(name);
		return value == null ? null : String.valueOf(value);
	}
}
