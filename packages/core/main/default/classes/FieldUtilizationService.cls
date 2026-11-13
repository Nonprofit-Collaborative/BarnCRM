/**
 * Counts how many records hold a value in each field of one object, by record type (plan
 * Section 6.1 item 10, canonical model Section 29F, ADR-0086 field-utilization-ships-in-core,
 * ADR-0101 field-utilization-on-demand).
 *
 * Every query and write is in user mode (R-FU3): a count covers what the person on the page can
 * see. Object and field names come only from describe (R-FU1), so no text a person typed
 * reaches a query. A field is counted with one `COUNT(field)` query grouped by record type,
 * which the platform charges as one query row per group however large the object is (R-FU4).
 * Required and Default Value come from describe; At Default is one more `COUNT(Id)` query per
 * field with a literal or picklist default, grouped the same way (R-FU13, R-FU14).
 */
public with sharing class FieldUtilizationService {
	/** How many recent records a field that cannot be counted is sampled on (R-FU4). */
	public static final Integer SAMPLE_SIZE = 200;

	/** Fields one count call may ask for: one query each, plus a sample when refused (R-FU7). */
	public static final Integer CHUNK_SIZE = 40;

	/** Fields per call on an object above LARGE_OBJECT_ROWS, so one call stays short (R-FU7). */
	public static final Integer LARGE_CHUNK_SIZE = 10;

	/** Above this many records an object is counted in the smaller chunks. */
	public static final Integer LARGE_OBJECT_ROWS = 100000;

	/** An object holding more records than this is not counted (R-FU5). */
	@TestVisible
	private static Integer sizeLimit = 1000000;

	/** The record type key for records with none, and for objects without record types. */
	public static final String NO_RECORD_TYPE = '';

	private static final String RECORD_TYPE_FIELD = 'recordtypeid';
	private static final String MODIFIED_FIELD = 'lastmodifieddate';
	private static final Set<Schema.DisplayType> NEVER_COUNTED = new Set<Schema.DisplayType>{
		Schema.DisplayType.ADDRESS,
		Schema.DisplayType.LOCATION,
		Schema.DisplayType.ID
	};

	/** The record limit above which an object is not counted (R-FU5). */
	public static Integer largeObjectLimit() {
		return sizeLimit;
	}

	/** Every object the person may count, by the rule Find offers objects by (R-FU1). */
	public static List<Schema.DescribeSObjectResult> offeredObjects() {
		List<Schema.DescribeSObjectResult> offered = new List<Schema.DescribeSObjectResult>();
		for (Schema.SObjectType type : NamespaceUtil.globalDescribe().values()) {
			Schema.DescribeSObjectResult described = type.getDescribe(
				SObjectDescribeOptions.DEFERRED
			);
			if (isCountable(described)) {
				offered.add(described);
			}
		}
		return offered;
	}

	/** The describe of an object the person may count, or null when there is no such object. */
	public static Schema.DescribeSObjectResult countable(String objectName) {
		if (String.isBlank(objectName)) {
			return null;
		}
		Schema.DescribeSObjectResult described = NamespaceUtil.describe(objectName);
		return described != null && isCountable(described) ? described : null;
	}

	/** The fields a person can fill in and the runner can read, by API name (R-FU2). */
	public static List<Schema.DescribeFieldResult> countableFields(
		Schema.DescribeSObjectResult described
	) {
		Map<String, Schema.SObjectField> byName = described.fields.getMap();
		List<String> names = new List<String>(byName.keySet());
		names.sort();
		List<Schema.DescribeFieldResult> fields = new List<Schema.DescribeFieldResult>();
		for (String name : names) {
			Schema.DescribeFieldResult field = byName.get(name).getDescribe();
			Boolean fillable = field.isCreateable() || field.isUpdateable();
			if (
				field.isAccessible() &&
				fillable &&
				!field.isCalculated() &&
				!field.isAutoNumber() &&
				!NEVER_COUNTED.contains(field.getType())
			) {
				fields.add(field);
			}
		}
		return fields;
	}

	/** The countable fields keyed by API name, for checking names a page sent back. */
	public static Map<String, Schema.DescribeFieldResult> countableFieldsByName(
		Schema.DescribeSObjectResult described
	) {
		Map<String, Schema.DescribeFieldResult> byName = new Map<String, Schema.DescribeFieldResult>();
		for (Schema.DescribeFieldResult field : countableFields(described)) {
			byName.put(field.getName(), field);
		}
		return byName;
	}

	/** The object's record count by record type key, in user mode: one query. */
	public static Map<String, Integer> totalsByRecordType(Schema.DescribeSObjectResult described) {
		Map<String, Integer> totals = new Map<String, Integer>();
		if (!groupsByRecordType(described)) {
			totals.put(
				NO_RECORD_TYPE,
				Database.countQuery(soql('COUNT()', described, ''), AccessLevel.USER_MODE)
			);
			return totals;
		}
		String query = soql('RecordTypeId, COUNT(Id) n', described, ' GROUP BY RecordTypeId');
		for (
			AggregateResult row : (List<AggregateResult>) Database.query(
				query,
				AccessLevel.USER_MODE
			)
		) {
			add(totals, recordTypeKey(described, row.get('RecordTypeId')), (Integer) row.get('n'));
		}
		return totals;
	}

	/** The sum of a totals map. */
	public static Integer sum(Map<String, Integer> totals) {
		Integer all = 0;
		for (Integer count : totals.values()) {
			all += count == null ? 0 : count;
		}
		return all;
	}

	/**
	 * Counts one field and returns one unsaved snapshot per record type that has records
	 * (R-FU6). A field that cannot be filtered, or whose count is refused, is sampled (R-FU4).
	 * A checkbox is never empty, so it is filled on every record and needs no query (R-FU2).
	 */
	public static List<Field_Utilization_Snapshot__c> count(
		Schema.DescribeSObjectResult described,
		Schema.DescribeFieldResult field,
		Map<String, Integer> totals
	) {
		String fieldName = field.getName();
		Map<String, Integer> looked = totals;
		Map<String, Integer> filled;
		Boolean sampled = !field.isFilterable();
		if (field.getType() == Schema.DisplayType.BOOLEAN) {
			sampled = false;
			filled = totals;
		} else if (!sampled) {
			try {
				filled = filledByRecordType(described, fieldName);
			} catch (System.QueryException refused) {
				sampled = true;
			}
		}
		if (sampled) {
			looked = new Map<String, Integer>();
			filled = new Map<String, Integer>();
			sample(described, fieldName, looked, filled);
		}
		List<Field_Utilization_Snapshot__c> rows = new List<Field_Utilization_Snapshot__c>();
		for (String recordType : looked.keySet()) {
			Integer recordCount = looked.get(recordType);
			if (recordCount == null || recordCount == 0) {
				continue;
			}
			Integer filledCount = filled.containsKey(recordType) ? filled.get(recordType) : 0;
			rows.add(
				snapshot(described.getName(), field, recordType, filledCount, recordCount, sampled)
			);
		}
		return rows;
	}

	/** One unsaved snapshot; the filled count is kept within the record count (R-FU7). */
	public static Field_Utilization_Snapshot__c snapshot(
		String objectName,
		Schema.DescribeFieldResult field,
		String recordType,
		Integer filledCount,
		Integer recordCount,
		Boolean sampled
	) {
		Integer total = Math.max(recordCount == null ? 0 : recordCount, 0);
		Integer filled = Math.max(filledCount == null ? 0 : filledCount, 0);
		return new Field_Utilization_Snapshot__c(
			Object_Name__c = objectName,
			Field_Name__c = field.getName(),
			Field_Label__c = field.getLabel().left(255),
			Record_Type__c = String.isBlank(recordType) ? null : recordType,
			// Records can change between the totals and the count; never above 100%.
			Filled_Count__c = Math.min(filled, total),
			Record_Count__c = total,
			Sampled__c = sampled == true
		);
	}

	/** Saves snapshots with one Taken At, in user mode (R-FU7). */
	public static void save(List<Field_Utilization_Snapshot__c> rows, Datetime takenAt) {
		if (rows == null || rows.isEmpty()) {
			return;
		}
		for (Field_Utilization_Snapshot__c row : rows) {
			row.Taken_At__c = takenAt;
		}
		Database.insert(rows, AccessLevel.USER_MODE);
	}

	/** True when the object has record types the runner can group by. */
	public static Boolean groupsByRecordType(Schema.DescribeSObjectResult described) {
		Schema.SObjectField recordType = described.fields.getMap().get(RECORD_TYPE_FIELD);
		return recordType != null && recordType.getDescribe().isAccessible();
	}

	/** The developer name of a record type Id, or the no record type key. */
	public static String recordTypeKey(
		Schema.DescribeSObjectResult described,
		Object recordTypeId
	) {
		if (recordTypeId == null) {
			return NO_RECORD_TYPE;
		}
		Schema.RecordTypeInfo info = described.getRecordTypeInfosById().get((Id) recordTypeId);
		return info == null || info.isMaster() ? NO_RECORD_TYPE : info.getDeveloperName();
	}

	private static Boolean isCountable(Schema.DescribeSObjectResult described) {
		return FindController.isOffered(described) &&
			described.getSObjectType() != Field_Utilization_Snapshot__c.SObjectType;
	}

	/**
	 * True when describe marks the field required: a person creating a record must fill it, so
	 * it can be created and holds no default and no empty value. A checkbox is never empty but
	 * is defaulted, so it is never required. Page layouts and validation rules are not read
	 * (R-FU13).
	 */
	public static Boolean isRequired(Schema.DescribeFieldResult field) {
		return field.isCreateable() && !field.isNillable() && !field.isDefaultedOnCreate();
	}

	/** A field's default value as describe gives it (R-FU13). */
	public class FieldDefault {
		/** The literal or picklist value to show; null when the default is a formula. */
		public String shown;
		/** The default formula's text, when it is not a simple literal. */
		public String formula;
		/** The value records are compared with for At Default; null when not comparable. */
		public Object value;
	}

	/** The field's default value, or null when it has none (R-FU13). */
	public static FieldDefault defaultOf(Schema.DescribeFieldResult field) {
		String picklistDefault;
		if (field.getType() == Schema.DisplayType.PICKLIST) {
			for (Schema.PicklistEntry entry : field.getPicklistValues()) {
				if (entry.isActive() && entry.isDefaultValue()) {
					picklistDefault = entry.getValue();
					break;
				}
			}
		}
		return defaultOf(
			field.getType(),
			field.getDefaultValue(),
			field.getDefaultValueFormula(),
			picklistDefault,
			field.isFilterable() && !field.isEncrypted()
		);
	}

	/**
	 * The default from describe's parts. A default formula that is only a quoted text (on a
	 * text field) or only a number (on a number field) is a literal; any other formula is shown
	 * as a formula and has no At Default. A value is compared only on a filterable field of a
	 * kind COMPARABLE lists.
	 */
	@TestVisible
	private static FieldDefault defaultOf(
		Schema.DisplayType type,
		Object literal,
		String formula,
		String picklistDefault,
		Boolean filterable
	) {
		FieldDefault found = new FieldDefault();
		String text = formula == null ? '' : formula.trim();
		if (picklistDefault != null) {
			found.value = picklistDefault;
		} else if (type == Schema.DisplayType.BOOLEAN) {
			found.value = literal instanceof Boolean
				? (Boolean) literal
				: 'true'.equalsIgnoreCase(text);
		} else if (literal != null) {
			found.value = NUMBERS.contains(type)
				? (Object) Decimal.valueOf(String.valueOf(literal))
				: String.valueOf(literal);
		} else if (TEXTS.contains(type) && QUOTED.matcher(text).matches()) {
			found.value = text.substring(1, text.length() - 1);
		} else if (NUMBERS.contains(type) && PLAIN_NUMBER.matcher(text).matches()) {
			found.value = Decimal.valueOf(text);
		} else if (String.isNotBlank(text)) {
			found.formula = text;
			return found;
		}
		if (found.value == null || String.isBlank(String.valueOf(found.value))) {
			return null;
		}
		found.shown = String.valueOf(found.value);
		if (found.value instanceof Boolean) {
			found.shown = (Boolean) found.value
				? System.Label.Core_BulkUpdate_True
				: System.Label.Core_BulkUpdate_False;
		}
		if (!filterable || !(COMPARABLE.contains(type) || picklistDefault != null)) {
			found.value = null;
		}
		return found;
	}

	/**
	 * Records holding the field's default, by record type key (R-FU14): one `COUNT(Id)` query
	 * in user mode, grouped like the filled count, the default passed as a bind. Null when the
	 * default cannot be compared, or the call has no query left for it.
	 */
	public static Map<String, Integer> atDefaultByRecordType(
		Schema.DescribeSObjectResult described,
		Schema.DescribeFieldResult field,
		FieldDefault fieldDefault
	) {
		if (
			fieldDefault == null ||
			fieldDefault.value == null ||
			Limits.getQueries() >= Limits.getLimitQueries() - 1
		) {
			return null;
		}
		return countByRecordType(
			described,
			'Id',
			' WHERE ' + String.escapeSingleQuotes(field.getName()) + ' = :atDefault',
			new Map<String, Object>{ 'atDefault' => fieldDefault.value }
		);
	}

	private static final Set<Schema.DisplayType> TEXTS = new Set<Schema.DisplayType>{
		Schema.DisplayType.STRING,
		Schema.DisplayType.TEXTAREA,
		Schema.DisplayType.EMAIL,
		Schema.DisplayType.PHONE,
		Schema.DisplayType.URL,
		Schema.DisplayType.COMBOBOX,
		Schema.DisplayType.PICKLIST
	};
	private static final Set<Schema.DisplayType> NUMBERS = new Set<Schema.DisplayType>{
		Schema.DisplayType.DOUBLE,
		Schema.DisplayType.CURRENCY,
		Schema.DisplayType.PERCENT,
		Schema.DisplayType.INTEGER,
		Schema.DisplayType.LONG
	};
	/** Kinds whose default records are compared with; percent is left out (its scale varies). */
	private static final Set<Schema.DisplayType> COMPARABLE = new Set<Schema.DisplayType>{
		Schema.DisplayType.STRING,
		Schema.DisplayType.TEXTAREA,
		Schema.DisplayType.EMAIL,
		Schema.DisplayType.PHONE,
		Schema.DisplayType.URL,
		Schema.DisplayType.COMBOBOX,
		Schema.DisplayType.PICKLIST,
		Schema.DisplayType.DOUBLE,
		Schema.DisplayType.CURRENCY,
		Schema.DisplayType.INTEGER,
		Schema.DisplayType.LONG,
		Schema.DisplayType.BOOLEAN
	};
	private static final Pattern QUOTED = Pattern.compile('^"[^"\\\\]*"$|^\'[^\'\\\\]*\'$');
	private static final Pattern PLAIN_NUMBER = Pattern.compile('^-?\\d+(\\.\\d+)?$');

	private static Map<String, Integer> filledByRecordType(
		Schema.DescribeSObjectResult described,
		String fieldName
	) {
		return countByRecordType(
			described,
			String.escapeSingleQuotes(fieldName),
			'',
			new Map<String, Object>()
		);
	}

	/** One `COUNT(countOf)` query grouped by record type, in user mode, keyed like the totals. */
	private static Map<String, Integer> countByRecordType(
		Schema.DescribeSObjectResult described,
		String countOf,
		String whereClause,
		Map<String, Object> binds
	) {
		Boolean grouped = groupsByRecordType(described);
		String query = soql(
			(grouped ? 'RecordTypeId, ' : '') + 'COUNT(' + countOf + ') n',
			described,
			whereClause + (grouped ? ' GROUP BY RecordTypeId' : '')
		);
		Map<String, Integer> counted = new Map<String, Integer>();
		for (
			AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
				query,
				binds,
				AccessLevel.USER_MODE
			)
		) {
			Object recordTypeId = grouped ? row.get('RecordTypeId') : null;
			add(counted, recordTypeKey(described, recordTypeId), (Integer) row.get('n'));
		}
		return counted;
	}

	private static void sample(
		Schema.DescribeSObjectResult described,
		String fieldName,
		Map<String, Integer> looked,
		Map<String, Integer> filled
	) {
		Boolean grouped = groupsByRecordType(described);
		Boolean ordered = described.fields.getMap().containsKey(MODIFIED_FIELD);
		// The sampled field can itself be RecordTypeId, and a select list may not name a field
		// twice (in any case), so the record type is added only when it is not already there.
		Boolean sampledIsRecordType = 'RecordTypeId'.equalsIgnoreCase(fieldName);
		String query = soql(
			(grouped && !sampledIsRecordType ? 'RecordTypeId, ' : '') +
			String.escapeSingleQuotes(fieldName),
			described,
			(ordered ? ' ORDER BY LastModifiedDate DESC' : '') + ' LIMIT ' + SAMPLE_SIZE
		);
		for (SObject record : Database.query(query, AccessLevel.USER_MODE)) {
			String key = recordTypeKey(described, grouped ? record.get('RecordTypeId') : null);
			add(looked, key, 1);
			Object value = record.get(fieldName);
			if (value != null && !(value instanceof String && String.isBlank((String) value))) {
				add(filled, key, 1);
			}
		}
	}

	/**
	 * One query's text. The object name and every field name in it come from describe (R-FU1)
	 * and are escaped anyway; the rest is literal. Run in user mode by every caller.
	 */
	private static String soql(
		String selectList,
		Schema.DescribeSObjectResult described,
		String tail
	) {
		return 'SELECT ' +
			selectList +
			' FROM ' +
			String.escapeSingleQuotes(described.getName()) +
			tail;
	}

	private static void add(Map<String, Integer> counts, String key, Integer amount) {
		Integer current = counts.containsKey(key) ? counts.get(key) : 0;
		counts.put(key, current + (amount == null ? 0 : amount));
	}
}
