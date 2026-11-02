/**
 * Where Used for BarnCRM setup (C-59, admin guide where-used.md, ADR-NEXT
 * `NEXT-where-used-extension.md`): for one field, or one whole object, every BarnCRM setup record
 * that names it, so an administrator can see what would break before retiring it.
 *
 * Core reads its own setup: saved Find queries (which Giving also lists as donor segments), Super
 * Transform step lists, import mappings, merge rules, matching sources and the settings that
 * name fields. A dependent package adds its own records through `WhereUsedExtension` (the Rollup
 * Builder's definitions, Giving's gift import columns), found by name, so Core never depends on
 * a module. Salesforce's own metadata (flows, Apex, page layouts, reports, validation rules) is
 * not read: that needs the Tooling API, and the page says so.
 *
 * The answer is plain JSON-shaped data (plan Section 9.9): label text, a record Id, and the tab
 * and page state that edit it. The page turns it into a Retire a Field checklist.
 */
@NamespaceAccessible
public with sharing class WhereUsedService {
    /** Raised for anything the person can act on; the message is shown as it is. */
    @NamespaceAccessible
    public class WhereUsedException extends Exception {
    }

    public static final String KIND_SAVED_QUERY = 'savedQuery';
    public static final String KIND_SAVED_TRANSFORM = 'savedTransform';
    @NamespaceAccessible
    public static final String KIND_IMPORT_MAPPING = 'importMapping';
    public static final String KIND_MERGE_RULE = 'mergeRule';
    public static final String KIND_MATCH_SOURCE = 'matchSource';
    public static final String KIND_SETTING = 'setting';

    /** The row entities of an import mapping Core resolves, by the object each one loads (R-IR1). */
    private static final Map<String, String> CORE_ENTITIES = new Map<String, String>{
        ImportMapping.ENTITY_HOUSEHOLD => 'Account',
        ImportMapping.ENTITY_ORGANIZATION => 'Account',
        ImportMapping.ENTITY_CONTACT_1 => 'Contact',
        ImportMapping.ENTITY_CONTACT_2 => 'Contact',
        ImportMapping.ENTITY_AFFILIATION => 'Affiliation__c'
    };

    /** The field or object asked about, and how every package reads a name against it. */
    @NamespaceAccessible
    public class Target {
        @NamespaceAccessible
        public String objectName { get; private set; }
        @NamespaceAccessible
        public String objectLabel { get; private set; }
        /** Null when the question is about the whole object. */
        @NamespaceAccessible
        public String fieldName { get; private set; }
        @NamespaceAccessible
        public String fieldLabel { get; private set; }
        private Schema.DescribeFieldResult field;
        private String compoundName;
        private Map<String, Map<String, Schema.SObjectField>> fieldMaps = new Map<String, Map<String, Schema.SObjectField>>();
        private Map<String, Map<String, Schema.DescribeFieldResult>> lookups = new Map<String, Map<String, Schema.DescribeFieldResult>>();
        private Map<String, Map<String, String>> children = new Map<String, Map<String, String>>();

        private Target(Schema.DescribeSObjectResult described, Schema.DescribeFieldResult field) {
            this.objectName = described.getName();
            this.objectLabel = described.getLabel();
            this.field = field;
            if (field != null) {
                this.fieldName = field.getName();
                this.fieldLabel = field.getLabel();
                this.compoundName = field.getCompoundFieldName();
            }
        }

        /** True for a custom field of this org, which an administrator can delete in Setup. */
        public Boolean isDeletable() {
            return field != null && field.isCustom() && field.getName() == field.getLocalName();
        }

        /** True when the question is about the whole object, not one field. */
        @NamespaceAccessible
        public Boolean isObject() {
            return fieldName == null;
        }

        /** True when the name is the target object (with or without this package's prefix). */
        @NamespaceAccessible
        public Boolean isObject(String name) {
            String canonical = canonicalObject(name);
            return canonical != null && canonical.equalsIgnoreCase(objectName);
        }

        /**
         * True when a field named on an object is the target: in object mode, any field of the
         * target object; otherwise the target field itself, or the compound field it is part of
         * (a merge rule on `MailingAddress` uses `MailingStreet`).
         */
        @NamespaceAccessible
        public Boolean matchesField(String onObject, String name) {
            if (String.isBlank(name) || !isObject(onObject)) {
                return false;
            }
            if (isObject()) {
                return true;
            }
            String trimmed = name.trim();
            Schema.SObjectField token = fieldMap(objectName).get(trimmed.toLowerCase());
            String canonical = token == null ? trimmed : token.getDescribe().getName();
            return canonical.equalsIgnoreCase(fieldName) ||
                (compoundName != null && canonical.equalsIgnoreCase(compoundName));
        }

        /**
         * True when a field path read from an object reaches the target: `Household__r.Name`
         * from Contact names the Household lookup and Account's Name. Relationship names are
         * resolved through describe; a path that does not resolve matches nothing.
         */
        @NamespaceAccessible
        public Boolean matchesPath(String fromObject, String path) {
            if (String.isBlank(path)) {
                return false;
            }
            String current = canonicalObject(fromObject);
            List<String> segments = path.trim().split('\\.');
            for (Integer i = 0; i < segments.size() && current != null; i++) {
                if (isObject() && isObject(current)) {
                    return true;
                }
                String segment = segments[i].trim();
                if (i == segments.size() - 1) {
                    return matchesField(current, segment);
                }
                Schema.DescribeFieldResult lookup = lookupMap(current).get(segment.toLowerCase());
                if (lookup == null) {
                    return false;
                }
                if (matchesField(current, lookup.getName())) {
                    return true;
                }
                current = referenced(lookup);
            }
            return false;
        }

        /** True when any condition of a filter document (R-R2), text or parsed, names the target. */
        @NamespaceAccessible
        public Boolean matchesFilter(String fromObject, Object filter) {
            Object parsed = filter;
            if (filter instanceof String) {
                if (String.isBlank((String) filter)) {
                    return false;
                }
                try {
                    parsed = JSON.deserializeUntyped((String) filter);
                } catch (Exception unreadable) {
                    return false;
                }
            }
            if (!(parsed instanceof Map<String, Object>)) {
                return false;
            }
            for (Object condition : listOf(((Map<String, Object>) parsed).get('conditions'))) {
                if (
                    condition instanceof Map<String, Object> &&
                    matchesPath(
                        fromObject,
                        stringOf(((Map<String, Object>) condition).get('field'))
                    )
                ) {
                    return true;
                }
            }
            return false;
        }

        /**
         * The object a lookup field on an object points to (the target object when it is one of
         * several), or null when the field is not a lookup or is not there.
         */
        @NamespaceAccessible
        public String objectOfLookup(String onObject, String lookupField) {
            String canonical = canonicalObject(onObject);
            if (canonical == null || String.isBlank(lookupField)) {
                return null;
            }
            Schema.SObjectField token = fieldMap(canonical).get(lookupField.trim().toLowerCase());
            return token == null ? null : referenced(token.getDescribe());
        }

        /** The object a child relationship of an object holds, or null. */
        public String objectOfChildren(String onObject, String relationship) {
            String canonical = canonicalObject(onObject);
            if (canonical == null || String.isBlank(relationship)) {
                return null;
            }
            String key = canonical.toLowerCase();
            if (!children.containsKey(key)) {
                Map<String, String> byName = new Map<String, String>();
                for (
                    Schema.ChildRelationship child : NamespaceUtil.objectType(canonical)
                        .getDescribe()
                        .getChildRelationships()
                ) {
                    if (child.getRelationshipName() != null) {
                        byName.put(
                            child.getRelationshipName().toLowerCase(),
                            child.getChildSObject()
                                .getDescribe(SObjectDescribeOptions.DEFERRED)
                                .getName()
                        );
                    }
                }
                children.put(key, byName);
            }
            return children.get(key).get(relationship.trim().toLowerCase());
        }

        private String referenced(Schema.DescribeFieldResult lookup) {
            List<Schema.SObjectType> targets = lookup.getReferenceTo();
            if (targets.isEmpty()) {
                return null;
            }
            for (Schema.SObjectType candidate : targets) {
                if (isObject(String.valueOf(candidate))) {
                    return objectName;
                }
            }
            return targets[0].getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        }

        private Map<String, Schema.SObjectField> fieldMap(String canonical) {
            String key = canonical.toLowerCase();
            if (!fieldMaps.containsKey(key)) {
                fieldMaps.put(
                    key,
                    NamespaceUtil.objectType(canonical)
                        .getDescribe(SObjectDescribeOptions.DEFERRED)
                        .fields.getMap()
                );
            }
            return fieldMaps.get(key);
        }

        /** An object's lookups by relationship name, described once per request. */
        private Map<String, Schema.DescribeFieldResult> lookupMap(String canonical) {
            String key = canonical.toLowerCase();
            if (!lookups.containsKey(key)) {
                Map<String, Schema.DescribeFieldResult> byRelationship = new Map<String, Schema.DescribeFieldResult>();
                for (Schema.SObjectField token : fieldMap(canonical).values()) {
                    Schema.DescribeFieldResult described = token.getDescribe();
                    String relationship = described.getRelationshipName();
                    if (relationship != null) {
                        // Stored documents name this package's relationships without its prefix.
                        byRelationship.put(relationship.toLowerCase(), described);
                        byRelationship.put(
                            relationship.toLowerCase()
                                .removeStart(NamespaceUtil.prefix().toLowerCase()),
                            described
                        );
                    }
                }
                lookups.put(key, byRelationship);
            }
            return lookups.get(key);
        }
    }

    /** One setup record that names the target. */
    @NamespaceAccessible
    public class Reference implements Comparable {
        // An @AuraEnabled field cannot also be @NamespaceAccessible, so a module reads one
        // through the getters below (the HealthCheckService.Finding pattern).
        /** A stable key for the kind of record, such as `savedQuery` or `rollup`. */
        @AuraEnabled
        public String kind;
        /** The kind as the page heads its group, such as "Saved Find Queries". */
        @AuraEnabled
        public String kindLabel;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String recordId;
        /** Where in the record the target is named, such as "Filter" or "Column Donor Email". */
        @AuraEnabled
        public List<String> parts = new List<String>();
        /** What stops working when the field is deleted. */
        @AuraEnabled
        public String breaks;
        /** The tab that edits this record, already qualified, or null when nothing in BarnCRM does. */
        @AuraEnabled
        public String editTab;
        /** The page state that opens the record on that tab, with qualified keys. */
        @AuraEnabled
        public Map<String, String> editState = new Map<String, String>();
        /** The same tab and state as a relative link, for any front end. */
        @AuraEnabled
        public String editUrl;

        @NamespaceAccessible
        public String getName() {
            return name;
        }

        @NamespaceAccessible
        public List<String> getParts() {
            return parts;
        }

        @NamespaceAccessible
        public String getBreaks() {
            return breaks;
        }

        @NamespaceAccessible
        public String getEditTab() {
            return editTab;
        }

        @NamespaceAccessible
        public Reference(String kind, String kindLabel, String name, Id recordId) {
            this.kind = kind;
            this.kindLabel = kindLabel;
            this.name = name;
            this.recordId = recordId;
        }

        /** Adds where the target is named, once. */
        @NamespaceAccessible
        public Reference addPart(String part) {
            if (String.isNotBlank(part) && !parts.contains(part)) {
                parts.add(part);
            }
            return this;
        }

        @NamespaceAccessible
        public Reference withBreaks(String breaks) {
            this.breaks = breaks;
            return this;
        }

        /** The packaged tab (unprefixed) and page state parameters (unprefixed) that edit it. */
        @NamespaceAccessible
        public Reference withEdit(String tabName, Map<String, String> state) {
            this.editTab = NamespaceUtil.qualify(tabName);
            if (state != null) {
                for (String key : state.keySet()) {
                    editState.put(NamespaceUtil.stateKey(key), state.get(key));
                }
            }
            this.editUrl = tabUrl(tabName, state);
            return this;
        }

        public Integer compareTo(Object other) {
            Reference that = (Reference) other;
            Integer byKind = (kindLabel == null ? '' : kindLabel)
                .compareTo(that.kindLabel == null ? '' : that.kindLabel);
            return byKind != 0
                ? byKind
                : (name == null ? '' : name).compareTo(that.name == null ? '' : that.name);
        }
    }

    /** The answer: the target, whether BarnCRM could delete it, and every reference. */
    public class Result {
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String fieldName;
        @AuraEnabled
        public String fieldLabel;
        /** True for a custom field of this org, which an administrator can delete in Setup. */
        @AuraEnabled
        public Boolean deletable = false;
        @AuraEnabled
        public List<Reference> references = new List<Reference>();
        /** True when a module's records could not be checked; the failure is logged. */
        @AuraEnabled
        public Boolean incomplete = false;
        /** Find opened on the object, where the field's values can be exported first. */
        @AuraEnabled
        public String findUrl;
    }

    /** A relative link to a packaged Lightning tab with page state, keys and values encoded. */
    @NamespaceAccessible
    public static String tabUrl(String tabName, Map<String, String> state) {
        List<String> pairs = new List<String>();
        if (state != null) {
            for (String key : state.keySet()) {
                pairs.add(
                    EncodingUtil.urlEncode(NamespaceUtil.stateKey(key), 'UTF-8') +
                        '=' +
                        EncodingUtil.urlEncode(String.valueOf(state.get(key)), 'UTF-8')
                );
            }
        }
        return '/lightning/n/' +
            NamespaceUtil.qualify(tabName) +
            (pairs.isEmpty() ? '' : '?' + String.join(pairs, '&'));
    }

    /** The target for an object and, optionally, one of its fields; refused when either is unknown. */
    @NamespaceAccessible
    public static Target target(String objectName, String fieldName) {
        Schema.SObjectType type = NamespaceUtil.objectType(objectName);
        if (type == null) {
            throw new WhereUsedException(
                String.format(
                    System.Label.Core_WhereUsed_ErrorNoObject,
                    new List<Object>{ objectName }
                )
            );
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (String.isBlank(fieldName)) {
            return new Target(described, null);
        }
        Schema.SObjectField token = described.fields.getMap().get(fieldName.trim().toLowerCase());
        if (token == null) {
            throw new WhereUsedException(
                String.format(
                    System.Label.Core_WhereUsed_ErrorNoField,
                    new List<Object>{ fieldName, described.getLabel() }
                )
            );
        }
        return new Target(described, token.getDescribe());
    }

    /** Every BarnCRM setup record, Core's and the installed modules', that names the target. */
    public static Result find(String objectName, String fieldName) {
        Target target = target(objectName, fieldName);
        Result result = new Result();
        result.objectName = target.objectName;
        result.objectLabel = target.objectLabel;
        result.fieldName = target.fieldName;
        result.fieldLabel = target.fieldLabel;
        result.deletable = target.isDeletable();
        result.findUrl = tabUrl('Find', new Map<String, String>{ 'object' => target.objectName });

        List<Reference> found = new List<Reference>();
        found.addAll(savedQueryReferences(target));
        found.addAll(savedTransformReferences(target));
        found.addAll(importTemplateReferences(target));
        found.addAll(importColumnReferences(target, CORE_ENTITIES));
        found.addAll(mergeRuleReferences(target));
        found.addAll(matchSourceReferences(target));
        found.addAll(settingReferences(target));
        Map<String, WhereUsedExtension> extensions = WhereUsedExtensions.findAll();
        for (String className : extensions.keySet()) {
            try {
                List<Reference> added = extensions.get(className).references(target);
                if (added != null) {
                    found.addAll(added);
                }
            } catch (Exception failed) {
                ErrorLogger.log(failed, 'WhereUsedService.find: ' + className);
                result.incomplete = true;
            }
        }
        result.references = merged(found);
        result.references.sort();
        return result;
    }

    /** One reference per record and kind: a mapping Core and Giving both read is listed once. */
    private static List<Reference> merged(List<Reference> found) {
        Map<String, Reference> byKey = new Map<String, Reference>();
        List<Reference> ordered = new List<Reference>();
        for (Reference reference : found) {
            String key =
                reference.kind +
                '|' +
                (reference.recordId == null ? reference.name : reference.recordId);
            Reference existing = byKey.get(key);
            if (existing == null) {
                byKey.put(key, reference);
                ordered.add(reference);
            } else {
                for (String part : reference.parts) {
                    existing.addPart(part);
                }
            }
        }
        return ordered;
    }

    @TestVisible
    private static List<Reference> savedQueryReferences(Target target) {
        List<Reference> found = new List<Reference>();
        Id me = UserInfo.getUserId();
        for (Saved_Query__c query : WhereUsedSelector.savedQueries()) {
            Map<String, Object> document = parsed(query.Query_JSON__c);
            String base = query.Object_Name__c;
            Reference reference = new Reference(
                KIND_SAVED_QUERY,
                System.Label.Core_WhereUsed_KindSavedQuery,
                query.Name,
                query.Id
            );
            if (target.isObject() && target.isObject(base)) {
                // A query on the object itself: one part says so, rather than every column.
                reference.addPart(System.Label.Core_WhereUsed_PartObject);
            } else {
                addQueryParts(target, base, document, reference);
            }
            if (reference.parts.isEmpty()) {
                continue;
            }
            reference.withBreaks(System.Label.Core_WhereUsed_BreaksSavedQuery);
            if (query.Shared__c != true && query.OwnerId != me) {
                // Private to someone else: say whose, not what it is called (R-SQ3).
                reference.name = String.format(
                    System.Label.Core_WhereUsed_PrivateQuery,
                    new List<Object>{ query.Owner?.Name }
                );
                reference.recordId = null;
            } else {
                reference.withEdit('Find', new Map<String, String>{ 'savedQueryId' => query.Id });
            }
            found.add(reference);
        }
        return found;
    }

    /** Each part of a query document (R-SQ1, R-SQ8, R-SQ9) that names the target. */
    private static void addQueryParts(
        Target target,
        String base,
        Map<String, Object> document,
        Reference reference
    ) {
        for (Object path : listOf(document.get('fields'))) {
            if (target.matchesPath(base, stringOf(path))) {
                reference.addPart(System.Label.Core_WhereUsed_PartColumns);
            }
        }
        if (target.matchesFilter(base, document.get('filter'))) {
            reference.addPart(System.Label.Core_WhereUsed_PartFilter);
        }
        for (Object order : listOf(document.get('orderBy'))) {
            if (
                order instanceof Map<String, Object> &&
                target.matchesPath(base, stringOf(((Map<String, Object>) order).get('field')))
            ) {
                reference.addPart(System.Label.Core_WhereUsed_PartSort);
            }
        }
        for (Object entry : listOf(document.get('related'))) {
            if (relatedNames(target, entry)) {
                reference.addPart(System.Label.Core_WhereUsed_PartRelated);
            }
        }
        for (Object entry : listOf(document.get('children'))) {
            if (childColumnsName(target, base, entry)) {
                reference.addPart(System.Label.Core_WhereUsed_PartChildren);
            }
        }
        if (document.get('aggregate') instanceof Map<String, Object>) {
            Map<String, Object> summary = (Map<String, Object>) document.get('aggregate');
            if (
                target.matchesPath(base, stringOf(summary.get('field'))) ||
                target.matchesPath(base, stringOf(summary.get('groupBy')))
            ) {
                reference.addPart(System.Label.Core_WhereUsed_PartSummary);
            }
        }
    }

    /** A related-records condition (R-SQ8): its child object, its lookup and its own filter. */
    private static Boolean relatedNames(Target target, Object entry) {
        if (!(entry instanceof Map<String, Object>)) {
            return false;
        }
        Map<String, Object> related = (Map<String, Object>) entry;
        String child = stringOf(related.get('object'));
        return (target.isObject() && target.isObject(child)) ||
            target.matchesField(child, stringOf(related.get('field'))) ||
            target.matchesFilter(child, related.get('filter'));
    }

    /** A related record column (R-SQ8): a child relationship of the query's object and its fields. */
    private static Boolean childColumnsName(Target target, String base, Object entry) {
        if (!(entry instanceof Map<String, Object>)) {
            return false;
        }
        Map<String, Object> column = (Map<String, Object>) entry;
        String child = target.objectOfChildren(base, stringOf(column.get('relationship')));
        if (child == null) {
            return false;
        }
        if (target.isObject() && target.isObject(child)) {
            return true;
        }
        for (Object path : listOf(column.get('fields'))) {
            if (target.matchesPath(child, stringOf(path))) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    private static List<Reference> savedTransformReferences(Target target) {
        List<Reference> found = new List<Reference>();
        for (Saved_Transform__c saved : WhereUsedSelector.savedTransforms()) {
            Map<String, Object> document = parsed(saved.Definition_JSON__c);
            String base = saved.Object_Name__c;
            Reference reference = new Reference(
                KIND_SAVED_TRANSFORM,
                System.Label.Core_WhereUsed_KindSavedTransform,
                saved.Name,
                saved.Id
            );
            if (target.isObject() && target.isObject(base)) {
                reference.addPart(System.Label.Core_WhereUsed_PartObject);
            } else {
                if (target.matchesFilter(base, document.get('filter'))) {
                    reference.addPart(System.Label.Core_WhereUsed_PartFilter);
                }
                if (namesFieldAnywhere(target, base, document.get('changes'))) {
                    reference.addPart(System.Label.Core_WhereUsed_PartChanges);
                }
            }
            if (!reference.parts.isEmpty()) {
                found.add(
                    reference.withBreaks(System.Label.Core_WhereUsed_BreaksSavedTransform)
                        .withEdit('Bulk_Update', null)
                );
            }
        }
        return found;
    }

    /** A change entry (R-ST1) or a step inside it: any `field` or `source` key, at any depth. */
    private static Boolean namesFieldAnywhere(Target target, String base, Object node) {
        if (node instanceof Map<String, Object>) {
            Map<String, Object> entry = (Map<String, Object>) node;
            for (String key : new List<String>{ 'field', 'source' }) {
                if (
                    entry.get(key) instanceof String &&
                    target.matchesPath(base, (String) entry.get(key))
                ) {
                    return true;
                }
            }
            for (Object value : entry.values()) {
                if (
                    (value instanceof Map<String, Object> || value instanceof List<Object>) &&
                    namesFieldAnywhere(target, base, value)
                ) {
                    return true;
                }
            }
        } else if (node instanceof List<Object>) {
            for (Object item : (List<Object>) node) {
                if (namesFieldAnywhere(target, base, item)) {
                    return true;
                }
            }
        }
        return false;
    }

    /** What an import mapping names outside its columns: the objects it loads and its matching fields. */
    @TestVisible
    private static List<Reference> importTemplateReferences(Target target) {
        List<Reference> found = new List<Reference>();
        for (Import_Template__c template : WhereUsedSelector.importTemplates()) {
            Reference reference = importReference(template);
            if (
                target.isObject() &&
                (target.isObject(template.Target_Object__c) ||
                target.isObject(template.Related_Object__c))
            ) {
                reference.addPart(System.Label.Core_WhereUsed_PartObject);
            }
            if (
                target.matchesField(template.Target_Object__c, template.Load_Match_Field__c) ||
                target.matchesField('Contact', template.Person_Match_Field__c) ||
                target.matchesField('Account', template.Person_Match_Field__c) ||
                target.matchesField('Account', template.Organization_Match_Field__c)
            ) {
                reference.addPart(System.Label.Core_WhereUsed_PartMatchingField);
            }
            if (target.matchesField(template.Related_Object__c, template.Related_Parent_Field__c)) {
                reference.addPart(System.Label.Core_WhereUsed_PartRelatedParent);
            }
            if (!reference.parts.isEmpty()) {
                found.add(reference);
            }
        }
        return found;
    }

    /**
     * The columns and default values of every import mapping (R-IT1) that load the target, for
     * the row entities given by the object each loads. Core passes its own entities; Giving
     * passes Gift, Allocation, Soft Credit and Tribute. A one-object mapping's `Record` and
     * `Related` entities load its target and related objects, whoever asks.
     */
    @NamespaceAccessible
    public static List<Reference> importColumnReferences(
        Target target,
        Map<String, String> entityObjects
    ) {
        List<Reference> found = new List<Reference>();
        Boolean withOneObject = entityObjects.containsKey(ImportMapping.ENTITY_CONTACT_1);
        for (Import_Template__c template : WhereUsedSelector.importTemplates()) {
            Map<String, String> objects = new Map<String, String>(entityObjects);
            if (withOneObject) {
                objects.put(ImportMapping.ENTITY_RECORD, template.Target_Object__c);
                objects.put(ImportMapping.ENTITY_RELATED, template.Related_Object__c);
            }
            Reference reference = importReference(template);
            Map<String, Object> mapping = parsed(template.Column_Mapping_JSON__c);
            for (Object entry : listOf(mapping.get('columns'))) {
                if (entry instanceof Map<String, Object>) {
                    Map<String, Object> column = (Map<String, Object>) entry;
                    if (columnNames(target, objects, column)) {
                        reference.addPart(
                            String.format(
                                System.Label.Core_WhereUsed_PartColumn,
                                new List<Object>{ stringOf(column.get('source')) }
                            )
                        );
                    }
                }
            }
            List<Object> defaults = listOf(mapping.get('defaults'));
            defaults.addAll(listOf(parsed(template.Default_Values_JSON__c).get('defaults')));
            for (Object entry : defaults) {
                if (
                    entry instanceof Map<String, Object> &&
                    columnNames(target, objects, (Map<String, Object>) entry)
                ) {
                    reference.addPart(System.Label.Core_WhereUsed_PartDefault);
                }
            }
            if (!reference.parts.isEmpty()) {
                found.add(reference);
            }
        }
        return found;
    }

    /** A column or default whose `Entity.Attribute` target, or lookup field, is the target. */
    private static Boolean columnNames(
        Target target,
        Map<String, String> objects,
        Map<String, Object> column
    ) {
        String mapped = stringOf(column.get('target'));
        if (String.isBlank(mapped) || !mapped.contains('.')) {
            return false;
        }
        String objectName = objects.get(mapped.substringBefore('.'));
        if (objectName == null) {
            return false;
        }
        String attribute = mapped.substringAfter('.');
        return target.matchesField(objectName, attribute) ||
            target.matchesField(
                target.objectOfLookup(objectName, attribute),
                stringOf(column.get('lookupField'))
            );
    }

    private static Reference importReference(Import_Template__c template) {
        return new Reference(
                KIND_IMPORT_MAPPING,
                System.Label.Core_WhereUsed_KindImportMapping,
                template.Name,
                template.Id
            )
            .withBreaks(System.Label.Core_WhereUsed_BreaksImportMapping)
            .withEdit('Data_Manager', null);
    }

    @TestVisible
    private static List<Reference> mergeRuleReferences(Target target) {
        List<Reference> found = new List<Reference>();
        for (Merge_Rule__mdt rule : WhereUsedSelector.mergeRules()) {
            if (target.matchesField('Contact', rule.Field_Name__c)) {
                found.add(
                    new Reference(
                            KIND_MERGE_RULE,
                            System.Label.Core_WhereUsed_KindMergeRule,
                            rule.MasterLabel,
                            null
                        )
                        .addPart(System.Label.Core_WhereUsed_PartField)
                        .withBreaks(System.Label.Core_WhereUsed_BreaksMergeRule)
                        .withEdit('Duplicate_Matching', null)
                );
            }
        }
        return found;
    }

    @TestVisible
    private static List<Reference> matchSourceReferences(Target target) {
        List<Reference> found = new List<Reference>();
        for (Match_Source__mdt source : MatchSourceSelector.selectAllSources()) {
            Reference reference = new Reference(
                KIND_MATCH_SOURCE,
                System.Label.Core_WhereUsed_KindMatchSource,
                source.MasterLabel,
                null
            );
            if (target.isObject() && target.isObject(source.Object_Name__c)) {
                reference.addPart(System.Label.Core_WhereUsed_PartObject);
            }
            for (
                String name : new List<String>{
                    source.Value_Field__c,
                    source.Parent_Field__c,
                    source.Postal_Code_Field__c
                }
            ) {
                if (!target.isObject() && target.matchesField(source.Object_Name__c, name)) {
                    reference.addPart(System.Label.Core_WhereUsed_PartField);
                }
            }
            if (!reference.parts.isEmpty()) {
                found.add(
                    reference.withBreaks(System.Label.Core_WhereUsed_BreaksMatchSource)
                        .withEdit('Duplicate_Matching', null)
                );
            }
        }
        return found;
    }

    /** Settings that hold a list of field names: Address Card Fields (R-AD10). */
    @TestVisible
    private static List<Reference> settingReferences(Target target) {
        List<Reference> found = new List<Reference>();
        String chosen = SettingsService.getSettings().Address_Card_Fields__c;
        if (target.isObject() || String.isBlank(chosen)) {
            return found;
        }
        for (String name : chosen.split(',')) {
            if (target.matchesField('Address__c', name)) {
                found.add(
                    new Reference(
                            KIND_SETTING,
                            System.Label.Core_WhereUsed_KindSetting,
                            Schema.BarnCRM_Settings__c.Address_Card_Fields__c.getDescribe()
                                .getLabel(),
                            null
                        )
                        .addPart(System.Label.Core_WhereUsed_PartField)
                        .withBreaks(System.Label.Core_WhereUsed_BreaksSetting)
                        .withEdit(
                            'BarnCRM_Settings',
                            new Map<String, String>{ 'section' => 'Addresses' }
                        )
                );
                break;
            }
        }
        return found;
    }

    /** A stored JSON document as a map; an empty map when it is blank or unreadable. */
    @NamespaceAccessible
    public static Map<String, Object> parsed(String json) {
        if (String.isBlank(json)) {
            return new Map<String, Object>();
        }
        try {
            Object value = System.JSON.deserializeUntyped(json);
            return value instanceof Map<String, Object>
                ? (Map<String, Object>) value
                : new Map<String, Object>();
        } catch (Exception unreadable) {
            return new Map<String, Object>();
        }
    }

    /** A JSON value as a list; an empty list when it is anything else. */
    @NamespaceAccessible
    public static List<Object> listOf(Object value) {
        return value instanceof List<Object>
            ? new List<Object>((List<Object>) value)
            : new List<Object>();
    }

    private static String stringOf(Object value) {
        return value instanceof String ? (String) value : null;
    }

    /** The canonical API name of an object named with or without this package's prefix, or null. */
    private static String canonicalObject(String name) {
        Schema.SObjectType type = NamespaceUtil.objectType(name);
        return type == null ? null : type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
    }
}
