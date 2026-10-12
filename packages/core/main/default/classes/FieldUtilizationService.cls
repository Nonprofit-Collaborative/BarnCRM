/**
 * Counts how many records hold a value in each field, per object and record type (plan
 * Section 6.1 item 10, canonical model Section 29D, ADR-NEXT field-utilization-ships-in-core).
 *
 * Every query and write is in user mode (R-FU3): a run counts what its runner can see. Object
 * and field names come only from describe (R-FU1), so no text a person typed reaches a query.
 * A field is counted with one `COUNT(field)` query grouped by record type, which the platform
 * charges as one query row per group however large the object is (R-FU4).
 */
public with sharing class FieldUtilizationService {
    /** How many recent records a field that cannot be counted is sampled on (R-FU4). */
    public static final Integer SAMPLE_SIZE = 200;

    /** How many months of snapshots are kept (R-FU7). */
    public static final Integer RETENTION_MONTHS = 13;

    /** An object holding more records than this is skipped (R-FU5). */
    @TestVisible
    private static Integer largeObjectRows = 1000000;

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

    /** One field of one object to count: one batch item. */
    public class Item {
        public String objectName;
        public String fieldName;
        public String fieldLabel;
        public Boolean sample;
    }

    /** What a run will count, read once at its start. */
    public class Plan {
        public List<Item> items = new List<Item>();
        /** Object name to record type developer name to record count. */
        public Map<String, Map<String, Integer>> totals = new Map<String, Map<String, Integer>>();
        /** Labels of objects skipped as too large. */
        public List<String> skipped = new List<String>();
    }

    /** The saved objects that can still be counted, as describe names them. */
    public static List<String> trackedObjects() {
        String saved = SettingsService.getSettings().Field_Utilization_Objects__c;
        List<String> names = new List<String>();
        if (String.isBlank(saved)) {
            return names;
        }
        for (String name : saved.split(',')) {
            Schema.DescribeSObjectResult described = countable(name);
            if (described != null) {
                names.add(described.getName());
            }
        }
        return names;
    }

    /** The describe of an object the runner may count, or null when there is no such object. */
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
        Boolean usable =
            described.isQueryable() &&
            described.isAccessible() &&
            !described.isCustomSetting() &&
            described.getSObjectType() != Field_Utilization_Snapshot__c.SObjectType;
        return usable ? described : null;
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

    /**
     * Reads each object's record count by record type and lists the fields to count. An object
     * with no records adds no item; one over the size limit is skipped by label (R-FU5).
     */
    public static Plan plan(List<String> objectNames, Set<String> onlyFields) {
        Plan planned = new Plan();
        for (String objectName : objectNames) {
            Schema.DescribeSObjectResult described = countable(objectName);
            if (described == null) {
                continue;
            }
            Map<String, Integer> totals = totalsByRecordType(described);
            Integer all = 0;
            for (Integer count : totals.values()) {
                all += count;
            }
            if (all > largeObjectRows) {
                planned.skipped.add(described.getLabel());
                continue;
            }
            if (all == 0) {
                continue;
            }
            planned.totals.put(described.getName(), totals);
            for (Schema.DescribeFieldResult field : countableFields(described)) {
                if (onlyFields != null && !onlyFields.contains(field.getName())) {
                    continue;
                }
                Item item = new Item();
                item.objectName = described.getName();
                item.fieldName = field.getName();
                item.fieldLabel = field.getLabel();
                item.sample = !field.isFilterable();
                planned.items.add(item);
            }
        }
        return planned;
    }

    /**
     * Counts one field and returns one unsaved snapshot per record type that has records
     * (R-FU6). A count the platform refuses falls back to the sample (R-FU4).
     */
    public static List<Field_Utilization_Snapshot__c> count(
        Item item,
        Map<String, Integer> totals,
        Datetime takenAt
    ) {
        Schema.DescribeSObjectResult described = countable(item.objectName);
        List<Field_Utilization_Snapshot__c> rows = new List<Field_Utilization_Snapshot__c>();
        if (described == null || totals == null) {
            return rows;
        }
        Map<String, Integer> looked = totals;
        Map<String, Integer> filled;
        Boolean sampled = item.sample == true;
        if (!sampled) {
            try {
                filled = filledByRecordType(described, item.fieldName);
            } catch (System.QueryException refused) {
                sampled = true;
            }
        }
        if (sampled) {
            looked = new Map<String, Integer>();
            filled = new Map<String, Integer>();
            sample(described, item.fieldName, looked, filled);
        }
        for (String recordType : looked.keySet()) {
            Integer recordCount = looked.get(recordType);
            if (recordCount == null || recordCount == 0) {
                continue;
            }
            Integer filledCount = filled.containsKey(recordType) ? filled.get(recordType) : 0;
            rows.add(
                new Field_Utilization_Snapshot__c(
                    Object_Name__c = item.objectName,
                    Field_Name__c = item.fieldName,
                    Field_Label__c = item.fieldLabel == null ? null : item.fieldLabel.left(255),
                    Record_Type__c = String.isBlank(recordType) ? null : recordType,
                    // Records can change between the plan and the count; never above 100%.
                    Filled_Count__c = Math.min(filledCount, recordCount),
                    Record_Count__c = recordCount,
                    Sampled__c = sampled,
                    Taken_At__c = takenAt
                )
            );
        }
        return rows;
    }

    /** Saves one chunk's snapshots, in user mode. */
    public static void save(List<Field_Utilization_Snapshot__c> rows) {
        if (rows != null && !rows.isEmpty()) {
            Database.insert(rows, AccessLevel.USER_MODE);
        }
    }

    /** Deletes snapshots past the retention period, in user mode (R-FU7). */
    public static Integer purgeOld(Datetime now) {
        List<Field_Utilization_Snapshot__c> old = FieldUtilizationSelector.takenBefore(
            now.addMonths(-RETENTION_MONTHS)
        );
        if (!old.isEmpty()) {
            Database.delete(old, AccessLevel.USER_MODE);
        }
        return old.size();
    }

    /** The one sentence a run leaves behind (R-FU8). */
    public static String summary(
        Integer fields,
        Integer objects,
        Integer failed,
        List<String> skipped
    ) {
        String text = String.format(
            System.Label.Core_FieldUtilization_RunSummary,
            new List<Object>{ fields, objects, failed }
        );
        if (skipped != null && !skipped.isEmpty()) {
            text +=
                ' ' +
                String.format(
                    System.Label.Core_FieldUtilization_RunSkipped,
                    new List<Object>{ String.join(skipped, ', ') }
                );
        }
        return text.abbreviate(255);
    }

    /** Records when a run finished and what it did, on the org settings (R-FU8). */
    public static void recordRun(Datetime finishedAt, String summaryText) {
        OrgSettingsSystemWriter.save(
            new Map<Schema.SObjectField, Object>{
                BarnCRM_Settings__c.Field_Utilization_Last_Run__c => finishedAt,
                BarnCRM_Settings__c.Field_Utilization_Last_Run_Summary__c => summaryText
            }
        );
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

    private static Map<String, Integer> totalsByRecordType(Schema.DescribeSObjectResult described) {
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
