/**
 * DLRS rollups in this org, read and never changed (canonical model R-R16, plan D-124 item 6).
 *
 * DLRS keeps its rollups in a custom metadata type and, in older installs, a custom object.
 * Both are found through describe by names built at run time from the `dlrs` namespace
 * (`OtherRollupTools.DLRS_NAMESPACE`), and read with dynamic SOQL, so this class compiles and
 * returns nothing in an org without DLRS. Only fields the installed DLRS version has are read.
 *
 * The reader is a seam: DLRS cannot be installed in a test, so a test hands `reader` rows
 * shaped like DLRS's. Everything else here (which DLRS rollup fills a field, the same-field
 * guard's words, the change history row) is the same code in a test and in an org.
 */
public with sharing class RollupDlrs {
    /** Where DLRS keeps a rollup: its custom metadata type, or its older custom object. */
    public static final String SOURCE_METADATA = 'metadata';
    public static final String SOURCE_OBJECT = 'object';

    private static final String METADATA_TYPE = 'LookupRollupSummary2__mdt';
    private static final String LEGACY_OBJECT = 'LookupRollupSummary__c';
    /** The DLRS fields read, without the namespace; a field this DLRS lacks is skipped. */
    @TestVisible
    private static final List<String> DLRS_FIELDS = new List<String>{
        'Active__c',
        'AggregateAllRows__c',
        'AggregateOperation__c',
        'AggregateResultField__c',
        'BypassPermissionApiName__c',
        'CalculationMode__c',
        'CalculationSharingMode__c',
        'ChildObject__c',
        'ConcatenateDelimiter__c',
        'Description__c',
        'FieldToAggregate__c',
        'FieldToOrderBy__c',
        'ParentObject__c',
        'RelationshipCriteria__c',
        'RelationshipField__c',
        'RowLimit__c',
        'UniqueName__c'
    };
    /** What the change history row is filed under, before the BarnCRM rollup's name. */
    private static final String CHANGE_PREFIX = 'Rollup Builder: ';

    /** One DLRS rollup as BarnCRM reads it. */
    public class Definition {
        /** DeveloperName for custom metadata, Unique Name (or Name) for the object. */
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String source { get; set; }
        @AuraEnabled
        public Boolean active { get; set; }
        @AuraEnabled
        public String parentObject { get; set; }
        @AuraEnabled
        public String childObject { get; set; }
        @AuraEnabled
        public String relationshipField { get; set; }
        @AuraEnabled
        public String relationshipCriteria { get; set; }
        @AuraEnabled
        public String fieldToAggregate { get; set; }
        @AuraEnabled
        public String aggregateOperation { get; set; }
        @AuraEnabled
        public String aggregateResultField { get; set; }
        @AuraEnabled
        public String fieldToOrderBy { get; set; }
        @AuraEnabled
        public Integer rowLimit { get; set; }
        @AuraEnabled
        public Boolean allRows { get; set; }
        @AuraEnabled
        public String concatenateDelimiter { get; set; }
        @AuraEnabled
        public String calculationMode { get; set; }
        @AuraEnabled
        public String calculationSharingMode { get; set; }
        @AuraEnabled
        public String bypassPermission { get; set; }
        @AuraEnabled
        public String description { get; set; }
    }

    /** Reads DLRS's rollups; replaced by a test. */
    public interface Reader {
        List<Definition> read();
    }

    @TestVisible
    private static Reader reader = new OrgReader();
    private static List<Definition> cached;

    /** Every DLRS rollup in the org, active or not; empty without DLRS. Never throws. */
    public static List<Definition> definitions() {
        if (cached == null) {
            try {
                cached = reader.read();
            } catch (Exception unreadable) {
                ErrorLogger.log(unreadable, 'RollupDlrs');
                cached = new List<Definition>();
            }
        }
        return cached;
    }

    /** Forgets what was read, so the next call reads again (a test that swaps the reader). */
    @TestVisible
    private static void reset() {
        cached = null;
    }

    /** Whether DLRS has an active rollup, so Import from DLRS has something to offer. */
    public static Boolean hasActive() {
        for (Definition other : definitions()) {
            if (other.active == true) {
                return true;
            }
        }
        return false;
    }

    /** The active DLRS rollup that fills this field, or null. */
    public static Definition activeOn(String targetObject, String targetField) {
        if (String.isBlank(targetObject) || String.isBlank(targetField)) {
            return null;
        }
        for (Definition other : definitions()) {
            if (
                other.active == true &&
                sameField(targetObject, targetField, other.parentObject, other.aggregateResultField)
            ) {
                return other;
            }
        }
        return null;
    }

    /**
     * Why a BarnCRM rollup on this field cannot be turned on without the administrator's word,
     * or null when no active DLRS rollup fills it (R-R16).
     */
    public static String conflict(String targetObject, String targetField) {
        Definition other = activeOn(targetObject, targetField);
        return other == null
            ? null
            : String.format(
                  Label.Core_RollupBuilder_DlrsSameField,
                  new List<String>{ other.label, targetObject + '.' + targetField }
              );
    }

    /**
     * Records in the settings change history that the administrator confirmed the DLRS rollup
     * on this field will be switched off, when one is active there. Nothing in DLRS changes.
     */
    public static void recordSwitchOff(String rollupName, String targetObject, String targetField) {
        Definition other = activeOn(targetObject, targetField);
        if (other == null) {
            return;
        }
        SettingsService.logChange(
            CHANGE_PREFIX + rollupName,
            String.format(
                Label.Core_RollupBuilder_DlrsHistoryBefore,
                new List<String>{ other.label, targetObject + '.' + targetField }
            ),
            Label.Core_RollupBuilder_DlrsHistoryConfirmed
        );
    }

    /**
     * One DLRS rollup from its values, keyed by field name without the namespace in any case.
     * Visible to tests, which build DLRS-shaped rows with it.
     */
    @TestVisible
    private static Definition fromValues(
        String key,
        String label,
        String source,
        Map<String, Object> values
    ) {
        Map<String, Object> byName = new Map<String, Object>();
        for (String name : values.keySet()) {
            byName.put(name.toLowerCase(), values.get(name));
        }
        Definition definition = new Definition();
        String uniqueName = text(byName, 'UniqueName__c');
        definition.key = String.isNotBlank(uniqueName) ? uniqueName : key;
        definition.label = String.isBlank(label) ? definition.key : label;
        definition.source = source;
        definition.active = byName.get('active__c') == true;
        definition.parentObject = text(byName, 'ParentObject__c');
        definition.childObject = text(byName, 'ChildObject__c');
        definition.relationshipField = text(byName, 'RelationshipField__c');
        definition.relationshipCriteria = text(byName, 'RelationshipCriteria__c');
        definition.fieldToAggregate = text(byName, 'FieldToAggregate__c');
        definition.aggregateOperation = text(byName, 'AggregateOperation__c');
        definition.aggregateResultField = text(byName, 'AggregateResultField__c');
        definition.fieldToOrderBy = text(byName, 'FieldToOrderBy__c');
        Object rowLimit = byName.get('rowlimit__c');
        definition.rowLimit = rowLimit instanceof Decimal ? ((Decimal) rowLimit).intValue() : null;
        definition.allRows = byName.get('aggregateallrows__c') == true;
        // Not trimmed: a delimiter may be a space.
        Object delimiter = byName.get('concatenatedelimiter__c');
        definition.concatenateDelimiter = delimiter == null ? null : String.valueOf(delimiter);
        definition.calculationMode = text(byName, 'CalculationMode__c');
        definition.calculationSharingMode = text(byName, 'CalculationSharingMode__c');
        definition.bypassPermission = text(byName, 'BypassPermissionApiName__c');
        definition.description = text(byName, 'Description__c');
        return definition;
    }

    private static String text(Map<String, Object> byName, String field) {
        Object value = byName.get(field.toLowerCase());
        return value == null || String.isBlank(String.valueOf(value))
            ? null
            : String.valueOf(value).trim();
    }

    /** Whether two object and field names are the same field, through describe when they resolve. */
    private static Boolean sameField(String objectA, String fieldA, String objectB, String fieldB) {
        if (String.isBlank(objectB) || String.isBlank(fieldB)) {
            return false;
        }
        Schema.SObjectType typeA = SettingsService.typeByName(objectA);
        Schema.SObjectType typeB = SettingsService.typeByName(objectB);
        if (typeA == null || typeB == null) {
            return objectA.equalsIgnoreCase(objectB.trim()) &&
                fieldA.equalsIgnoreCase(fieldB.trim());
        }
        if (typeA != typeB) {
            return false;
        }
        Map<String, Schema.SObjectField> fields = typeA.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        Schema.SObjectField a = fields.get(fieldA.toLowerCase());
        return a != null
            ? a == fields.get(fieldB.trim().toLowerCase())
            : fieldA.equalsIgnoreCase(fieldB.trim());
    }

    /** Reads the org's DLRS rollups: the custom metadata type, then the older object. */
    private with sharing class OrgReader implements Reader {
        public List<Definition> read() {
            List<Definition> found = new List<Definition>();
            if (!OtherRollupTools.hasDlrs()) {
                return found;
            }
            String prefix = OtherRollupTools.DLRS_NAMESPACE + '__';
            found.addAll(
                readFrom(prefix, METADATA_TYPE, 'DeveloperName', 'MasterLabel', SOURCE_METADATA)
            );
            found.addAll(readFrom(prefix, LEGACY_OBJECT, 'Name', 'Name', SOURCE_OBJECT));
            return found;
        }
    }

    /**
     * The rows of one DLRS store, in system mode: they are configuration, read so the Builder
     * and Health Check can tell an administrator about them, and shown to no one else. Visible
     * to tests, which read an object of their own with no prefix through the same code.
     */
    @TestVisible
    private static List<Definition> readFrom(
        String prefix,
        String localName,
        String keyField,
        String labelField,
        String source
    ) {
        List<Definition> found = new List<Definition>();
        Schema.SObjectType type = Schema.getGlobalDescribe().get(prefix + localName);
        if (type == null) {
            return found;
        }
        Map<String, Schema.SObjectField> fields = type.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        Set<String> selected = new Set<String>{ keyField, labelField };
        Map<String, String> localByQualified = new Map<String, String>();
        // Apex names ignore case, so this list is not called FIELDS: `fields` above would hide it.
        for (String field : DLRS_FIELDS) {
            if (fields.containsKey((prefix + field).toLowerCase())) {
                selected.add(prefix + field);
                localByQualified.put(prefix + field, field);
            }
        }
        String query =
            'SELECT ' +
            String.join(new List<String>(selected), ', ') +
            ' FROM ' +
            prefix +
            localName +
            ' LIMIT 2000';
        for (SObject row : Database.query(query, AccessLevel.SYSTEM_MODE)) {
            Map<String, Object> values = new Map<String, Object>();
            for (String qualified : localByQualified.keySet()) {
                values.put(localByQualified.get(qualified), row.get(qualified));
            }
            found.add(
                fromValues(
                    String.valueOf(row.get(keyField)),
                    String.valueOf(row.get(labelField)),
                    source,
                    values
                )
            );
        }
        return found;
    }
}
