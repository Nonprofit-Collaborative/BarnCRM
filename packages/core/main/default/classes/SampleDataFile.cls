/**
 * A module's sample data set written as JSON and loaded by Core (C-10, D-200 S2), so a module
 * ships a static resource instead of loader Apex. SampleDataModules finds the file by the same
 * name it would look a module's class up by (for example FundersSampleData), when no class of
 * that name is installed. The format, documented in data/sample/README.md:
 *
 *     {
 *       "module": "Funders",                  the name module detection uses
 *       "countLabel": "Grants",               what the status card's number counts
 *       "count": { "object": "Grant__c", "where": "Sample_Data__c = TRUE" },
 *       "steps": [                            one insert per step, one step per transaction
 *         { "object": "Grant__c", "records": [ { "key": "award", "Name": "...", ... } ] }
 *       ],
 *       "remove": [ { "object": "Grant__c", "where": "Sample_Data__c = TRUE" } ]
 *     }
 *
 * A record is its field values by API name, plus an optional `key` later records point at. A
 * value is a literal, or one of:
 *
 * - `{ "ref": "award" }`: the record of that key this file inserted earlier.
 * - `{ "sample": "H001-1" }`: Core's sample person, household or organization of that key.
 * - `{ "currentUser": true }`: the person loading the set.
 * - `{ "days": -30, "months": 6, "time": "08:30" }`: today moved by days then months, as a date,
 *   or a date and time (local) for a Date/Time field; `{ "time": "16:00" }` alone for a Time field.
 *
 * A record whose `ref` or `sample` does not resolve is left out, unless the value also says
 * `"optional": true`, which leaves that field blank instead: one module never breaks the load
 * because the set it builds on is smaller. A step whose object the person loading cannot create
 * is skipped, and so is a field they cannot set, as the module loaders did. Every insert is in
 * user mode, so the module's own rules run as they would for an administrator.
 *
 * Removal deletes each `remove` entry's matches in order, a chunk per transaction, with partial
 * success: a record the organization's own records point at refuses the delete (a Restrict lookup
 * or a rule) and is kept, never deleted from under them, and one Warning in the Error Log says
 * how many of each were kept. `where` is SOQL written by the module, never by a user.
 */
