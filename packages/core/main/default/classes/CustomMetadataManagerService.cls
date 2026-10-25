/**
 * The custom metadata manager (plan Section 6.1 item 9): lets an administrator add, edit and
 * archive the organization's own rows of the custom metadata types BarnCRM reads directly,
 * and never a row the package ships.
 *
 * Only the types in the registry below can be changed, with only the fields named there
 * (ADR-0085, 0085-custom-metadata-manager-edits-only-types-read-directly.md; canonical model
 * R-D2). Saving is a metadata deployment: it is validated here, built into a container, and
 * enqueued; CustomMetadataDeployCallback records how it ended.
 */
public with sharing class CustomMetadataManagerService {
    public class CustomMetadataManagerException extends Exception {
    }

    /** The prefix of every DeveloperName this manager creates; no shipped row uses it. */
    public static final String ORG_PREFIX = 'Org_';
    public static final String SHIPPED_FIELD = 'Is_Shipped__c';
    private static final Integer NAME_LIMIT = 40;

    /** Starts a deployment. Tests replace it, because Metadata.Operations cannot deploy there. */
    public interface Deployer {
        Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback);
    }

    private class PlatformDeployer implements Deployer {
        public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            return Metadata.Operations.enqueueDeployment(container, callback);
        }
    }

    @TestVisible
    private static Deployer deployer = new PlatformDeployer();

    /** One editable type: what may be changed on it and what has to hold before it is. */
    public class EditableType {
        public Schema.SObjectType type;
        public String label;
        public String help;
        public List<Schema.SObjectField> fields;
        public Set<Schema.SObjectField> required;
        public Schema.SObjectField archiveField;
        public Schema.SObjectField uniqueField;
        /** A field whose value has to be an active choice of a picklist on choicesObject. */
        public Map<Schema.SObjectField, Schema.SObjectField> choicesFrom;
        public Schema.SObjectType choicesObject;
        /** A shipped row may be archived and restored, and nothing else changed (ADR-NEXT). */
        public Boolean shippedArchivable = false;
        /** Checks a save against the org beyond the field rules here, or null. */
        public RowValidator validator;
    }

    /** A type's own check of a save; throws CustomMetadataManagerException to refuse it. */
    public interface RowValidator {
        void validate(Map<String, Object> values);
    }

    /** What the page draws for one type. */
    public class TypeView {
        @AuraEnabled
        public String typeName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String help;
        @AuraEnabled
        public Boolean shippedArchivable;
        @AuraEnabled
        public List<FieldView> fields;
        @AuraEnabled
        public List<RowView> rows;
    }

    public class FieldView {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Boolean required;
        @AuraEnabled
        public Boolean isLong;
        @AuraEnabled
        public Integer maxLength;
        @AuraEnabled
        public List<Choice> choices;
    }

    public class Choice {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
    }

    public class RowView {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Boolean shipped;
        @AuraEnabled
        public Boolean archived;
        @AuraEnabled
        public Map<String, String> values;
    }

    /** A save from the page. A blank developer name adds a row. */
    public class RowInput {
        @AuraEnabled
        public String developerName { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public Map<String, String> values { get; set; }
    }

    // ------------------------------------------------------------------ the registry

    public static Map<String, EditableType> registry() {
        EditableType relationshipTypes = new EditableType();
        relationshipTypes.type = Relationship_Type__mdt.SObjectType;
        relationshipTypes.label = System.Label.Core_CmdtManager_RelationshipTypes;
        relationshipTypes.help = System.Label.Core_CmdtManager_RelationshipTypesHelp;
        relationshipTypes.fields = new List<Schema.SObjectField>{
            Relationship_Type__mdt.Type__c,
            Relationship_Type__mdt.Reciprocal_Type__c,
            Relationship_Type__mdt.Description__c
        };
        relationshipTypes.required = new Set<Schema.SObjectField>{
            Relationship_Type__mdt.Type__c,
            Relationship_Type__mdt.Reciprocal_Type__c
        };
        relationshipTypes.archiveField = Relationship_Type__mdt.Active__c;
        relationshipTypes.uniqueField = Relationship_Type__mdt.Type__c;
        relationshipTypes.choicesFrom = new Map<Schema.SObjectField, Schema.SObjectField>{
            Relationship_Type__mdt.Type__c => Relationship__c.Type__c,
            Relationship_Type__mdt.Reciprocal_Type__c => Relationship__c.Type__c
        };
        relationshipTypes.choicesObject = Relationship__c.SObjectType;

        EditableType matchSources = new EditableType();
        matchSources.type = Match_Source__mdt.SObjectType;
        matchSources.label = System.Label.Core_CmdtManager_MatchSources;
        matchSources.help = System.Label.Core_CmdtManager_MatchSourcesHelp;
        matchSources.fields = new List<Schema.SObjectField>{
            Match_Source__mdt.Object_Name__c,
            Match_Source__mdt.Value_Field__c,
            Match_Source__mdt.Postal_Code_Field__c,
            Match_Source__mdt.Parent_Field__c,
            Match_Source__mdt.Normalization__c
        };
        matchSources.required = new Set<Schema.SObjectField>{
            Match_Source__mdt.Object_Name__c,
            Match_Source__mdt.Value_Field__c,
            Match_Source__mdt.Parent_Field__c,
            Match_Source__mdt.Normalization__c
        };
        matchSources.archiveField = Match_Source__mdt.Active__c;
        matchSources.choicesFrom = new Map<Schema.SObjectField, Schema.SObjectField>{
            Match_Source__mdt.Normalization__c => Match_Source__mdt.Normalization__c
        };
        matchSources.choicesObject = Match_Source__mdt.SObjectType;
        matchSources.shippedArchivable = true;
        matchSources.validator = new MatchSourceService.Validator();

        return new Map<String, EditableType>{
            nameOf(relationshipTypes) => relationshipTypes,
            nameOf(matchSources) => matchSources
        };
    }

    // ------------------------------------------------------------------ reading

    public static List<TypeView> getTypes() {
        List<TypeView> views = new List<TypeView>();
        for (EditableType editable : registry().values()) {
            views.add(viewOf(editable));
        }
        return views;
    }

    private static TypeView viewOf(EditableType editable) {
        TypeView view = new TypeView();
        view.typeName = nameOf(editable);
        view.label = editable.label;
        view.help = editable.help;
        view.shippedArchivable = editable.shippedArchivable;
        view.fields = new List<FieldView>();
        for (Schema.SObjectField token : editable.fields) {
            Schema.DescribeFieldResult field = token.getDescribe();
            FieldView fieldView = new FieldView();
            fieldView.apiName = field.getLocalName();
            fieldView.label = field.getLabel();
            fieldView.required = editable.required.contains(token);
            fieldView.isLong = field.getType() == Schema.DisplayType.TEXTAREA;
            fieldView.maxLength = field.getLength();
            if (editable.choicesFrom.containsKey(token)) {
                fieldView.choices = choicesOf(editable.choicesFrom.get(token));
            }
            view.fields.add(fieldView);
        }
        view.rows = new List<RowView>();
        for (CustomMetadataManagerSelector.StoredRow stored : rowsOf(editable)) {
            RowView row = new RowView();
            row.developerName = stored.developerName;
            row.label = stored.label;
            row.shipped = isShipped(stored);
            row.archived = !isActive(editable, stored);
            row.values = new Map<String, String>();
            for (Schema.SObjectField token : editable.fields) {
                String name = token.getDescribe().getLocalName();
                Object value = stored.values.get(name);
                row.values.put(name, value == null ? null : String.valueOf(value));
            }
            view.rows.add(row);
        }
        return view;
    }

    private static List<Choice> choicesOf(Schema.SObjectField picklist) {
        List<Choice> choices = new List<Choice>();
        for (Schema.PicklistEntry entry : picklist.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                Choice choice = new Choice();
                choice.label = entry.getLabel();
                choice.value = entry.getValue();
                choices.add(choice);
            }
        }
        return choices;
    }

    // ------------------------------------------------------------------ saving

    /** Validates a save, enqueues it, and returns the deployment Id the page waits on. */
    public static Id save(String typeName, RowInput input) {
        EditableType editable = editableType(typeName);
        List<CustomMetadataManagerSelector.StoredRow> rows = rowsOf(editable);
        CustomMetadataManagerSelector.StoredRow existing = null;
        if (input != null && String.isNotBlank(input.developerName)) {
            existing = changeableRow(editable, rows, input.developerName);
        }
        Boolean active = existing == null || isActive(editable, existing);
        Map<String, Object> values = validated(editable, rows, input, existing, active);
        String developerName = existing != null
            ? existing.developerName
            : newDeveloperName(input.label, rows);
        return enqueue(editable, developerName, input.label.trim(), values, existing);
    }

    /** Archives a row (it stops being used) or restores it. */
    public static Id setArchived(String typeName, String developerName, Boolean archived) {
        EditableType editable = editableType(typeName);
        List<CustomMetadataManagerSelector.StoredRow> rows = rowsOf(editable);
        if (editable.shippedArchivable) {
            CustomMetadataManagerSelector.StoredRow found = rowNamed(rows, developerName);
            if (isShipped(found)) {
                return setShippedArchived(editable, found, archived != true);
            }
        }
        CustomMetadataManagerSelector.StoredRow existing = changeableRow(
            editable,
            rows,
            developerName
        );
        RowInput input = new RowInput();
        input.developerName = existing.developerName;
        input.label = existing.label;
        input.values = new Map<String, String>();
        for (Schema.SObjectField token : editable.fields) {
            String name = token.getDescribe().getLocalName();
            Object value = existing.values.get(name);
            input.values.put(name, value == null ? null : String.valueOf(value));
        }
        Boolean active = archived != true;
        Map<String, Object> values = validated(editable, rows, input, existing, active);
        return enqueue(editable, existing.developerName, existing.label, values, existing);
    }

    /**
     * Archives or restores a shipped row of a type that allows it (ADR-NEXT): every other value
     * is deployed exactly as shipped and the row stays marked shipped. A packaged row's name
     * carries the package prefix once the namespace exists.
     */
    private static Id setShippedArchived(
        EditableType editable,
        CustomMetadataManagerSelector.StoredRow shipped,
        Boolean active
    ) {
        Map<String, Object> values = new Map<String, Object>();
        for (Schema.SObjectField token : editable.fields) {
            String name = token.getDescribe().getLocalName();
            values.put(name, shipped.values.get(name));
        }
        values.put(editable.archiveField.getDescribe().getLocalName(), active);
        values.put(SHIPPED_FIELD, true);
        return enqueue(
            editable,
            NamespaceUtil.qualify(shipped.developerName),
            shipped.label,
            values,
            shipped
        );
    }

    /**
     * Checks a save and returns the values to deploy, archive field and shipped marker
     * included, by local field name. Throws with a message the page shows as it is.
     */
    @TestVisible
    private static Map<String, Object> validated(
        EditableType editable,
        List<CustomMetadataManagerSelector.StoredRow> rows,
        RowInput input,
        CustomMetadataManagerSelector.StoredRow existing,
        Boolean active
    ) {
        if (input == null || String.isBlank(input.label)) {
            throw new CustomMetadataManagerException(System.Label.Core_CmdtManager_NameRequired);
        }
        if (input.label.trim().length() > NAME_LIMIT) {
            throw new CustomMetadataManagerException(System.Label.Core_CmdtManager_NameTooLong);
        }
        Map<String, String> given = input.values == null ? new Map<String, String>() : input.values;
        Map<String, Object> values = new Map<String, Object>();
        for (Schema.SObjectField token : editable.fields) {
            Schema.DescribeFieldResult field = token.getDescribe();
            String value = given.get(field.getLocalName());
            value = String.isBlank(value) ? null : value.trim();
            if (value == null && editable.required.contains(token)) {
                throw new CustomMetadataManagerException(
                    String.format(
                        System.Label.Core_CmdtManager_FieldRequired,
                        new List<Object>{ field.getLabel() }
                    )
                );
            }
            if (value != null && value.length() > field.getLength()) {
                throw new CustomMetadataManagerException(
                    String.format(
                        System.Label.Core_CmdtManager_FieldTooLong,
                        new List<Object>{ field.getLabel(), field.getLength() }
                    )
                );
            }
            if (value != null && editable.choicesFrom.containsKey(token)) {
                requireChoice(value, editable.choicesFrom.get(token), editable.choicesObject);
            }
            values.put(field.getLocalName(), value);
        }
        // An archived row is not used, so archiving one never waits on the org's checks.
        if (active && editable.validator != null) {
            editable.validator.validate(values);
        }
        if (active && editable.uniqueField != null) {
            requireUnique(editable, rows, values, existing);
        }
        values.put(editable.archiveField.getDescribe().getLocalName(), active);
        values.put(SHIPPED_FIELD, false);
        return values;
    }

    private static void requireChoice(
        String value,
        Schema.SObjectField picklist,
        Schema.SObjectType owner
    ) {
        for (Choice choice : choicesOf(picklist)) {
            // Exact case: the reciprocal is written into a restricted picklist as it is here.
            if (choice.value.equals(value)) {
                return;
            }
        }
        throw new CustomMetadataManagerException(
            String.format(
                System.Label.Core_CmdtManager_NotAChoice,
                new List<Object>{
                    value,
                    picklist.getDescribe().getLabel(),
                    owner.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel()
                }
            )
        );
    }

    private static void requireUnique(
        EditableType editable,
        List<CustomMetadataManagerSelector.StoredRow> rows,
        Map<String, Object> values,
        CustomMetadataManagerSelector.StoredRow existing
    ) {
        String name = editable.uniqueField.getDescribe().getLocalName();
        String wanted = (String) values.get(name);
        for (CustomMetadataManagerSelector.StoredRow row : rows) {
            Boolean sameRow = existing != null && row.developerName == existing.developerName;
            Object held = row.values.get(name);
            if (
                !sameRow &&
                isActive(editable, row) &&
                held != null &&
                wanted != null &&
                String.valueOf(held).equalsIgnoreCase(wanted)
            ) {
                throw new CustomMetadataManagerException(
                    String.format(
                        System.Label.Core_CmdtManager_DuplicateActive,
                        new List<Object>{ wanted, row.label }
                    )
                );
            }
        }
    }

    // ------------------------------------------------------------------ building and enqueuing

    /** The deployment for one row: every editable field, the archive field, not shipped. */
    @TestVisible
    private static Metadata.DeployContainer buildContainer(
        EditableType editable,
        String developerName,
        String label,
        Map<String, Object> values
    ) {
        Metadata.CustomMetadata record = new Metadata.CustomMetadata();
        record.fullName =
            NamespaceUtil.prefix() +
            nameOf(editable).removeEnd('__mdt') +
            '.' +
            developerName;
        record.label = label;
        record.protected_x = false;
        List<String> names = new List<String>(values.keySet());
        names.sort();
        for (String name : names) {
            Metadata.CustomMetadataValue value = new Metadata.CustomMetadataValue();
            value.field = NamespaceUtil.qualify(name);
            value.value = values.get(name);
            record.values.add(value);
        }
        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(record);
        return container;
    }

    private static Id enqueue(
        EditableType editable,
        String developerName,
        String label,
        Map<String, Object> values,
        CustomMetadataManagerSelector.StoredRow existing
    ) {
        String rowName = nameOf(editable).removeEnd('__mdt') + '.' + developerName;
        Map<String, Object> before = null;
        if (existing != null) {
            before = new Map<String, Object>(existing.values);
            before.put('Label', existing.label);
        }
        Map<String, Object> after = new Map<String, Object>(values);
        after.put('Label', label);
        CustomMetadataDeployCallback callback = new CustomMetadataDeployCallback(
            rowName,
            label,
            before == null ? null : JSON.serialize(before),
            JSON.serialize(after),
            UserInfo.getUserId()
        );
        Metadata.DeployContainer container = buildContainer(editable, developerName, label, values);
        try {
            return deployer.deploy(container, callback);
        } catch (Exception refused) {
            ErrorLogger.log(refused, CustomMetadataDeployCallback.ERROR_CONTEXT);
            throw new CustomMetadataManagerException(System.Label.Core_CmdtManager_DeployRefused);
        }
    }

    /**
     * A DeveloperName for a new row: the prefix, then the name with every run of characters a
     * DeveloperName cannot hold turned into one underscore, then a short random code.
     *
     * The code is what keeps two adds of the same name apart while the first is still
     * deploying (ADMIN-22): the rows read here are only the deployed ones, so a name worked out
     * from them alone would be the same twice, and the second deployment would overwrite the
     * first.
     */
    @TestVisible
    private static String newDeveloperName(
        String label,
        List<CustomMetadataManagerSelector.StoredRow> rows
    ) {
        String body = label.trim().replaceAll('[^A-Za-z0-9]+', '_').removeStart('_').removeEnd('_');
        if (String.isBlank(body)) {
            body = 'Row';
        }
        String base = (ORG_PREFIX + body).left(NAME_LIMIT - CODE_LENGTH - 1).removeEnd('_');
        Set<String> taken = new Set<String>();
        for (CustomMetadataManagerSelector.StoredRow row : rows) {
            taken.add(row.developerName.toLowerCase());
        }
        String candidate;
        do {
            candidate = base + '_' + randomCode();
        } while (taken.contains(candidate.toLowerCase()));
        return candidate;
    }

    private static final Integer CODE_LENGTH = 4;
    private static final String CODE_CHARACTERS = 'abcdefghijkmnpqrstuvwxyz23456789';

    private static String randomCode() {
        String code = '';
        for (Integer i = 0; i < CODE_LENGTH; i++) {
            Integer index = Math.abs(Math.mod(Crypto.getRandomInteger(), CODE_CHARACTERS.length()));
            code += CODE_CHARACTERS.substring(index, index + 1);
        }
        return code;
    }

    // ------------------------------------------------------------------ helpers

    private static EditableType editableType(String typeName) {
        EditableType editable = String.isBlank(typeName) ? null : registry().get(typeName);
        if (editable == null) {
            throw new CustomMetadataManagerException(System.Label.Core_CmdtManager_UnknownType);
        }
        return editable;
    }

    private static CustomMetadataManagerSelector.StoredRow changeableRow(
        EditableType editable,
        List<CustomMetadataManagerSelector.StoredRow> rows,
        String developerName
    ) {
        CustomMetadataManagerSelector.StoredRow row = rowNamed(rows, developerName);
        if (isShipped(row)) {
            throw new CustomMetadataManagerException(
                String.format(
                    System.Label.Core_CmdtManager_ShippedReadOnly,
                    new List<Object>{ row.label }
                )
            );
        }
        return row;
    }

    private static CustomMetadataManagerSelector.StoredRow rowNamed(
        List<CustomMetadataManagerSelector.StoredRow> rows,
        String developerName
    ) {
        for (CustomMetadataManagerSelector.StoredRow row : rows) {
            if (row.developerName == developerName) {
                return row;
            }
        }
        throw new CustomMetadataManagerException(System.Label.Core_CmdtManager_RecordNotFound);
    }

    private static List<CustomMetadataManagerSelector.StoredRow> rowsOf(EditableType editable) {
        List<String> names = new List<String>();
        for (Schema.SObjectField token : editable.fields) {
            names.add(token.getDescribe().getLocalName());
        }
        names.add(editable.archiveField.getDescribe().getLocalName());
        names.add(SHIPPED_FIELD);
        return CustomMetadataManagerSelector.selectRows(editable.type, names);
    }

    private static Boolean isShipped(CustomMetadataManagerSelector.StoredRow row) {
        return isTrue(row.values.get(SHIPPED_FIELD));
    }

    private static Boolean isActive(
        EditableType editable,
        CustomMetadataManagerSelector.StoredRow row
    ) {
        return isTrue(row.values.get(editable.archiveField.getDescribe().getLocalName()));
    }

    private static Boolean isTrue(Object value) {
        return value instanceof Boolean && (Boolean) value;
    }

    /** The type's API name without a namespace, which is how the page and the registry name it. */
    private static String nameOf(EditableType editable) {
        return editable.type.getDescribe(SObjectDescribeOptions.DEFERRED).getLocalName();
    }
}
