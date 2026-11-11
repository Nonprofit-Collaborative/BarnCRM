/**
 * Generic Record Merge (C-62, canonical model R-DP11 and R-DP12, extends ADR-0145): merges two
 * records of one BarnCRM object, journaled and undoable like auto-merge.
 *
 * The platform's merge serves only people, households, leads and cases, so this merges by hand,
 * in user mode and in one transaction: the related records move to the kept record (the links
 * auto-merge records, `AutoMergeService.movedRecords`), the other record goes to the Recycle Bin,
 * then the kept record takes the values the person chose. The order lets a value move across
 * once the other record no longer holds it. A Merge Journal row records it all, so the shared
 * undo (`AutoMergeService.undo`) restores the record, its values and its related records.
 *
 * Nothing is merged when a related record would be lost: one that could not be read, or one
 * under a master-detail link that cannot be changed, which the delete would take with it.
 */
public with sharing class GenericMergeService {
	/** BarnCRM's own logs, journals and configuration, never offered (by name, no prefix). */
	private static final Set<String> INTERNAL = new Set<String>{
		'automation_setting__c',
		'automation_snapshot__c',
		'duplicate_dismissal__c',
		'duplicate_reason__c',
		'erasure__c',
		'error_log__c',
		'field_history__c',
		'field_utilization_snapshot__c',
		'household_adoption__c',
		'household_member__c',
		'import_batch__c',
		'import_journal__c',
		'import_row__c',
		'merge_journal__c',
		'nightly_job__c',
		'setting_change__c',
		'setup_change__c',
		'whats_new_seen__c'
	};

	/** One field of the two records, as the merge page compares them. */
	public class FieldRow {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String first;
		@AuraEnabled
		public String second;
		@AuraEnabled
		public Boolean differs = false;
		/** The rules' choice, with the first record kept: true takes the second's value. */
		@AuraEnabled
		public Boolean takeSecond = false;
	}

	/** The two records side by side. */
	public class Comparison {
		@AuraEnabled
		public String objectLabel;
		@AuraEnabled
		public String firstName;
		@AuraEnabled
		public String secondName;
		@AuraEnabled
		public List<FieldRow> fields = new List<FieldRow>();
	}

	/** What one merge did. */
	public class Outcome {
		@AuraEnabled
		public Integer moved = 0;
		@AuraEnabled
		public Integer changed = 0;
	}

	/** The objects this person may merge, by label: API name to label. */
	public static Map<String, String> objects() {
		String prefix = NamespaceUtil.prefix();
		Map<String, String> byName = new Map<String, String>();
		for (String key : NamespaceUtil.globalDescribe().keySet()) {
			if (key.endsWith('__c') && (prefix == '' || key.startsWithIgnoreCase(prefix))) {
				Schema.DescribeSObjectResult described = NamespaceUtil.globalDescribe()
					.get(key)
					.getDescribe(SObjectDescribeOptions.DEFERRED);
				if (isOffered(described)) {
					byName.put(described.getName(), described.getLabel());
				}
			}
		}
		return byName;
	}

	/** The object of that name when this person may merge its records, else null. */
	public static Schema.SObjectType offeredType(String objectName) {
		Schema.SObjectType type = NamespaceUtil.objectType(objectName);
		return type != null && isOffered(type.getDescribe(SObjectDescribeOptions.DEFERRED))
			? type
			: null;
	}

	private static Boolean isOffered(Schema.DescribeSObjectResult described) {
		String name = described.getName();
		String prefix = NamespaceUtil.prefix();
		return described.isCustom() &&
			!described.isCustomSetting() &&
			name.endsWithIgnoreCase('__c') &&
			(prefix == '' || name.startsWithIgnoreCase(prefix)) &&
			!INTERNAL.contains(MergeRuleService.bare(name).toLowerCase()) &&
			described.isAccessible() &&
			described.isUpdateable() &&
			described.isDeletable() &&
			described.isUndeletable();
	}

	/**
	 * The fields a person chooses between: those the merge rules may change, less any unique
	 * field, which the kept record keeps (the other record still holds its value until the
	 * delete, and undo could not bring it back beside the kept one).
	 */
	public static List<String> choosableFields(Schema.SObjectType type) {
		Map<String, Schema.SObjectField> byName = type.getDescribe().fields.getMap();
		List<String> names = new List<String>();
		for (String name : MergeRuleService.mergeableFields(type)) {
			if (!byName.get(name).getDescribe().isUnique()) {
				names.add(name);
			}
		}
		return names;
	}

	/** The two records field by field, with the merge rules' choice for each. */
	public static Comparison compare(String objectName, Id firstId, Id secondId) {
		Schema.SObjectType type = requireType(objectName, firstId, secondId);
		Schema.DescribeSObjectResult described = type.getDescribe();
		List<String> fields = choosableFields(type);
		Map<Id, SObject> records = read(type, firstId, secondId, fields);
		SObject first = records.get(firstId);
		SObject second = records.get(secondId);
		Map<String, Object> wins = MergeRuleService.winningValues(
			first,
			second,
			fields,
			scopeOf(described)
		);
		Comparison result = new Comparison();
		result.objectLabel = described.getLabel();
		result.firstName = nameOf(first);
		result.secondName = nameOf(second);
		Map<String, Schema.SObjectField> byName = described.fields.getMap();
		for (String field : fields) {
			FieldRow row = new FieldRow();
			row.name = field;
			row.label = byName.get(field).getDescribe().getLabel();
			row.first = text(first.get(field));
			row.second = text(second.get(field));
			row.differs = !row.first.equals(row.second);
			row.takeSecond = wins.containsKey(field);
			result.fields.add(row);
		}
		return result;
	}

	/**
	 * Merges `otherId` into `keepId`: the fields named in `fromOther` take the other record's
	 * value, every related record moves to the kept record, and the other goes to the Recycle
	 * Bin. All or nothing, journaled for undo.
	 */
	public static Outcome mergeRecords(
		String objectName,
		Id keepId,
		Id otherId,
		List<String> fromOther
	) {
		Schema.SObjectType type = requireType(objectName, keepId, otherId);
		Map<String, String> choosable = new Map<String, String>();
		for (String name : choosableFields(type)) {
			choosable.put(name.toLowerCase(), name);
		}
		List<String> taking = new List<String>();
		for (String name : fromOther == null ? new List<String>() : fromOther) {
			String field = name == null ? null : choosable.get(name.toLowerCase());
			if (field == null) {
				throw new DuplicateService.DuplicateException(
					String.format(
						BarnHelp.text('Core', 'Core_GenericMerge_ErrorField'),
						new List<Object>{ name }
					)
				);
			}
			taking.add(field);
		}
		Map<Id, SObject> records = read(type, keepId, otherId, taking);
		refuseLostRecords(type, otherId);
		AutoMergeService.Moved moved = AutoMergeService.movedRecords(type, new Set<Id>{ otherId })
			.get(otherId);
		if (!moved.notes.isEmpty()) {
			throw new DuplicateService.DuplicateException(
				String.format(
					BarnHelp.text('Core', 'Core_GenericMerge_ErrorUnread'),
					new List<Object>{ String.join(moved.notes, ' ') }
				)
			);
		}
		Outcome outcome = new Outcome();
		Savepoint before = Database.setSavepoint();
		try {
			outcome.moved = moveRelated(moved.byLink, keepId);
			Database.delete(type.newSObject(otherId), AccessLevel.USER_MODE);
			SObject keep = type.newSObject(keepId);
			Map<String, Object> changed = new Map<String, Object>();
			for (String field : taking) {
				Object was = records.get(keepId).get(field);
				Object now = records.get(otherId).get(field);
				if (!JSON.serialize(was).equals(JSON.serialize(now))) {
					keep.put(field, now);
					changed.put(field, new Map<String, Object>{ 'before' => was, 'after' => now });
				}
			}
			if (!changed.isEmpty()) {
				Database.update(keep, AccessLevel.USER_MODE);
			}
			outcome.changed = changed.size();
			String mergedName = nameOf(records.get(otherId));
			Database.insert(
				new Merge_Journal__c(
					Run_Id__c = UUID.randomUUID().toString(),
					Survivor_Id__c = keepId,
					Merged_Id__c = otherId,
					Merged_Name__c = mergedName == null ? null : mergedName.left(255),
					Status__c = AutoMergeService.MERGED,
					Changed_Values__c = JSON.serialize(changed),
					Moved_Records__c = JSON.serialize(moved.byLink)
				),
				AccessLevel.USER_MODE
			);
		} catch (Exception failed) {
			Database.rollback(before);
			throw failed;
		}
		return outcome;
	}

	/** Points every recorded related record at the kept record; answers how many moved. */
	private static Integer moveRelated(Map<String, List<Id>> byLink, Id keepId) {
		Integer count = 0;
		for (String key : byLink.keySet()) {
			String field = key.substringAfter('.');
			List<SObject> moves = new List<SObject>();
			for (Id recordId : byLink.get(key)) {
				// The kept record linked to the other is left: it cannot point at itself.
				if (recordId != keepId) {
					SObject move = recordId.getSObjectType().newSObject(recordId);
					move.put(field, keepId);
					moves.add(move);
				}
			}
			Database.update(moves, AccessLevel.USER_MODE);
			count += moves.size();
		}
		return count;
	}

	/**
	 * Refuses the merge when a record of a BarnCRM object sits under the other record through a
	 * master-detail link this person cannot change: the delete would take it too.
	 */
	@TestVisible
	private static void refuseLostRecords(Schema.SObjectType type, Id otherId) {
		for (Schema.ChildRelationship link : type.getDescribe().getChildRelationships()) {
			if (!link.isCascadeDelete()) {
				continue;
			}
			Schema.DescribeFieldResult field = link.getField().getDescribe();
			Schema.DescribeSObjectResult child = link.getChildSObject()
				.getDescribe(SObjectDescribeOptions.DEFERRED);
			if (!child.isCustom() || (field.isUpdateable() && child.isUpdateable())) {
				continue;
			}
			Integer held = Database.countQueryWithBinds(
				'SELECT COUNT() FROM ' +
					child.getName() +
					' WHERE ' +
					field.getName() +
					' = :otherId LIMIT 1',
				new Map<String, Object>{ 'otherId' => otherId },
				AccessLevel.SYSTEM_MODE
			);
			if (held > 0) {
				throw new DuplicateService.DuplicateException(
					String.format(
						BarnHelp.text('Core', 'Core_GenericMerge_ErrorLost'),
						new List<Object>{ child.getLabelPlural() }
					)
				);
			}
		}
	}

	// ------------------------------------------------------------------ helpers

	private static Schema.SObjectType requireType(String objectName, Id firstId, Id secondId) {
		if (SettingsService.getSettings().Generic_Merge_Enabled__c != true) {
			throw new DuplicateService.DuplicateException(
				BarnHelp.text('Core', 'Core_GenericMerge_ErrorOff')
			);
		}
		Schema.SObjectType type = offeredType(objectName);
		if (type == null) {
			throw new DuplicateService.DuplicateException(
				String.format(
					BarnHelp.text('Core', 'Core_GenericMerge_ErrorObject'),
					new List<Object>{ objectName }
				)
			);
		}
		if (
			firstId == null ||
			secondId == null ||
			firstId == secondId ||
			firstId.getSObjectType() != type ||
			secondId.getSObjectType() != type
		) {
			throw new DuplicateService.DuplicateException(
				BarnHelp.text('Core', 'Core_GenericMerge_ErrorPair')
			);
		}
		return type;
	}

	/** Both records in user mode, with these fields, the name and the dates the rules read. */
	private static Map<Id, SObject> read(
		Schema.SObjectType type,
		Id firstId,
		Id secondId,
		List<String> fields
	) {
		Map<String, String> names = new Map<String, String>{
			'id' => 'Id',
			'name' => 'Name',
			'createddate' => 'CreatedDate',
			'lastmodifieddate' => 'LastModifiedDate'
		};
		for (String field : fields) {
			names.put(field.toLowerCase(), field);
		}
		Map<Id, SObject> records = new Map<Id, SObject>(
			Database.queryWithBinds(
				'SELECT ' +
					String.join(names.values(), ', ') +
					' FROM ' +
					type.getDescribe().getName() +
					' WHERE Id IN :ids',
				new Map<String, Object>{ 'ids' => new Set<Id>{ firstId, secondId } },
				AccessLevel.USER_MODE
			)
		);
		if (records.size() < 2) {
			throw new DuplicateService.DuplicateException(
				BarnHelp.text('Core', 'Core_GenericMerge_ErrorNotFound')
			);
		}
		return records;
	}

	/** The merge rules' scope for an object: its name without a prefix, lower case, and a dot. */
	private static String scopeOf(Schema.DescribeSObjectResult described) {
		return MergeRuleService.bare(described.getName()).toLowerCase() + '.';
	}

	private static String nameOf(SObject record) {
		return text(record.get('Name'));
	}

	private static String text(Object value) {
		return value == null ? '' : String.valueOf(value);
	}
}
