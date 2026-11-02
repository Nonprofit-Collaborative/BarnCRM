/**
 * The Data Dictionary section of Org Optimizer (plan Section 6.1.1 item 13, D-154): one object
 * at a time, every field the person can see, as describe reports it. Describe only: no Tooling
 * API, no callout. The automation inventory (C-60, `getAutomation`) adds, on request, the Apex
 * triggers and record-triggered flows of an object from user-mode SOQL
 * (AutomationInventoryService); validation rules need the Tooling API and are not covered.
 * Fill rates are not counted here; the page asks
 * FieldUtilizationController for them, so there is one counting implementation and one set of
 * limits. Every method requires `Manage_BarnCRM_Settings`, like Field Utilization.
 *
 * What describe does not expose is left out: a field's description is metadata, not describe.
 */
public with sharing class DataDictionaryController {
    private static final String PERMISSION = 'Manage_BarnCRM_Settings';

    /** Longest picklist value text one field carries, to keep a response small. */
    @TestVisible
    private static final Integer MAX_PICKLIST_CHARS = 4000;

    /**
     * Core's own data objects, by name without a prefix, preselected in the picker. Each is
     * resolved through NamespaceUtil, so a subscriber's object of the same name never matches
     * and no prefix is written here. Once the namespace exists, every object of the package's
     * prefix is preselected too, modules included (Core names no module object). Account and
     * Contact are the commonly used standard objects.
     */
    private static final Set<String> DEFAULT_PACKAGED = new Set<String>{
        'Address__c',
        'Affiliation__c',
        'Duplicate_Dismissal__c',
        'Erasure__c',
        'Household_Member__c',
        'Import_Batch__c',
        'Import_Row__c',
        'Import_Template__c',
        'Relationship__c',
        'Saved_Query__c'
    };
    private static final Set<String> DEFAULT_STANDARD = new Set<String>{ 'account', 'contact' };

    /** Raised with a message the page shows as it is. */
    public class DataDictionaryException extends Exception {
    }

    /** One choice in the object picker. */
    public class Option {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
        /** Whether the picker starts with this object chosen. */
        @AuraEnabled
        public Boolean isDefault;
    }

    /** One field, as describe reports it. */
    public class FieldRow {
        @AuraEnabled
        public String fieldLabel;
        @AuraEnabled
        public String fieldName;
        @AuraEnabled
        public String dataType;
        /** Maximum characters, for text-like fields; null otherwise. */
        @AuraEnabled
        public Integer length;
        /** `precision,scale` for number fields; null otherwise. */
        @AuraEnabled
        public String precision;
        @AuraEnabled
        public Boolean required;
        @AuraEnabled
        public Boolean isUnique;
        @AuraEnabled
        public Boolean externalId;
        @AuraEnabled
        public Boolean isCustom;
        /** Active picklist values, separated by a semicolon and a space. */
        @AuraEnabled
        public String picklistValues;
        @AuraEnabled
        public String helpText;
        @AuraEnabled
        public String formula;
        /** The objects a lookup field points to, separated by a comma and a space. */
        @AuraEnabled
        public String relatedTo;
    }

    /** One object's fields. */
    public class ObjectDictionary {
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public Boolean isCustom;
        @AuraEnabled
        public List<FieldRow> fields = new List<FieldRow>();
    }

    /**
     * Every object the person may document, by label, with the default choices marked.
     * @return the picker's options
     */
    @AuraEnabled(cacheable=true)
    public static List<Option> listObjects() {
        try {
            requirePermission();
            Map<String, Option> byKey = new Map<String, Option>();
            for (
                Schema.DescribeSObjectResult described : FieldUtilizationService.offeredObjects()
            ) {
                Option option = new Option();
                option.value = described.getName();
                option.label = described.getLabel();
                option.isDefault = isDefault(described);
                byKey.put(option.label.toLowerCase() + '\u0000' + option.value, option);
            }
            List<String> keys = new List<String>(byKey.keySet());
            keys.sort();
            List<Option> options = new List<Option>();
            for (String key : keys) {
                options.add(byKey.get(key));
            }
            return options;
        } catch (Exception caught) {
            throw asUserError(caught, 'Data dictionary object list');
        }
    }

    /**
     * The fields of one object the person can see, sorted by label.
     * @param objectName the object's API name, as the picker offers it
     * @return the object and its visible fields
     */
    @AuraEnabled
    public static ObjectDictionary describeObject(String objectName) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            ObjectDictionary result = new ObjectDictionary();
            result.objectName = described.getName();
            result.objectLabel = described.getLabel();
            result.isCustom = described.isCustom();
            Map<String, Schema.DescribeFieldResult> byKey = new Map<String, Schema.DescribeFieldResult>();
            for (Schema.SObjectField token : described.fields.getMap().values()) {
                Schema.DescribeFieldResult field = token.getDescribe();
                if (field.isAccessible()) {
                    byKey.put(field.getLabel().toLowerCase() + '\u0000' + field.getName(), field);
                }
            }
            List<String> keys = new List<String>(byKey.keySet());
            keys.sort();
            for (String key : keys) {
                result.fields.add(toRow(byKey.get(key)));
            }
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Data dictionary describe');
        }
    }

    /** One Apex trigger or flow that runs on an object. */
    public class AutomationRow {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String objectName;
        /** ApexTrigger or Flow. */
        @AuraEnabled
        public String automationType;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String status;
        /** Trigger events, or a flow's kind and the point in the save it runs at. */
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public Integer apiVersion;
    }

    /** One object's automation, and which parts could not be read. */
    public class AutomationInventory {
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public List<AutomationRow> rows = new List<AutomationRow>();
        @AuraEnabled
        public Boolean triggersFailed = false;
        @AuraEnabled
        public Boolean flowsFailed = false;
        /** True when the triggers or the flows stopped at the most listed for one object. */
        @AuraEnabled
        public Boolean truncated = false;
    }

    /**
     * The Apex triggers and record-triggered flows of one object (C-60), read as the person with
     * user-mode SOQL. Validation rules, workflow rules and process builder criteria need the
     * Tooling API and are not covered; flows that no record triggers are not tied to an object.
     * @param objectName the object's API name, as the picker offers it
     * @return the object's triggers and flows
     */
    @AuraEnabled
    public static AutomationInventory getAutomation(String objectName) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            AutomationInventoryService.Result found = AutomationInventoryService.forObject(
                described
            );
            AutomationInventory result = new AutomationInventory();
            result.objectName = described.getName();
            result.objectLabel = described.getLabel();
            result.triggersFailed = found.triggersFailed;
            result.flowsFailed = found.flowsFailed;
            result.truncated = found.truncated;
            for (AutomationInventoryService.Item item : found.items) {
                AutomationRow row = new AutomationRow();
                row.key = result.objectName + '|' + item.automationType + '|' + item.apiName;
                row.objectLabel = result.objectLabel;
                row.objectName = result.objectName;
                row.automationType = item.automationType;
                row.name = item.name;
                row.apiName = item.apiName;
                row.status = item.status;
                row.detail = item.detail;
                row.apiVersion = item.apiVersion;
                result.rows.add(row);
            }
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Data dictionary automation inventory');
        }
    }

    private static Boolean isDefault(Schema.DescribeSObjectResult described) {
        String name = described.getName().toLowerCase();
        if (!described.isCustom()) {
            return DEFAULT_STANDARD.contains(name);
        }
        String prefix = NamespaceUtil.prefix().toLowerCase();
        if (!String.isBlank(prefix) && name.startsWith(prefix)) {
            return true;
        }
        for (String packagedName : DEFAULT_PACKAGED) {
            Schema.SObjectType packaged = NamespaceUtil.packagedObjectType(packagedName);
            if (packaged != null && packaged == described.getSObjectType()) {
                return true;
            }
        }
        return false;
    }

    private static FieldRow toRow(Schema.DescribeFieldResult field) {
        Schema.DisplayType type = field.getType();
        FieldRow row = new FieldRow();
        row.fieldLabel = field.getLabel();
        row.fieldName = field.getName();
        row.dataType = type.name().toLowerCase();
        row.length = field.getLength() > 0 ? field.getLength() : null;
        row.precision = field.getPrecision() > 0
            ? field.getPrecision() + (field.getScale() > 0 ? ',' + field.getScale() : '')
            : null;
        row.required = field.isCreateable() && !field.isNillable() && !field.isDefaultedOnCreate();
        row.isUnique = field.isUnique();
        row.externalId = field.isExternalId();
        row.isCustom = field.isCustom();
        row.helpText = field.getInlineHelpText();
        row.formula = field.isCalculated() ? field.getCalculatedFormula() : null;
        if (type == Schema.DisplayType.PICKLIST || type == Schema.DisplayType.MULTIPICKLIST) {
            row.picklistValues = picklistText(field);
        }
        if (type == Schema.DisplayType.REFERENCE) {
            List<String> targets = new List<String>();
            for (Schema.SObjectType target : field.getReferenceTo()) {
                targets.add(target.getDescribe(SObjectDescribeOptions.DEFERRED).getName());
            }
            row.relatedTo = String.join(targets, ', ');
        }
        return row;
    }

    private static String picklistText(Schema.DescribeFieldResult field) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : field.getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        String text = String.join(values, '; ');
        return text.length() > MAX_PICKLIST_CHARS ? text.left(MAX_PICKLIST_CHARS) : text;
    }

    private static Schema.DescribeSObjectResult requireObject(String objectName) {
        Schema.DescribeSObjectResult described;
        if (!String.isBlank(objectName)) {
            try {
                described = Schema.describeSObjects(
                    new List<String>{ objectName.trim() },
                    SObjectDescribeOptions.DEFERRED
                )[0];
            } catch (System.InvalidParameterValueException unknown) {
                described = null;
            }
        }
        if (
            described == null ||
            !FindController.isOffered(described) ||
            described.getSObjectType() == Field_Utilization_Snapshot__c.SObjectType
        ) {
            throw new DataDictionaryException(
                String.format(
                    System.Label.Core_DataDictionary_UnknownObject,
                    new List<Object>{ String.isBlank(objectName) ? '' : objectName }
                )
            );
        }
        return described;
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            throw new DataDictionaryException(System.Label.Core_DataDictionary_PermissionRequired);
        }
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        return UserErrors.wrap(
            caught,
            caught instanceof DataDictionaryException,
            context,
            System.Label.Core_DataDictionary_UnexpectedError
        );
    }
}
