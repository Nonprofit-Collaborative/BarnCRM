/**
 * Saved Super Transform step lists (C-50f1, canonical model Section 29P): a named, org-wide
 * definition of an object, a filter and the changes, kept as one version 1 JSON document in
 * `Saved_Transform__c.Definition_JSON__c`.
 *
 *     { "version": 1, "object": "Contact", "filter": { ...Find filter document... },
 *       "changes": [ { "field": "Phone", "action": "transform", "transforms": [ ... ] } ] }
 *
 * A save checks the document's shape and its steps, never the records: loading a list only fills
 * the page in, and a run still compiles the query, checks every field and saves every record as
 * the person who runs it. Every read and write is in user mode, so the object permissions of
 * BarnCRM Bulk Update (read, create, edit, delete) are what grant access; the sharing model is
 * public read and write, so every user of the tool sees every list.
 */
public with sharing class SavedTransformService {
    public static final Integer DOCUMENT_VERSION = 1;
    public static final Integer MAX_NAME = 80;
    /** The longest document stored, below the field's 131,072 characters. */
    public static final Integer MAX_DOCUMENT = 100000;
    /** The most lists read for the picker. */
    public static final Integer MAX_LISTS = 200;

    private static final Set<String> ACTIONS = new Set<String>{
        BulkUpdateService.ACTION_SET,
        BulkUpdateService.ACTION_CLEAR,
        BulkUpdateService.ACTION_COPY,
        BulkUpdateService.ACTION_TRANSFORM
    };

    /** One list in the picker. */
    public class ListEntry {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String objectName;
        /** The object's label, or its API name when the org no longer has it. */
        @AuraEnabled
        public String objectLabel;
    }

    /** One list with its document, for loading. */
    public class SavedList {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String definitionJson;
    }

    /** Every saved list, by name. */
    public static List<ListEntry> listAll() {
        List<ListEntry> entries = new List<ListEntry>();
        for (Saved_Transform__c saved : [
            SELECT Id, Name, Object_Name__c
            FROM Saved_Transform__c
            WITH USER_MODE
            ORDER BY Name
            LIMIT :MAX_LISTS
        ]) {
            ListEntry entry = new ListEntry();
            entry.recordId = saved.Id;
            entry.name = saved.Name;
            entry.objectName = saved.Object_Name__c;
            entry.objectLabel = objectLabel(saved.Object_Name__c);
            entries.add(entry);
        }
        return entries;
    }

    /** One list with its document. */
    public static SavedList load(Id recordId) {
        return toView(find(recordId));
    }

    /** Saves a new list; the name must be new and the document must pass the checks. */
    public static SavedList save(String name, String definitionJson) {
        String cleaned = cleanName(name);
        String objectName = checkDefinition(definitionJson);
        requireFreeName(cleaned, null);
        Saved_Transform__c saved = new Saved_Transform__c(
            Name = cleaned,
            Object_Name__c = objectName,
            Definition_JSON__c = definitionJson
        );
        insert as user saved;
        return toView(saved);
    }

    /** Gives a list a new name; its document is untouched. */
    public static SavedList rename(Id recordId, String name) {
        Saved_Transform__c saved = find(recordId);
        String cleaned = cleanName(name);
        requireFreeName(cleaned, saved.Id);
        saved.Name = cleaned;
        update as user saved;
        return toView(saved);
    }

    /** Deletes a list. */
    public static void remove(Id recordId) {
        Saved_Transform__c saved = find(recordId);
        delete as user saved;
    }

    /**
     * Checks a document and returns the API name of its object. Refuses a document that is not
     * version 1 JSON, names an object a bulk update may not write, holds more changes than one
     * run allows, or has a change whose steps DataTransform names a problem with.
     */
    public static String checkDefinition(String definitionJson) {
        if (String.isBlank(definitionJson) || definitionJson.length() > MAX_DOCUMENT) {
            throw refused(Label.Core_SavedTransform_ErrorTooBig);
        }
        Map<String, Object> document;
        try {
            document = (Map<String, Object>) JSON.deserializeUntyped(definitionJson);
        } catch (Exception unreadable) {
            throw refused(Label.Core_SavedTransform_ErrorUnreadable);
        }
        if (
            document.get('version') != DOCUMENT_VERSION ||
            !(document.get('object') instanceof String)
        ) {
            throw refused(Label.Core_SavedTransform_ErrorUnreadable);
        }
        String objectName = (String) document.get('object');
        if (!BulkUpdateFields.isWritable(objectName)) {
            throw refused(
                String.format(Label.Core_SavedTransform_ErrorObject, new List<Object>{ objectName })
            );
        }
        if (
            document.get('filter') != null &&
            !(document.get('filter') instanceof Map<String, Object>)
        ) {
            throw refused(Label.Core_SavedTransform_ErrorUnreadable);
        }
        checkChanges(document.get('changes'));
        return objectName;
    }

    private static void checkChanges(Object rawChanges) {
        if (!(rawChanges instanceof List<Object>)) {
            throw refused(Label.Core_SavedTransform_ErrorUnreadable);
        }
        List<Object> changes = (List<Object>) rawChanges;
        if (changes.size() > BulkUpdateService.MAX_CHANGES) {
            throw refused(
                String.format(
                    Label.Core_SavedTransform_ErrorChanges,
                    new List<Object>{ BulkUpdateService.MAX_CHANGES }
                )
            );
        }
        for (Object each : changes) {
            Map<String, Object> change = each instanceof Map<String, Object>
                ? (Map<String, Object>) each
                : null;
            if (
                change == null ||
                !(change.get('field') instanceof String) ||
                !(change.get('action') instanceof String) ||
                !ACTIONS.contains((String) change.get('action'))
            ) {
                throw refused(
                    String.format(
                        Label.Core_SavedTransform_ErrorChanges,
                        new List<Object>{ BulkUpdateService.MAX_CHANGES }
                    )
                );
            }
            if (change.get('action') == BulkUpdateService.ACTION_TRANSFORM) {
                checkSteps((String) change.get('field'), change.get('transforms'));
            }
        }
    }

    private static void checkSteps(String field, Object rawSteps) {
        List<DataTransform.Step> steps = rawSteps instanceof List<Object>
            ? DataTransform.parse(JSON.serialize(rawSteps))
            : new List<DataTransform.Step>();
        List<String> problems = DataTransform.problems(steps);
        if (!problems.isEmpty()) {
            throw refused(
                String.format(
                    Label.Core_SavedTransform_ErrorSteps,
                    new List<Object>{ field, String.join(problems, ' ') }
                )
            );
        }
    }

    private static String cleanName(String name) {
        String cleaned = name == null ? '' : name.normalizeSpace();
        if (cleaned.length() == 0 || cleaned.length() > MAX_NAME) {
            throw refused(
                String.format(Label.Core_SavedTransform_ErrorName, new List<Object>{ MAX_NAME })
            );
        }
        return cleaned;
    }

    /** A list may not share a name (capitals ignored) with another. */
    private static void requireFreeName(String name, Id except) {
        List<Saved_Transform__c> same = [
            SELECT Id
            FROM Saved_Transform__c
            WHERE Name = :name AND Id != :except
            WITH USER_MODE
            LIMIT 1
        ];
        if (!same.isEmpty()) {
            throw refused(
                String.format(Label.Core_SavedTransform_ErrorExists, new List<Object>{ name })
            );
        }
    }

    private static Saved_Transform__c find(Id recordId) {
        List<Saved_Transform__c> found = recordId == null
            ? new List<Saved_Transform__c>()
            : [
                  SELECT Id, Name, Object_Name__c, Definition_JSON__c
                  FROM Saved_Transform__c
                  WHERE Id = :recordId
                  WITH USER_MODE
                  LIMIT 1
              ];
        if (found.isEmpty()) {
            throw refused(Label.Core_SavedTransform_ErrorNotFound);
        }
        return found[0];
    }

    private static SavedList toView(Saved_Transform__c saved) {
        SavedList view = new SavedList();
        view.recordId = saved.Id;
        view.name = saved.Name;
        view.objectName = saved.Object_Name__c;
        view.definitionJson = saved.Definition_JSON__c;
        return view;
    }

    private static String objectLabel(String objectName) {
        try {
            return QueryFieldCatalog.describeObject(objectName).getLabel();
        } catch (Exception gone) {
            return objectName;
        }
    }

    private static BulkUpdateFields.BulkUpdateException refused(String message) {
        return new BulkUpdateFields.BulkUpdateException(message);
    }
}
