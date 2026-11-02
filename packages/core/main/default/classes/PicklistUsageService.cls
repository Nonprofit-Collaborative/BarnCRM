/**
 * Picklist value usage for the Field Utilization section of Org Optimizer (plan 6.1.5 research
 * item C-57, canonical model Section 29F, rules R-FU9 to R-FU11).
 *
 * For one single-select picklist field, one aggregate query groups the object's records by the
 * field's value and returns the record count and the newest LastModifiedDate of the records
 * that hold each value (CreatedDate on an object with no LastModifiedDate). The values come
 * from describe, so a value nobody uses shows as Never Used, and a value found in the data that
 * is not an active value shows as Inactive. Every query runs in user mode, so a count covers
 * what the person on the page can see; object and field names come only from describe.
 */
public with sharing class PicklistUsageService {
    /** Fields one usage call may ask for: one aggregate query each. */
    public static final Integer CHUNK_SIZE = 20;

    /** The most distinct values in the data one field returns; more are cut and marked. */
    public static final Integer MAX_VALUES = 500;

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

    /** Groups one field's records by value: one aggregate query in user mode (R-FU9). */
    public static FieldResult usage(
        Schema.DescribeSObjectResult described,
        Schema.DescribeFieldResult field
    ) {
        Map<String, Schema.SObjectField> known = described.fields.getMap();
        String dateField = known.containsKey('lastmodifieddate')
            ? 'LastModifiedDate'
            : (known.containsKey('createddate') ? 'CreatedDate' : null);
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
