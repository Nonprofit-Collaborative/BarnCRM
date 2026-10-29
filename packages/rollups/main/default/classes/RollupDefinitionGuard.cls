/**
 * Who may change a Rollup Definition, and what it may read and write, checked on every save
 * however it arrives: the Builder, import, the record page, the API or a data loader
 * (2026-10-28 security review, R-H1).
 *
 * The engine reads in system mode and writes totals in system mode (`RollupWriter`), so a
 * definition is, in effect, a standing instruction to copy one field into another. The Builder
 * already asks that its author may configure BarnCRM, may write the target field and may read
 * every field the rollup reads; this class asks the same of every other path, so holding the
 * Rollup Builder set alone, with Create and Edit on the object, is not enough.
 *
 * - Any change but the engine's own `Last_Calculated__c` stamp needs Manage BarnCRM Settings.
 * - An insert, or a change to what the rollup reads or writes, needs the target object to be
 *   one a total may be written to (never User, setup objects or BarnCRM's own bookkeeping),
 *   the target field writable by the author, and every field it reads readable by the author:
 *   the source object, the lookups on its path, the summarized, order and fiscal date fields,
 *   and every field either filter names.
 *
 * It runs from the trigger itself, not from a handler, because a handler can be switched off,
 * bypassed or paused, and a security check must not be. The one trusted writer is the package's
 * own install of its shipped defaults (`RollupWriter.insertDefinitions`), which runs where no
 * permission set is assigned yet and writes only definitions the package itself ships.
 */
