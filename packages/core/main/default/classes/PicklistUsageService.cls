/**
 * Picklist value usage for the Field Utilization section of Org Optimizer (plan 6.1.5 research
 * item C-57, canonical model Section 29F, rules R-FU9 to R-FU12).
 *
 * For one single-select picklist field, one aggregate query groups the object's records by the
 * field's value and returns the record count per value. COUNT grouped by a field is charged one
 * query row per group however many records it counts, so the count works on any object up to
 * the R-FU5 size limit. MAX is charged one query row per record it reads, so the newest
 * LastModifiedDate of the records holding each value (CreatedDate on an object with no
 * LastModifiedDate) is read in the same query only while the object is small enough; otherwise
 * it is read by lastUsed, a chunk of records at a time in Id order, one call per chunk (R-FU12).
 * The values come from describe, so a value nobody uses shows as Never Used, and a value found
 * in the data that is not an active value shows as Inactive. Every query runs in user mode, so a
 * count covers what the person on the page can see; object and field names come only from
 * describe.
 */
public with sharing class PicklistUsageService {
	/** Fields one usage call may ask for: one aggregate query each. */
	public static final Integer CHUNK_SIZE = 20;

	/** The most distinct values in the data one field returns; more are cut and marked. */
	public static final Integer MAX_VALUES = 500;

	/**
	 * The most query rows one usage call spends on reading dates with MAX, which is charged one
	 * row per record read; a field whose dates would go over is left for lastUsed (R-FU12).
	 */
	@TestVisible
	private static Integer dateRowBudget = 40000;

	/** The most records one lastUsed call reads: well under the 50,000 query-row limit. */
	@TestVisible
	private static Integer maxScanRows = 20000;

	/** Records times fields one lastUsed call handles, which keeps its CPU time and heap low. */
	public static final Integer SCAN_FIELD_VALUES = 100000;

	/** The most distinct values per field one lastUsed call keeps; more mark the field cut. */
	public static final Integer MAX_SCAN_VALUES = 1000;

	public static final String ACTIVE = 'Active';
	public static final String INACTIVE = 'Inactive';
	public static final String NEVER_USED = 'NeverUsed';
	public static final String NO_VALUE = 'NoValue';

	/** One value of a picklist: how many records hold it and when they were last changed. */
	public class Usage {
		public String value;
		public String valueLabel;
		public String status;
		public Integer records;
		public Datetime lastUsed;
	}

	/** One field's values, and whether the values found in the data were cut at MAX_VALUES. */
	public class FieldResult {
		public List<Usage> values = new List<Usage>();
		public Boolean truncated = false;
	}

	/** The single-select picklist fields the person can read and group by, by label. */
	public static List<Schema.DescribeFieldResult> picklistFields(
		Schema.DescribeSObjectResult described
	) {
		List<Schema.DescribeFieldResult> fields = new List<Schema.DescribeFieldResult>();
		for (Schema.SObjectField token : described.fields.getMap().values()) {
			Schema.DescribeFieldResult field = token.getDescribe();
			if (
				field.getType() == Schema.DisplayType.PICKLIST &&
				field.isAccessible() &&
				field.isGroupable()
			) {
				fields.add(field);
			}
		}
		fields.sort(new FieldOrder());
		return fields;
	}

	/** The picklist fields keyed by API name, for checking names a page sent back. */
	public static Map<String, Schema.DescribeFieldResult> picklistFieldsByName(
		Schema.DescribeSObjectResult described
	) {
		Map<String, Schema.DescribeFieldResult> byName = new Map<String, Schema.DescribeFieldResult>();
		for (Schema.DescribeFieldResult field : picklistFields(described)) {
			byName.put(field.getName(), field);
		}
		return byName;
	}

	/** The object's record count, in user mode: one query. */
	public static Integer total(Schema.DescribeSObjectResult described) {
		return Database.countQuery(
			'SELECT COUNT() FROM ' + String.escapeSingleQuotes(described.getName()),
			AccessLevel.USER_MODE
		);
	}

	/** The date Last Used is read from: LastModifiedDate, else CreatedDate, else none. */
	public static String dateField(Schema.DescribeSObjectResult described) {
		Map<String, Schema.SObjectField> known = described.fields.getMap();
		return known.containsKey('lastmodifieddate')
			? 'LastModifiedDate'
			: (known.containsKey('createddate') ? 'CreatedDate' : null);
	}

	/** How many records one lastUsed call reads for this many fields (R-FU12). */
	public static Integer scanRows(Integer fieldCount) {
		Integer fields = fieldCount == null || fieldCount < 1 ? 1 : fieldCount;
		return Math.min(maxScanRows, Math.max(1000, SCAN_FIELD_VALUES / fields));
	}

	/**
	 * True when one more usage query may read dates with MAX over total records in this call:
	 * MAX is charged one query row per record, COUNT one per value (R-FU12).
	 */
	public static Boolean datesFit(Integer total) {
		return Limits.getQueryRows() + (total == null ? 0 : total) + MAX_VALUES + 1 <=
			dateRowBudget;
	}

	/** One chunk of Last Used dates: the newest date per field and value in the records read. */
	public class ScanResult {
		/** Field API name to value ('' for no value) to the newest date among the records read. */
		public Map<String, Map<String, Datetime>> lastUsed = new Map<String, Map<String, Datetime>>();
		/** Fields with more than MAX_SCAN_VALUES distinct values in the records read. */
		public Set<String> cut = new Set<String>();
		/** The Id of the last record read: the next chunk starts after it. */
		public Id lastId;
		/** How many records this chunk read. */
		public Integer read = 0;
		/** True when this chunk reached the end of the records. */
		public Boolean done = false;
	}

	/**
	 * Reads one chunk of records in Id order, after afterId (from the start when null), and
	 * keeps the newest date per value of each field (R-FU12). One query in user mode, at most
	 * scanRows records, so one call stays well under the query-row limit on any object size.
	 */
	public static ScanResult lastUsed(
		Schema.DescribeSObjectResult described,
		List<Schema.DescribeFieldResult> fields,
		Id afterId
	) {
		ScanResult result = new ScanResult();
		String dateField = dateField(described);
		if (dateField == null || fields == null || fields.isEmpty()) {
			result.done = true;
			return result;
		}
		Integer rows = scanRows(fields.size());
		List<String> names = new List<String>();
		for (Schema.DescribeFieldResult field : fields) {
			names.add(String.escapeSingleQuotes(field.getName()));
			result.lastUsed.put(field.getName(), new Map<String, Datetime>());
		}
		String query =
			'SELECT Id, ' +
			String.escapeSingleQuotes(dateField) +
			', ' +
			String.join(names, ', ') +
			' FROM ' +
			String.escapeSingleQuotes(described.getName()) +
			(afterId == null ? '' : ' WHERE Id > :afterId') +
			' ORDER BY Id LIMIT ' +
			rows;
		for (
			SObject record : Database.queryWithBinds(
				query,
				new Map<String, Object>{ 'afterId' => afterId },
				AccessLevel.USER_MODE
			)
		) {
			result.read++;
			result.lastId = record.Id;
			Datetime stamp = (Datetime) record.get(dateField);
			for (Schema.DescribeFieldResult field : fields) {
				String fieldName = field.getName();
				Object held = record.get(fieldName);
				String value = held == null ? '' : (String) held;
				Map<String, Datetime> newest = result.lastUsed.get(fieldName);
				if (!newest.containsKey(value)) {
					if (newest.size() >= MAX_SCAN_VALUES) {
						result.cut.add(fieldName);
					} else {
						newest.put(value, stamp);
					}
					continue;
				}
				Datetime known = newest.get(value);
				if (stamp != null && (known == null || stamp > known)) {
					newest.put(value, stamp);
				}
			}
		}
		result.done = result.read < rows;
		return result;
	}

	/** The aggregate query behind usage: every name is escaped, the row cap is a constant. */
	private static String usageQuery(
		Schema.DescribeSObjectResult described,
		String fieldName,
		String dateField
	) {
		return 'SELECT ' +
			String.escapeSingleQuotes(fieldName) +
			' v, COUNT(Id) n' +
			(dateField == null
				? ''
				: ', MAX(' + String.escapeSingleQuotes(dateField) + ') lastUsed') +
			' FROM ' +
			String.escapeSingleQuotes(described.getName()) +
			' GROUP BY ' +
			String.escapeSingleQuotes(fieldName) +
			' ORDER BY COUNT(Id) DESC LIMIT ' +
			(MAX_VALUES + 1);
	}

	/**
	 * Groups one field's records by value: one aggregate query in user mode (R-FU9). With
	 * withDates false the query holds only COUNT, charged one query row per value; with it true
	 * it also reads the newest date per value, charged one query row per record (R-FU12).
	 */
	public static FieldResult usage(
		Schema.DescribeSObjectResult described,
		Schema.DescribeFieldResult field,
		Boolean withDates
	) {
		String dateField = withDates == true ? dateField(described) : null;
		Map<String, Usage> observed = new Map<String, Usage>();
		for (
			AggregateResult row : (List<AggregateResult>) Database.query(
				usageQuery(described, field.getName(), dateField),
				AccessLevel.USER_MODE
			)
		) {
			Usage seen = new Usage();
			seen.value = (String) row.get('v');
			seen.records = (Integer) row.get('n');
			seen.lastUsed = dateField == null ? null : (Datetime) row.get('lastUsed');
			observed.put(seen.value == null ? '' : seen.value, seen);
		}
		Map<String, String> activeLabels = new Map<String, String>();
		for (Schema.PicklistEntry entry : field.getPicklistValues()) {
			if (entry.isActive()) {
				activeLabels.put(entry.getValue(), entry.getLabel());
			}
		}
		return combine(activeLabels, observed);
	}

	/**
	 * Joins the active values (value to label) with the values found in the data (R-FU10): a
	 * value in the data that is not active is Inactive, an active value in no record is Never
	 * Used, and records with no value are listed once as No Value. Values found in the data come
	 * first, most used first; the never used values follow, by label.
	 */
	@TestVisible
	private static FieldResult combine(
		Map<String, String> activeLabels,
		Map<String, Usage> observed
	) {
		FieldResult result = new FieldResult();
		List<Usage> found = new List<Usage>();
		for (String value : observed.keySet()) {
			Usage seen = observed.get(value);
			seen.value = value;
			if (value == '') {
				seen.valueLabel = '';
				seen.status = NO_VALUE;
			} else if (activeLabels.containsKey(value)) {
				seen.valueLabel = activeLabels.get(value);
				seen.status = ACTIVE;
			} else {
				seen.valueLabel = value;
				seen.status = INACTIVE;
			}
			found.add(seen);
		}
		found.sort(new MostUsedFirst());
		if (found.size() > MAX_VALUES) {
			result.truncated = true;
			while (found.size() > MAX_VALUES) {
				found.remove(found.size() - 1);
			}
		}
		result.values.addAll(found);
		List<Usage> unused = new List<Usage>();
		for (String value : activeLabels.keySet()) {
			if (!observed.containsKey(value)) {
				Usage never = new Usage();
				never.value = value;
				never.valueLabel = activeLabels.get(value);
				never.status = NEVER_USED;
				never.records = 0;
				unused.add(never);
			}
		}
		unused.sort(new MostUsedFirst());
		result.values.addAll(unused);
		return result;
	}

	private class MostUsedFirst implements System.Comparator<Usage> {
		public Integer compare(Usage a, Usage b) {
			if (a.records != b.records) {
				return a.records > b.records ? -1 : 1;
			}
			return a.valueLabel.toLowerCase().compareTo(b.valueLabel.toLowerCase());
		}
	}

	private class FieldOrder implements System.Comparator<Schema.DescribeFieldResult> {
		public Integer compare(Schema.DescribeFieldResult a, Schema.DescribeFieldResult b) {
			Integer byLabel = a.getLabel().toLowerCase().compareTo(b.getLabel().toLowerCase());
			return byLabel != 0 ? byLabel : a.getName().compareTo(b.getName());
		}
	}
}
