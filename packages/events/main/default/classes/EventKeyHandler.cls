/**
 * The "once per event" rules of the Event Management module (ADR-NEXT `NEXT-events-module.md`),
 * run by the Core trigger dispatcher through registry rows that always run (ADR-0024): R-PC1, a
 * promo code is unique within its event, regardless of case (row `Promo_Code_Key`).
 *
 * Each object the handler serves names its key field, the field that groups (the event) and the
 * field that must not repeat in the group. The key is the group's identifier, a colon and the
 * value (text in capitals, trimmed). A repeat in the same save or against a saved record is
 * refused in plain words; the unique key field backs it against two saves at once.
 */
@NamespaceAccessible
public with sharing class EventKeyHandler extends TriggerHandler {
	/** How one object's key is made. */
	private class KeyRule {
		String keyField;
		String groupField;
		String valueField;
		Boolean isText;

		KeyRule(String keyField, String groupField, String valueField, Boolean isText) {
			this.keyField = keyField;
			this.groupField = groupField;
			this.valueField = valueField;
			this.isText = isText;
		}
	}

	private static final Map<Schema.SObjectType, KeyRule> RULES = new Map<Schema.SObjectType, KeyRule>{
		Promo_Code__c.SObjectType => new KeyRule('Code_Key__c', 'Event__c', 'Name', true)
	};

	@NamespaceAccessible
	public EventKeyHandler() {
		return;
	}

	public override String getName() {
		return 'EventKeyHandler';
	}

	public override void beforeInsert() {
		setKeys(newRecords());
	}

	public override void beforeUpdate() {
		setKeys(newRecords());
	}

	/** Sets each record's key and refuses a record whose key another record already has. */
	@TestVisible
	private static void setKeys(List<SObject> records) {
		if (records == null || records.isEmpty()) {
			return;
		}
		Schema.SObjectType objectType = records[0].getSObjectType();
		KeyRule rule = RULES.get(objectType);
		if (rule == null) {
			return;
		}
		Map<String, SObject> byKey = new Map<String, SObject>();
		for (SObject record : records) {
			String key = keyOf(record, rule);
			record.put(rule.keyField, key);
			if (key == null) {
				continue;
			}
			if (byKey.containsKey(key)) {
				record.addError(duplicateMessage(record, rule));
			} else {
				byKey.put(key, record);
			}
		}
		if (byKey.isEmpty()) {
			return;
		}
		Set<String> keys = byKey.keySet();
		// Access mode: AccessLevel.USER_MODE below; a record the person cannot see is still
		// caught by the unique key field.
		List<SObject> saved = Database.queryWithBinds(
			'SELECT Id, ' +
				rule.keyField +
				' FROM ' +
				objectType.getDescribe().getName() +
				' WHERE ' +
				rule.keyField +
				' IN :keys',
			new Map<String, Object>{ 'keys' => keys },
			AccessLevel.USER_MODE
		);
		for (SObject other : saved) {
			SObject record = byKey.get((String) other.get(rule.keyField));
			if (record != null && record.Id != other.Id) {
				record.addError(duplicateMessage(record, rule));
			}
		}
	}

	/** The record's key, or null while the value is empty (a validation rule asks for it). */
	@TestVisible
	private static String keyOf(SObject record, KeyRule rule) {
		Object groupId = record.get(rule.groupField);
		Object value = record.get(rule.valueField);
		if (rule.isText && value != null) {
			value = ((String) value).trim();
			record.put(rule.valueField, value);
		}
		if (groupId == null || value == null || String.isBlank(String.valueOf(value))) {
			return null;
		}
		String part = rule.isText
			? ((String) value).toUpperCase()
			: String.valueOf(Id.valueOf(String.valueOf(value)));
		return String.valueOf(Id.valueOf(String.valueOf(groupId))) + ':' + part;
	}

	/** The plain-words refusal for a repeat, naming the value repeated. */
	private static String duplicateMessage(SObject record, KeyRule rule) {
		List<Object> args = new List<Object>{ record.get(rule.valueField) };
		return BarnHelp.text('Events', 'Events_PromoCode_Duplicate', args);
	}
}
