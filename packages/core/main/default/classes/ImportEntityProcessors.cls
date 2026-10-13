/**
 * Finds the entity processor a dependent package installed (R-IR6), or answers that there is
 * none, which is the ordinary case in an org without Giving.
 *
 * The class is found by namespace and name, the pattern `SampleDataModules` uses: a class
 * name is not an API name, so it takes no `__` prefix. A class that cannot be built, or does
 * not implement the interface, is logged and treated as absent, because an import must not
 * fail over a module it can do without.
 */
@NamespaceAccessible
public with sharing class ImportEntityProcessors {
    /** The class name a dependent package registers to resolve the rest of a row (R-IR6). */
    @NamespaceAccessible
    public static final String CLASS_NAME = 'GiftImportProcessor';

    /** The field every record an import creates carries, naming the import (R-IB3). */
    @NamespaceAccessible
    public static final String TAG_FIELD = 'Created_By_Import_Batch__c';

    /**
     * What the installed processor carries from one chunk of a run to the next (R-IR6), such
     * as the scheduled payments earlier chunks already matched. Each chunk runs in its own
     * transaction, so the import batch keeps this between chunks and sets it again before the
     * next one. Core never reads it.
     */
    @NamespaceAccessible
    public static String carriedState;

    /** Injected by Core's tests, which have no other package to resolve a real one from. */
    @TestVisible
    private static ImportEntityProcessor processorOverride;

    /** Set by Core's tests to see the org as having no processor at all. */
    @TestVisible
    private static Boolean noneForTest = false;

    private static Boolean looked = false;
    private static ImportEntityProcessor found;

    /** The installed processor, or null. Looked up once per transaction. */
    @NamespaceAccessible
    public static ImportEntityProcessor find() {
        if (processorOverride != null) {
            return processorOverride;
        }
        if (noneForTest == true) {
            return null;
        }
        if (!looked) {
            looked = true;
            found = resolve(CLASS_NAME);
        }
        return found;
    }

    /**
     * The objects the installed processor tags with Created By Import Batch, in the order an
     * undo deletes them (R-IB9). An object that does not carry a Created By Import Batch
     * reference to the import, or a Name, is left out rather than queried, because the undo
     * would otherwise fail on a module's mistake.
     */
    @NamespaceAccessible
    public static List<Schema.SObjectType> taggedTypes() {
        List<Schema.SObjectType> result = new List<Schema.SObjectType>();
        ImportEntityProcessor processor = find();
        if (processor == null) {
            return result;
        }
        List<Schema.SObjectType> named;
        try {
            named = processor.taggedObjects();
        } catch (Exception cannotSay) {
            ErrorLogger.log(cannotSay, 'ImportEntityProcessors.taggedTypes');
            return result;
        }
        for (Schema.SObjectType type : named == null ? new List<Schema.SObjectType>() : named) {
            if (type != null && !result.contains(type) && carriesTheTag(type)) {
                result.add(type);
            }
        }
        return result;
    }

    /** Whether records of this type name the import that created them, and have a Name. */
    private static Boolean carriesTheTag(Schema.SObjectType type) {
        Map<String, Schema.SObjectField> fields = type.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        Schema.SObjectField tag = fields.get(NamespaceUtil.qualify(TAG_FIELD));
        return tag != null &&
            fields.containsKey('name') &&
            tag.getDescribe().getReferenceTo().contains(Import_Batch__c.SObjectType);
    }

    /** The class by name, namespace first; tests pass names of their own. */
    @TestVisible
    private static ImportEntityProcessor resolve(String className) {
        Type processorType = NamespaceUtil.resolveType(className);
        if (processorType == null) {
            return null;
        }
        Object candidate;
        try {
            candidate = processorType.newInstance();
        } catch (Exception cannotBuild) {
            ErrorLogger.log(cannotBuild, 'ImportEntityProcessors.resolve');
            return null;
        }
        if (candidate instanceof ImportEntityProcessor) {
            return (ImportEntityProcessor) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement ImportEntityProcessor'),
            'ImportEntityProcessors.resolve'
        );
        return null;
    }
}
