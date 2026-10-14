/**
 * Loads one chunk of a one-object template (canonical model R-IT12 to R-IT14; ADR-0080
 * `0080-import-load-one-object.md`): Insert, Update by record Id, Update by a matching field, or
 * Upsert by external ID, for any object `ImportObjectSchema` admits, custom ones included.
 *
 * Every read and save of the target object and of lookup parents is in the running user's own
 * mode; the only system-mode writes are the staged rows and the journal, the package's own
 * bookkeeping (ADR-0021). What is never written comes from `DataProtectedFields`.
 *
 * Bulk safe: a query or a save per chunk and lookup column, never per row. A dry run makes the
 * same decisions as the commit and writes only the rows. A row is one record, so a value its
 * field cannot take rejects the row, and a row naming a record an earlier row named is rejected
 * wherever the file's chunks fall. The loader finds records itself rather than calling the
 * platform's upsert, so a dry run can say which rows create and the journal holds each value
 * before. Each record a commit creates is journaled on a Created page, since an arbitrary object
 * has no batch tag, and undo deletes it from there.
 *
 * With Use Duplicate Rules ticked (R-IT16), a row of an Insert or an Upsert that would create a
 * record is first asked about through the org's active duplicate rules for the object; a record
 * they match is updated instead. A record ID or upsert key match always wins over the rules.
 *
 * With a Related Object (R-IT17; ADR-0111 `0111-load-related-records.md`) each row may also
 * create a related record pointing at its parent. The first row of a key is the parent row;
 * later rows of the key only add related records. Parents are saved before related records,
 * and a related row of a failed parent is rejected.
 */