public with sharing class RollupDefinitionGuard {
    /** True only while `RollupWriter.insertDefinitions` saves the package's shipped defaults. */
    @TestVisible
    private static Boolean shippedDefaultsSaving = false;

    /**
     * Objects a total is never written to: the user record and setup objects, whose fields
     * govern who can do what, plus BarnCRM's own bookkeeping. Local API names, in lower case.
     */
    private static final Set<String> NEVER_TARGETS = new Set<String>{
        'user',
        'userrole',
        'group',
        'groupmember',
        'organization',
        'profile',
        'permissionset',
        'permissionsetassignment',
        'permissionsetgroup',
        'permissionsetlicenseassign',
        'queuesobject',
        'territory',
        'userterritory',
        'territory2',
        'userterritory2association',
        'automation_setting__c',
        'duplicate_dismissal__c',
        'error_log__c',
        'import_batch__c',
        'import_journal__c',
        'import_row__c',
        'import_template__c',
        'rollup_definition__c',
        'rollup_queue__c',
        'setting_change__c'
    };

    /** The fields whose change alters what a rollup reads or writes. */
    private static final List<Schema.SObjectField> READ_OR_WRITE_FIELDS = new List<Schema.SObjectField>{
        Rollup_Definition__c.Target_Object__c,
        Rollup_Definition__c.Target_Field__c,
        Rollup_Definition__c.Source_Object__c,
        Rollup_Definition__c.Relationship_Path__c,
        Rollup_Definition__c.Source_Field__c,
        Rollup_Definition__c.Order_By_Field__c,
        Rollup_Definition__c.Fiscal_Date_Field__c,
        Rollup_Definition__c.Filter_JSON__c,
        Rollup_Definition__c.Target_Filter_JSON__c
    };

    /**
     * Marks the start (true) and end (false) of `RollupWriter.insertDefinitions`, the only save
     * the check trusts. The writer clears it in a finally block.
     */
    public static void trustShippedDefaults(Boolean saving) {
        shippedDefaultsSaving = saving == true;
    }

    /**
     * Whether a total may be written to this object at all, whoever asks. The Builder offers
     * only objects this allows.
     */
    public static Boolean isAllowedTarget(String objectName) {
        if (String.isBlank(objectName)) {
            return false;
        }
        String name = objectName.trim().toLowerCase();
        List<String> parts = name.split('__');
        String local = parts.size() > 2 ? parts[1] + '__c' : name;
        return !NEVER_TARGETS.contains(local);
    }

    /**
     * Checks a before insert or before update save, adding an error to each record refused.
     *
     * @param records the records being saved
     * @param previousById the records as they were, or null on insert
     */
    public static void check(List<Rollup_Definition__c> records, Map<Id, SObject> previousById) {
        if (shippedDefaultsSaving || records == null || records.isEmpty()) {
            return;
        }
        Boolean canManage = null;
        for (Rollup_Definition__c record : records) {
            SObject previous = previousById == null ? null : previousById.get(record.Id);
            if (previous != null && !changedBeyondEngine(record, previous)) {
                continue;
            }
            if (canManage == null) {
                canManage = BarnCRMPermissions.canManageSettings();
            }
            if (!canManage) {
                record.addError(System.Label.Core_Rollups_ErrorNoPermission);
                continue;
            }
            if (previous != null && !readsOrWritesChanged(record, previous)) {
                continue;
            }
            String problem = accessProblem(record);
            if (problem != null) {
                record.addError(problem);
            }
        }
    }

    /** Why the author may not save this definition's reads and write, or null. */
    @TestVisible
    private static String accessProblem(Rollup_Definition__c record) {
        if (!isAllowedTarget(record.Target_Object__c)) {
            return System.Label.Core_Rollups_ErrorTargetNotAllowed;
        }
        Schema.SObjectType targetType = SettingsService.typeByName(record.Target_Object__c);
        Schema.SObjectType sourceType = SettingsService.typeByName(record.Source_Object__c);
        if (targetType == null || sourceType == null) {
            // Not this check's question: the type check refuses or explains it.
            return null;
        }
        Map<String, Schema.SObjectField> targetFields = fieldMap(targetType);
        Schema.SObjectField target = String.isBlank(record.Target_Field__c)
            ? null
            : targetFields.get(record.Target_Field__c.trim().toLowerCase());
        if (target == null || !target.getDescribe().isUpdateable()) {
            return System.Label.Core_Rollups_ErrorTargetNotWritable;
        }
        if (!sourceType.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
            return System.Label.Core_Rollups_ErrorFieldNotReadable;
        }
        Map<String, Schema.SObjectField> sourceFields = fieldMap(sourceType);
        Set<String> read = new Set<String>();
        addIfSet(read, record.Source_Field__c);
        addIfSet(read, record.Order_By_Field__c);
        addIfSet(read, record.Fiscal_Date_Field__c);
        read.addAll(pathFields(record.Relationship_Path__c));
        for (String field : read) {
            if (!readable(sourceFields, field)) {
                return System.Label.Core_Rollups_ErrorFieldNotReadable;
            }
        }
        if (
            !filterReadable(sourceFields, record.Filter_JSON__c) ||
            !filterReadable(targetFields, record.Target_Filter_JSON__c)
        ) {
            return System.Label.Core_Rollups_ErrorFieldNotReadable;
        }
        return null;
    }

    /**
     * Whether a field an administrator sets changed: the name, the owner or a custom field, apart
     * from the engine's own `Last_Calculated__c` stamp, the one change that needs no permission.
     */
    private static Boolean changedBeyondEngine(Rollup_Definition__c record, SObject previous) {
        for (String field : record.getPopulatedFieldsAsMap().keySet()) {
            String name = field.toLowerCase();
            Boolean setByPeople = name.endsWith('__c') || name == 'name' || name == 'ownerid';
            if (!setByPeople || name.endsWith('last_calculated__c')) {
                continue;
            }
            if (record.get(field) != previous.get(field)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean readsOrWritesChanged(Rollup_Definition__c record, SObject previous) {
        for (Schema.SObjectField field : READ_OR_WRITE_FIELDS) {
            if (record.get(field) != previous.get(field)) {
                return true;
            }
        }
        return false;
    }

    /** The lookup on the source object that starts each branch of the path; tokens need none. */
    private static Set<String> pathFields(String path) {
        Set<String> fields = new Set<String>();
        if (String.isBlank(path)) {
            return fields;
        }
        try {
            for (RollupPath.Branch branch : RollupPath.parse(path).branches) {
                String first = branch.segments[0];
                if (!RollupPath.isToken(first)) {
                    fields.add(first);
                }
            }
        } catch (RollupPath.RollupPathException unreadable) {
            // The path check refuses an unreadable path; nothing is read through it.
            return fields;
        }
        return fields;
    }

    /** Every field a filter names is readable, one lookup away included. */
    private static Boolean filterReadable(
        Map<String, Schema.SObjectField> fields,
        String document
    ) {
        if (String.isBlank(document)) {
            return true;
        }
        Set<String> named;
        try {
            named = RollupFilterParser.fieldsOf(document);
        } catch (Exception unreadable) {
            // The filter check refuses an unreadable document; it reads nothing.
            return true;
        }
        for (String field : named) {
            if (field.contains('.') ? !parentReadable(fields, field) : !readable(fields, field)) {
                return false;
            }
        }
        return true;
    }

    private static Boolean readable(Map<String, Schema.SObjectField> fields, String name) {
        Schema.SObjectField field = fields.get(name.trim().toLowerCase());
        // An unknown name is the type check's question, not this one's.
        return field == null || field.getDescribe().isAccessible();
    }

    /** `Lookup__r.Field__c`: the lookup and the field on the record it points to are readable. */
    private static Boolean parentReadable(Map<String, Schema.SObjectField> fields, String path) {
        List<String> parts = path.split('\\.');
        for (Schema.SObjectField field : fields.values()) {
            Schema.DescribeFieldResult lookup = field.getDescribe();
            if (
                lookup.getType() == Schema.DisplayType.REFERENCE &&
                parts[0].equalsIgnoreCase(lookup.getRelationshipName())
            ) {
                if (!lookup.isAccessible() || parts.size() < 2) {
                    return false;
                }
                return readable(fieldMap(lookup.getReferenceTo()[0]), parts[1]);
            }
        }
        return true;
    }

    private static void addIfSet(Set<String> names, String name) {
        if (String.isNotBlank(name)) {
            names.add(name);
        }
    }

    private static Map<String, Schema.SObjectField> fieldMap(Schema.SObjectType type) {
        return type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
    }
}
