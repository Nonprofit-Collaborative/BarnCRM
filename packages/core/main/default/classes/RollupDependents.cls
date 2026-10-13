/**
 * The totals a save of one record moves through the source rows under it (canonical model R-R11),
 * the half of change collection `RollupChanges` cannot see from the records in front of it:
 *
 * - A rollup that reads an attribute through a relationship (the fund totals read a gift's status
 *   as `Gift__r.Status__c`) moves when that attribute changes on the parent, though no source row
 *   was saved. The rows under the changed parents are read and their targets marked.
 * - The platform deletes the rows under a master record with it (a gift's allocations and soft
 *   credits) and restores them with it, firing no trigger on them. Before the delete the rows are
 *   read and their targets held until `RollupChanges.afterDelete`; after an undelete they are
 *   read again.
 *
 * Definitions reading the same rows through the same reference share one query.
 *
 * DOCUMENTED EXCEPTION to user mode reads (plan Section 4.13): the rows are read in system mode
 * and without sharing, for the reason `RollupAggregator` gives.
 */
public without sharing class RollupDependents {
    private static final String LOG_CONTEXT = 'RollupDependents';

    /** Targets read before a delete, of the rows the platform deletes with the record. */
    private static RollupChanges.Marked readBeforeDelete = new RollupChanges.Marked();

    /** Reference attributes on one entity that point at another, by `source|target`. */
    private static final Map<String, List<Schema.SObjectField>> REFERENCES = new Map<String, List<Schema.SObjectField>>();

    /**
     * After an update, the targets of the rows whose rollups read a changed attribute of their
     * parent; after an undelete, the targets of the rows restored with it.
     *
     * @param changedType the entity saved
     * @param records the records saved
     * @param oldRecords the records before an update, or null after an undelete
     * @param definitions the active real-time definitions, of every source entity
     * @param marked where the targets are added
     */
    public static void forSave(
        Schema.SObjectType changedType,
        List<SObject> records,
        Map<Id, SObject> oldRecords,
        List<Rollup_Definition__c> definitions,
        RollupChanges.Marked marked
    ) {
        mark(changedType, records, oldRecords, definitions, marked);
    }

    /** Before a delete: reads and holds the targets of the rows deleted with these records. */
    public static void beforeDelete(
        Schema.SObjectType changedType,
        List<SObject> records,
        List<Rollup_Definition__c> definitions
    ) {
        mark(changedType, records, null, definitions, readBeforeDelete);
    }

    /** What `beforeDelete` held, handed over once. */
    public static RollupChanges.Marked takeReadBeforeDelete() {
        RollupChanges.Marked held = readBeforeDelete;
        readBeforeDelete = new RollupChanges.Marked();
        return held;
    }

    /**
     * With old records, the rows under parents whose read-through attributes changed; without,
     * the rows under every parent that the platform deletes and restores them with.
     */
    private static void mark(
        Schema.SObjectType changedType,
        List<SObject> records,
        Map<Id, SObject> oldRecords,
        List<Rollup_Definition__c> definitions,
        RollupChanges.Marked marked
    ) {
        if (changedType == null || records == null || records.isEmpty()) {
            return;
        }
        Map<String, Schema.SObjectField> changedFields = RollupChanges.fieldMap(changedType);
        Map<String, Set<Id>> parentsByQuery = new Map<String, Set<Id>>();
        Map<String, List<Rollup_Definition__c>> definitionsByQuery = new Map<String, List<Rollup_Definition__c>>();
        for (Rollup_Definition__c definition : definitions) {
            Schema.SObjectType sourceType = SettingsService.typeByName(definition.Source_Object__c);
            if (sourceType == null || sourceType == changedType) {
                continue;
            }
            RollupPath.Parsed path = RollupChanges.pathOf(definition);
            if (path == null) {
                continue;
            }
            for (Schema.SObjectField reference : referencesTo(sourceType, changedType)) {
                Schema.DescribeFieldResult describe = reference.getDescribe();
                Set<Id> parents = oldRecords == null
                    ? (describe.isCascadeDelete()
                          ? new Map<Id, SObject>(records).keySet()
                          : new Set<Id>())
                    : changedParents(
                          readThrough(
                              RollupChanges.readsOf(definition, path),
                              describe.getRelationshipName(),
                              changedFields
                          ),
                          records,
                          oldRecords
                      );
                if (parents.isEmpty()) {
                    continue;
                }
                String key = (String.valueOf(sourceType) + '|' + describe.getName()).toLowerCase();
                if (!parentsByQuery.containsKey(key)) {
                    parentsByQuery.put(key, new Set<Id>());
                    definitionsByQuery.put(key, new List<Rollup_Definition__c>());
                }
                parentsByQuery.get(key).addAll(parents);
                definitionsByQuery.get(key).add(definition);
            }
        }
        for (String key : parentsByQuery.keySet()) {
            try {
                markRowsUnder(key, parentsByQuery.get(key), definitionsByQuery.get(key), marked);
            } catch (Exception unreadable) {
                // A path the org cannot query marks nothing here; the nightly run covers it.
                ErrorLogger.log(unreadable, LOG_CONTEXT);
            }
        }
    }

    private static Set<Id> changedParents(
        Set<String> readThrough,
        List<SObject> records,
        Map<Id, SObject> oldRecords
    ) {
        Set<Id> parents = new Set<Id>();
        for (SObject record : records) {
            SObject previous = oldRecords.get(record.Id);
            if (previous != null && RollupChanges.changed(readThrough, record, previous)) {
                parents.add(record.Id);
            }
        }
        return parents;
    }

    /** Reads the source rows under these parents once, and marks each definition's targets. */
    private static void markRowsUnder(
        String key,
        Set<Id> parents,
        List<Rollup_Definition__c> definitions,
        RollupChanges.Marked marked
    ) {
        String sourceName = key.substringBefore('|');
        Schema.SObjectType sourceType = SettingsService.typeByName(sourceName);
        Set<String> columns = new Set<String>{ 'id' };
        for (Rollup_Definition__c definition : definitions) {
            for (RollupPath.Branch branch : RollupChanges.pathOf(definition).branches) {
                List<String> prefix = branch.referencePrefix();
                if (!prefix.isEmpty()) {
                    columns.add(prefix[0].toLowerCase());
                }
            }
        }
        // Every name here is an entity or reference the org described or RollupPath checked.
        List<SObject> rows = Database.queryWithBinds(
            'SELECT ' +
                String.join(new List<String>(columns), ', ') +
                ' FROM ' +
                sourceName +
                ' WHERE ' +
                key.substringAfter('|') +
                ' IN :parents',
            new Map<String, Object>{ 'parents' => parents },
            AccessLevel.SYSTEM_MODE
        );
        for (Rollup_Definition__c definition : definitions) {
            marked.add(
                definition.Target_Object__c,
                RollupChanges.targetsOf(RollupChanges.pathOf(definition), sourceType, rows)
            );
        }
    }

    /** The reference attributes on `sourceType` that point at `changedType`, remembered. */
    private static List<Schema.SObjectField> referencesTo(
        Schema.SObjectType sourceType,
        Schema.SObjectType changedType
    ) {
        String key = String.valueOf(sourceType) + '|' + String.valueOf(changedType);
        if (!REFERENCES.containsKey(key)) {
            List<Schema.SObjectField> found = new List<Schema.SObjectField>();
            for (Schema.SObjectField field : RollupChanges.fieldMap(sourceType).values()) {
                Schema.DescribeFieldResult describe = field.getDescribe();
                if (
                    describe.getType() == Schema.DisplayType.REFERENCE &&
                    describe.getReferenceTo().contains(changedType) &&
                    String.isNotBlank(describe.getRelationshipName())
                ) {
                    found.add(field);
                }
            }
            REFERENCES.put(key, found);
        }
        return REFERENCES.get(key);
    }

    /**
     * The attributes on the parent that reads through `relationshipName` depend on:
     * `Gift__r.Status__c`, read through `Gift__r`, depends on the gift's `Status__c`.
     */
    @TestVisible
    private static Set<String> readThrough(
        Set<String> reads,
        String relationshipName,
        Map<String, Schema.SObjectField> parentFields
    ) {
        Set<String> onParent = new Set<String>();
        String prefix = relationshipName.toLowerCase() + '.';
        for (String read : reads) {
            if (read.toLowerCase().startsWith(prefix)) {
                onParent.addAll(
                    RollupChanges.localFields(
                        new Set<String>{ read.substring(prefix.length()) },
                        parentFields
                    )
                );
            }
        }
        return onParent;
    }
}
