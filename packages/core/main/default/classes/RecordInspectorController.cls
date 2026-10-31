/**
 * The Record Inspector (C-55): every field of one record that the person is allowed to read,
 * with its label, API name and value, including the fields the page layout leaves out.
 *
 * Read only, and it widens nothing. Fields are chosen from the object's describe by what the
 * person can read, the record is read in user mode, and sharing applies as it does everywhere,
 * so the inspector never shows a value the person could not see by building a report. It needs
 * Manage BarnCRM Settings, because it is an administrator's tool. Long values are cut at a
 * limit, and fields that cannot be shown as text (binary, compound address and location
 * fields, whose parts are listed on their own) are left out.
 */
public with sharing class RecordInspectorController {
    /** The longest value returned in full; a longer one is cut and marked. */
    @TestVisible
    private static final Integer VALUE_LIMIT = 2000;
    /** The most fields one query selects; SOQL text may not pass 100,000 characters. */
    @TestVisible
    private static Integer fieldLimit = 2000;

    /** One field of the record. */
    public class FieldRow {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public Boolean isCustom;
        /** The value as text, or null when the field is empty. */
        @AuraEnabled
        public String value;
        /** True when the value was longer than the limit and has been cut. */
        @AuraEnabled
        public Boolean truncated = false;
    }

    /** The record and its readable fields. */
    public class Inspection {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public List<FieldRow> fields = new List<FieldRow>();
        /** True when the object has more readable fields than one read can carry. */
        @AuraEnabled
        public Boolean fieldsCut = false;
    }

    /** The record's readable fields, sorted by label. */
    @AuraEnabled
    public static Inspection inspect(String recordId) {
        try {
            if (!BarnCRMPermissions.canManageSettings()) {
                throw new RecordInspectorException(
                    System.Label.Core_RecordInspector_ErrorNoPermission
                );
            }
            Id parsed = parse(recordId);
            Schema.DescribeSObjectResult described = parsed.getSObjectType()
                .getDescribe(SObjectDescribeOptions.DEFERRED);
            if (!described.isAccessible()) {
                throw new RecordInspectorException(System.Label.Core_RecordInspector_ErrorNotFound);
            }
            Inspection result = new Inspection();
            result.recordId = parsed;
            result.objectApiName = described.getName();
            result.objectLabel = described.getLabel();

            List<Schema.DescribeFieldResult> readable = readableFields(described);
            if (readable.size() > fieldLimit) {
                readable = trim(readable, fieldLimit);
                result.fieldsCut = true;
            }
            SObject record = read(described.getName(), parsed, readable);
            if (record == null) {
                throw new RecordInspectorException(System.Label.Core_RecordInspector_ErrorNotFound);
            }
            for (Schema.DescribeFieldResult field : readable) {
                result.fields.add(row(field, record));
            }
            result.fields.sort(new ByLabel());
            return result;
        } catch (Exception caught) {
            throw UserErrors.wrap(caught, 'Record Inspector', false);
        }
    }

    private static Id parse(String recordId) {
        try {
            return Id.valueOf(recordId);
        } catch (Exception notAnId) {
            throw new RecordInspectorException(System.Label.Core_RecordInspector_ErrorNotFound);
        }
    }

    /**
     * The fields the person can read and the inspector can show as text. Compound fields (an
     * address, a location) and binary fields are skipped; an address's parts are fields of
     * their own.
     */
    private static List<Schema.DescribeFieldResult> readableFields(
        Schema.DescribeSObjectResult described
    ) {
        List<Schema.DescribeFieldResult> found = new List<Schema.DescribeFieldResult>();
        for (Schema.SObjectField token : described.fields.getMap().values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            Schema.DisplayType type = field.getType();
            if (
                field.isAccessible() &&
                type != Schema.DisplayType.ADDRESS &&
                type != Schema.DisplayType.LOCATION &&
                type != Schema.DisplayType.BASE64
            ) {
                found.add(field);
            }
        }
        return found;
    }

    private static List<Schema.DescribeFieldResult> trim(
        List<Schema.DescribeFieldResult> fields,
        Integer keep
    ) {
        List<Schema.DescribeFieldResult> kept = new List<Schema.DescribeFieldResult>();
        for (Integer i = 0; i < keep; i++) {
            kept.add(fields[i]);
        }
        return kept;
    }

    private static SObject read(
        String objectName,
        Id recordId,
        List<Schema.DescribeFieldResult> fields
    ) {
        List<String> names = new List<String>();
        for (Schema.DescribeFieldResult field : fields) {
            names.add(field.getName());
        }
        List<SObject> found = Database.queryWithBinds(
            'SELECT ' +
                String.join(names, ', ') +
                ' FROM ' +
                objectName +
                ' WHERE Id = :recordId LIMIT 1',
            new Map<String, Object>{ 'recordId' => recordId },
            AccessLevel.USER_MODE
        );
        return found.isEmpty() ? null : found[0];
    }

    private static FieldRow row(Schema.DescribeFieldResult field, SObject record) {
        FieldRow row = new FieldRow();
        row.label = field.getLabel();
        row.apiName = field.getName();
        row.type = String.valueOf(field.getType());
        row.isCustom = field.isCustom();
        String text = asText(record.get(field.getName()));
        if (text != null && text.length() > VALUE_LIMIT) {
            text = text.left(VALUE_LIMIT);
            row.truncated = true;
        }
        row.value = text;
        return row;
    }

    private static String asText(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).format();
        }
        return String.valueOf(value);
    }

    /** Label order, then API name, so two fields with one label keep a fixed order. */
    private class ByLabel implements System.Comparator<FieldRow> {
        public Integer compare(FieldRow left, FieldRow right) {
            Integer byLabel = left.label.toLowerCase().compareTo(right.label.toLowerCase());
            return byLabel != 0 ? byLabel : left.apiName.compareTo(right.apiName);
        }
    }

    /** A refusal written for a person. */
    public class RecordInspectorException extends Exception {
    }
}
