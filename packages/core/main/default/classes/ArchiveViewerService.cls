/**
 * The Archived Records panel (canonical model Section 29D1, R-ARC1, R-ARC4, R-ARC7; ADR-0240 archive
 * rules and big object archive): the archived objects, one object's rows newest first within a
 * date range, a row's fields from its JSON, and starting a restore.
 *
 * Only a person granted the Archived Record object (BarnCRM Admin) may use it; the rows are read
 * in user mode through `ArchiveStore`. A row's JSON holds every field the archiving person could
 * read, and a viewer sees all of it, which the panel and the admin guide say. Restoring also needs
 * the archive rule permissions (ADR-0240 item 6).
 */
public with sharing class ArchiveViewerService {
	/** Rows shown per page, and the most one restore takes. */
	public static final Integer PAGE_SIZE = 50;
	/** The most archived objects the panel lists. */
	@TestVisible
	private static final Integer OBJECTS_READ = 50;

	/** An archived object, as the picker lists it. */
	public class ObjectChoice {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String label;
	}

	/** What the panel opens with. */
	public class Viewer {
		@AuraEnabled
		public List<ObjectChoice> objects = new List<ObjectChoice>();
		@AuraEnabled
		public Integer archivedCount;
		@AuraEnabled
		public Integer cap = BigObjectArchiveJob.CAP;
		@AuraEnabled
		public Integer warnAt = BigObjectArchiveJob.WARN_AT;
		@AuraEnabled
		public Boolean canRestore;
		@AuraEnabled
		public Integer mostRestored = PAGE_SIZE;
	}

	/** One archived row, without its JSON. `id` is the archive time in milliseconds, `|`, the Original Id. */
	public class Row {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String originalId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Datetime archivedAt;
		@AuraEnabled
		public Long archivedAtMillis;
		@AuraEnabled
		public String ruleName;
		@AuraEnabled
		public String archivedBy;
	}

	/** One page of rows and whether more follow. */
	public class RowPage {
		@AuraEnabled
		public List<Row> rows = new List<Row>();
		@AuraEnabled
		public Boolean more = false;
	}

	/** One field of an archived record. */
	public class FieldValue {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;
	}

	/** The related records saved with an archived record, by kind. */
	public class ChildGroup {
		@AuraEnabled
		public String objectName;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public Integer count;
	}

	/** One archived record's fields and related records, from its JSON. */
	public class Detail {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public List<FieldValue> fields = new List<FieldValue>();
		@AuraEnabled
		public List<ChildGroup> children = new List<ChildGroup>();
	}

	/** Whether the running person may see archived rows: the grant on the big object. */
	public static Boolean allowed() {
		return Schema.SObjectType.Archived_Record__b.isAccessible();
	}

	/** Whether the running person may restore archived rows. */
	public static Boolean canRestore() {
		return allowed() && ArchiveRuleService.allowed();
	}

	/** The archived objects, in name order, up to `OBJECTS_READ`, and the archive's use. */
	public static Viewer open() {
		requireAllowed();
		Viewer result = new Viewer();
		result.archivedCount = BigObjectArchiveJob.archivedCount();
		result.canRestore = canRestore();
		String after;
		for (Integer i = 0; i < OBJECTS_READ; i++) {
			after = ArchiveStore.get().nextObject(after);
			if (after == null) {
				break;
			}
			ObjectChoice choice = new ObjectChoice();
			choice.name = after;
			choice.label = labelOf(after);
			result.objects.add(choice);
		}
		return result;
	}

	/**
	 * One page of an object's rows, newest first, archived from the start of `fromDay` to the end
	 * of `toDay` (either may be empty), after the row `afterRowId` (empty for the first page).
	 */
	public static RowPage rows(String objectName, Date fromDay, Date toDay, String afterRowId) {
		requireAllowed();
		if (String.isBlank(objectName)) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveViewer_ErrorNoObject'));
		}
		Datetime fromAt = fromDay == null
			? Datetime.newInstance(0)
			: Datetime.newInstance(fromDay, Time.newInstance(0, 0, 0, 0));
		Datetime toAt = toDay == null
			? Datetime.now()
			: Datetime.newInstance(toDay, Time.newInstance(0, 0, 0, 0)).addDays(1).addSeconds(-1);
		Datetime afterAt;
		String afterId;
		if (String.isNotBlank(afterRowId)) {
			ArchiveStore.Key after = keyOf(objectName, afterRowId);
			afterAt = after.archivedAt;
			afterId = after.originalId;
		}
		List<Archived_Record__b> found = ArchiveStore.get()
			.page(objectName, fromAt, toAt, afterAt, afterId, PAGE_SIZE + 1);
		RowPage result = new RowPage();
		result.more = found.size() > PAGE_SIZE;
		// Who archived a row is its CreatedById, read by name: the offline compiler does not know
		// a big object's system fields.
		Set<Id> archivists = new Set<Id>();
		for (Integer i = 0; i < Math.min(found.size(), PAGE_SIZE); i++) {
			Id createdBy = (Id) found[i].get('CreatedById');
			if (createdBy != null) {
				archivists.add(createdBy);
			}
		}
		Map<Id, User> users = new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :archivists WITH USER_MODE]);
		for (Integer i = 0; i < Math.min(found.size(), PAGE_SIZE); i++) {
			Archived_Record__b one = found[i];
			Row row = new Row();
			row.archivedAtMillis = one.Archived_At__c.getTime();
			row.id = row.archivedAtMillis + '|' + one.Original_Id__c;
			row.originalId = one.Original_Id__c;
			row.name = String.isBlank(one.Record_Name__c) ? one.Original_Id__c : one.Record_Name__c;
			row.archivedAt = one.Archived_At__c;
			row.ruleName = one.Rule_Name__c;
			Id createdBy = (Id) one.get('CreatedById');
			row.archivedBy = users.containsKey(createdBy) ? users.get(createdBy).Name : null;
			result.rows.add(row);
		}
		return result;
	}

	/** One row's fields and related records, from its JSON. */
	public static Detail detail(String objectName, String rowId) {
		requireAllowed();
		ArchiveStore.Key key = keyOf(objectName, rowId);
		List<Archived_Record__b> found = ArchiveStore.get()
			.rows(objectName, key.archivedAt, new Set<String>{ key.originalId });
		if (found.isEmpty() || String.isBlank(found[0].Record_JSON__c)) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveViewer_ErrorGone'));
		}
		Detail result = new Detail();
		result.id = rowId;
		result.name = found[0].Record_Name__c;
		String body = found[0].Record_JSON__c;
		SObject record = ArchiveRecordJson.recordOf(body);
		Map<String, Schema.SObjectField> fields = record.getSObjectType() == null
			? new Map<String, Schema.SObjectField>()
			: record.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
		Map<String, FieldValue> byLabel = new Map<String, FieldValue>();
		Map<String, Object> populated = record.getPopulatedFieldsAsMap();
		for (String name : populated.keySet()) {
			Object value = populated.get(name);
			if (value == null || value instanceof SObject || value instanceof List<SObject>) {
				continue;
			}
			FieldValue field = new FieldValue();
			field.name = name;
			field.label = fields.containsKey(name) ? fields.get(name).getDescribe().getLabel() : name;
			field.value = textOf(value);
			byLabel.put(field.label.toLowerCase() + '|' + name, field);
		}
		List<String> order = new List<String>(byLabel.keySet());
		order.sort();
		for (String one : order) {
			result.fields.add(byLabel.get(one));
		}
		Map<String, List<SObject>> children = ArchiveRecordJson.childrenOf(body, new Map<String, String>());
		for (String childObject : children.keySet()) {
			ChildGroup kind = new ChildGroup();
			kind.objectName = childObject;
			kind.label = labelOf(childObject);
			kind.count = children.get(childObject).size();
			result.children.add(kind);
		}
		return result;
	}

	/** Starts restoring rows of one object; returns the Archive data job. */
	public static Import_Batch__c restore(String objectName, List<String> rowIds) {
		if (!canRestore()) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveViewer_ErrorNoRestore'));
		}
		Set<String> distinct = rowIds == null ? new Set<String>() : new Set<String>(rowIds);
		distinct.remove(null);
		if (distinct.isEmpty() || distinct.size() > PAGE_SIZE) {
			throw new ArchiveRules.ArchiveRuleException(
				BarnHelp.text('Core', 'Core_ArchiveViewer_ErrorPick', new List<Object>{ PAGE_SIZE })
			);
		}
		for (String one : distinct) {
			keyOf(objectName, one);
		}
		String label = labelOf(objectName);
		Datetime now = Datetime.now();
		Import_Batch__c job = new Import_Batch__c(
			Operation__c = BigObjectArchiveJob.OPERATION_ARCHIVE,
			Operation_JSON__c = JSON.serialize(
				new Map<String, Object>{
					'version' => 1,
					'action' => 'restore',
					'name' => BarnHelp.text('Core', 'Core_ArchiveViewer_RunName', new List<Object>{ label }),
					'object' => objectName
				}
			),
			Status__c = ImportBatchService.STATUS_COMMITTING,
			Is_Dry_Run__c = false,
			Row_Count__c = distinct.size(),
			Rows_Created__c = 0,
			Rows_Deleted__c = 0,
			Rows_Rejected__c = 0,
			Started_At__c = now,
			Committed_By__c = UserInfo.getUserId(),
			Run_Log__c = BarnHelp.text(
				'Core',
				'Core_ArchiveViewer_LogStarted',
				new List<Object>{ UserInfo.getName(), now.format(), distinct.size().format(), label }
			)
		);
		// The package's own bookkeeping (ADR-0021); the records are created as the person.
		Database.insert(job, AccessLevel.SYSTEM_MODE);
		BigObjectArchiveJob.queue(new ArchiveRestoreJob(job.Id, objectName, new List<String>(distinct)));
		return job;
	}

	/** A row id as a key of this object; refused when it is not one. */
	public static ArchiveStore.Key keyOf(String objectName, String rowId) {
		List<String> parts = String.isBlank(rowId) ? new List<String>() : rowId.split('\\|');
		if (String.isBlank(objectName) || parts.size() != 2 || !parts[0].isNumeric() || String.isBlank(parts[1])) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveViewer_ErrorGone'));
		}
		return new ArchiveStore.Key(objectName, Datetime.newInstance(Long.valueOf(parts[0])), parts[1]);
	}

	/** An object's label, or its name when the org no longer has it. */
	public static String labelOf(String objectName) {
		Schema.SObjectType type = NamespaceUtil.objectType(objectName);
		return type == null ? objectName : type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
	}

	private static String textOf(Object value) {
		if (value instanceof Datetime) {
			return ((Datetime) value).format();
		}
		if (value instanceof Date) {
			return ((Date) value).format();
		}
		return String.valueOf(value);
	}

	private static void requireAllowed() {
		if (!allowed()) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveViewer_ErrorNoAccess'));
		}
	}
}
