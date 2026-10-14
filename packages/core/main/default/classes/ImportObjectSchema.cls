/**
 * What a template that loads one object may name, read from the running user's describe at run
 * time (canonical model R-IT12 to R-IT14; ADR-0080 `0080-import-load-one-object.md`): the
 * objects a file may load, the fields a column may fill, the fields an upsert may match on, the
 * fields a lookup may name its parent by, and how a cell is read as its field's type.
 *
 * Core names no object here, so it runs on a Platform-only org (ADR-0013). What is never loaded
 * or written comes from `DataProtectedFields`. `ImportObjectLoader` runs a chunk with these
 * answers; the wizard asks them through `ImportController`.
 */
@NamespaceAccessible
public with sharing class ImportObjectSchema {
    @NamespaceAccessible
    public static final String OPERATION_INSERT = 'Insert';
    @NamespaceAccessible
    public static final String OPERATION_UPDATE = 'Update by record Id';
    @NamespaceAccessible
    public static final String OPERATION_UPSERT = 'Upsert by external ID';

    /**
     * The most records an object may hold, counted in the user's access, for a field it does not
     * index to be matched on (R-IT13, the large object guard).
     */
    @NamespaceAccessible
    public static final Integer LARGE_OBJECT_ROWS = 100000;

    /** The guard's ceiling, lowered by a test so it need not make 100,000 records. */
    @TestVisible
    private static Integer largeObjectRows = LARGE_OBJECT_ROWS;

    /** Whether each object is over the guard's ceiling, counted once per transaction. */
    private static Map<Schema.SObjectType, Boolean> large = new Map<Schema.SObjectType, Boolean>();

    /** The field types a row or a lookup may be matched on beyond the record ID (R-IT13). */
    private static final Set<Schema.DisplayType> MATCH_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE
    };

    @NamespaceAccessible
    public static final String LOOKUP_REJECT = 'Reject the row';
    @NamespaceAccessible
    public static final String LOOKUP_LEAVE_EMPTY = 'Leave it empty';

    /** The attribute a row names its record by under Update by record Id. */
    @NamespaceAccessible
    public static final String ID_ATTRIBUTE = 'Id';

    /** The objects a one-object load may only update (R-IT14): people and organizations. */
    private static final Set<Schema.SObjectType> UPDATE_ONLY = new Set<Schema.SObjectType>{
        Account.SObjectType,
        Contact.SObjectType
    };

    /** The field types a file's text is read into; any other is not offered. */
    @NamespaceAccessible
    public static final Set<Schema.DisplayType> TEXT_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.MULTIPICKLIST,
        Schema.DisplayType.ENCRYPTEDSTRING,
        Schema.DisplayType.COMBOBOX
    };

    /** The global describe, asked once per transaction. */
    private static Map<String, Schema.SObjectType> globalDescribe;

    /** Each object's fields, described once per transaction. */
    private static Map<Schema.SObjectType, Map<String, Schema.SObjectField>> fieldMaps = new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();

    // -------------------------------------------------------------------------------------
    // The template's choices
    // -------------------------------------------------------------------------------------

    /** True when this template loads one object rather than people and organizations. */
    @NamespaceAccessible
    public static Boolean loadsOneObject(Import_Template__c template) {
        return template != null && String.isNotBlank(template.Target_Object__c);
    }

    /** The object this template loads, or null when the org has none of that name. */
    @NamespaceAccessible
    public static Schema.SObjectType typeOf(Import_Template__c template) {
        return template == null ? null : typeNamed(template.Target_Object__c);
    }

    /** The object of this API name in this org, or null. */
    @NamespaceAccessible
    public static Schema.SObjectType typeNamed(String objectName) {
        if (String.isBlank(objectName)) {
            return null;
        }
        if (globalDescribe == null) {
            globalDescribe = Schema.getGlobalDescribe();
        }
        String lower = objectName.trim().toLowerCase();
        Schema.SObjectType found = globalDescribe.get(lower);
        return found != null
            ? found
            : globalDescribe.get(NamespaceUtil.prefix().toLowerCase() + lower);
    }

    /** The template's load operation; an empty or unknown one is Insert. */
    @NamespaceAccessible
    public static String operationOf(Import_Template__c template) {
        String chosen = template == null ? null : template.Load_Operation__c;
        for (String known : new List<String>{ OPERATION_UPDATE, OPERATION_UPSERT }) {
            if (known.equalsIgnoreCase(chosen)) {
                return known;
            }
        }
        return OPERATION_INSERT;
    }

    /** Whether a lookup that finds no record leaves the lookup empty rather than rejecting. */
    @NamespaceAccessible
    public static Boolean leavesLookupEmpty(Import_Template__c template) {
        return template != null &&
            LOOKUP_LEAVE_EMPTY.equalsIgnoreCase(template.Lookup_Not_Found__c);
    }

    /** The field an upsert matches rows on, as describe names it, or null when it cannot. */
    @NamespaceAccessible
    public static String keyFieldOf(Import_Template__c template) {
        return template == null ? null : keyField(typeOf(template), template.Load_Match_Field__c);
    }

    /** True when a one-object load may only update records of this object (R-IT14). */
    @NamespaceAccessible
    public static Boolean updatesOnly(Schema.SObjectType type) {
        return type != null && UPDATE_ONLY.contains(type);
    }

    // -------------------------------------------------------------------------------------
    // What the wizard offers
    // -------------------------------------------------------------------------------------

    /**
     * The objects a template may load (R-IT14): those `DataProtectedFields` admits that the
     * user can read and query and can create or edit records of, sorted by label. Found in
     * describe, so every object the org has is a candidate and Core names none.
     */
    @NamespaceAccessible
    public static List<ImportMapping.Target> loadableObjects() {
        if (globalDescribe == null) {
            globalDescribe = Schema.getGlobalDescribe();
        }
        Map<String, ImportMapping.Target> byLabel = new Map<String, ImportMapping.Target>();
        for (Schema.SObjectType type : globalDescribe.values()) {
            Schema.DescribeSObjectResult described = type.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );
            Boolean writable = updatesOnly(type)
                ? described.isUpdateable()
                : described.isCreateable() || described.isUpdateable();
            if (
                !described.isAccessible() ||
                !described.isQueryable() ||
                !writable ||
                DataProtectedFields.objectRefusal(type) != null
            ) {
                continue;
            }
            byLabel.put(
                described.getLabel() + '|' + described.getName(),
                new ImportMapping.Target(described.getName(), described.getLabel())
            );
        }
        return sortedValues(byLabel);
    }

    /** The operations a load of this object may use: Update only for people (R-IT14). */
    @NamespaceAccessible
    public static List<String> operationsFor(Schema.SObjectType type) {
        return updatesOnly(type)
            ? new List<String>{ OPERATION_UPDATE }
            : new List<String>{ OPERATION_INSERT, OPERATION_UPDATE, OPERATION_UPSERT };
    }

    /**
     * The fields a column may fill (R-IT12): the record ID first, then every field the user may
     * create or edit that is not protected and holds a type a file's text can be read into,
     * sorted by label. Values are field API names.
     */
    @NamespaceAccessible
    public static List<ImportMapping.Target> writableFields(Schema.SObjectType type) {
        List<ImportMapping.Target> result = new List<ImportMapping.Target>{
            new ImportMapping.Target(ID_ATTRIBUTE, Label.Core_Import_RecordIdOption)
        };
        if (type == null) {
            return result;
        }
        Map<String, ImportMapping.Target> byLabel = new Map<String, ImportMapping.Target>();
        for (Schema.SObjectField token : fieldsOf(type).values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (isWritable(type, field)) {
                byLabel.put(
                    field.getLabel() + '|' + field.getName(),
                    new ImportMapping.Target(field.getName(), field.getLabel())
                );
            }
        }
        result.addAll(sortedValues(byLabel));
        return result;
    }

    /**
     * The fields an upsert may match on (R-IT12): the object's External ID fields holding text
     * or an email that the user may read. Upsert is the platform's own meaning, so a unique
     * field that is not an external ID is not offered.
     */
    @NamespaceAccessible
    public static List<ImportMapping.Target> keyFields(Schema.SObjectType type) {
        List<ImportMapping.Target> result = new List<ImportMapping.Target>();
        for (Schema.DescribeFieldResult field : ImportMatcher.matchableFields(type)) {
            if (field.isExternalId()) {
                result.add(new ImportMapping.Target(field.getName(), field.getLabel()));
            }
        }
        return result;
    }

    /** The field's API name when an upsert may match on it, or null. Blank is null. */
    @NamespaceAccessible
    public static String keyField(Schema.SObjectType type, String fieldName) {
        if (type == null || String.isBlank(fieldName)) {
            return null;
        }
        for (ImportMapping.Target candidate : keyFields(type)) {
            if (sameField(candidate.value, fieldName)) {
                return candidate.value;
            }
        }
        return null;
    }

    /**
     * The fields rows or lookups may be matched on beyond the record ID (R-IT12, R-IT13): every
     * text, email or phone field of the object that the user may read and filter on, sorted by
     * label. The large object guard (`unselective`) decides later whether one may be searched.
     */
    @NamespaceAccessible
    public static List<ImportMapping.Target> matchFields(Schema.SObjectType type) {
        Map<String, ImportMapping.Target> byLabel = new Map<String, ImportMapping.Target>();
        if (type == null) {
            return new List<ImportMapping.Target>();
        }
        for (Schema.SObjectField token : fieldsOf(type).values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (
                MATCH_TYPES.contains(field.getType()) &&
                field.isAccessible() &&
                field.isFilterable()
            ) {
                byLabel.put(
                    field.getLabel() + '|' + field.getName(),
                    new ImportMapping.Target(field.getName(), field.getLabel())
                );
            }
        }
        return sortedValues(byLabel);
    }

    /** The field's API name when rows may be matched on it (`matchFields`), or null. */
    @NamespaceAccessible
    public static String matchField(Schema.SObjectType type, String fieldName) {
        if (type == null || String.isBlank(fieldName)) {
            return null;
        }
        for (ImportMapping.Target candidate : matchFields(type)) {
            if (sameField(candidate.value, fieldName)) {
                return candidate.value;
            }
        }
        return null;
    }

    /**
     * Whether the platform indexes this field, so a search by it stays quick on any number of
     * records (R-IT13): the record ID, the name field, a field marked External ID or Unique, and
     * a standard Email field. Custom indexes cannot be seen from Apex, so they are not counted.
     */
    @NamespaceAccessible
    public static Boolean isIndexed(Schema.SObjectType type, String fieldName) {
        if (ID_ATTRIBUTE.equalsIgnoreCase(fieldName)) {
            return true;
        }
        Schema.SObjectField token = fieldNamed(type, fieldName);
        if (token == null) {
            return false;
        }
        Schema.DescribeFieldResult field = token.getDescribe();
        return field.isNameField() ||
            field.isExternalId() ||
            field.isUnique() ||
            (!field.isCustom() &&
            field.getType() == Schema.DisplayType.EMAIL &&
            field.getName() == 'Email');
    }

    /**
     * Why rows cannot be matched on this field of this object, or null (R-IT13, the large object
     * guard): a field the platform does not index, on an object holding more than
     * LARGE_OBJECT_ROWS records the user can see, would be searched by reading the whole object,
     * which is slow and can time out. Counted once per object per transaction, the count capped
     * one past the ceiling.
     */
    @NamespaceAccessible
    public static String unselective(Schema.SObjectType type, String fieldName) {
        if (type == null || String.isBlank(fieldName) || isIndexed(type, fieldName)) {
            return null;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!large.containsKey(type)) {
            Integer counted = Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' +
                    String.escapeSingleQuotes(described.getName()) +
                    ' LIMIT :cap',
                new Map<String, Object>{ 'cap' => largeObjectRows + 1 },
                AccessLevel.USER_MODE
            );
            large.put(type, counted > largeObjectRows);
        }
        if (!large.get(type)) {
            return null;
        }
        return String.format(
            Label.Core_Import_ErrorFieldNotSelective,
            new List<String>{
                labelOf(type, fieldName),
                described.getLabelPlural(),
                largeObjectRows.format()
            }
        );
    }

    /**
     * The fields a lookup column may name its parent by (R-IT13): the record ID, the parent's
     * name field, and any text, email or phone field of the parent the user may read and filter
     * on (`matchFields`). A lookup that can point at more than one object is named by record ID
     * only, as is a field that is not a lookup of this object.
     */
    @NamespaceAccessible
    public static List<ImportMapping.Target> parentFields(
        Schema.SObjectType type,
        String lookupName
    ) {
        List<ImportMapping.Target> result = new List<ImportMapping.Target>{
            new ImportMapping.Target(ID_ATTRIBUTE, Label.Core_Import_RecordIdOption)
        };
        Schema.SObjectType parent = parentOf(type, lookupName);
        if (parent == null) {
            return result;
        }
        Set<String> offered = new Set<String>();
        String nameField = nameFieldOf(parent);
        if (nameField != null) {
            Schema.DescribeFieldResult name = fieldNamed(parent, nameField).getDescribe();
            result.add(new ImportMapping.Target(name.getName(), name.getLabel()));
            offered.add(name.getName().toLowerCase());
        }
        for (ImportMapping.Target field : matchFields(parent)) {
            if (!offered.contains(field.value.toLowerCase())) {
                result.add(field);
            }
        }
        return result;
    }

    /**
     * The one object this lookup field of this object points at, or null when it is not a
     * lookup, points at several objects, or the object has no such field.
     */
    @NamespaceAccessible
    public static Schema.SObjectType parentOf(Schema.SObjectType type, String lookupName) {
        if (type == null) {
            return null;
        }
        Schema.SObjectField token = fieldNamed(type, lookupName);
        if (token == null) {
            return null;
        }
        List<Schema.SObjectType> parents = token.getDescribe().getReferenceTo();
        return parents.size() == 1 ? parents[0] : null;
    }

    /** The parent field as describe names it when a lookup may name its parent by it, or null. */
    @NamespaceAccessible
    public static String parentField(Schema.SObjectType parent, String fieldName) {
        if (parent == null || String.isBlank(fieldName)) {
            return null;
        }
        String nameField = nameFieldOf(parent);
        if (nameField != null && sameField(nameField, fieldName)) {
            return nameField;
        }
        return matchField(parent, fieldName);
    }

    /** The object's name field when the user may read and filter on it, or null. */
    @NamespaceAccessible
    public static String nameFieldOf(Schema.SObjectType type) {
        if (type == null) {
            return null;
        }
        for (Schema.SObjectField token : fieldsOf(type).values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (field.isNameField() && field.isAccessible() && field.isFilterable()) {
                return field.getName();
            }
        }
        return null;
    }

    /**
     * A mapping suggested from a file's header row (R-IT12): a heading that is a writable
     * field's label or API name, ignoring case, spaces and punctuation, is mapped to it, and Id
     * or Record Id to the record ID; anything else is Do not load, never a guess. A second
     * heading for one field is left for the administrator.
     */
    @NamespaceAccessible
    public static ImportMapping suggestMapping(Schema.SObjectType type, List<String> headers) {
        ImportMapping mapping = new ImportMapping();
        if (headers == null) {
            return mapping;
        }
        Map<String, String> known = new Map<String, String>{
            'id' => ID_ATTRIBUTE,
            'recordid' => ID_ATTRIBUTE,
            'salesforcerecordid' => ID_ATTRIBUTE
        };
        if (type != null) {
            for (Schema.SObjectField token : fieldsOf(type).values()) {
                Schema.DescribeFieldResult field = token.getDescribe();
                if (!isWritable(type, field)) {
                    continue;
                }
                for (
                    String spelling : new List<String>{
                        normalized(field.getLabel()),
                        normalized(localName(field.getName().toLowerCase()).removeEnd('__c')),
                        normalized(field.getName())
                    }
                ) {
                    if (!known.containsKey(spelling)) {
                        known.put(spelling, field.getName());
                    }
                }
            }
        }
        Set<String> used = new Set<String>();
        for (String header : headers) {
            String field = known.get(normalized(header));
            Boolean maps = field != null && !used.contains(field);
            if (maps) {
                used.add(field);
            }
            mapping.columns.add(
                new ImportMapping.Column(
                    header,
                    maps ? ImportMapping.ENTITY_RECORD + '.' + field : ImportMapping.TARGET_IGNORE
                )
            );
        }
        return mapping;
    }

    // -------------------------------------------------------------------------------------
    // Refusals before any row is read
    // -------------------------------------------------------------------------------------

    /**
     * Why this template cannot load its rows, or null (R-IT12, R-IT14): an object that is gone
     * or protected, an operation people do not allow, access the operation needs and the user
     * lacks, no column mapped to the object, the key column an update or an upsert needs, a
     * value for every row that names the record, and a field searched by that the large object
     * guard refuses (R-IT13). Asked when a run starts and in every chunk.
     */
    @NamespaceAccessible
    public static String refusal(Import_Template__c template, ImportMapping mapping) {
        Schema.SObjectType type = typeOf(template);
        String refused = DataProtectedFields.objectRefusal(type);
        if (refused != null) {
            return refused;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        List<String> plural = new List<String>{ described.getLabelPlural() };
        String operation = operationOf(template);
        if (updatesOnly(type) && operation != OPERATION_UPDATE) {
            return String.format(Label.Core_Import_ErrorPeopleUpdateOnly, plural);
        }
        if (!canRun(described, operation)) {
            return String.format(Label.Core_Import_ErrorObjectNoAccess, plural);
        }
        ImportMapping given = mapping == null ? new ImportMapping() : mapping;
        Set<String> attributes = given.recordAttributes();
        if (attributes.isEmpty()) {
            return Label.Core_Import_ErrorNothingMapped;
        }
        String key = operation == OPERATION_UPDATE ? ID_ATTRIBUTE : null;
        if (operation == OPERATION_UPDATE && !attributes.contains(ID_ATTRIBUTE.toLowerCase())) {
            return Label.Core_Import_ErrorIdColumnMissing;
        }
        if (operation == OPERATION_UPSERT) {
            String chosen = template.Load_Match_Field__c;
            if (String.isBlank(chosen)) {
                return Label.Core_Import_ErrorKeyFieldRequired;
            }
            key = keyField(type, chosen);
            if (key == null) {
                return String.format(
                    Label.Core_Import_ErrorKeyFieldUnusable,
                    new List<String>{ chosen.trim().abbreviate(80) }
                );
            }
            if (!mapsField(attributes, key)) {
                return String.format(
                    Label.Core_Import_ErrorKeyColumnMissing,
                    new List<String>{ labelOf(type, key) }
                );
            }
        }
        if (key != null && givesEveryRow(given, key)) {
            return String.format(
                Label.Core_Import_ErrorKeyForEveryRow,
                new List<String>{
                    key == ID_ATTRIBUTE ? Label.Core_Import_RecordIdOption : labelOf(type, key)
                }
            );
        }
        return slowSearch(type, key, given);
    }

    /**
     * The large object guard over every field this template searches by (R-IT13): the field
     * rows find their record by, and each lookup column's parent field.
     */
    private static String slowSearch(Schema.SObjectType type, String key, ImportMapping mapping) {
        String refused = key == null ? null : unselective(type, key);
        if (refused != null) {
            return refused;
        }
        Map<String, String> lookups = mapping.lookupFieldsByAttribute();
        for (String attribute : lookups.keySet()) {
            Schema.SObjectType parent = parentOf(type, attribute);
            String field = parentField(parent, lookups.get(attribute));
            refused = field == null ? null : unselective(parent, field);
            if (refused != null) {
                return refused;
            }
        }
        return null;
    }

    /** Whether the user's object access allows the operation. */
    private static Boolean canRun(Schema.DescribeSObjectResult described, String operation) {
        if (!described.isAccessible() || !described.isQueryable()) {
            return false;
        }
        if (operation == OPERATION_INSERT) {
            return described.isCreateable();
        }
        if (operation == OPERATION_UPDATE) {
            return described.isUpdateable();
        }
        return described.isCreateable() && described.isUpdateable();
    }

    /** Whether a value for every row (R-IB14) fills this attribute: every row one record. */
    private static Boolean givesEveryRow(ImportMapping mapping, String fieldName) {
        for (ImportMapping.Assignment assignment : mapping.defaults) {
            if (
                assignment != null &&
                !ImportMapping.isIgnored(assignment.target) &&
                ImportMapping.ENTITY_RECORD.equalsIgnoreCase(
                    ImportMapping.entityOf(assignment.target)
                ) &&
                String.isNotBlank(assignment.value) &&
                mapsField(
                    new Set<String>{ ImportMapping.attributeOf(assignment.target).toLowerCase() },
                    fieldName
                )
            ) {
                return true;
            }
        }
        return false;
    }

    /** Whether one of these attributes names this field, with or without the namespace. */
    @NamespaceAccessible
    public static Boolean mapsField(Set<String> attributes, String fieldName) {
        String lower = fieldName.toLowerCase();
        return attributes.contains(lower) || attributes.contains(localName(lower));
    }

    // -------------------------------------------------------------------------------------
    // Reading a cell as its field's type
    // -------------------------------------------------------------------------------------

    /**
     * Why this value cannot be written to this field, or null when it can (R-IT12): text longer
     * than the field, or a value that cannot be read as the field's type.
     */
    @NamespaceAccessible
    public static String unreadable(String value, Schema.DescribeFieldResult field) {
        Integer length = field.getLength();
        if (
            TEXT_TYPES.contains(field.getType()) &&
            length != null &&
            length > 0 &&
            value.length() > length
        ) {
            return String.format(
                Label.Core_Import_ErrorValueTooLong,
                new List<String>{ field.getLabel(), String.valueOf(length) }
            );
        }
        Object converted;
        try {
            converted = typed(value, field);
        } catch (Exception notReadable) {
            converted = null;
        }
        if (converted == null) {
            return String.format(
                Label.Core_Import_ErrorValueUnreadable,
                new List<String>{ field.getLabel(), value.abbreviate(80) }
            );
        }
        return null;
    }

    /**
     * A value as its field's type. A date is read as ISO 8601 (2026-10-12) or in the running
     * user's locale; a date and time as ISO 8601 or in the locale; a number as
     * `ImportValues.number` reads it, so "$1,250.00", "1 250,50" in a locale that writes it so
     * and "(45.00)" load; a checkbox as `checkbox` reads it.
     * Returns null, or throws, when the value cannot be read. Lookups are not read here.
     */
    @NamespaceAccessible
    public static Object typed(String value, Schema.DescribeFieldResult field) {
        Schema.DisplayType kind = field.getType();
        String trimmed = value == null ? '' : value.trim();
        if (TEXT_TYPES.contains(kind)) {
            return value;
        }
        if (kind == Schema.DisplayType.BOOLEAN) {
            return checkbox(trimmed);
        }
        if (
            kind == Schema.DisplayType.CURRENCY ||
            kind == Schema.DisplayType.DOUBLE ||
            kind == Schema.DisplayType.PERCENT
        ) {
            return ImportValues.number(trimmed);
        }
        if (kind == Schema.DisplayType.INTEGER || kind == Schema.DisplayType.LONG) {
            // A whole number, however it is written; "12.5" is not one.
            Decimal whole = ImportValues.number(trimmed);
            if (whole == null || whole != whole.round(System.RoundingMode.DOWN)) {
                return null;
            }
            if (kind == Schema.DisplayType.LONG) {
                return whole.longValue();
            }
            return Math.abs(whole) > 2147483647 ? null : whole.intValue();
        }
        if (kind == Schema.DisplayType.DATE) {
            return dateOf(trimmed);
        }
        if (kind == Schema.DisplayType.DATETIME) {
            return datetimeOf(trimmed);
        }
        if (kind == Schema.DisplayType.TIME) {
            return timeOf(trimmed);
        }
        return null;
    }

    /** The spellings a file uses for a ticked checkbox, lower case (canonical model R-IT11). */
    private static final Set<String> CHECKED = new Set<String>{
        'true',
        'yes',
        'y',
        '1',
        'x',
        'checked',
        'on',
        't'
    };

    /** The spellings a file uses for a cleared checkbox, lower case (canonical model R-IT11). */
    private static final Set<String> CLEARED = new Set<String>{
        'false',
        'no',
        'n',
        '0',
        'off',
        'f'
    };

    /**
     * A checkbox value as every import reads it (R-IT11): true or false, ignoring case and
     * surrounding spaces, or null for a blank value or one that is neither, which is never read
     * as cleared. The people import and the one-object load share this one reading.
     */
    @NamespaceAccessible
    public static Boolean checkbox(String value) {
        String lower = value == null ? '' : value.trim().toLowerCase();
        if (CHECKED.contains(lower)) {
            return true;
        }
        if (CLEARED.contains(lower)) {
            return false;
        }
        return null;
    }

    private static Date dateOf(String value) {
        if (Pattern.matches('\\d{4}-\\d{1,2}-\\d{1,2}', value)) {
            return Date.valueOf(value);
        }
        return Date.parse(value);
    }

    private static Datetime datetimeOf(String value) {
        if (Pattern.matches('\\d{4}-\\d{1,2}-\\d{1,2} \\d{1,2}:\\d{2}(:\\d{2})?', value)) {
            return Datetime.valueOf(value.countMatches(':') == 1 ? value + ':00' : value);
        }
        if (Pattern.matches('\\d{4}-\\d{2}-\\d{2}T.*', value)) {
            return (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
        }
        return Datetime.parse(value);
    }

    private static Time timeOf(String value) {
        if (!Pattern.matches('\\d{1,2}:\\d{2}(:\\d{2})?', value)) {
            return null;
        }
        List<String> parts = value.split(':');
        Integer hours = Integer.valueOf(parts[0]);
        Integer minutes = Integer.valueOf(parts[1]);
        Integer seconds = parts.size() > 2 ? Integer.valueOf(parts[2]) : 0;
        if (hours > 23 || minutes > 59 || seconds > 59) {
            return null;
        }
        return Time.newInstance(hours, minutes, seconds, 0);
    }

    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    /**
     * Whether a column may fill this field: the user may create or edit it, it is not
     * protected, and a file's text can be read into it (a lookup is read as its parent).
     */
    @NamespaceAccessible
    public static Boolean isWritable(Schema.SObjectType type, Schema.DescribeFieldResult field) {
        Schema.DisplayType kind = field.getType();
        Boolean readableType =
            kind == Schema.DisplayType.REFERENCE ||
            TEXT_TYPES.contains(kind) ||
            kind == Schema.DisplayType.BOOLEAN ||
            kind == Schema.DisplayType.CURRENCY ||
            kind == Schema.DisplayType.DOUBLE ||
            kind == Schema.DisplayType.PERCENT ||
            kind == Schema.DisplayType.INTEGER ||
            kind == Schema.DisplayType.LONG ||
            kind == Schema.DisplayType.DATE ||
            kind == Schema.DisplayType.DATETIME ||
            kind == Schema.DisplayType.TIME;
        return readableType &&
            (field.isCreateable() || field.isUpdateable()) &&
            !DataProtectedFields.isProtected(type, field.getName());
    }

    /** Each object's fields by lower case API name, described once per transaction. */
    @NamespaceAccessible
    public static Map<String, Schema.SObjectField> fieldsOf(Schema.SObjectType type) {
        if (type == null) {
            return new Map<String, Schema.SObjectField>();
        }
        if (!fieldMaps.containsKey(type)) {
            fieldMaps.put(type, type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap());
        }
        return fieldMaps.get(type);
    }

    /** The field of this name, with or without the package's namespace, or null. */
    @NamespaceAccessible
    public static Schema.SObjectField fieldNamed(Schema.SObjectType type, String fieldName) {
        if (String.isBlank(fieldName)) {
            return null;
        }
        Map<String, Schema.SObjectField> fields = fieldsOf(type);
        String lower = fieldName.trim().toLowerCase();
        Schema.SObjectField found = fields.get(lower);
        return found != null ? found : fields.get(NamespaceUtil.prefix().toLowerCase() + lower);
    }

    /** A field's label, or its name when the object has no such field. */
    @NamespaceAccessible
    public static String labelOf(Schema.SObjectType type, String fieldName) {
        Schema.SObjectField token = fieldNamed(type, fieldName);
        return token == null ? fieldName : token.getDescribe().getLabel();
    }

    /** A lower case API name without this package's namespace. */
    @NamespaceAccessible
    public static String localName(String lowerCaseName) {
        String prefix = NamespaceUtil.prefix();
        prefix = prefix == null ? '' : prefix.toLowerCase();
        return String.isNotBlank(prefix) && lowerCaseName.startsWith(prefix)
            ? lowerCaseName.removeStart(prefix)
            : lowerCaseName;
    }

    /** Whether a name given in a template is this field, with or without the namespace. */
    private static Boolean sameField(String describedName, String given) {
        String lower = given.trim().toLowerCase();
        String described = describedName.toLowerCase();
        return described == lower || localName(described) == localName(lower);
    }

    /** A heading or a name folded for comparison: lower case, letters and digits only. */
    private static String normalized(String text) {
        return text == null ? '' : text.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static List<ImportMapping.Target> sortedValues(
        Map<String, ImportMapping.Target> byLabel
    ) {
        List<String> labels = new List<String>(byLabel.keySet());
        labels.sort();
        List<ImportMapping.Target> result = new List<ImportMapping.Target>();
        for (String label : labels) {
            result.add(byLabel.get(label));
        }
        return result;
    }
}
