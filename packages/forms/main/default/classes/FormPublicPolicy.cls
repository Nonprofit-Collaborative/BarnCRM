/**
 * What a public form may do (canonical model R-FM3; ADR-NEXT public forms on a Salesforce Site,
 * decisions 3, 4 and 6): its spam settings, the allowlist of what it may write, and the copy of
 * its definition a guest is given.
 *
 * The allowlist is checked as the person publishing and again as the person processing, so a
 * field either of them may not create is never written from an anonymous answer.
 */
public with sharing class FormPublicPolicy {
	public static final Integer DEFAULT_MIN_SECONDS = 3;
	public static final Integer DEFAULT_HOURLY_LIMIT = 50;
	private static final Set<String> FORMS_OBJECTS = new Set<String>{
		'form__c',
		'form_version__c',
		'form_submission__c'
	};
	private static final Set<Schema.DisplayType> NEVER_ANSWERED = new Set<Schema.DisplayType>{
		Schema.DisplayType.REFERENCE,
		Schema.DisplayType.ENCRYPTEDSTRING
	};

	/** The `public` block, or an empty map when the definition has none. */
	public static Map<String, Object> settings(Map<String, Object> definition) {
		Object block = definition == null ? null : definition.get('public');
		return block instanceof Map<String, Object>
			? (Map<String, Object>) block
			: new Map<String, Object>();
	}

	/** True when the definition may be filled in on a Site or by an API caller. */
	public static Boolean isPublic(Map<String, Object> definition) {
		return settings(definition).get('enabled') == true;
	}

	public static Integer minSeconds(Map<String, Object> definition) {
		return whole(settings(definition).get('minSeconds'), DEFAULT_MIN_SECONDS, 0, 600);
	}

	public static Integer hourlyLimit(Map<String, Object> definition) {
		return whole(settings(definition).get('hourlyLimit'), DEFAULT_HOURLY_LIMIT, 1, 1000);
	}

	/** The form's own thank-you text, or null for the shipped one. */
	public static String confirmation(Map<String, Object> definition) {
		Object text = settings(definition).get('confirmation');
		return text instanceof String && String.isNotBlank((String) text)
			? ((String) text).abbreviate(1000)
			: null;
	}

	private static Integer whole(Object value, Integer fallback, Integer low, Integer high) {
		if (!(value instanceof Integer || value instanceof Decimal || value instanceof Long)) {
			return fallback;
		}
		Integer given = Integer.valueOf(value);
		return Math.max(low, Math.min(high, given));
	}

	/**
	 * The first reason a public form may not write what it maps, in words, or null when it may
	 * (R-FM3). Read with the running user's access: a field they may not create is refused.
	 */
	public static String problem(Map<String, Object> definition) {
		Map<String, String> objectByRecord = new Map<String, String>();
		for (
			FormSubmitService.Plan entry : FormSubmitService.plan(
				definition,
				new Map<String, Object>()
			)
		) {
			objectByRecord.put(entry.key, entry.objectName);
			if (entry.onMatch == 'overwrite') {
				return BarnHelp.text(
					'Forms',
					'Forms_Public_NoOverwrite',
					new List<Object>{ entry.key }
				);
			}
			if (!objectAllowed(entry.objectName)) {
				return BarnHelp.text(
					'Forms',
					'Forms_Public_ObjectNotAllowed',
					new List<Object>{ entry.objectName }
				);
			}
		}
		for (Map<String, Object> field : FormRules.allFields(definition)) {
			Map<String, Object> target = field.get('target') instanceof Map<String, Object>
				? (Map<String, Object>) field.get('target')
				: null;
			String objectName = target == null
				? null
				: objectByRecord.get(String.valueOf(target.get('record')));
			if (objectName == null) {
				continue;
			}
			String fieldName = String.valueOf(target.get('field'));
			if (!fieldAllowed(objectName, fieldName)) {
				return BarnHelp.text(
					'Forms',
					'Forms_Public_FieldNotAllowed',
					new List<Object>{ objectName, fieldName }
				);
			}
		}
		return null;
	}

	private static Boolean objectAllowed(String objectName) {
		String name = objectName == null ? '' : objectName.toLowerCase();
		if (name == 'contact' || name == 'account') {
			return true;
		}
		if (!name.endsWith('__c') || FORMS_OBJECTS.contains(name)) {
			return false;
		}
		List<Schema.DescribeSObjectResult> described = Schema.describeSObjects(
			new List<String>{ objectName },
			SObjectDescribeOptions.DEFERRED
		);
		return !described.isEmpty() && !described[0].isCustomSetting();
	}

	private static Boolean fieldAllowed(String objectName, String fieldName) {
		Schema.SObjectField field = Schema.describeSObjects(
				new List<String>{ objectName },
				SObjectDescribeOptions.DEFERRED
			)[0]
			.fields.getMap()
			.get(fieldName == null ? '' : fieldName.toLowerCase());
		if (field == null) {
			return false;
		}
		Schema.DescribeFieldResult about = field.getDescribe();
		return about.isCreateable() && !NEVER_ANSWERED.contains(about.getType());
	}

	/**
	 * The definition a guest is given: the questions and the public settings, with the records,
	 * every target and every constant left out, so no API name is published (decision 4).
	 */
	public static String publicCopy(Map<String, Object> definition) {
		Map<String, Object> copy = (Map<String, Object>) JSON.deserializeUntyped(
			JSON.serialize(definition)
		);
		copy.remove('records');
		for (Map<String, Object> field : FormRules.allFields(copy)) {
			field.remove('target');
		}
		return JSON.serialize(copy);
	}
}
