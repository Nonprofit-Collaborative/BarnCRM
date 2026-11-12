/**
 * Field History Keeper (C-68, canonical model Section 29FH1, ADR-NEXT field history keeper):
 * keeps every change to chosen fields of BarnCRM's own objects, beyond Salesforce's 20 tracked
 * fields, shows it with the record's own access and lets an admin restore an earlier value.
 *
 * The trigger dispatcher hands each after update here (R-FH2). The fields are `History_Field__mdt`
 * rows (`Object.Field`, no prefix), read with `getAll()`, so a save spends no query on them. One
 * `Field_History__c` row per changed record, written in system mode: the person saving need not
 * see the history. Nothing stops the save: a failure goes to the Error Log.
 */
public with sharing class FieldHistoryService {
	/** The longest text value kept whole; a longer one is cut, marked, and cannot be restored. */
	public static final Integer MAX_VALUE = 1000;
	private static final Integer MAX_ROWS = 200;
	private static final String CONTEXT = 'Field History';
	private static final String ADMIN_PERMISSION = 'Manage_BarnCRM_Settings';
	/** BarnCRM's own log, which has a trigger but is never history. */
	private static final Set<String> NEVER = new Set<String>{ 'error_log__c' };

	public class FieldHistoryException extends Exception {
	}

	/** Test seam: rows standing in for `History_Field__mdt`, which a test cannot insert. */
	@TestVisible
	private static List<History_Field__mdt> rowsForTest;

	/** The tracked field API names by object (lower case, as the dispatcher names it). */
	private static Map<String, List<String>> fieldsByObject;

	/** One change, as the Field History card shows it. */
	public class Entry {
		@AuraEnabled
		public Id historyId;
		@AuraEnabled
		public String field;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String before;
		@AuraEnabled
		public String after;
		@AuraEnabled
		public Datetime changedAt;
		@AuraEnabled
		public String changedBy;
		@AuraEnabled
		public Boolean cut = false;
		@AuraEnabled
		public Boolean canRestore = false;
	}

	// ------------------------------------------------------------------ capturing

	/**
	 * Keeps the changes to the tracked fields of these records (an after update). Does nothing
	 * while the setting is off or automation is paused or bypassed for the person saving.
	 */
	public static void capture(String objectName, List<SObject> records, Map<Id, SObject> oldById) {
		try {
			if (
				SettingsService.getSettings().Field_History_Enabled__c != true ||
				records == null ||
				oldById == null ||
				AutomationControl.isOffForRunningUser() ||
				AutomationControl.isPaused()
			) {
				return;
			}
			List<String> fields = trackedFields().get(objectName.toLowerCase());
			if (fields == null) {
				return;
			}
			List<Field_History__c> rows = new List<Field_History__c>();
			for (SObject record : records) {
				SObject old = oldById.get(record.Id);
				List<Map<String, Object>> changes = new List<Map<String, Object>>();
				for (String field : fields) {
					Object before = old == null ? null : old.get(field);
					Object after = record.get(field);
					if (!JSON.serialize(before).equals(JSON.serialize(after))) {
						changes.add(change(field, before, after));
					}
				}
				if (!changes.isEmpty()) {
					rows.add(
						new Field_History__c(
							Record_Id__c = record.Id,
							Object_Name__c = objectName,
							Changes__c = JSON.serialize(changes)
						)
					);
				}
			}
			// System mode: the person saving need not have access to the history (R-FH2).
			for (
				Database.SaveResult saved : Database.insert(rows, false, AccessLevel.SYSTEM_MODE)
			) {
				if (!saved.isSuccess()) {
					ErrorLogger.logMessage(
						saved.getErrors()[0].getMessage(),
						CONTEXT,
						ErrorLogger.SEVERITY_WARNING
					);
				}
			}
		} catch (Exception failed) {
			ErrorLogger.log(failed, CONTEXT);
		}
	}

	/** One field's change: `f`, `o` and `n`, with long text cut and marked `t` (R-FH3). */
	private static Map<String, Object> change(String field, Object before, Object after) {
		Map<String, Object> result = new Map<String, Object>{ 'f' => field };
		Boolean cut = false;
		for (String key : new List<String>{ 'o', 'n' }) {
			Object value = key == 'o' ? before : after;
			if (value instanceof String && ((String) value).length() > MAX_VALUE) {
				value = ((String) value).left(MAX_VALUE);
				cut = true;
			}
			result.put(key, value);
		}
		if (cut) {
			result.put('t', true);
		}
		return result;
	}

	/** The active rows' fields that can be kept, by object, read once per transaction. */
	@TestVisible
	private static Map<String, List<String>> trackedFields() {
		if (fieldsByObject == null) {
			fieldsByObject = new Map<String, List<String>>();
			for (History_Field__mdt row : rows()) {
				// By type only: who saves a record must not decide what is kept.
				Schema.DescribeFieldResult field = row.Active__c == true
					? keepable(row.Field_Name__c, false)
					: null;
				if (field != null) {
					String key = row.Field_Name__c.substringBefore('.').trim().toLowerCase();
					if (!fieldsByObject.containsKey(key)) {
						fieldsByObject.put(key, new List<String>());
					}
					fieldsByObject.get(key).add(field.getName());
				}
			}
		}
		return fieldsByObject;
	}

	private static List<History_Field__mdt> rows() {
		return rowsForTest != null ? rowsForTest : History_Field__mdt.getAll().values();
	}

	// ------------------------------------------------------------------ what can be kept

	/**
	 * The object of that name when Field History Keeper offers it (R-FH1): a custom object whose
	 * trigger runs through the dispatcher (named in the Automation Registry), not a log.
	 */
	public static Schema.SObjectType offeredType(String objectName) {
		String key = objectName == null ? '' : objectName.trim().toLowerCase();
		Boolean dispatched = false;
		for (Automation_Registry__mdt entry : AutomationRegistrySelector.selectForFramework()) {
			dispatched |= key.equalsIgnoreCase(entry.Object_Name__c);
		}
		Schema.SObjectType type = dispatched && !NEVER.contains(key)
			? NamespaceUtil.objectType(key)
			: null;
		return type != null && type.getDescribe(SObjectDescribeOptions.DEFERRED).isCustom()
			? type
			: null;
	}

	/**
	 * The field an `Object.Field` name means when its changes can be kept: a stored field (not a
	 * formula, roll-up summary, auto number, long text area or rich text) of an offered object.
	 */
	public static Schema.DescribeFieldResult keepable(String name) {
		return keepable(name, true);
	}

	/** `checkAccess` false leaves out the running user's create or edit access to the field. */
	private static Schema.DescribeFieldResult keepable(String name, Boolean checkAccess) {
		if (String.isBlank(name) || !name.contains('.')) {
			return null;
		}
		Schema.SObjectType type = offeredType(name.substringBefore('.'));
		Schema.SObjectField token = type == null
			? null
			: type.getDescribe(SObjectDescribeOptions.DEFERRED)
					.fields.getMap()
					.get(name.substringAfter('.').trim());
		Schema.DescribeFieldResult field = token == null ? null : token.getDescribe();
		Boolean longText =
			field != null &&
			field.getType() == Schema.DisplayType.TEXTAREA &&
			field.getLength() > 255;
		return field != null &&
			!field.isCalculated() &&
			!field.isAutoNumber() &&
			!longText &&
			(!checkAccess ||
			field.isUpdateable() ||
			field.isCreateable())
			? field
			: null;
	}

	/** The custom metadata manager's check of a History Field save (ADR-0085). */
	public class Validator implements CustomMetadataManagerService.RowValidator {
		public void validate(Map<String, Object> values) {
			String name = values == null ? null : (String) values.get('Field_Name__c');
			if (keepable(name) == null) {
				throw new CustomMetadataManagerService.CustomMetadataManagerException(
					String.format(
						BarnHelp.text('Core', 'Core_FieldHistory_FieldInvalid'),
						new List<Object>{ name }
					)
				);
			}
		}
	}

	/** Health Check: on, but no field chosen, or a chosen field that can no longer be kept. */
	public class HealthCheck implements HealthCheckService.Check {
		public HealthCheckService.Finding run() {
			if (SettingsService.getSettings().Field_History_Enabled__c != true) {
				return null;
			}
			List<String> unusable = new List<String>();
			Integer usable = 0;
			for (History_Field__mdt row : rows()) {
				if (row.Active__c == true && keepable(row.Field_Name__c) == null) {
					unusable.add(row.Field_Name__c);
				} else if (row.Active__c == true) {
					usable++;
				}
			}
			if (unusable.isEmpty() && usable > 0) {
				return null;
			}
			String detail = BarnHelp.text('Core', 'Core_FieldHistory_HealthNone');
			if (!unusable.isEmpty()) {
				detail = String.format(
					BarnHelp.text('Core', 'Core_FieldHistory_HealthUnusable'),
					new List<Object>{ String.join(unusable, ', ') }
				);
			}
			return new HealthCheckService.Finding(
				'field_history_fields',
				BarnHelp.text('Core', 'Core_FieldHistory_HealthTitle'),
				detail,
				HealthCheckService.SEVERITY_WARNING,
				HealthCheckService.CATEGORY_SETTINGS
			);
		}
	}

	// ------------------------------------------------------------------ reading and restoring

	/**
	 * The record's changes, newest first, at most 200 saves: only for someone who can read the
	 * record, and only the fields they can read (R-FH4).
	 */
	public static List<Entry> historyFor(Id recordId) {
		Schema.DescribeSObjectResult described = recordId.getSObjectType()
			.getDescribe(SObjectDescribeOptions.DEFERRED);
		Integer readable = Database.countQueryWithBinds(
			'SELECT COUNT() FROM ' + described.getName() + ' WHERE Id = :recordId',
			new Map<String, Object>{ 'recordId' => recordId },
			AccessLevel.USER_MODE
		);
		if (readable == 0) {
			throw new FieldHistoryException(BarnHelp.text('Core', 'Core_FieldHistory_NotFound'));
		}
		Map<String, Schema.SObjectField> fields = described.fields.getMap();
		Boolean admin = FeatureManagement.checkPermission(ADMIN_PERMISSION);
		List<Entry> entries = new List<Entry>();
		String key = String.valueOf(recordId);
		// System mode after the check above: the history is private bookkeeping (R-FH4).
		for (Field_History__c row : [
			SELECT Id, Changes__c, CreatedDate, CreatedBy.Name
			FROM Field_History__c
			WHERE Record_Id__c = :key
			WITH SYSTEM_MODE
			ORDER BY CreatedDate DESC
			LIMIT :MAX_ROWS
		]) {
			for (Object item : (List<Object>) JSON.deserializeUntyped(row.Changes__c)) {
				Map<String, Object> change = (Map<String, Object>) item;
				Schema.SObjectField token = fields.get(String.valueOf(change.get('f')));
				Schema.DescribeFieldResult field = token == null ? null : token.getDescribe();
				if (field == null || !field.isAccessible()) {
					continue;
				}
				Entry entry = new Entry();
				entry.historyId = row.Id;
				entry.field = field.getName();
				entry.label = field.getLabel();
				entry.before = text(change.get('o'));
				entry.after = text(change.get('n'));
				entry.changedAt = row.CreatedDate;
				entry.changedBy = row.CreatedBy.Name;
				entry.cut = change.get('t') == true;
				entry.canRestore = admin && !entry.cut && field.isUpdateable();
				entries.add(entry);
			}
		}
		return entries;
	}

	/**
	 * Writes a change's earlier value back onto its record, in user mode, so field access and
	 * validation apply; the restore is itself kept as a change (R-FH4). Admins only.
	 */
	public static void restore(Id historyId, String fieldName) {
		if (!FeatureManagement.checkPermission(ADMIN_PERMISSION)) {
			throw new FieldHistoryException(
				BarnHelp.text('Core', 'Core_FieldHistory_NoPermission')
			);
		}
		List<Field_History__c> rows = [
			SELECT Record_Id__c, Changes__c
			FROM Field_History__c
			WHERE Id = :historyId
			WITH SYSTEM_MODE
		];
		Map<String, Object> found;
		List<Object> changes = rows.isEmpty()
			? new List<Object>()
			: (List<Object>) JSON.deserializeUntyped(rows[0].Changes__c);
		for (Object item : changes) {
			Map<String, Object> change = (Map<String, Object>) item;
			if (String.valueOf(change.get('f')).equalsIgnoreCase(fieldName)) {
				found = change;
			}
		}
		if (found == null || found.get('t') == true) {
			throw new FieldHistoryException(BarnHelp.text('Core', 'Core_FieldHistory_NoRestore'));
		}
		Id recordId = Id.valueOf(rows[0].Record_Id__c);
		Map<String, Object> putBack = new Map<String, Object>{
			'attributes' => new Map<String, Object>{
				'type' => String.valueOf(recordId.getSObjectType())
			},
			'Id' => recordId,
			String.valueOf(found.get('f')) => found.get('o')
		};
		Database.update(
			(SObject) JSON.deserialize(JSON.serialize(putBack), SObject.class),
			AccessLevel.USER_MODE
		);
	}

	private static String text(Object value) {
		return value == null ? '' : String.valueOf(value);
	}
}
