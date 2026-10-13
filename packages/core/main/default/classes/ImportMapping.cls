/**
 * The mapping document of an import template (canonical model R-IT1): which source column
 * describes which attribute of which row entity, and the values applied to every row that
 * does not carry its own.
 *
 * The document is held as one JSON value per template for the same reason the rollup filter
 * is: it is built and saved as one unit in the two-column picker, and shared as a single
 * file in `data/import-templates/`. Targets are written `Entity.Attribute` using the row
 * entity names in R-IR1, so a template can be read without knowing the object model.
 *
 * Parsing is deliberately forgiving. A template edited by hand, or written by a contributor,
 * must not make an import fail with a stack trace: an unreadable document reads as an empty
 * mapping, which the caller reports as "no column was matched".
 */
@NamespaceAccessible
public with sharing class ImportMapping {
    /** The row entities Core itself resolves (R-IR1, R-IR6). */
    @NamespaceAccessible
    public static final String ENTITY_HOUSEHOLD = 'Household';
    @NamespaceAccessible
    public static final String ENTITY_CONTACT_1 = 'Contact1';
    @NamespaceAccessible
    public static final String ENTITY_CONTACT_2 = 'Contact2';
    @NamespaceAccessible
    public static final String ENTITY_ORGANIZATION = 'Organization';

    /**
     * The one entity of a template that loads one object (R-IT12): its attributes are the
     * target object's field API names, and `Record.Id` names an existing record.
     */
    @NamespaceAccessible
    public static final String ENTITY_RECORD = 'Record';

    /** The person-to-organization link Core makes from a row (R-AF5). */
    @NamespaceAccessible
    public static final String ENTITY_AFFILIATION = 'Affiliation';

    /** The row entities Core stages but does not write (R-IR6). */
    @NamespaceAccessible
    public static final Set<String> DEFERRED_ENTITIES = new Set<String>{
        'Gift',
        'Allocation',
        'SoftCredit',
        'Tribute'
    };

    /** The target that means "keep this column with the row and write it nowhere". */
    @NamespaceAccessible
    public static final String TARGET_IGNORE = 'Ignore';

    /**
     * The virtual attribute that holds a whole name in one column. The processor splits it
     * into a first and a last name, because a great many contact lists have only this.
     */
    @NamespaceAccessible
    public static final String ATTRIBUTE_FULL_NAME = 'FullName';

    /** One source column and what it describes. */
    @NamespaceAccessible
    public class Column {
        @AuraEnabled
        public String source;
        @AuraEnabled
        public String target;
        /**
         * For a lookup column of a one-object template, the parent field its values name the
         * parent by (R-IT13); empty or `Id` for the record ID.
         */
        @AuraEnabled
        public String lookupField;
        /** The steps that change this column's values before they are used (R-IT15). */
        @AuraEnabled
        public List<DataTransform.Step> transforms;

        // JSON.deserialize requires a no-arg constructor to build this class from the stored
        // mapping document (see parse below); the fields it fills in are set afterward by the
        // deserializer, so this constructor only states that starting point explicitly.
        @NamespaceAccessible
        public Column() {
            this.source = null;
            this.target = null;
            this.lookupField = null;
            this.transforms = null;
        }

        @NamespaceAccessible
        public Column(String source, String target) {
            this.source = source;
            this.target = target;
        }
    }

    /**
     * One target the column picker offers: the value stored in the mapping document and the
     * label an administrator reads. An entity processor names its own (R-IR6).
     */
    @NamespaceAccessible
    public class Target {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;

        @NamespaceAccessible
        public Target(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    /** One value applied to every row that does not carry its own. */
    @NamespaceAccessible
    public class Assignment {
        @AuraEnabled
        public String target;
        @AuraEnabled
        public String value;

        // JSON.deserialize requires a no-arg constructor to build this class from the stored
        // mapping document (see parse below); the fields it fills in are set afterward by the
        // deserializer, so this constructor only states that starting point explicitly.
        @NamespaceAccessible
        public Assignment() {
            this.target = null;
            this.value = null;
        }

        @NamespaceAccessible
        public Assignment(String target, String value) {
            this.target = target;
            this.value = value;
        }
    }

    @AuraEnabled
    public Integer version;
    @AuraEnabled
    public List<Column> columns;
    @AuraEnabled
    public List<Assignment> defaults;

    @NamespaceAccessible
    public ImportMapping() {
        this.version = 1;
        this.columns = new List<Column>();
        this.defaults = new List<Assignment>();
    }

    /**
     * Reads a mapping document. A blank or unreadable document reads as an empty mapping
     * rather than throwing, so one hand-edited template cannot break the wizard.
     */
    @NamespaceAccessible
    public static ImportMapping parse(String document) {
        ImportMapping result = new ImportMapping();
        if (String.isBlank(document)) {
            return result;
        }
        try {
            ImportMapping parsed = (ImportMapping) JSON.deserialize(document, ImportMapping.class);
            if (parsed == null) {
                return result;
            }
            result.version = parsed.version == null ? 1 : parsed.version;
            result.columns = parsed.columns == null ? new List<Column>() : parsed.columns;
            result.defaults = parsed.defaults == null ? new List<Assignment>() : parsed.defaults;
        } catch (Exception ignored) {
            // An unreadable document is an empty mapping. The caller reports the emptiness.
            return new ImportMapping();
        }
        return result;
    }

    /**
     * Reads the column document and the defaults document of a template, which are two
     * fields but one mapping.
     */
    @NamespaceAccessible
    public static ImportMapping parse(String columnDocument, String defaultsDocument) {
        ImportMapping result = parse(columnDocument);
        ImportMapping fromDefaults = parse(defaultsDocument);
        if (result.defaults.isEmpty() && !fromDefaults.defaults.isEmpty()) {
            result.defaults = fromDefaults.defaults;
        }
        return result;
    }

    /**
     * Puts a file's values (R-IB14) before this mapping's defaults, in place, and returns
     * this mapping. A file value replaces the template's default for the same target, and
     * the row's own value still wins over both, because defaults only fill blanks. A blank or
     * unreadable document changes nothing.
     */
    @NamespaceAccessible
    public ImportMapping withFileValues(String fileValuesDocument) {
        ImportMapping file = parse(fileValuesDocument);
        if (file.defaults.isEmpty()) {
            return this;
        }
        List<Assignment> merged = new List<Assignment>();
        Set<String> given = new Set<String>();
        for (Assignment assignment : file.defaults) {
            if (assignment != null && !isIgnored(assignment.target)) {
                merged.add(assignment);
                given.add(assignment.target.trim().toLowerCase());
            }
        }
        for (Assignment assignment : defaults) {
            if (
                assignment != null &&
                assignment.target != null &&
                !given.contains(assignment.target.trim().toLowerCase())
            ) {
                merged.add(assignment);
            }
        }
        defaults = merged;
        return this;
    }

    /**
     * True when a target names or finds a person: either person's first, last or full name,
     * their email, their record ID (R-IT10), or the field people are matched on (null when the
     * rule uses none). A value
     * for every row of a file may not be one of these, since every row would then be one
     * person (R-IB14).
     */
    @NamespaceAccessible
    public static Boolean namesAPerson(String target, String personMatchField) {
        String entity = entityOf(target);
        String attribute = attributeOf(target);
        if (
            attribute == null ||
            !(ENTITY_CONTACT_1.equalsIgnoreCase(entity) ||
            ENTITY_CONTACT_2.equalsIgnoreCase(entity))
        ) {
            return false;
        }
        for (
            String identifying : new List<String>{
                'FirstName',
                'LastName',
                'Email',
                'Id',
                ATTRIBUTE_FULL_NAME
            }
        ) {
            if (identifying.equalsIgnoreCase(attribute)) {
                return true;
            }
        }
        return personMatchField != null && personMatchField.equalsIgnoreCase(attribute);
    }

    /** The document, as it is stored on the template. */
    @NamespaceAccessible
    public String serialize() {
        return JSON.serialize(this);
    }

    /** The entity half of a target, or null when the target names no entity. */
    @NamespaceAccessible
    public static String entityOf(String target) {
        Integer dot = target == null ? -1 : target.indexOf('.');
        return dot <= 0 ? null : target.substring(0, dot).trim();
    }

    /** The attribute half of a target, or null when the target names no attribute. */
    @NamespaceAccessible
    public static String attributeOf(String target) {
        Integer dot = target == null ? -1 : target.indexOf('.');
        return dot < 0 || dot == target.length() - 1 ? null : target.substring(dot + 1).trim();
    }

    /** True when this target writes nothing, whether it says so or is simply unreadable. */
    @NamespaceAccessible
    public static Boolean isIgnored(String target) {
        return String.isBlank(target) ||
            TARGET_IGNORE.equalsIgnoreCase(target.trim()) ||
            entityOf(target) == null ||
            attributeOf(target) == null;
    }

    /**
     * The mapped target for each source column, keyed by the column name folded to lower
     * case and trimmed, which is how a header row is matched to a mapping. Ignored columns
     * are left out.
     */
    @NamespaceAccessible
    public Map<String, String> targetsBySourceKey() {
        Map<String, String> result = new Map<String, String>();
        for (Column column : columns) {
            if (column == null || String.isBlank(column.source) || isIgnored(column.target)) {
                continue;
            }
            result.put(key(column.source), column.target.trim());
        }
        return result;
    }

    /**
     * The source columns the administrator set to Do not load, keyed as `targetsBySourceKey`
     * keys them. Only the explicit ignore target counts: a blank or unreadable target is a
     * column nobody decided about. `targetsBySourceKey` leaves these out, which is right for
     * loading a row and wrong for suggesting a mapping, where a saved Do not load has to win
     * over a heading the column library recognizes, or the column is mapped again on the next
     * upload.
     */
    @NamespaceAccessible
    public Set<String> ignoredSourceKeys() {
        Set<String> result = new Set<String>();
        for (Column column : columns) {
            if (
                column != null &&
                String.isNotBlank(column.source) &&
                column.target != null &&
                TARGET_IGNORE.equalsIgnoreCase(column.target.trim())
            ) {
                result.add(key(column.source));
            }
        }
        return result;
    }

    /**
     * The steps of each column that has any (R-IT15), keyed as `targetsBySourceKey` keys
     * them. A column set to Do not load is left out, since nothing of it is used.
     */
    @NamespaceAccessible
    public Map<String, List<DataTransform.Step>> transformsBySourceKey() {
        Map<String, List<DataTransform.Step>> result = new Map<String, List<DataTransform.Step>>();
        for (Column column : columns) {
            if (
                column == null ||
                String.isBlank(column.source) ||
                isIgnored(column.target) ||
                column.transforms == null ||
                column.transforms.isEmpty()
            ) {
                continue;
            }
            result.put(key(column.source), column.transforms);
        }
        return result;
    }

    /**
     * What is wrong with the columns' steps, one sentence per column naming it, or an empty
     * list. A mapping is not saved while this is not empty (R-IT15).
     */
    @NamespaceAccessible
    public List<String> transformProblems() {
        List<String> result = new List<String>();
        for (Column column : columns) {
            if (column == null || column.transforms == null || column.transforms.isEmpty()) {
                continue;
            }
            List<String> problems = DataTransform.problems(column.transforms);
            if (!problems.isEmpty()) {
                result.add(
                    String.format(
                        Label.Core_Import_ErrorColumnChanges,
                        new List<String>{ column.source, String.join(problems, ' ') }
                    )
                );
            }
        }
        return result;
    }

    /** Every entity this mapping names, in no particular order. */
    @NamespaceAccessible
    public Set<String> mappedEntities() {
        Set<String> result = new Set<String>();
        for (String target : targetsBySourceKey().values()) {
            result.add(entityOf(target));
        }
        for (Assignment assignment : defaults) {
            if (assignment != null && !isIgnored(assignment.target)) {
                result.add(entityOf(assignment.target));
            }
        }
        return result;
    }

    /** The entities this mapping names that Core stages but cannot write (R-IR6). */
    @NamespaceAccessible
    public Set<String> deferredEntities() {
        Set<String> result = new Set<String>();
        for (String entity : mappedEntities()) {
            if (DEFERRED_ENTITIES.contains(entity)) {
                result.add(entity);
            }
        }
        return result;
    }

    /**
     * True when this mapping can identify somebody: a person needs a name or an email, an
     * organization needs a name. A mapping that identifies nobody is refused before a dry
     * run rather than producing a file of rejected rows.
     */
    @NamespaceAccessible
    public Boolean identifiesSomebody() {
        for (String target : targetsBySourceKey().values()) {
            String entity = entityOf(target);
            String attribute = attributeOf(target);
            Boolean isPerson =
                ENTITY_CONTACT_1.equalsIgnoreCase(entity) ||
                ENTITY_CONTACT_2.equalsIgnoreCase(entity);
            if (
                isPerson &&
                (ATTRIBUTE_FULL_NAME.equalsIgnoreCase(attribute) ||
                'LastName'.equalsIgnoreCase(attribute) ||
                'Email'.equalsIgnoreCase(attribute))
            ) {
                return true;
            }
            if (
                ENTITY_ORGANIZATION.equalsIgnoreCase(entity) && 'Name'.equalsIgnoreCase(attribute)
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     * The parent field each `Record` lookup column names its parent by (R-IT13), keyed by the
     * attribute folded to lower case. A column with no `lookupField`, or with `Id`, is left out:
     * it names its parent by record ID.
     */
    @NamespaceAccessible
    public Map<String, String> lookupFieldsByAttribute() {
        Map<String, String> result = new Map<String, String>();
        for (Column column : columns) {
            if (
                column == null ||
                isIgnored(column.target) ||
                String.isBlank(column.lookupField) ||
                'Id'.equalsIgnoreCase(column.lookupField.trim()) ||
                !ENTITY_RECORD.equalsIgnoreCase(entityOf(column.target))
            ) {
                continue;
            }
            result.put(attributeOf(column.target).toLowerCase(), column.lookupField.trim());
        }
        return result;
    }

    /**
     * Every `Record` attribute this mapping writes, from its columns and its values for every
     * row, folded to lower case (R-IT12).
     */
    @NamespaceAccessible
    public Set<String> recordAttributes() {
        Set<String> result = new Set<String>();
        List<String> targets = new List<String>(targetsBySourceKey().values());
        for (Assignment assignment : defaults) {
            if (assignment != null && !isIgnored(assignment.target)) {
                targets.add(assignment.target);
            }
        }
        for (String target : targets) {
            if (ENTITY_RECORD.equalsIgnoreCase(entityOf(target))) {
                result.add(attributeOf(target).toLowerCase());
            }
        }
        return result;
    }

    /** The lookup key of a column name: trimmed and folded to lower case. */
    @NamespaceAccessible
    public static String key(String columnName) {
        return columnName == null ? '' : columnName.trim().toLowerCase();
    }
}
