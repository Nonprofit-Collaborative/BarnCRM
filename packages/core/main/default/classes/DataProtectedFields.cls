/**
 * What data management may never write (plan Section 4.9, "Fields that can never be bulk updated
 * or imported over"; canonical model R-IT14; ADR-0080 `0080-import-load-one-object.md`): the
 * objects a load may not touch, decided by an allow-list rule over describe, and the fields the
 * package or the platform keeps.
 *
 * One class for every tool that writes many records at once: a one-object import (C-33) and
 * bulk update (C-35, through `BulkUpdateFields`). Everything is worked out at run time from describe and the Rollup
 * Definitions, so a rollup added later is protected without code, and Core names no object of
 * another package: a module names its own protected objects through `DataProtectionExtensions`.
 *
 * This decides protection, not access. Whether the running user may read, create or edit an
 * object or field is still asked of describe by the caller, and every write is in user mode.
 */
@NamespaceAccessible
public with sharing class DataProtectedFields {
    /**
     * The package's own bookkeeping objects, by local name: imports and the journal, the error
     * log, settings and setting changes, automation settings, rollup definitions, duplicate
     * dismissals and saved queries.
     */
    private static final Set<String> BOOKKEEPING = new Set<String>{
        'import_template__c',
        'import_batch__c',
        'import_row__c',
        'import_journal__c',
        'error_log__c',
        'barncrm_settings__c',
        'setting_change__c',
        'automation_setting__c',
        'rollup_definition__c',
        'duplicate_dismissal__c',
        'saved_query__c'
    };

    /** Household membership rows, written only through the household service (R-M5). */
    private static final String MEMBERSHIP = 'household_member__c';

    /**
     * Suffixes of objects that are never records a person loads: custom metadata, platform
     * events, big and external objects, and the share, history, feed and change event objects
     * the platform keeps beside another object (AccountShare, Widget__History).
     */
    private static final List<String> NEVER_LOADED_SUFFIXES = new List<String>{
        '__mdt',
        '__e',
        '__b',
        '__x',
        'share',
        'history',
        'feed',
        'changeevent'
    };

    /**
     * Salesforce setup and security objects, by name. Plan Section 4.9 leaves permission
     * management and the rest of Setup to Setup, and these are what could otherwise be assigned
     * or changed in bulk here, whatever describe says of them.
     */
    private static final Set<String> SETUP = new Set<String>{
        'user',
        'group',
        'groupmember',
        'queuesobject',
        'profile',
        'userrole',
        'permissionset',
        'permissionsetassignment',
        'permissionsetgroup',
        'permissionsetgroupcomponent',
        'permissionsetlicenseassign',
        'setupentityaccess',
        'objectpermissions',
        'fieldpermissions',
        'recordtype',
        'organization',
        'userlicense',
        'userpackagelicense',
        'networkmember'
    };

    /**
     * Fields the package keeps, by local name, on any object that has them: the batch tag
     * (R-IB3), the sample data marks, and what the household automation writes (R-H8, R-M5,
     * ADR-0044, R-AF2).
     */
    private static final Set<String> KEPT_BY_THE_PACKAGE = new Set<String>{
        'created_by_import_batch__c',
        'sample_data__c',
        'sample_data_key__c',
        'custom_name__c',
        'household_formal_greeting__c',
        'household_informal_greeting__c',
        'household_role__c',
        'member_count__c',
        'primary_contact__c',
        'primary_affiliation__c'
    };

    /** The suffix of every package field that says when something was last calculated. */
    private static final String LAST_CALCULATED_SUFFIX = 'last_calculated__c';

    /** Fields the platform keeps on every record. */
    private static final Set<String> SYSTEM_FIELDS = new Set<String>{
        'id',
        'isdeleted',
        'createddate',
        'createdbyid',
        'lastmodifieddate',
        'lastmodifiedbyid',
        'systemmodstamp',
        'lastactivitydate',
        'lastvieweddate',
        'lastreferenceddate'
    };

    /**
     * Set only by tests: the rollup target fields by object to read in place of the ones the
     * Rollup Builder module reports (`RollupEngineExtension.targetFieldsByObject`).
     */
    @TestVisible
    private static Map<String, Set<String>> targetsOverride;

    /**
     * Set only by tests: bookkeeping objects (lower-case local names) to treat as the org's own
     * records. Core's only custom object with an External ID is Duplicate_Dismissal__c, so the
     * one-object import tests load it as a stand-in for an org's own object.
     */
    @TestVisible
    private static Set<String> ordinaryForTest = new Set<String>();

    /** The protected field names of each object, worked out once per transaction. */
    private static final Map<Schema.SObjectType, Set<String>> PROTECTED_BY_TYPE = new Map<Schema.SObjectType, Set<String>>();

    /** The rollup target fields by object, read once per transaction. */
    private static Map<String, Set<String>> rollupTargets;

    /**
     * Why records of this object can never be loaded, or null when the allow-list rule admits it
     * (R-IT14): it must exist, be a custom object or a standard business record (searchable
     * and queryable), and be none of the setup and security objects, the package's own
     * bookkeeping, household membership rows, an object a module protects, a custom setting, or
     * a metadata, event, big, external, share, history, feed or change event object. Access is
     * the caller's question.
     */
    @NamespaceAccessible
    public static String objectRefusal(Schema.SObjectType type) {
        if (type == null) {
            return Label.Core_Data_ObjectUnknown;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        String name = described.getName().toLowerCase();
        String own = described.isCustom() ? ownLocalName(name) : null;
        List<String> plural = new List<String>{ described.getLabelPlural() };
        if (!described.isCustom() && SETUP.contains(name)) {
            return String.format(Label.Core_Data_ObjectSetup, plural);
        }
        if (isOwnBookkeeping(own) || DataProtectionExtensions.protectedObjects().contains(type)) {
            return String.format(Label.Core_Data_ObjectBookkeeping, plural);
        }
        if (own == MEMBERSHIP) {
            return String.format(Label.Core_Data_ObjectMembership, plural);
        }
        if (
            described.isCustomSetting() ||
            neverLoaded(name) ||
            !described.isQueryable() ||
            (!described.isCustom() && !described.isSearchable())
        ) {
            return String.format(Label.Core_Data_ObjectNotLoadable, plural);
        }
        return null;
    }

    /**
     * Whether this object is the package's own bookkeeping or one a module protects, which no
     * tool writes in bulk.
     */
    @NamespaceAccessible
    public static Boolean isBookkeeping(Schema.SObjectType type) {
        if (type == null) {
            return false;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        String own = described.isCustom() ? ownLocalName(described.getName().toLowerCase()) : null;
        return isOwnBookkeeping(own) || DataProtectionExtensions.protectedObjects().contains(type);
    }

    private static Boolean isOwnBookkeeping(String ownLocalName) {
        return ownLocalName != null &&
            BOOKKEEPING.contains(ownLocalName) &&
            !ordinaryForTest.contains(ownLocalName);
    }

    /** Whether this object is a Salesforce setup or security object, which Setup manages. */
    @NamespaceAccessible
    public static Boolean isSetup(Schema.SObjectType type) {
        if (type == null) {
            return false;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        return !described.isCustom() && SETUP.contains(described.getName().toLowerCase());
    }

    /**
     * Whether the package keeps this field of this object: a field the package writes itself, a
     * last calculated field, or a Rollup Definition target. The platform's own, formula and auto
     * number fields are not counted here; `isProtected` covers them too.
     */
    @NamespaceAccessible
    public static Boolean isKeptByThePackage(
        Schema.SObjectType type,
        Schema.DescribeFieldResult field
    ) {
        if (type == null || field == null) {
            return false;
        }
        String name = field.getName().toLowerCase();
        String own = field.isCustom() ? ownLocalName(name) : null;
        Set<String> targets = rollupTargetsOf(
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
        );
        return (own != null &&
            (KEPT_BY_THE_PACKAGE.contains(own) || own.endsWith(LAST_CALCULATED_SUFFIX))) ||
            targets.contains(name) ||
            targets.contains(localName(name));
    }

    /**
     * The fields of this object that are never written, by their API names in lower case: the
     * fields the platform keeps, formula and auto number fields, every Rollup Definition target
     * on it, and the fields the package keeps.
     */
    @NamespaceAccessible
    public static Set<String> fieldNames(Schema.SObjectType type) {
        if (type == null) {
            return new Set<String>();
        }
        if (!PROTECTED_BY_TYPE.containsKey(type)) {
            PROTECTED_BY_TYPE.put(type, computeProtected(type));
        }
        return PROTECTED_BY_TYPE.get(type);
    }

    /** Whether this field of this object is never written. */
    @NamespaceAccessible
    public static Boolean isProtected(Schema.SObjectType type, String fieldName) {
        return String.isNotBlank(fieldName) &&
            fieldNames(type).contains(fieldName.trim().toLowerCase());
    }

    /**
     * Whether this field is never written on this particular record: a household's name, which
     * the household naming patterns keep (R-H8). An organization's name is not protected.
     */
    @NamespaceAccessible
    public static Boolean isProtectedOnRecord(
        Schema.SObjectType type,
        String fieldName,
        Id recordTypeId
    ) {
        return type == Account.SObjectType &&
            'name'.equalsIgnoreCase(String.isBlank(fieldName) ? '' : fieldName.trim()) &&
            recordTypeId != null &&
            recordTypeId == HouseholdService.householdRecordTypeId();
    }

    private static Set<String> computeProtected(Schema.SObjectType type) {
        Set<String> result = new Set<String>();
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        Map<String, Schema.SObjectField> fields = described.fields.getMap();
        Set<String> targets = rollupTargetsOf(described.getName());
        for (String key : fields.keySet()) {
            Schema.DescribeFieldResult field = fields.get(key).getDescribe();
            String name = field.getName().toLowerCase();
            // The package's own fields only: a subscriber's field of the same local name is theirs.
            String own = field.isCustom() ? ownLocalName(name) : null;
            if (
                SYSTEM_FIELDS.contains(name) ||
                field.isCalculated() ||
                field.isAutoNumber() ||
                targets.contains(name) ||
                targets.contains(localName(name)) ||
                (own != null &&
                (KEPT_BY_THE_PACKAGE.contains(own) || own.endsWith(LAST_CALCULATED_SUFFIX)))
            ) {
                result.add(name);
            }
        }
        return result;
    }

    /**
     * The target fields of every Rollup Definition, active or not, on the object of this name,
     * in lower case, as written and without a namespace, so either form matches. The Rollup
     * Builder module reports them; without it there are none (ADR-NEXT).
     */
    private static Set<String> rollupTargetsOf(String objectName) {
        if (rollupTargets == null) {
            rollupTargets = new Map<String, Set<String>>();
            Map<String, Set<String>> reported = targetsOverride;
            if (reported == null) {
                reported = reportedRollupTargets();
            }
            for (String objectKey : reported.keySet()) {
                if (String.isBlank(objectKey) || reported.get(objectKey) == null) {
                    continue;
                }
                String target = localName(objectKey.trim().toLowerCase());
                if (!rollupTargets.containsKey(target)) {
                    rollupTargets.put(target, new Set<String>());
                }
                for (String fieldName : reported.get(objectKey)) {
                    if (String.isBlank(fieldName)) {
                        continue;
                    }
                    String field = fieldName.trim().toLowerCase();
                    rollupTargets.get(target).add(field);
                    rollupTargets.get(target).add(localName(field));
                }
            }
        }
        String key = localName(objectName.toLowerCase());
        return rollupTargets.containsKey(key) ? rollupTargets.get(key) : new Set<String>();
    }

    /**
     * What the Rollup Builder module reports, or nothing when it is absent or fails. A failing
     * module is logged and costs only its targets, as at every other engine seam caller.
     */
    private static Map<String, Set<String>> reportedRollupTargets() {
        try {
            RollupEngineExtension engine = RollupEngineExtensions.find();
            Map<String, Set<String>> reported = engine == null
                ? null
                : engine.targetFieldsByObject();
            return reported == null ? new Map<String, Set<String>>() : reported;
        } catch (Exception e) {
            ErrorLogger.log(e, 'DataProtectedFields.rollupTargetsOf');
            return new Map<String, Set<String>>();
        }
    }

    /**
     * A lower case API name without this package's namespace when it is the package's own, and
     * null when it belongs to another namespace. With no namespace, as today, every name is.
     */
    private static String ownLocalName(String lowerCaseName) {
        String prefix = NamespaceUtil.prefix().toLowerCase();
        if (String.isBlank(prefix)) {
            return lowerCaseName;
        }
        return lowerCaseName.startsWith(prefix) ? lowerCaseName.removeStart(prefix) : null;
    }

    /** A lower case API name without this package's namespace. */
    private static String localName(String lowerCaseName) {
        String prefix = NamespaceUtil.prefix().toLowerCase();
        return String.isNotBlank(prefix) && lowerCaseName.startsWith(prefix)
            ? lowerCaseName.removeStart(prefix)
            : lowerCaseName;
    }

    private static Boolean neverLoaded(String lowerCaseName) {
        for (String suffix : NEVER_LOADED_SUFFIXES) {
            if (lowerCaseName.endsWith(suffix)) {
                return true;
            }
        }
        return false;
    }
}