@NamespaceAccessible
public with sharing class SampleDataFile implements SampleDataModule {
	/** Records each removal stage deletes. Tests, the modules' included, lower it. */
	@NamespaceAccessible
	public static Integer removeChunkSize = 200;

	/** Parsed files by resource name, this transaction. Tests put their own here. */
	@TestVisible
	private static Map<String, Map<String, Object>> filesByName = new Map<String, Map<String, Object>>();

	/** Core's sample records by Sample_Data_Key__c, read once per transaction. */
	private static Map<String, Id> sampleIdsByKey;

	private final String resourceName;

	private SampleDataFile(String resourceName) {
		this.resourceName = resourceName;
	}

	/** The module file of this static resource name, or null when no such file is installed. */
	@NamespaceAccessible
	public static SampleDataFile find(String resourceName) {
		if (!filesByName.containsKey(resourceName)) {
			String body = SetupObjectSelector.staticResourceBody(resourceName);
			filesByName.put(
				resourceName,
				String.isBlank(body) ? null : (Map<String, Object>) JSON.deserializeUntyped(body)
			);
		}
		return filesByName.get(resourceName) == null ? null : new SampleDataFile(resourceName);
	}

	private Map<String, Object> root() {
		find(resourceName);
		return filesByName.get(resourceName);
	}

	private List<Object> listOf(String name) {
		Object value = root().get(name);
		return value == null ? new List<Object>() : (List<Object>) value;
	}

	// ------------------------------------------------------------------------- SampleDataModule

	@NamespaceAccessible
	public String moduleName() {
		return (String) root().get('module');
	}

	@NamespaceAccessible
	public String countLabel() {
		return (String) root().get('countLabel');
	}

	@NamespaceAccessible
	public Integer countLoaded() {
		return countOf((Map<String, Object>) root().get('count'), null);
	}

	@NamespaceAccessible
	public Boolean hasSampleRecords() {
		for (Object entry : listOf('remove')) {
			if (countOf((Map<String, Object>) entry, 1) > 0) {
				return true;
			}
		}
		return false;
	}

	@NamespaceAccessible
	public void enqueueLoad() {
		SampleDataStageBatch.start(new LoadStages(resourceName));
	}

	@NamespaceAccessible
	public void enqueueRemove() {
		SampleDataRemoveBatch.startRemoval(new RemoveStages(resourceName));
	}

	// ------------------------------------------------------------------------- load

	/** The load, one step per stage. Only the keys inserted so far travel between stages. */
	@NamespaceAccessible
	public with sharing class LoadStages implements SampleDataStages {
		private final String resourceName;
		private Map<String, Id> idsByKey = new Map<String, Id>();

		@NamespaceAccessible
		public LoadStages(String resourceName) {
			this.resourceName = resourceName;
		}

		@NamespaceAccessible
		public String name() {
			return resourceName + '.load';
		}

		@NamespaceAccessible
		public Integer stageCount() {
			return find(resourceName).listOf('steps').size();
		}

		@NamespaceAccessible
		public void runStage(Integer stage) {
			Map<String, Object> step = (Map<String, Object>) find(resourceName)
				.listOf('steps')[stage];
			idsByKey.putAll(insertStep(step, idsByKey));
		}

		@NamespaceAccessible
		public void finish() {
			SampleDataModules.startAfter(find(resourceName).moduleName());
		}
	}

	/** Inserts one step's records and returns their keys mapped to the Ids they were given. */
	@TestVisible
	private static Map<String, Id> insertStep(Map<String, Object> step, Map<String, Id> idsByKey) {
		Map<String, Id> inserted = new Map<String, Id>();
		Schema.SObjectType type = NamespaceUtil.objectType((String) step.get('object'));
		if (type == null || !type.getDescribe().isCreateable()) {
			return inserted;
		}
		List<SObject> rows = new List<SObject>();
		List<String> keys = new List<String>();
		Date today = Date.today();
		for (Object entry : (List<Object>) step.get('records')) {
			SObject row = buildRow(type, (Map<String, Object>) entry, idsByKey, today);
			if (row != null) {
				rows.add(row);
				keys.add((String) ((Map<String, Object>) entry).get('key'));
			}
		}
		if (rows.isEmpty()) {
			return inserted;
		}
		Database.insert(rows, AccessLevel.USER_MODE);
		for (Integer index = 0; index < rows.size(); index++) {
			if (keys[index] != null) {
				inserted.put(keys[index], rows[index].Id);
			}
		}
		return inserted;
	}

	/** One record, or null when a link it needs does not resolve. */
	private static SObject buildRow(
		Schema.SObjectType type,
		Map<String, Object> record,
		Map<String, Id> idsByKey,
		Date today
	) {
		SObject row = type.newSObject();
		for (String name : record.keySet()) {
			Schema.SObjectField field = name == 'key' ? null : NamespaceUtil.field(type, name);
			if (field == null || !field.getDescribe().isCreateable()) {
				continue;
			}
			Object raw = record.get(name);
			Object value = raw instanceof Map<String, Object>
				? resolve(field.getDescribe(), (Map<String, Object>) raw, idsByKey, today)
				: literal(field.getDescribe(), raw);
			if (value instanceof Unresolved) {
				return null;
			}
			row.put(field, value);
		}
		return row;
	}

	/** Marks a link that did not resolve. */
	private class Unresolved {
	}

	private static Object resolve(
		Schema.DescribeFieldResult field,
		Map<String, Object> spec,
		Map<String, Id> idsByKey,
		Date today
	) {
		if (spec.containsKey('ref') || spec.containsKey('sample')) {
			Id found = spec.containsKey('ref')
				? idsByKey.get((String) spec.get('ref'))
				: sampleIds().get((String) spec.get('sample'));
			if (found == null && spec.get('optional') != true) {
				return new Unresolved();
			}
			return found;
		}
		if (spec.get('currentUser') == true) {
			return UserInfo.getUserId();
		}
		Time clock = timeOf((String) spec.get('time'));
		if (field.getType() == Schema.DisplayType.TIME) {
			return clock;
		}
		Date day = today.addDays(toInteger(spec.get('days')))
			.addMonths(toInteger(spec.get('months')));
		return field.getType() == Schema.DisplayType.DATETIME
			? (Object) Datetime.newInstance(
					day,
					clock == null ? Time.newInstance(0, 0, 0, 0) : clock
			  )
			: (Object) day;
	}

	/** A JSON number put in a number field as a Decimal, which every number field takes. */
	private static Object literal(Schema.DescribeFieldResult field, Object raw) {
		if (
			raw instanceof Integer ||
			raw instanceof Long ||
			raw instanceof Decimal ||
			raw instanceof Double
		) {
			Decimal value = Decimal.valueOf(String.valueOf(raw));
			if (field.getType() == Schema.DisplayType.INTEGER) {
				return value.intValue();
			}
			return value;
		}
		return raw;
	}

	private static Integer toInteger(Object value) {
		return value == null ? 0 : Integer.valueOf(value);
	}

	private static Time timeOf(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		List<String> parts = value.split(':');
		return Time.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 0, 0);
	}

	/** Core's sample people and accounts by key; a person wins over an account of the same key. */
	private static Map<String, Id> sampleIds() {
		if (sampleIdsByKey == null) {
			sampleIdsByKey = new Map<String, Id>();
			for (Account account : [
				SELECT Id, Sample_Data_Key__c
				FROM Account
				WHERE Sample_Data__c = TRUE AND Sample_Data_Key__c != NULL
				WITH USER_MODE
			]) {
				sampleIdsByKey.put(account.Sample_Data_Key__c, account.Id);
			}
			for (Contact person : [
				SELECT Id, Sample_Data_Key__c
				FROM Contact
				WHERE Sample_Data__c = TRUE AND Sample_Data_Key__c != NULL
				WITH USER_MODE
			]) {
				sampleIdsByKey.put(person.Sample_Data_Key__c, person.Id);
			}
		}
		return sampleIdsByKey;
	}

	// ------------------------------------------------------------------------- removal

	/** The removal, a chunk per stage. The Ids that refused a delete travel between stages. */
	@NamespaceAccessible
	public with sharing class RemoveStages implements SampleDataStages {
		private final String resourceName;
		private Map<Id, String> kept = new Map<Id, String>();

		@NamespaceAccessible
		public RemoveStages(String resourceName) {
			this.resourceName = resourceName;
		}

		@NamespaceAccessible
		public String name() {
			return resourceName + '.remove';
		}

		/** Each entry's chunks, counted once when the removal starts. */
		@NamespaceAccessible
		public Integer stageCount() {
			Integer stages = 0;
			for (Object entry : find(resourceName).listOf('remove')) {
				Integer rows = countOf((Map<String, Object>) entry, null);
				stages += (rows + removeChunkSize - 1) / removeChunkSize;
			}
			return stages;
		}

		/** Deletes the first entry's next chunk that has one; a refused row is kept. */
		@NamespaceAccessible
		public void runStage(Integer stage) {
			for (Object entry : find(resourceName).listOf('remove')) {
				List<Id> ids = idsOf((Map<String, Object>) entry, kept.keySet());
				if (ids.isEmpty()) {
					continue;
				}
				List<Database.DeleteResult> results = Database.delete(
					ids,
					false,
					AccessLevel.USER_MODE
				);
				for (Integer index = 0; index < results.size(); index++) {
					if (!results[index].isSuccess()) {
						kept.put(ids[index], (String) ((Map<String, Object>) entry).get('object'));
					}
				}
				return;
			}
		}

		@NamespaceAccessible
		public void finish() {
			SampleDataFile file = find(resourceName);
			logKept(file.moduleName(), kept);
			SampleDataModules.removeAfter(file.moduleName());
		}
	}

	/** One Warning naming each record removal kept, by kind; null when none was. */
	@TestVisible
	private static String logKept(String moduleName, Map<Id, String> kept) {
		if (kept.isEmpty()) {
			return null;
		}
		Map<String, Set<Id>> byObject = new Map<String, Set<Id>>();
		for (Id recordId : kept.keySet()) {
			String objectName = kept.get(recordId);
			if (!byObject.containsKey(objectName)) {
				byObject.put(objectName, new Set<Id>());
			}
			byObject.get(objectName).add(recordId);
		}
		List<String> parts = new List<String>();
		for (String objectName : byObject.keySet()) {
			Set<Id> ids = byObject.get(objectName);
			List<String> names = new List<String>();
			for (
				SObject row : Database.queryWithBinds(
					'SELECT Name FROM ' + objectName + ' WHERE Id IN :ids ORDER BY Name LIMIT 50',
					new Map<String, Object>{ 'ids' => ids },
					AccessLevel.USER_MODE
				)
			) {
				names.add((String) row.get('Name'));
			}
			parts.add(
				NamespaceUtil.describe(objectName).getLabelPlural() +
					' (' +
					String.join(names, ', ') +
					')'
			);
		}
		String message = String.format(
			BarnHelp.text('Core', 'Core_SampleData_Kept'),
			new List<Object>{ moduleName, String.join(parts, ', ') }
		);
		ErrorLogger.logMessage(message, 'SampleDataFile', ErrorLogger.SEVERITY_WARNING);
		return message;
	}

	/** How many rows an entry matches, at most `cap` when one is given; 0 when unreadable. */
	private static Integer countOf(Map<String, Object> entry, Integer cap) {
		if (entry == null || !readable(entry, false)) {
			return 0;
		}
		return Database.countQueryWithBinds(
			'SELECT COUNT() FROM ' +
				(String) entry.get('object') +
				' WHERE ' +
				(String) entry.get('where') +
				(cap == null ? '' : ' LIMIT ' + cap),
			new Map<String, Object>(),
			AccessLevel.USER_MODE
		);
	}

	/** The next chunk of an entry's rows, leaving out the ones already kept. */
	private static List<Id> idsOf(Map<String, Object> entry, Set<Id> kept) {
		List<Id> ids = new List<Id>();
		if (!readable(entry, true)) {
			return ids;
		}
		for (
			SObject row : Database.queryWithBinds(
				'SELECT Id FROM ' +
					(String) entry.get('object') +
					' WHERE (' +
					(String) entry.get('where') +
					') AND Id NOT IN :kept LIMIT :chunk',
				new Map<String, Object>{ 'kept' => kept, 'chunk' => removeChunkSize },
				AccessLevel.USER_MODE
			)
		) {
			ids.add(row.Id);
		}
		return ids;
	}

	/** Whether the object is in the org and the person can read it (and delete from it). */
	private static Boolean readable(Map<String, Object> entry, Boolean toDelete) {
		Schema.DescribeSObjectResult described = NamespaceUtil.describe(
			(String) entry.get('object')
		);
		return described != null &&
			described.isAccessible() &&
			(!toDelete || described.isDeletable());
	}
}