@NamespaceAccessible
public with sharing class ImportObjectLoader {
    /** Prefixes a record key before its digest, apart from people and organizations. */
    private static final String RECORD_DIGEST = 'record:';

    /** Prefixes a parent row's key when its parent failed, for later rows of the key (R-IT17). */
    private static final String FAILED_DIGEST = 'parentfailed:';

    /** How many records one read of stored values takes, a chunk's worth and more. */
    private static final Integer READ_LIMIT = 10000;

    /** How many records one lookup query reads. */
    private static final Integer ROWS_PER_QUERY = 5000;

    /** One row's working state while the chunk is resolved. */
    private class Item {
        Import_Row__c row;
        /** The row's Record attributes, folded to lower case, with defaults applied. */
        Map<String, String> held = new Map<String, String>();
        /** Field API name to the value to write, as the field's type. */
        Map<String, Object> values = new Map<String, Object>();
        /** The record key: an ID, or an upsert value folded to lower case. */
        String key;
        Id recordId;
        SObject stored;
        Boolean creates = false;
        Boolean changes = false;
        /** True when the org's duplicate rules, not the row's key, found its record (R-IT16). */
        Boolean ruleMatch = false;
        String error;
        /** The row's Related values as the mapping gives them (R-IT17), or null. */
        Map<String, String> relatedGiven;
        /** True for the first row of its key, which loads the parent (R-IT17). */
        Boolean leads = false;
        /** A later row of a key whose parent row is in this chunk: that row's item. */
        Item leader;
        /** A later row of a key whose parent row was in an earlier chunk. */
        Boolean follows = false;
        /** The row's related record, or null when the row has none. */
        Item related;

        Item(Import_Row__c row, Map<String, String> given) {
            this.row = row;
            if (given != null) {
                for (String attribute : given.keySet()) {
                    held.put(attribute.toLowerCase(), given.get(attribute));
                }
            }
        }
    }

    /** One mapped attribute, worked out once per chunk. */
    private class Plan {
        String attribute;
        Schema.DescribeFieldResult field;
        Boolean lookup = false;
        Schema.SObjectType parentType;
        /** The parent field a lookup names its parent by; null for the record ID. */
        String parentField;
        /** A lookup named by a field the user cannot search by finds nobody. */
        Boolean findsNobody = false;
    }

    /** What one lookup query found: the record per key, and the keys several records hold. */
    private class Found {
        Map<String, Id> ids = new Map<String, Id>();
        Set<String> several = new Set<String>();
    }

    /**
     * Resolves one chunk. Writes nothing but the staged rows when dryRun is true. Each row is
     * updated with its status, its error and the record it resulted in, and saved.
     */
    @NamespaceAccessible
    public static ImportRowProcessor.Outcome process(
        Import_Batch__c batch,
        Import_Template__c template,
        ImportMapping mapping,
        List<Import_Row__c> rows,
        Boolean dryRun
    ) {
        ImportRowProcessor.Outcome outcome = new ImportRowProcessor.Outcome();
        List<Item> items = read(batch, mapping, rows, ImportObjectSchema.loadsRelated(template));
        String refused = ImportObjectSchema.refusal(template, mapping);
        if (refused != null) {
            // Nothing can load: every row says why, in words the administrator can act on.
            for (Item item : items) {
                item.error = refused;
            }
            writeBack(items, outcome);
            return outcome;
        }
        Schema.SObjectType type = ImportObjectSchema.typeOf(template);
        String operation = ImportObjectSchema.operationOf(template);
        if (operation == ImportObjectSchema.OPERATION_DELETE) {
            // Delete by record Id (R-BD7) only checks each row; the bulk delete job deletes.
            checkDeletes(batch, type, items);
            writeBack(items, outcome);
            return outcome;
        }
        Boolean mostRecent = ImportTemplateService.usesMostRecent(template);
        Boolean related = ImportObjectSchema.loadsRelated(template);
        // With related records only a key's first row loads the parent (R-IT17).
        List<Item> parents = related ? groupByKey(batch, template, type, operation, items) : items;
        // An empty cell clears its field only where the column says so, and never on insert
        // (R-IT19).
        Set<String> clearing = operation == ImportObjectSchema.OPERATION_INSERT
            ? new Set<String>()
            : mapping.clearingAttributes();
        Map<String, Plan> plans = plan(
            type,
            mapping,
            parents,
            clearing,
            outcome,
            ImportMapping.ENTITY_RECORD
        );
        readValues(parents, plans, clearing);
        resolveLookups(
            parents,
            plans,
            ImportObjectSchema.leavesLookupEmpty(template),
            mostRecent,
            outcome
        );
        findRecords(batch, template, type, operation, parents, plans);
        if (template.Use_Duplicate_Rules__c == true && createsRecords(operation)) {
            // Only rows that would create are asked: a record ID or key match wins (R-IT16).
            matchByDuplicateRules(batch, type, parents, plans, mostRecent, outcome);
        }
        readRecords(type, parents, plans);
        if (operation == ImportObjectSchema.OPERATION_UPSERT) {
            rejectKeyConflicts(type, ImportObjectSchema.keyFieldOf(template), parents);
        }
        for (Item item : parents) {
            if (item.error == null && item.creates && batch.Match_Only__c == true) {
                // A file that only matches creates nothing (R-IB15).
                item.error = Label.Core_Import_ErrorMatchOnlyWouldCreate;
            }
        }
        decide(type, parents, plans, outcome);
        List<Map<String, Object>> created = new List<Map<String, Object>>();
        if (!dryRun) {
            save(type, parents, outcome, created);
        }
        List<Map<String, Object>> relatedCreated = new List<Map<String, Object>>();
        if (related) {
            loadRelated(batch, template, mapping, items, dryRun, outcome, relatedCreated);
        }
        writeBack(items, outcome);
        if (!dryRun && !journal(batch.Id, outcome.journal, created, relatedCreated)) {
            outcome.notes.add(Label.Core_Import_LogJournalFailed);
        }
        return outcome;
    }

    /** Each row's Record values, rejecting a row that cannot be read or holds nothing. */
    private static List<Item> read(
        Import_Batch__c batch,
        ImportMapping mapping,
        List<Import_Row__c> rows,
        Boolean related
    ) {
        List<Item> items = new List<Item>();
        Decimal pass = ImportRowSelector.passOf(batch);
        for (Import_Row__c row : rows) {
            ImportRowProcessor.startPass(row, pass);
            Map<String, Map<String, String>> byEntity = ImportRowProcessor.valuesByEntity(
                row,
                mapping
            );
            Item item = new Item(row, byEntity.get(ImportMapping.ENTITY_RECORD));
            item.relatedGiven = related ? byEntity.get(ImportMapping.ENTITY_RELATED) : null;
            if (String.isBlank(row.Raw_Values_JSON__c)) {
                item.error = Label.Core_Import_ErrorRowUnreadable;
            } else if (!hasAnyValue(item.held) && !hasAnyValue(item.relatedGiven)) {
                item.error = Label.Core_Import_ErrorRowEmpty;
            }
            items.add(item);
        }
        return items;
    }

    /**
     * Writes the update entries on Commit pages and the creations on Created pages (R-IJ3).
     * Related records go on pages written after their parents', so the undo, which reads the
     * newest page first, deletes them before the parents they point at (R-IT17).
     */
    private static Boolean journal(
        Id batchId,
        List<Map<String, Object>> updates,
        List<Map<String, Object>> created,
        List<Map<String, Object>> relatedCreated
    ) {
        Boolean updatesWritten = ImportJournalService.write(
            batchId,
            ImportJournalService.PHASE_COMMIT,
            updates
        );
        Boolean createdWritten = ImportJournalService.write(
            batchId,
            ImportJournalService.PHASE_CREATED,
            created
        );
        Boolean relatedWritten = ImportJournalService.write(
            batchId,
            ImportJournalService.PHASE_CREATED,
            relatedCreated
        );
        return updatesWritten && createdWritten && relatedWritten;
    }

    /**
     * Works out, once per chunk, what each mapped attribute is: a value field, a lookup and how
     * it names its parent, or something not loaded, said once in the run log (a field the object
     * does not have, or one that is protected, R-IT14). Access is asked when the record is built,
     * because an upsert does not know yet whether a row creates or updates.
     */
    private static Map<String, Plan> plan(
        Schema.SObjectType type,
        ImportMapping mapping,
        List<Item> items,
        Set<String> clearing,
        ImportRowProcessor.Outcome outcome,
        String entity
    ) {
        Map<String, Plan> plans = new Map<String, Plan>();
        Map<String, String> lookupFields = mapping.lookupFieldsByAttribute(entity);
        // A clearing column is planned even when every cell of the chunk is empty.
        Set<String> attributes = new Set<String>(clearing);
        for (Item item : items) {
            attributes.addAll(item.held.keySet());
        }
        attributes.remove(ImportObjectSchema.ID_ATTRIBUTE.toLowerCase());
        for (String attribute : attributes) {
            Schema.SObjectField token = ImportObjectSchema.fieldNamed(type, attribute);
            if (token == null) {
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogAttributeUnknown,
                        new List<String>{ attribute }
                    )
                );
                continue;
            }
            Schema.DescribeFieldResult field = token.getDescribe();
            if (DataProtectedFields.isProtected(type, field.getName())) {
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogFieldProtected,
                        new List<String>{ field.getLabel() }
                    )
                );
                continue;
            }
            Plan planned = new Plan();
            planned.attribute = attribute;
            planned.field = field;
            if (field.getType() == Schema.DisplayType.REFERENCE) {
                planLookup(type, planned, lookupFields.get(attribute), outcome);
            }
            plans.put(attribute, planned);
        }
        return plans;
    }

    /** How a lookup column names its parent (R-IT13). */
    private static void planLookup(
        Schema.SObjectType type,
        Plan planned,
        String chosen,
        ImportRowProcessor.Outcome outcome
    ) {
        planned.lookup = true;
        planned.parentType = ImportObjectSchema.parentOf(type, planned.field.getName());
        if (chosen == null) {
            return;
        }
        if (planned.parentType == null) {
            // A lookup to several objects is read by record ID only.
            outcome.notes.add(
                String.format(
                    Label.Core_Import_LogLookupPolymorphic,
                    new List<String>{ planned.field.getLabel() }
                )
            );
            return;
        }
        planned.parentField = ImportObjectSchema.parentField(planned.parentType, chosen);
        if (planned.parentField == null) {
            // Nothing is found by a field the user cannot search by; each row's rule decides.
            planned.findsNobody = true;
            outcome.notes.add(
                String.format(
                    Label.Core_Import_LogLookupFieldUnusable,
                    new List<String>{ planned.field.getLabel(), chosen.abbreviate(80) }
                )
            );
        }
    }

    /** Converts each row's values to their fields' types; one that cannot be read rejects it. */
    private static void readValues(
        List<Item> items,
        Map<String, Plan> plans,
        Set<String> clearing
    ) {
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            for (String attribute : clearing) {
                // An empty cell of a clearing column, with no value for every row to fill it,
                // clears the field; `decide` keeps it only for a record that holds a value.
                Plan planned = plans.get(attribute);
                if (planned != null && String.isBlank(item.held.get(attribute))) {
                    item.values.put(planned.field.getName(), null);
                }
            }
            for (String attribute : item.held.keySet()) {
                Plan planned = plans.get(attribute);
                String value = item.held.get(attribute);
                if (planned == null || planned.lookup || String.isBlank(value)) {
                    continue;
                }
                String problem = ImportObjectSchema.unreadable(value, planned.field);
                if (problem != null) {
                    item.error = problem;
                    break;
                }
                item.values.put(
                    planned.field.getName(),
                    ImportObjectSchema.typed(value, planned.field)
                );
            }
        }
    }

    /** Finds the parent each lookup column names, one query per column and chunk (R-IT13). */
    private static void resolveLookups(
        List<Item> items,
        Map<String, Plan> plans,
        Boolean leaveEmpty,
        Boolean mostRecent,
        ImportRowProcessor.Outcome outcome
    ) {
        for (Plan planned : plans.values()) {
            if (planned.lookup) {
                resolveLookup(items, planned, leaveEmpty, mostRecent, outcome);
            }
        }
    }

    private static void resolveLookup(
        List<Item> items,
        Plan planned,
        Boolean leaveEmpty,
        Boolean mostRecent,
        ImportRowProcessor.Outcome outcome
    ) {
        Set<String> keys = new Set<String>();
        for (Item item : items) {
            String value = item.held.get(planned.attribute);
            if (item.error == null && String.isNotBlank(value)) {
                keys.add(lookupKey(planned, value));
            }
        }
        if (keys.isEmpty()) {
            return;
        }
        Found found = planned.findsNobody
            ? new Found()
            : planned.parentField == null
                  ? parentsById(planned, keys)
                  : findBy(planned.parentType, planned.parentField, keys, mostRecent);
        Boolean leftEmpty = false;
        for (Item item : items) {
            String value = item.held.get(planned.attribute);
            if (item.error != null || String.isBlank(value)) {
                continue;
            }
            String key = lookupKey(planned, value);
            Id parent = found.ids.get(key);
            if (parent != null && found.several.contains(key)) {
                item.row.Several_Matches__c = true;
                if (!mostRecent) {
                    item.error = String.format(
                        Label.Core_Import_ErrorLookupSeveral,
                        new List<String>{ planned.field.getLabel(), value.abbreviate(80) }
                    );
                    continue;
                }
            }
            if (parent != null) {
                item.values.put(planned.field.getName(), parent);
            } else if (leaveEmpty) {
                leftEmpty = true;
            } else {
                item.error = String.format(
                    Label.Core_Import_ErrorLookupNotFound,
                    new List<String>{ planned.field.getLabel(), value.abbreviate(80) }
                );
            }
        }
        if (leftEmpty) {
            outcome.notes.add(
                String.format(
                    Label.Core_Import_LogLookupLeftEmpty,
                    new List<String>{ planned.field.getLabel() }
                )
            );
        }
    }

    private static String lookupKey(Plan planned, String value) {
        return planned.parentField == null ? value.trim() : ImportMatcher.nameKey(value);
    }

    /**
     * The parents named by record ID that the user can see, keyed by the value as given. A value
     * that is not an ID of an object the lookup points at is not found.
     */
    private static Found parentsById(Plan planned, Set<String> values) {
        Found result = new Found();
        Set<Schema.SObjectType> allowed = new Set<Schema.SObjectType>(
            planned.field.getReferenceTo()
        );
        Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();
        // A 15 and an 18 character form of one ID are one record, named by both values.
        Map<Id, List<String>> valuesById = new Map<Id, List<String>>();
        for (String value : values) {
            Id candidate = ImportValues.idOrNull(value);
            if (candidate == null || !allowed.contains(candidate.getSObjectType())) {
                continue;
            }
            if (!idsByType.containsKey(candidate.getSObjectType())) {
                idsByType.put(candidate.getSObjectType(), new Set<Id>());
            }
            idsByType.get(candidate.getSObjectType()).add(candidate);
            if (!valuesById.containsKey(candidate)) {
                valuesById.put(candidate, new List<String>());
            }
            valuesById.get(candidate).add(value);
        }
        for (Schema.SObjectType parentType : idsByType.keySet()) {
            for (Id seen : visibleIds(parentType, idsByType.get(parentType))) {
                for (String value : valuesById.get(seen)) {
                    result.ids.put(value, seen);
                }
            }
        }
        return result;
    }

    /** The records of these IDs the user can see, in user mode. */
    private static Set<Id> visibleIds(Schema.SObjectType type, Set<Id> ids) {
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        Set<Id> result = new Set<Id>();
        if (!described.isAccessible() || !described.isQueryable()) {
            return result;
        }
        for (
            SObject record : Database.queryWithBinds(
                'SELECT Id FROM ' + described.getName() + ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        ) {
            result.add(record.Id);
        }
        return result;
    }

    /**
     * The records of this object whose field holds one of these values, compared ignoring case,
     * in user mode, keyed by the value folded to lower case. A value several records hold is in
     * `several`, and the one kept is the first created, or the most recently changed when the
     * template says so (R-IT9). The field name comes from describe, never from the file.
     */
    private static Found findBy(
        Schema.SObjectType type,
        String fieldName,
        Set<String> keys,
        Boolean mostRecent
    ) {
        Found result = new Found();
        Schema.SObjectField token = ImportObjectSchema.fieldNamed(type, fieldName);
        if (token == null || !token.getDescribe().isFilterable()) {
            return result;
        }
        String field = token.getDescribe().getName();
        String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        Map<Id, Datetime> changedAt = new Map<Id, Datetime>();
        for (List<String> slice : ImportValues.slices(keys, ImportValues.KEYS_PER_QUERY)) {
            for (SObject record : findSlice(objectName, field, slice)) {
                String key = ImportMatcher.nameKey(String.valueOf(record.get(field)));
                Datetime changed = (Datetime) record.get('LastModifiedDate');
                changedAt.put(record.Id, changed);
                Id held = result.ids.get(key);
                if (held == null) {
                    result.ids.put(key, record.Id);
                    continue;
                }
                result.several.add(key);
                Datetime heldChanged = changedAt.get(held);
                if (
                    mostRecent &&
                    changed != null &&
                    (heldChanged == null ||
                    changed >= heldChanged)
                ) {
                    result.ids.put(key, record.Id);
                }
            }
        }
        return result;
    }

    /** One slice's worth of records found by a field, oldest first, in user mode. */
    private static List<SObject> findSlice(String objectName, String field, List<String> slice) {
        return Database.queryWithBinds(
            'SELECT Id, LastModifiedDate, ' +
                field +
                ' FROM ' +
                objectName +
                ' WHERE ' +
                field +
                ' IN :slice ORDER BY CreatedDate ASC, Id ASC LIMIT ' +
                ROWS_PER_QUERY,
            new Map<String, Object>{ 'slice' => slice },
            AccessLevel.USER_MODE
        );
    }

    /**
     * Finds the record each row names under Update by record Id, Update by a matching field and
     * Upsert by external ID, and rejects a row whose key an earlier row of the file used.
     */
    private static void findRecords(
        Import_Batch__c batch,
        Import_Template__c template,
        Schema.SObjectType type,
        String operation,
        List<Item> items,
        Map<String, Plan> plans
    ) {
        if (operation == ImportObjectSchema.OPERATION_INSERT) {
            for (Item item : items) {
                item.creates = item.error == null;
            }
            return;
        }
        String keyField = ImportObjectSchema.keyFieldOf(template);
        for (Item item : items) {
            if (item.error == null) {
                keyOf(item, type, operation, keyField);
            }
        }
        if (!ImportObjectSchema.loadsRelated(template)) {
            // With related records a repeated key is a later row of its parent (groupByKey).
            rejectRepeats(batch, items);
        }
        if (operation != ImportObjectSchema.OPERATION_UPDATE) {
            matchKeys(items, type, keyField, ImportTemplateService.usesMostRecent(template));
        }
        if (operation == ImportObjectSchema.OPERATION_UPDATE_BY_FIELD) {
            // An update creates nothing: a value no record holds rejects its row (R-IT12).
            for (Item item : items) {
                if (item.error == null && item.creates) {
                    item.creates = false;
                    item.error = String.format(
                        Label.Core_Import_ErrorNoRecordMatched,
                        new List<String>{ ImportObjectSchema.labelOf(type, keyField) }
                    );
                }
            }
        }
    }

    /**
     * Reads what each found record holds now, rejecting a row whose record the user can no
     * longer see.
     */
    private static void readRecords(
        Schema.SObjectType type,
        List<Item> items,
        Map<String, Plan> plans
    ) {
        Map<Id, SObject> stored = readStored(type, items, plans);
        for (Item item : items) {
            if (item.error != null || item.recordId == null) {
                continue;
            }
            item.stored = stored.get(item.recordId);
            if (item.stored == null) {
                item.error = Label.Core_Import_ErrorRecordNotFound;
            }
        }
    }

    /** Whether the operation can create a record, the only rows duplicate rules are asked of. */
    @TestVisible
    private static Boolean createsRecords(String operation) {
        return operation == ImportObjectSchema.OPERATION_INSERT ||
            operation == ImportObjectSchema.OPERATION_UPSERT;
    }

    /**
     * Asks the org's active duplicate rules for the object about each row that would create a
     * record (R-IT16), through `ImportDuplicateRuleMatcher` as a people import asks: the row's
     * values on an unsaved record, at most 50 a call, matches read back in the user's mode. A
     * row they match updates that record instead; several follow Several Matches (R-IT9). A
     * record an earlier chunk of this pass created or loaded is set aside before choosing,
     * because the dry run could not have seen it as the commit does, and a row whose matches
     * were all loaded by earlier rows is rejected, as a repeated key is. With no rule to ask,
     * the rows create and the run log says so; when a rule could not be run, the asked rows are
     * rejected rather than risk a duplicate.
     */
    private static void matchByDuplicateRules(
        Import_Batch__c batch,
        Schema.SObjectType type,
        List<Item> items,
        Map<String, Plan> plans,
        Boolean mostRecent,
        ImportRowProcessor.Outcome outcome
    ) {
        List<Item> asked = new List<Item>();
        List<SObject> probes = new List<SObject>();
        Set<Id> taken = new Set<Id>();
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            if (item.creates) {
                probes.add(
                    ImportDuplicateRuleMatcher.probe(
                        type,
                        probeValues(item, plans),
                        recordTypeOf(item)
                    )
                );
                asked.add(item);
            } else if (item.recordId != null) {
                taken.add(item.recordId);
            }
        }
        if (probes.isEmpty()) {
            return;
        }
        List<List<SObject>> found = ImportDuplicateRuleMatcher.matchesFor(probes, null);
        if (found == null && ImportDuplicateRuleMatcher.lastAskFailed()) {
            for (Item item : asked) {
                item.error = Label.Core_Import_ErrorDuplicateRulesUnavailable;
            }
            return;
        }
        if (found == null) {
            outcome.notes.add(Label.Core_Import_LogNoDuplicateRuleRecords);
            return;
        }
        Set<String> ids = new Set<String>();
        for (List<SObject> matches : found) {
            for (SObject matched : matches) {
                ids.add(String.valueOf(matched.Id));
            }
        }
        Map<String, Boolean> earlier = ImportRowSelector.resultingRecordsWrittenEarlier(batch, ids);
        for (Integer i = 0; i < asked.size(); i++) {
            Id matched = chosenByRule(asked[i], found[i], earlier, mostRecent);
            if (matched == null) {
                continue;
            }
            if (taken.contains(matched)) {
                asked[i].error = Label.Core_Import_ErrorDuplicateRuleRecordRepeated;
                continue;
            }
            taken.add(matched);
            asked[i].recordId = matched;
            asked[i].creates = false;
            asked[i].ruleMatch = true;
        }
    }

    /**
     * The record the rules matched for one row, or null: none, only records an earlier chunk
     * of this pass created, or several under a Several Matches that rejects the row. Records an
     * earlier chunk created or loaded are set aside first: a commit's earlier update changes
     * when a record was last changed, so keeping them could choose otherwise than the dry run.
     */
    private static Id chosenByRule(
        Item item,
        List<SObject> found,
        Map<String, Boolean> earlier,
        Boolean mostRecent
    ) {
        List<SObject> kept = new List<SObject>();
        Boolean loadedEarlier = false;
        for (SObject matched : found) {
            Boolean created = earlier.get(String.valueOf(matched.Id));
            if (created == null) {
                kept.add(matched);
            } else if (!created) {
                loadedEarlier = true;
            }
        }
        if (kept.isEmpty()) {
            if (loadedEarlier) {
                item.error = Label.Core_Import_ErrorDuplicateRuleRecordRepeated;
            }
            return null;
        }
        if (kept.size() > 1) {
            item.row.Several_Matches__c = true;
            if (!mostRecent) {
                item.error = Label.Core_Import_ErrorSeveralDuplicateRuleRecords;
                return null;
            }
        }
        return ImportDuplicateRuleMatcher.mostRecent(kept).Id;
    }

    /** The row's own values for the probe, keyed by field API name; lookups are left off. */
    private static Map<String, String> probeValues(Item item, Map<String, Plan> plans) {
        Map<String, String> result = new Map<String, String>();
        for (Plan planned : plans.values()) {
            String value = item.held.get(planned.attribute);
            if (!planned.lookup && String.isNotBlank(value)) {
                result.put(planned.field.getName(), value);
            }
        }
        return result;
    }

    /**
     * Rejects an upsert row the duplicate rules matched to a record that already holds another
     * value in the key field: loading it would overwrite that record's external ID. A blank key
     * is filled in; no other record can hold the row's key, or the key itself would have found
     * it.
     */
    private static void rejectKeyConflicts(
        Schema.SObjectType type,
        String keyField,
        List<Item> items
    ) {
        Schema.SObjectField token = ImportObjectSchema.fieldNamed(type, keyField);
        if (token == null) {
            return;
        }
        Schema.DescribeFieldResult field = token.getDescribe();
        for (Item item : items) {
            if (item.error != null || !item.ruleMatch || item.stored == null) {
                continue;
            }
            Object held = item.stored.getPopulatedFieldsAsMap().get(field.getName());
            if (
                held != null &&
                String.isNotBlank(String.valueOf(held)) &&
                ImportMatcher.nameKey(String.valueOf(held)) != item.key
            ) {
                item.error = String.format(
                    Label.Core_Import_ErrorDuplicateRuleKeyDiffers,
                    new List<String>{ field.getLabel() }
                );
            }
        }
    }

    /** The record type the row gives, so a rule for one record type compares like with like. */
    private static Id recordTypeOf(Item item) {
        Object given = item.values.get('RecordTypeId');
        return given instanceof Id ? (Id) given : null;
    }

    /**
     * Checks each row of a delete by record Id (R-BD7): an ID of the object, not named by an
     * earlier row, of a record the user can see now. A row that passes is Matched, with the
     * record as its Resulting Record, which the bulk delete job reads.
     */
    private static void checkDeletes(
        Import_Batch__c batch,
        Schema.SObjectType type,
        List<Item> items
    ) {
        for (Item item : items) {
            if (item.error == null) {
                keyOf(item, type, ImportObjectSchema.OPERATION_DELETE, null);
            }
        }
        rejectRepeats(batch, items);
        Set<Id> ids = new Set<Id>();
        for (Item item : items) {
            if (item.error == null) {
                ids.add(item.recordId);
            }
        }
        Set<Id> visible = ids.isEmpty() ? new Set<Id>() : visibleIds(type, ids);
        for (Item item : items) {
            if (item.error == null && !visible.contains(item.recordId)) {
                item.error = Label.Core_Import_ErrorRecordNotFound;
            }
        }
    }

    /** The row's record key: its record ID under Update, its upsert value under Upsert. */
    private static void keyOf(
        Item item,
        Schema.SObjectType type,
        String operation,
        String keyField
    ) {
        if (
            operation == ImportObjectSchema.OPERATION_UPDATE ||
            operation == ImportObjectSchema.OPERATION_DELETE
        ) {
            String value = item.held.get(ImportObjectSchema.ID_ATTRIBUTE.toLowerCase());
            Id candidate = ImportValues.idOrNull(value);
            if (candidate == null) {
                item.error = String.format(
                    Label.Core_Import_ErrorRecordIdInvalid,
                    new List<String>{ String.isBlank(value) ? '' : value.abbreviate(40) }
                );
            } else if (candidate.getSObjectType() != type) {
                item.error = String.format(
                    Label.Core_Import_ErrorRecordIdWrongObject,
                    new List<String>{
                        value.abbreviate(40),
                        type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel()
                    }
                );
            } else {
                item.recordId = candidate;
                item.key = String.valueOf(candidate);
            }
            return;
        }
        String value = item.held.get(keyField.toLowerCase());
        if (value == null) {
            value = item.held.get(ImportObjectSchema.localName(keyField.toLowerCase()));
        }
        if (String.isBlank(value)) {
            item.error = String.format(
                operation == ImportObjectSchema.OPERATION_UPSERT
                    ? Label.Core_Import_ErrorKeyMissing
                    : Label.Core_Import_ErrorMatchValueMissing,
                new List<String>{ ImportObjectSchema.labelOf(type, keyField) }
            );
            return;
        }
        item.key = ImportMatcher.nameKey(value);
    }

    /** Finds each upsert row's record by its key; none found means the row creates one. */
    private static void matchKeys(
        List<Item> items,
        Schema.SObjectType type,
        String keyField,
        Boolean mostRecent
    ) {
        Set<String> keys = new Set<String>();
        for (Item item : items) {
            if (item.error == null) {
                keys.add(item.key);
            }
        }
        Found found = keys.isEmpty() ? new Found() : findBy(type, keyField, keys, mostRecent);
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            Id match = found.ids.get(item.key);
            if (match != null && found.several.contains(item.key)) {
                item.row.Several_Matches__c = true;
                if (!mostRecent) {
                    item.error = Label.Core_Import_ErrorSeveralRecords;
                    continue;
                }
            }
            item.recordId = match;
            item.creates = match == null;
        }
    }

    /**
     * Rejects a row whose record key an earlier row of this file used: in this chunk, or in an
     * earlier chunk of the same pass, found by digest. Every other row with a key carries its
     * digest for the chunks after it, in the dry run and the commit alike.
     */
    private static void rejectRepeats(Import_Batch__c batch, List<Item> items) {
        Set<String> digests = new Set<String>();
        for (Item item : items) {
            if (item.error == null && item.key != null) {
                digests.add(ImportValues.digest(RECORD_DIGEST, item.key));
            }
        }
        if (digests.isEmpty()) {
            return;
        }
        Set<String> earlier = ImportRowSelector.processorDigestsWrittenEarlier(batch, digests);
        Set<String> inChunk = new Set<String>();
        for (Item item : items) {
            if (item.error != null || item.key == null) {
                continue;
            }
            String digest = ImportValues.digest(RECORD_DIGEST, item.key);
            if (earlier.contains(digest) || inChunk.contains(digest)) {
                item.error = Label.Core_Import_ErrorRecordRepeated;
                continue;
            }
            inChunk.add(digest);
            item.row.Processor_Key__c = digest;
        }
    }

    /**
     * The records the rows update, with the mapped fields the user may read, in user mode, so a
     * change can be compared and its value before journaled. A field the user cannot read is
     * never written to a record that exists (`decide`).
     */
    private static Map<Id, SObject> readStored(
        Schema.SObjectType type,
        List<Item> items,
        Map<String, Plan> plans
    ) {
        Set<Id> ids = new Set<Id>();
        for (Item item : items) {
            if (item.error == null && item.recordId != null) {
                ids.add(item.recordId);
            }
        }
        if (ids.isEmpty()) {
            return new Map<Id, SObject>();
        }
        Set<String> selected = new Set<String>{ 'Id' };
        Schema.SObjectField recordType = ImportObjectSchema.fieldNamed(type, 'RecordTypeId');
        if (recordType != null && recordType.getDescribe().isAccessible()) {
            selected.add('RecordTypeId');
        }
        for (Plan planned : plans.values()) {
            if (planned.field.isAccessible()) {
                selected.add(planned.field.getName());
            }
        }
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT ' +
                    String.join(new List<String>(selected), ', ') +
                    ' FROM ' +
                    type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
                    ' WHERE Id IN :ids LIMIT ' +
                    READ_LIMIT,
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        );
    }

    /**
     * Decides what each row does, the same in the dry run as in the commit: a new record with
     * every value the user may set on one, or the values that differ on an existing record that
     * the user may read and edit, leaving a household's name alone (R-IT14). A field skipped for
     * access is named once in the run log.
     */
    private static void decide(
        Schema.SObjectType type,
        List<Item> items,
        Map<String, Plan> plans,
        ImportRowProcessor.Outcome outcome
    ) {
        Map<String, Schema.DescribeFieldResult> byName = new Map<String, Schema.DescribeFieldResult>();
        for (Plan planned : plans.values()) {
            byName.put(planned.field.getName(), planned.field);
        }
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            Map<String, Object> kept = new Map<String, Object>();
            Id recordType = item.stored == null ||
                !item.stored.getPopulatedFieldsAsMap().containsKey('RecordTypeId')
                ? null
                : (Id) item.stored.get('RecordTypeId');
            for (String name : item.values.keySet()) {
                Schema.DescribeFieldResult field = byName.get(name);
                Boolean clears = item.values.get(name) == null;
                if (clears && item.creates) {
                    // A new record has nothing to clear (R-IT19).
                    continue;
                }
                if (
                    clears && (!field.isNillable() || field.getType() == Schema.DisplayType.BOOLEAN)
                ) {
                    outcome.notes.add(
                        String.format(
                            Label.Core_Import_LogCannotClear,
                            new List<String>{ field.getLabel() }
                        )
                    );
                    continue;
                }
                if (!mayWrite(field, item.creates)) {
                    outcome.notes.add(noAccess(field));
                } else if (
                    !item.creates && DataProtectedFields.isProtectedOnRecord(type, name, recordType)
                ) {
                    outcome.notes.add(
                        String.format(
                            Label.Core_Import_LogFieldProtected,
                            new List<String>{ field.getLabel() }
                        )
                    );
                } else if (
                    item.creates || !ImportValues.same(item.stored.get(name), item.values.get(name))
                ) {
                    kept.put(name, item.values.get(name));
                    outcome.cleared += clears ? 1 : 0;
                }
            }
            item.values = kept;
            item.changes = item.creates || !kept.isEmpty();
        }
    }

    /**
     * Saves the chunk's new records and changes in the running user's own mode, each record on
     * its own and past a duplicate rule that only alerts, as the people import saves, and
     * journals each creation and each update with the values it replaced (R-IJ3).
     */
    private static void save(
        Schema.SObjectType type,
        List<Item> items,
        ImportRowProcessor.Outcome outcome,
        List<Map<String, Object>> createdEntries
    ) {
        String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        List<SObject> toCreate = new List<SObject>();
        List<Item> creators = new List<Item>();
        List<SObject> toUpdate = new List<SObject>();
        List<Item> updaters = new List<Item>();
        for (Item item : items) {
            if (item.error != null || !item.changes) {
                continue;
            }
            SObject record = item.creates ? type.newSObject() : type.newSObject(item.recordId);
            for (String name : item.values.keySet()) {
                record.put(name, item.values.get(name));
            }
            if (item.creates) {
                toCreate.add(record);
                creators.add(item);
            } else {
                toUpdate.add(record);
                updaters.add(item);
            }
        }
        List<Database.SaveResult> created = toCreate.isEmpty()
            ? new List<Database.SaveResult>()
            : Database.insert(toCreate, ImportRowProcessor.saveOptions(), AccessLevel.USER_MODE);
        for (Integer i = 0; i < created.size(); i++) {
            Item item = creators[i];
            if (created[i].isSuccess()) {
                item.recordId = created[i].getId();
                createdEntries.add(
                    ImportJournalService.created(
                        objectName,
                        item.recordId,
                        ImportValues.rowNumber(item.row)
                    )
                );
            } else {
                item.error = ImportRowProcessor.message(created[i]);
            }
        }
        List<Database.SaveResult> updated = toUpdate.isEmpty()
            ? new List<Database.SaveResult>()
            : Database.update(toUpdate, ImportRowProcessor.saveOptions(), AccessLevel.USER_MODE);
        for (Integer i = 0; i < updated.size(); i++) {
            Item item = updaters[i];
            if (!updated[i].isSuccess()) {
                item.error = ImportRowProcessor.message(updated[i]);
                continue;
            }
            Map<String, Object> before = new Map<String, Object>();
            for (String name : item.values.keySet()) {
                before.put(name, item.stored.get(name));
            }
            outcome.journal.add(
                ImportJournalService.updated(
                    objectName,
                    item.recordId,
                    ImportValues.rowNumber(item.row),
                    before,
                    item.values
                )
            );
        }
    }

    // -------------------------------------------------------------------------------------
    // Related records (R-IT17)
    // -------------------------------------------------------------------------------------

    /**
     * Returns the chunk's parent rows: the first row of each key in the pass. A later row of a
     * key points at its parent row's item when that row is in this chunk, or follows one from
     * an earlier chunk, known by the digest that row wrote; a key whose parent row failed
     * rejects the row. A row without a key is rejected by `keyOf`.
     */
    private static List<Item> groupByKey(
        Import_Batch__c batch,
        Import_Template__c template,
        Schema.SObjectType type,
        String operation,
        List<Item> items
    ) {
        String keyField = ImportObjectSchema.keyFieldOf(template);
        Set<String> digests = new Set<String>();
        for (Item item : items) {
            if (item.error == null) {
                keyOf(item, type, operation, keyField);
            }
            if (item.error == null) {
                digests.add(ImportValues.digest(RECORD_DIGEST, item.key));
                digests.add(ImportValues.digest(FAILED_DIGEST, item.key));
            }
        }
        Set<String> earlier = digests.isEmpty()
            ? new Set<String>()
            : ImportRowSelector.processorDigestsWrittenEarlier(batch, digests);
        Map<String, Item> leaders = new Map<String, Item>();
        List<Item> parents = new List<Item>();
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            if (earlier.contains(ImportValues.digest(FAILED_DIGEST, item.key))) {
                item.error = Label.Core_Import_ErrorRelatedParentFailed;
            } else if (earlier.contains(ImportValues.digest(RECORD_DIGEST, item.key))) {
                item.follows = true;
            } else if (leaders.containsKey(item.key)) {
                item.leader = leaders.get(item.key);
            } else {
                item.leads = true;
                leaders.put(item.key, item);
                parents.add(item);
            }
        }
        return parents;
    }

    /**
     * Gives each later row of a key its parent, once the parents are saved: its parent row's
     * record when that row is in this chunk, or in a commit the record its key finds now when
     * it was in an earlier chunk, under Several Matches. A failed parent rejects the row. A dry
     * run needs no ID for a parent an earlier chunk would create.
     */
    private static void linkParents(
        Import_Template__c template,
        Schema.SObjectType type,
        List<Item> items,
        Boolean dryRun
    ) {
        String operation = ImportObjectSchema.operationOf(template);
        List<Item> earlier = new List<Item>();
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            if (item.leader != null) {
                item.recordId = item.leader.recordId;
                if (item.leader.error != null) {
                    item.error = Label.Core_Import_ErrorRelatedParentFailed;
                }
            } else if (
                item.follows &&
                !dryRun &&
                operation != ImportObjectSchema.OPERATION_UPDATE
            ) {
                earlier.add(item);
            }
        }
        if (earlier.isEmpty()) {
            return;
        }
        matchKeys(
            earlier,
            type,
            ImportObjectSchema.keyFieldOf(template),
            ImportTemplateService.usesMostRecent(template)
        );
        for (Item item : earlier) {
            item.creates = false;
            if (item.error == null && item.recordId == null) {
                item.error = Label.Core_Import_ErrorRelatedParentFailed;
            }
        }
    }

    /**
     * Creates each row's related record after the parents are saved, through the same plan,
     * value reading, lookups and access checks as the parents, with the Related Parent Field
     * set to the row's parent. A row whose parent failed has its related record rejected and
     * nothing created; under Match only every related record is rejected, since it would be
     * created. A dry run decides the same and saves nothing.
     */
    private static void loadRelated(
        Import_Batch__c batch,
        Import_Template__c template,
        ImportMapping mapping,
        List<Item> items,
        Boolean dryRun,
        ImportRowProcessor.Outcome outcome,
        List<Map<String, Object>> createdEntries
    ) {
        Schema.SObjectType type = ImportObjectSchema.typeOf(template);
        Schema.SObjectType relatedType = ImportObjectSchema.relatedTypeOf(template);
        String parentField = ImportObjectSchema.relatedParentField(
            type,
            relatedType,
            template.Related_Parent_Field__c
        );
        linkParents(template, type, items, dryRun);
        List<Item> children = new List<Item>();
        for (Item item : items) {
            if (hasAnyValue(item.relatedGiven)) {
                item.related = new Item(item.row, item.relatedGiven);
                item.related.creates = true;
                children.add(item.related);
            }
        }
        if (children.isEmpty()) {
            return;
        }
        Map<String, Plan> plans = plan(
            relatedType,
            mapping,
            children,
            new Set<String>(),
            outcome,
            ImportMapping.ENTITY_RELATED
        );
        for (String attribute : new List<String>(plans.keySet())) {
            Schema.DescribeFieldResult field = plans.get(attribute).field;
            if (field.getName() == parentField) {
                plans.remove(attribute);
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogRelatedParentFieldSkipped,
                        new List<String>{ field.getLabel() }
                    )
                );
            }
        }
        // A related record is always created, so it has nothing to clear (R-IT19).
        readValues(children, plans, new Set<String>());
        resolveLookups(
            children,
            plans,
            ImportObjectSchema.leavesLookupEmpty(template),
            ImportTemplateService.usesMostRecent(template),
            outcome
        );
        for (Item item : items) {
            Item child = item.related;
            if (child == null || child.error != null) {
                continue;
            }
            if (item.error != null || (!dryRun && item.recordId == null)) {
                child.error = Label.Core_Import_ErrorRelatedParentFailed;
            } else if (batch.Match_Only__c == true) {
                child.error = Label.Core_Import_ErrorMatchOnlyWouldCreate;
            }
        }
        decide(relatedType, children, plans, outcome);
        for (Item item : items) {
            if (item.related != null && item.related.error == null && item.recordId != null) {
                item.related.values.put(parentField, item.recordId);
            }
        }
        if (!dryRun) {
            save(relatedType, children, outcome, createdEntries);
        }
    }

    /**
     * The run log's line on related records (R-IT17): how many were created, or would be, and
     * how many were not. Empty for an import without them. Read from the rows, so a resumed run
     * still reports the truth.
     */
    @NamespaceAccessible
    public static List<String> relatedLines(Id batchId, Boolean dryRun) {
        Map<String, Integer> counts = ImportBatchSelector.countRelatedByStatus(batchId);
        if (counts.isEmpty()) {
            return new List<String>();
        }
        Integer created = counts.get(ImportRowProcessor.STATUS_CREATED);
        Integer rejected = counts.get(ImportRowProcessor.STATUS_REJECTED);
        return new List<String>{
            String.format(
                dryRun == true
                    ? Label.Core_Import_LogRelatedDryRun
                    : Label.Core_Import_LogRelatedCommit,
                new List<String>{
                    String.valueOf(created == null ? 0 : created),
                    String.valueOf(rejected == null ? 0 : rejected)
                }
            )
        };
    }

    /**
     * Writes each row's outcome back, in system mode (ADR-0021): Rejected with the reason,
     * Created, Updated, or Matched when the record already held every value, with the record it
     * resulted in as its Resulting Record.
     */
    private static void writeBack(List<Item> items, ImportRowProcessor.Outcome outcome) {
        List<Import_Row__c> rows = new List<Import_Row__c>();
        for (Item item : items) {
            Import_Row__c row = item.row;
            String error = item.error;
            if (item.related != null) {
                // The row's related record (R-IT17): a refusal rejects the row, not its parent.
                row.Related_Status__c = item.related.error == null
                    ? ImportRowProcessor.STATUS_CREATED
                    : ImportRowProcessor.STATUS_REJECTED;
                row.Soft_Credit_Id__c = item.related.error == null &&
                    item.related.recordId != null
                    ? String.valueOf(item.related.recordId)
                    : null;
                if (error == null && item.related.error != null) {
                    error = String.format(
                        Label.Core_Import_ErrorRelatedRecord,
                        new List<String>{ item.related.error }
                    );
                }
            }
            if (error != null) {
                row.Status__c = ImportRowProcessor.STATUS_REJECTED;
                row.Error_Message__c = error.abbreviate(4000);
                row.Processor_Key__c = null;
                outcome.rejected++;
            } else if (item.creates) {
                row.Status__c = ImportRowProcessor.STATUS_CREATED;
                outcome.created++;
            } else if (item.changes) {
                row.Status__c = ImportRowProcessor.STATUS_UPDATED;
                outcome.updated++;
            } else {
                row.Status__c = ImportRowProcessor.STATUS_MATCHED;
                outcome.matched++;
            }
            // Ticked so the rows a looser rule matched can be read before a commit (R-IT16).
            row.Duplicate_Rule_Match__c = item.ruleMatch && error == null;
            if (row.Duplicate_Rule_Match__c) {
                outcome.notes.add(Label.Core_Import_LogDuplicateRuleMatchesRecords);
            }
            // A parent saved for a row whose related record failed stays its resulting record.
            row.Gift_Id__c = item.error == null &&
                item.recordId != null
                ? String.valueOf(item.recordId)
                : null;
            if (item.leads) {
                // Later chunks read whether this key's parent was saved (R-IT17).
                row.Processor_Key__c = ImportValues.digest(
                    item.error == null ? RECORD_DIGEST : FAILED_DIGEST,
                    item.key
                );
            }
            rows.add(row);
        }
        ImportRowProcessor.saveRows(rows, outcome, 'ImportObjectLoader.writeBack');
    }

    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    private static Boolean hasAnyValue(Map<String, String> held) {
        if (held == null) {
            return false;
        }
        for (String value : held.values()) {
            if (String.isNotBlank(value)) {
                return true;
            }
        }
        return false;
    }

    /** A new record needs create access to the field; a change needs read and edit access. */
    private static Boolean mayWrite(Schema.DescribeFieldResult field, Boolean creates) {
        return creates ? field.isCreateable() : field.isUpdateable() && field.isAccessible();
    }

    private static String noAccess(Schema.DescribeFieldResult field) {
        return String.format(
            Label.Core_Import_LogAttributeNoAccess,
            new List<String>{ field.getLabel() }
        );
    }
}
