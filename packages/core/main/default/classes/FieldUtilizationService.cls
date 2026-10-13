/**
 * Counts how many records hold a value in each field of one object, by record type (plan
 * Section 6.1 item 10, canonical model Section 29F, ADR-0086 field-utilization-ships-in-core,
 * ADR-0101 field-utilization-on-demand).
 *
 * Every query and write is in user mode (R-FU3): a count covers what the person on the page can
 * see. Object and field names come only from describe (R-FU1), so no text a person typed
 * reaches a query. A field is counted with one `COUNT(field)` query grouped by record type,
 * which the platform charges as one query row per group however large the object is (R-FU4).
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
        Schema.DisplayType.BOOLEAN,
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
        for (Schema.SObjectType type : Schema.getGlobalDescribe().values()) {
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
        Schema.DescribeSObjectResult described;
        try {
            described = Schema.describeSObjects(
                new List<String>{ objectName.trim() },
                SObjectDescribeOptions.DEFERRED
            )[0];
        } catch (System.InvalidParameterValueException unknown) {
            return null;
        }
        return isCountable(described) ? described : null;
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
                field.isNillable() &&
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
        if (!sampled) {
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

    private static Map<String, Integer> filledByRecordType(
        Schema.DescribeSObjectResult described,
        String fieldName
    ) {
        Boolean grouped = groupsByRecordType(described);
        String query = soql(
            (grouped ? 'RecordTypeId, ' : '') +
                'COUNT(' +
                String.escapeSingleQuotes(fieldName) +
                ') n',
            described,
            grouped ? ' GROUP BY RecordTypeId' : ''
        );
        Map<String, Integer> filled = new Map<String, Integer>();
        for (
            AggregateResult row : (List<AggregateResult>) Database.query(
                query,
                AccessLevel.USER_MODE
            )
        ) {
            Object recordTypeId = grouped ? row.get('RecordTypeId') : null;
            add(filled, recordTypeKey(described, recordTypeId), (Integer) row.get('n'));
        }
        return filled;
    }

    private static void sample(
        Schema.DescribeSObjectResult described,
        String fieldName,
        Map<String, Integer> looked,
        Map<String, Integer> filled
    ) {
        Boolean grouped = groupsByRecordType(described);
        Boolean ordered = described.fields.getMap().containsKey(MODIFIED_FIELD);
        String query = soql(
            (grouped ? 'RecordTypeId, ' : '') + String.escapeSingleQuotes(fieldName),
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
