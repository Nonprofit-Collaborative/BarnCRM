/**
 * Matching Logic on the Duplicate Matching tab (ADR-0139): the match sources in plain words,
 * the fields an object offers a new source, and "Try a value".
 *
 * Reading needs Manage BarnCRM Settings or Manage BarnCRM Metadata. Saving is not here: the
 * page saves through CustomMetadataManagerController, which validates a source with
 * MatchSourceService.validate, deploys it and needs Manage BarnCRM Metadata (ADR-0085,
 * ADR-0133).
 */
public with sharing class MatchSourceController {
    private static final String SETTINGS_PERMISSION = 'Manage_BarnCRM_Settings';
    private static final String METADATA_PERMISSION = 'Manage_BarnCRM_Metadata';
    /** The most records "Try a value" names of each kind. */
    private static final Integer MAX_NAMED = 20;

    public class View {
        @AuraEnabled
        public Boolean canEdit = false;
        @AuraEnabled
        public List<SourceView> sources = new List<SourceView>();
        @AuraEnabled
        public List<Choice> normalizations = new List<Choice>();
    }

    /** One source, with the labels of what it names where the org has them. */
    public class SourceView {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Boolean shipped;
        @AuraEnabled
        public Boolean active;
        /** False when the scan skips it here: object or field missing, or not readable. */
        @AuraEnabled
        public Boolean usable;
        @AuraEnabled
        public Map<String, String> values = new Map<String, String>();
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String valueFieldLabel;
        @AuraEnabled
        public String postalFieldLabel;
        @AuraEnabled
        public String parentFieldLabel;
        /** Person, Household, or both, from what the parent field points at. */
        @AuraEnabled
        public String linksTo;
    }

    /** The fields of an object a source can use. */
    public class ObjectView {
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public List<Choice> valueFields = new List<Choice>();
        @AuraEnabled
        public List<Choice> parentFields = new List<Choice>();
    }

    public class Choice {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;

        Choice(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /** What "Try a value" found. */
    public class TryResult {
        /** The value as it is compared, or null when it says too little to compare. */
        @AuraEnabled
        public String comparedAs;
        @AuraEnabled
        public List<Choice> records = new List<Choice>();
    }

    @AuraEnabled
    public static View getView() {
        requireReader();
        try {
            View view = new View();
            view.canEdit = FeatureManagement.checkPermission(METADATA_PERMISSION);
            for (Match_Source__mdt row : MatchSourceSelector.selectAllSources()) {
                view.sources.add(sourceView(row));
            }
            for (
                Schema.PicklistEntry entry : Match_Source__mdt.Normalization__c.getDescribe()
                    .getPicklistValues()
            ) {
                if (entry.isActive()) {
                    view.normalizations.add(
                        new Choice(normalizationText(entry.getValue()), entry.getValue())
                    );
                }
            }
            return view;
        } catch (Exception e) {
            throw logged(e);
        }
    }

    /** The text fields and person or household lookups of an object, by API name. */
    @AuraEnabled
    public static ObjectView describeObject(String objectName) {
        requireReader();
        Schema.SObjectType type = NamespaceUtil.objectType(objectName);
        if (type == null) {
            throw UserErrors.message(
                String.format(Label.Core_MatchSource_NoSuchObject, new List<Object>{ objectName })
            );
        }
        try {
            Schema.DescribeSObjectResult described = type.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );
            ObjectView view = new ObjectView();
            view.objectName = described.getLocalName();
            view.objectLabel = described.getLabel();
            for (Schema.SObjectField token : described.fields.getMap().values()) {
                Schema.DescribeFieldResult field = token.getDescribe();
                Choice choice = new Choice(
                    field.getLabel() + ' (' + field.getLocalName() + ')',
                    field.getLocalName()
                );
                if (MatchSourceService.isMatchableText(field)) {
                    view.valueFields.add(choice);
                } else if (!MatchSourceService.parentObjectsOf(field).isEmpty()) {
                    view.parentFields.add(choice);
                }
            }
            sortByLabel(view.valueFields);
            sortByLabel(view.parentFields);
            return view;
        } catch (Exception e) {
            throw logged(e);
        }
    }

    /**
     * The people and households holding a value on a source given as its values (saved or not
     * yet), found as the scan would find them. The source is checked as a save would be.
     */
    @AuraEnabled
    public static TryResult tryValue(
        String label,
        Map<String, String> values,
        String value,
        String postal
    ) {
        requireReader();
        Map<String, Object> given = new Map<String, Object>();
        if (values != null) {
            given.putAll(values);
        }
        try {
            MatchSourceService.validate(given);
            MatchSourceService.Source source = MatchSourceService.sourceFrom(label, given);
            if (source == null) {
                throw new CustomMetadataManagerService.CustomMetadataManagerException(
                    System.Label.Core_MatchLogic_NotUsable
                );
            }
            TryResult result = new TryResult();
            result.comparedAs = MatchSourceService.key(source.normalization, value, postal);
            Map<Schema.SObjectType, Set<Id>> holders = MatchSourceService.holdersOfValue(
                source,
                value,
                postal
            );
            for (Schema.SObjectType target : holders.keySet()) {
                String kind = target == Contact.SObjectType
                    ? System.Label.Core_Duplicates_ObjectPerson
                    : System.Label.Core_Duplicates_ObjectHousehold;
                for (
                    SObject record : MatchSourceSelector.namesOf(
                        target,
                        holders.get(target),
                        MAX_NAMED
                    )
                ) {
                    result.records.add(
                        new Choice(kind + ': ' + (String) record.get('Name'), record.Id)
                    );
                }
            }
            return result;
        } catch (Exception e) {
            throw logged(e);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static SourceView sourceView(Match_Source__mdt row) {
        SourceView view = new SourceView();
        view.developerName = row.DeveloperName;
        view.label = row.MasterLabel;
        view.shipped = row.Is_Shipped__c == true;
        view.active = row.Active__c == true;
        view.values.put('Object_Name__c', row.Object_Name__c);
        view.values.put('Value_Field__c', row.Value_Field__c);
        view.values.put('Postal_Code_Field__c', row.Postal_Code_Field__c);
        view.values.put('Parent_Field__c', row.Parent_Field__c);
        view.values.put('Normalization__c', row.Normalization__c);
        // A Map<String, Object> cannot be built from a Map<String, String> in one step.
        Map<String, Object> asGiven = new Map<String, Object>();
        for (String field : view.values.keySet()) {
            asGiven.put(field, view.values.get(field));
        }
        view.usable = MatchSourceService.sourceFrom(row.MasterLabel, asGiven) != null;
        Schema.SObjectType type = NamespaceUtil.objectType(row.Object_Name__c);
        if (type == null) {
            return view;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        view.objectLabel = described.getLabel();
        Map<String, Schema.SObjectField> fields = described.fields.getMap();
        view.valueFieldLabel = labelOf(fields, row.Value_Field__c);
        view.postalFieldLabel = labelOf(fields, row.Postal_Code_Field__c);
        view.parentFieldLabel = labelOf(fields, row.Parent_Field__c);
        Schema.SObjectField parent = MatchSourceService.field(fields, row.Parent_Field__c);
        if (parent != null) {
            view.linksTo = linksTo(MatchSourceService.parentObjectsOf(parent.getDescribe()));
        }
        return view;
    }

    private static String labelOf(Map<String, Schema.SObjectField> fields, String name) {
        Schema.SObjectField token = MatchSourceService.field(fields, name);
        return token == null ? null : token.getDescribe().getLabel();
    }

    /** A contact or an Individual is a person; an account is a household or person account. */
    @TestVisible
    private static String linksTo(Set<String> parents) {
        Boolean person = parents.contains('Contact') || parents.contains('Individual');
        Boolean household = parents.contains('Account');
        if (person && household) {
            return Label.Core_MatchLogic_LinksEither;
        }
        if (person) {
            return Label.Core_MatchLogic_LinksPerson;
        }
        return household ? Label.Core_MatchLogic_LinksHousehold : null;
    }

    @TestVisible
    private static String normalizationText(String normalization) {
        if (normalization == MatchSourceService.EMAIL) {
            return Label.Core_MatchLogic_CompareEmail;
        }
        if (normalization == MatchSourceService.PHONE) {
            return Label.Core_MatchLogic_ComparePhone;
        }
        return Label.Core_MatchLogic_CompareAddress;
    }

    private static void sortByLabel(List<Choice> choices) {
        Map<String, Choice> byLabel = new Map<String, Choice>();
        for (Choice choice : choices) {
            byLabel.put(choice.label.toLowerCase() + '|' + choice.value, choice);
        }
        List<String> keys = new List<String>(byLabel.keySet());
        keys.sort();
        choices.clear();
        for (String key : keys) {
            choices.add(byLabel.get(key));
        }
    }

    private static void requireReader() {
        if (
            !FeatureManagement.checkPermission(SETTINGS_PERMISSION) &&
            !FeatureManagement.checkPermission(METADATA_PERMISSION)
        ) {
            throw UserErrors.message(Label.Core_MatchLogic_PermissionRequired);
        }
    }

    /** A refusal the service explains is shown as it is; anything else is logged first. */
    private static AuraHandledException logged(Exception e) {
        return UserErrors.wrap(
            e,
            e instanceof CustomMetadataManagerService.CustomMetadataManagerException,
            'Duplicate Matching: matching logic',
            Label.Core_CmdtManager_LoadError
        );
    }
}
