/**
 * The fields of one object as the running user sees them, for the filter builder and Find.
 *
 * Everything here comes from describe calls made as the running user: an object the user cannot
 * query is refused, and a field the user cannot read is left out. That is what lets the filter
 * builder promise it never offers a field the user cannot see, and what lets a query compiler
 * take object and field names only from describe results (plan Section 4.9, ADR-0047). Core
 * names no object here: the object arrives as text, so the same catalog serves an org with or
 * without the standard objects (ADR-0013).
 */
public with sharing class QueryFieldCatalog {
    /** Raised when an object or field is not one the running user can see. */
    public class QueryFieldCatalogException extends Exception {
    }

    /** How many lookups a field path may cross (canonical model R-R2, parent fields). */
    public static final Integer MAX_PARENT_DEPTH = 2;

    /** Compound and binary types no filter, sort or grid can use. */
    private static final Set<Schema.DisplayType> NEVER_OFFERED = new Set<Schema.DisplayType>{
        Schema.DisplayType.ADDRESS,
        Schema.DisplayType.LOCATION,
        Schema.DisplayType.BASE64,
        Schema.DisplayType.COMPLEXVALUE,
        Schema.DisplayType.ANYTYPE
    };

    /**
     * Name endings of the platform's own tables: sharing, field history, feeds, change events
     * (standard ones such as AccountShare as well as custom ones), metadata types, platform
     * events, external and big objects.
     */
    private static final Set<String> SYSTEM_SUFFIXES = new Set<String>{
        'share',
        'history',
        'feed',
        'changeevent',
        '__mdt',
        '__e',
        '__x',
        '__b'
    };

    private static final Pattern NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$');

    /**
     * Describes already read in this transaction, by running user and lower-cased object name,
     * so one compile describes each object once however many paths cross it. Keyed by user
     * because what a user may read differs, and a test can run as several.
     */
    private static Map<String, Schema.DescribeSObjectResult> objectsRead = new Map<String, Schema.DescribeSObjectResult>();
    /** Each object's readable single-parent lookups by lower-cased relationship name. */
    private static Map<String, Map<String, Schema.DescribeFieldResult>> lookupsRead = new Map<String, Map<String, Schema.DescribeFieldResult>>();

    private static String cacheKey(String objectApiName) {
        return UserInfo.getUserId() + ':' + objectApiName.toLowerCase();
    }

    /**
     * Whether an object is one of the platform's own tables or settings rather than records
     * people keep, so Find offers it neither as a query's object nor as related records. One
     * rule for both lists.
     */
    public static Boolean isSystemObject(Schema.DescribeSObjectResult described) {
        if (described.isCustomSetting() || described.isDeprecatedAndHidden()) {
            return true;
        }
        String lowerName = described.getName().toLowerCase();
        for (String suffix : SYSTEM_SUFFIXES) {
            if (lowerName.endsWith(suffix)) {
                return true;
            }
        }
        return false;
    }

    /** One field, as the builder offers it. */
    public class FieldInfo {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        /** The describe type in lower case: string, picklist, double, currency, date, and so on. */
        @AuraEnabled
        public String dataType;
        @AuraEnabled
        public Boolean filterable;
        @AuraEnabled
        public Boolean sortable;
        /** Whether a summary may group by the field (SOQL GROUP BY). */
        @AuraEnabled
        public Boolean groupable;
        /** Whether a summary may total, or take the lowest or highest of, the field. */
        @AuraEnabled
        public Boolean aggregatable;
        /** The parent object of a lookup with exactly one parent type; empty otherwise. */
        @AuraEnabled
        public String referenceTo;
        /** The name a path uses to cross this lookup (`Household__r`), set with referenceTo. */
        @AuraEnabled
        public String relationshipName;
        @AuraEnabled
        public List<PicklistOption> picklistValues;
    }

    /** One active picklist value. */
    public class PicklistOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
    }

    /** One object and its fields, sorted by label. */
    public class ObjectInfo {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String labelPlural;
        @AuraEnabled
        public List<FieldInfo> fields;
    }

    /** What the filter builder and Find read. Cached per object in the browser. */
    @AuraEnabled(cacheable=true)
    public static ObjectInfo getObjectInfo(String objectApiName) {
        try {
            return describe(objectApiName);
        } catch (QueryFieldCatalogException refused) {
            AuraHandledException reported = new AuraHandledException(refused.getMessage());
            reported.setMessage(refused.getMessage());
            throw reported;
        }
    }

    /** The object and every field the running user can read on it. */
    public static ObjectInfo describe(String objectApiName) {
        Schema.DescribeSObjectResult objectDescribe = describeObject(objectApiName);
        ObjectInfo info = new ObjectInfo();
        info.apiName = objectDescribe.getName();
        info.label = objectDescribe.getLabel();
        info.labelPlural = objectDescribe.getLabelPlural();
        info.fields = new List<FieldInfo>();
        Map<String, FieldInfo> byLabel = new Map<String, FieldInfo>();
        for (Schema.SObjectField field : objectDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (!isOffered(fieldDescribe)) {
                continue;
            }
            FieldInfo fieldInfo = toFieldInfo(fieldDescribe);
            byLabel.put(fieldInfo.label.toLowerCase() + '\u0000' + fieldInfo.apiName, fieldInfo);
        }
        List<String> keys = new List<String>(byLabel.keySet());
        keys.sort();
        for (String key : keys) {
            info.fields.add(byLabel.get(key));
        }
        return info;
    }

    /**
     * The describe of an object the running user can query, or a refusal that says so. The
     * platform's own tables and settings (`isSystemObject`) are refused here too, not only left
     * out of the picker: Find, its export, Bulk Update and Bulk Delete, and every parent a field
     * path crosses come through this method, so a call made outside the page cannot reach an
     * object the page never offers.
     */
    public static Schema.DescribeSObjectResult describeObject(String objectApiName) {
        if (String.isBlank(objectApiName) || !NAME.matcher(objectApiName).matches()) {
            throw unknownObject(objectApiName);
        }
        String key = cacheKey(objectApiName);
        if (objectsRead.containsKey(key)) {
            return objectsRead.get(key);
        }
        List<Schema.DescribeSObjectResult> found;
        try {
            found = Schema.describeSObjects(
                new List<String>{ objectApiName },
                SObjectDescribeOptions.DEFERRED
            );
        } catch (InvalidParameterValueException missing) {
            throw unknownObject(objectApiName);
        }
        if (
            found.isEmpty() ||
            !found[0].isAccessible() ||
            !found[0].isQueryable() ||
            isSystemObject(found[0])
        ) {
            throw unknownObject(objectApiName);
        }
        objectsRead.put(key, found[0]);
        return found[0];
    }

    /**
     * Follows a field path such as `Household__r.Name` from an object, checking each step against
     * the running user's describe, and returns the field it ends on. A path may cross at most
     * MAX_PARENT_DEPTH lookups, each with exactly one parent type.
     */
    public static Schema.DescribeFieldResult resolvePath(String objectApiName, String path) {
        Schema.DescribeSObjectResult current = describeObject(objectApiName);
        List<String> segments = String.isBlank(path) ? new List<String>() : path.split('\\.');
        if (segments.isEmpty() || segments.size() > MAX_PARENT_DEPTH + 1) {
            throw unknownField(path);
        }
        for (Integer index = 0; index < segments.size() - 1; index++) {
            Schema.DescribeFieldResult lookup = lookupByRelationship(current, segments[index]);
            if (lookup == null) {
                throw unknownField(path);
            }
            current = describeObject(lookup.getReferenceTo()[0].getDescribe().getName());
        }
        String leafName = segments[segments.size() - 1];
        Schema.SObjectField leaf = NAME.matcher(leafName).matches()
            ? current.fields.getMap().get(leafName)
            : null;
        if (leaf == null || !isOffered(leaf.getDescribe())) {
            throw unknownField(path);
        }
        return leaf.getDescribe();
    }

    private static Schema.DescribeFieldResult lookupByRelationship(
        Schema.DescribeSObjectResult objectDescribe,
        String relationshipName
    ) {
        String key = cacheKey(objectDescribe.getName());
        Map<String, Schema.DescribeFieldResult> lookups = lookupsRead.get(key);
        if (lookups == null) {
            // Every field is looked at once per object, not once per path that crosses it.
            lookups = new Map<String, Schema.DescribeFieldResult>();
            for (Schema.SObjectField field : objectDescribe.fields.getMap().values()) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                String name = fieldDescribe.getRelationshipName();
                if (
                    name != null &&
                    fieldDescribe.getReferenceTo().size() == 1 &&
                    fieldDescribe.isAccessible() &&
                    !lookups.containsKey(name.toLowerCase())
                ) {
                    lookups.put(name.toLowerCase(), fieldDescribe);
                }
            }
            lookupsRead.put(key, lookups);
        }
        return relationshipName == null ? null : lookups.get(relationshipName.toLowerCase());
    }

    private static Boolean isOffered(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe.isAccessible() && !NEVER_OFFERED.contains(fieldDescribe.getType());
    }

    private static FieldInfo toFieldInfo(Schema.DescribeFieldResult fieldDescribe) {
        FieldInfo info = new FieldInfo();
        info.apiName = fieldDescribe.getName();
        info.label = fieldDescribe.getLabel();
        info.dataType = String.valueOf(fieldDescribe.getType()).toLowerCase();
        info.filterable = fieldDescribe.isFilterable();
        info.sortable = fieldDescribe.isSortable();
        info.groupable = fieldDescribe.isGroupable();
        info.aggregatable = fieldDescribe.isAggregatable();
        List<Schema.SObjectType> parents = fieldDescribe.getReferenceTo();
        if (parents.size() == 1 && fieldDescribe.getRelationshipName() != null) {
            info.referenceTo = parents[0].getDescribe().getName();
            info.relationshipName = fieldDescribe.getRelationshipName();
        }
        info.picklistValues = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                PicklistOption option = new PicklistOption();
                option.label = entry.getLabel();
                option.value = entry.getValue();
                info.picklistValues.add(option);
            }
        }
        return info;
    }

    private static QueryFieldCatalogException unknownObject(String objectApiName) {
        return new QueryFieldCatalogException(
            String.format(
                System.Label.Core_Filter_ErrorUnknownObject,
                new List<Object>{ String.valueOf(objectApiName) }
            )
        );
    }

    private static QueryFieldCatalogException unknownField(String path) {
        return new QueryFieldCatalogException(
            String.format(
                System.Label.Core_Filter_ErrorUnknownField,
                new List<Object>{ String.valueOf(path) }
            )
        );
    }
}
