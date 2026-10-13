/**
 * Loads one chunk of a one-object template (canonical model R-IT12 to R-IT14; ADR-0080
 * `0080-import-load-one-object.md`): Insert, Update by record Id, or Upsert by external ID, for
 * any object `ImportObjectSchema` admits, custom ones included.
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
 */
@NamespaceAccessible
public with sharing class ImportObjectLoader {
    /** Prefixes a record key before its digest, apart from people and organizations. */
    private static final String RECORD_DIGEST = 'record:';

    /** How many records one read of stored values takes, a chunk's worth and more. */
    private static final Integer READ_LIMIT = 10000;

    /** How many values one lookup query carries. */
    private static final Integer KEYS_PER_QUERY = 1000;

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
        String error;

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
        List<Item> items = read(batch, mapping, rows);
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
        Boolean mostRecent = ImportTemplateService.usesMostRecent(template);
        Map<String, Plan> plans = plan(type, mapping, items, outcome);
        readValues(items, plans);
        resolveLookups(
            items,
            plans,
            ImportObjectSchema.leavesLookupEmpty(template),
            mostRecent,
            outcome
        );
        findRecords(batch, template, type, operation, items, plans);
        for (Item item : items) {
            if (item.error == null && item.creates && batch.Match_Only__c == true) {
                // A file that only matches creates nothing (R-IB15).
                item.error = Label.Core_Import_ErrorMatchOnlyWouldCreate;
            }
        }
        decide(type, items, plans, outcome);
        List<Map<String, Object>> created = new List<Map<String, Object>>();
        if (!dryRun) {
            save(type, items, outcome, created);
        }
        writeBack(items, outcome);
        if (!dryRun && !journal(batch.Id, outcome.journal, created)) {
            outcome.notes.add(Label.Core_Import_LogJournalFailed);
        }
        return outcome;
    }

    /** Each row's Record values, rejecting a row that cannot be read or holds nothing. */
    private static List<Item> read(
        Import_Batch__c batch,
        ImportMapping mapping,
        List<Import_Row__c> rows
    ) {
        List<Item> items = new List<Item>();
        Decimal pass = ImportRowSelector.passOf(batch);
        for (Import_Row__c row : rows) {
            ImportRowProcessor.startPass(row, pass);
            Item item = new Item(
                row,
                ImportRowProcessor.valuesByEntity(row, mapping).get(ImportMapping.ENTITY_RECORD)
            );
            if (String.isBlank(row.Raw_Values_JSON__c)) {
                item.error = Label.Core_Import_ErrorRowUnreadable;
            } else if (!hasAnyValue(item.held)) {
                item.error = Label.Core_Import_ErrorRowEmpty;
            }
            items.add(item);
        }
        return items;
    }

    /** Writes the update entries on Commit pages and the creations on Created pages (R-IJ3). */
    private static Boolean journal(
        Id batchId,
        List<Map<String, Object>> updates,
        List<Map<String, Object>> created
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
        return updatesWritten && createdWritten;
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
        ImportRowProcessor.Outcome outcome
    ) {
        Map<String, Plan> plans = new Map<String, Plan>();
        Map<String, String> lookupFields = mapping.lookupFieldsByAttribute();
        Set<String> attributes = new Set<String>();
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
    private static void readValues(List<Item> items, Map<String, Plan> plans) {
        for (Item item : items) {
            if (item.error != null) {
                continue;
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
            Id candidate = idOrNull(value);
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
        for (List<String> slice : slices(keys)) {
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
     * Finds the record each row names under Update by record Id and Upsert by external ID,
     * reads what it holds now, and rejects a row whose key an earlier row of the file used.
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
        rejectRepeats(batch, items);
        if (operation == ImportObjectSchema.OPERATION_UPSERT) {
            matchKeys(items, type, keyField, ImportTemplateService.usesMostRecent(template));
        }
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

    /** The row's record key: its record ID under Update, its upsert value under Upsert. */
    private static void keyOf(
        Item item,
        Schema.SObjectType type,
        String operation,
        String keyField
    ) {
        if (operation == ImportObjectSchema.OPERATION_UPDATE) {
            String value = item.held.get(ImportObjectSchema.ID_ATTRIBUTE.toLowerCase());
            Id candidate = idOrNull(value);
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
                Label.Core_Import_ErrorKeyMissing,
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
                digests.add(digest(item.key));
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
            String digest = digest(item.key);
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
                } else if (item.creates || !same(item.stored.get(name), item.values.get(name))) {
                    kept.put(name, item.values.get(name));
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
                    ImportJournalService.created(objectName, item.recordId, rowNumber(item.row))
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
                    rowNumber(item.row),
                    before,
                    item.values
                )
            );
        }
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
            if (item.error != null) {
                row.Status__c = ImportRowProcessor.STATUS_REJECTED;
                row.Error_Message__c = item.error.abbreviate(4000);
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
            row.Gift_Id__c = item.error == null &&
                item.recordId != null
                ? String.valueOf(item.recordId)
                : null;
            rows.add(row);
        }
        ImportRowProcessor.saveRows(rows, outcome, 'ImportObjectLoader.writeBack');
    }

    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    private static Boolean hasAnyValue(Map<String, String> held) {
        for (String value : held.values()) {
            if (String.isNotBlank(value)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Whether a stored value equals the one a row would write, as the undo compares them
     * (R-IJ2): numbers as numbers, IDs in either length, and text exactly, since a correction of
     * capitals is a correction.
     */
    private static Boolean same(Object stored, Object incoming) {
        if (stored == null || incoming == null) {
            return stored == null && incoming == null;
        }
        if (
            incoming instanceof Decimal ||
            incoming instanceof Integer ||
            incoming instanceof Long
        ) {
            return Decimal.valueOf(String.valueOf(stored)) ==
                Decimal.valueOf(String.valueOf(incoming));
        }
        if (incoming instanceof Id) {
            return idOrNull(String.valueOf(stored)) == incoming;
        }
        if (
            incoming instanceof Date ||
            incoming instanceof Datetime ||
            incoming instanceof Time ||
            incoming instanceof Boolean
        ) {
            return stored == incoming;
        }
        return String.valueOf(stored).equals(String.valueOf(incoming));
    }

    private static Id idOrNull(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception notAnId) {
            return null;
        }
    }

    /** A record key as sixteen hex digits, as the people import digests its keys. */
    private static String digest(String key) {
        return EncodingUtil.convertToHex(
                Crypto.generateDigest('MD5', Blob.valueOf(RECORD_DIGEST + key))
            )
            .left(16);
    }

    private static Integer rowNumber(Import_Row__c row) {
        return row == null || row.Row_Number__c == null ? null : row.Row_Number__c.intValue();
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

    /** The keys cut into query-sized lists, with blanks dropped. */
    private static List<List<String>> slices(Set<String> keys) {
        List<List<String>> result = new List<List<String>>();
        List<String> current = new List<String>();
        for (String key : keys) {
            if (String.isBlank(key)) {
                continue;
            }
            current.add(key);
            if (current.size() == KEYS_PER_QUERY) {
                result.add(current);
                current = new List<String>();
            }
        }
        if (!current.isEmpty()) {
            result.add(current);
        }
        return result;
    }
}
