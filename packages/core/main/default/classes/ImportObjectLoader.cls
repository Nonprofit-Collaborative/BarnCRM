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
 * A chunk loads in steps (R-IT20; ADR-NEXT `NEXT-several-objects-in-one-upload.md`): one for a
 * one-object template, two with a Related Object (R-IT17; ADR-0111), one per object for an
 * upload of several objects, parents first. Each step runs the one-object load above over the
 * rows that give its object values. A record links to its row's record of each earlier step
 * its object points at; a step that later steps link to groups repeated keys, so the first row
 * of a key loads the parent and later rows link to it. A row whose parent failed is rejected
 * for that object, and a row is Rejected when any of its objects is.
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
        /** True for the first row of its key, which loads the parent (R-IT17, R-IT20). */
        Boolean leads = false;
        /** A later row of a key whose parent row is in this chunk: that row's item. */
        Item leader;
        /** A later row of a key whose parent row was in an earlier chunk. */
        Boolean follows = false;
        /** The link field to this row's record of each earlier step it points at (R-IT20). */
        Map<String, Item> parents = new Map<String, Item>();
        /** In a dry run, an existing record would be linked to a parent the commit creates. */
        Boolean linksNew = false;
        /** The record an earlier pass created for this row, reused as it is (R-IT20). */
        Boolean reused = false;

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
        List<ImportObjectSchema.Step> steps = ImportObjectSchema.steps(template, mapping);
        List<Line> lines = read(batch, mapping, rows, steps);
        String refused = ImportObjectSchema.refusal(template, mapping);
        if (refused != null) {
            // Nothing can load: every row says why, in words the administrator can act on.
            for (Line line : lines) {
                line.error = refused;
            }
            writeBack(lines, steps, outcome);
            return outcome;
        }
        if (
            ImportObjectSchema.operationOf(steps[0].template) == ImportObjectSchema.OPERATION_DELETE
        ) {
            // Delete by record Id (R-BD7) only checks each row; the bulk delete job deletes.
            checkDeletes(batch, steps[0].type, itemsOf(lines, 0));
            writeBack(lines, steps, outcome);
            return outcome;
        }
        Boolean several = mapping.loadsSeveralObjects();
        Set<Schema.SObjectType> created = several && dryRun ? createdHere(steps) : null;
        if (several) {
            // A row loaded again reuses what an earlier pass created for it (R-IT20).
            reuseLoaded(batch, lines, steps);
        }
        List<List<Map<String, Object>>> createdPages = new List<List<Map<String, Object>>>();
        for (Integer index = 0; index < steps.size(); index++) {
            List<Map<String, Object>> page = new List<Map<String, Object>>();
            Step step = new Step(steps, index, created);
            attachParents(lines, step.given, index);
            load(batch, step, loadable(itemsOf(lines, index)), dryRun, outcome, page);
            createdPages.add(page);
        }
        writeBack(lines, steps, outcome, several && !dryRun);
        if (!dryRun && !journal(batch.Id, outcome.journal, createdPages)) {
            outcome.notes.add(Label.Core_Import_LogJournalFailed);
        }
        return outcome;
    }

    /** One step of the chunk as the loader runs it (R-IT20). */
    private class Step {
        ImportObjectSchema.Step given;
        Import_Template__c template;
        Schema.SObjectType type;
        String operation;
        /** In a dry run of several objects, the objects this upload may create, else null. */
        Set<Schema.SObjectType> createdHere;

        Step(List<ImportObjectSchema.Step> steps, Integer index, Set<Schema.SObjectType> created) {
            given = steps[index];
            template = given.template;
            type = given.type;
            operation = ImportObjectSchema.operationOf(template);
            createdHere = created;
        }
    }

    /**
     * The objects an upload of several objects may create, under Insert or Upsert: in a dry
     * run, a lookup to one of them that finds nothing may name a record the commit creates.
     */
    private static Set<Schema.SObjectType> createdHere(List<ImportObjectSchema.Step> steps) {
        Set<Schema.SObjectType> result = new Set<Schema.SObjectType>();
        for (ImportObjectSchema.Step step : steps) {
            if (createsRecords(ImportObjectSchema.operationOf(step.template))) {
                result.add(step.type);
            }
        }
        return result;
    }

    /** One row of the chunk and its record of each step, null where it loads none (R-IT20). */
    private class Line {
        Import_Row__c row;
        /** Why the whole row is rejected before any step: unreadable, empty or refused. */
        String error;
        List<Item> items = new List<Item>();
        /** The records earlier passes created for this row, by object in lower case (R-IT20). */
        Map<String, Id> loaded = new Map<String, Id>();

        Line(Import_Row__c row) {
            this.row = row;
        }
    }

    /**
     * Each row's values for each step, rejecting a row that cannot be read or holds nothing. A
     * row loads a step's object when it has a value for it; with several objects, a value of
     * its own, not one for every row, so a sheet of one object creates none of another.
     */
    private static List<Line> read(
        Import_Batch__c batch,
        ImportMapping mapping,
        List<Import_Row__c> rows,
        List<ImportObjectSchema.Step> steps
    ) {
        List<Line> lines = new List<Line>();
        Decimal pass = ImportRowSelector.passOf(batch);
        ImportMapping bare = null;
        if (mapping.loadsSeveralObjects()) {
            bare = new ImportMapping();
            bare.columns = mapping.columns;
        }
        for (Import_Row__c row : rows) {
            ImportRowProcessor.startPass(row, pass);
            Line line = new Line(row);
            Map<String, Map<String, String>> byEntity = ImportRowProcessor.valuesByEntity(
                row,
                mapping
            );
            Map<String, Map<String, String>> own = bare == null
                ? byEntity
                : ImportRowProcessor.valuesByEntity(row, bare);
            Boolean hasValues = false;
            for (ImportObjectSchema.Step step : steps) {
                Map<String, String> given = valuesOf(byEntity, step.entity);
                Boolean has = hasAnyValue(step.needsOwnValue ? valuesOf(own, step.entity) : given);
                line.items.add(has || step.everyRow ? new Item(row, given) : null);
                hasValues = hasValues || has;
            }
            if (String.isBlank(row.Raw_Values_JSON__c)) {
                line.error = Label.Core_Import_ErrorRowUnreadable;
            } else if (!hasValues) {
                line.error = Label.Core_Import_ErrorRowEmpty;
            }
            lines.add(line);
        }
        return lines;
    }

    /** One entity's values of a row, the entity's name compared ignoring capitals. */
    private static Map<String, String> valuesOf(
        Map<String, Map<String, String>> byEntity,
        String entity
    ) {
        if (byEntity.containsKey(entity)) {
            return byEntity.get(entity);
        }
        for (String each : byEntity.keySet()) {
            if (each != null && each.equalsIgnoreCase(entity)) {
                return byEntity.get(each);
            }
        }
        return null;
    }

    /** Gives each record of a step its row's records of the earlier steps it points at. */
    private static void attachParents(
        List<Line> lines,
        ImportObjectSchema.Step step,
        Integer index
    ) {
        for (Line line : lines) {
            Item item = line.items[index];
            if (item == null) {
                continue;
            }
            for (Integer parent : step.links.keySet()) {
                String fieldName = step.links.get(parent);
                if (fieldName != null && line.items[parent] != null) {
                    item.parents.put(fieldName, line.items[parent]);
                }
            }
        }
    }

    /** The items of one step, of the rows not rejected before any step. */
    private static List<Item> itemsOf(List<Line> lines, Integer index) {
        List<Item> result = new List<Item>();
        for (Line line : lines) {
            Item item = line.error == null ? line.items[index] : null;
            if (item != null) {
                result.add(item);
            }
        }
        return result;
    }

    /** The items a step loads: all but the records reused from an earlier pass (R-IT20). */
    private static List<Item> loadable(List<Item> items) {
        List<Item> result = new List<Item>();
        for (Item item : items) {
            if (!item.reused) {
                result.add(item);
            }
        }
        return result;
    }

    /**
     * Reuses, for a row loaded again, each record an earlier pass created for it and the user
     * can still see (R-IT20): the record is not created, changed or journaled again, and the
     * row's other records link to it, so a retry never makes a second copy. A record that is
     * gone is created again.
     */
    private static void reuseLoaded(
        Import_Batch__c batch,
        List<Line> lines,
        List<ImportObjectSchema.Step> steps
    ) {
        readLoaded(batch, lines);
        for (Integer index = 0; index < steps.size(); index++) {
            ImportObjectSchema.Step step = steps[index];
            String entity = step.entity == null ? '' : step.entity.toLowerCase();
            Set<Id> ids = new Set<Id>();
            for (Line line : lines) {
                Id prior = line.loaded.get(entity);
                if (line.error == null && line.items[index] != null && prior != null) {
                    ids.add(prior);
                }
            }
            if (ids.isEmpty() || step.type == null) {
                continue;
            }
            Set<Id> visible = visibleIds(step.type, ids);
            for (Line line : lines) {
                Item item = line.items[index];
                Id prior = line.loaded.get(entity);
                if (line.error == null && item != null && visible.contains(prior)) {
                    item.reused = true;
                    item.recordId = prior;
                }
            }
        }
    }

    /**
     * Each row's Loaded Records (R-IT20): its own, from an earlier pass of the same row, over
     * those of the rejected row a retry's fixed row names in its Row column (R-IB17). Read in
     * system mode, as the bookkeeping is written (ADR-0021).
     */
    private static void readLoaded(Import_Batch__c batch, List<Line> lines) {
        Set<Id> rowIds = new Set<Id>();
        Map<Integer, Decimal> originalByLine = new Map<Integer, Decimal>();
        Decimal after = batch != null && batch.isSet(Import_Batch__c.Retry_After_Row__c)
            ? batch.Retry_After_Row__c
            : null;
        for (Integer i = 0; i < lines.size(); i++) {
            Import_Row__c row = lines[i].row;
            if (row.Id != null) {
                rowIds.add(row.Id);
            }
            if (after != null && row.Row_Number__c != null && row.Row_Number__c > after) {
                Decimal original = originalRowOf(row);
                if (original != null && original <= after) {
                    originalByLine.put(i, original);
                }
            }
        }
        Set<Decimal> numbers = new Set<Decimal>(originalByLine.values());
        Id batchId = batch == null ? null : batch.Id;
        Map<Id, Map<String, Id>> byId = new Map<Id, Map<String, Id>>();
        Map<Decimal, Map<String, Id>> byNumber = new Map<Decimal, Map<String, Id>>();
        for (Import_Row__c found : [
            SELECT Id, Row_Number__c, Loaded_Records_JSON__c
            FROM Import_Row__c
            WHERE Id IN :rowIds OR (Import_Batch__c = :batchId AND Row_Number__c IN :numbers)
            WITH SYSTEM_MODE
        ]) {
            Map<String, Id> loaded = loadedOf(found.Loaded_Records_JSON__c);
            if (rowIds.contains(found.Id)) {
                byId.put(found.Id, loaded);
            }
            if (found.Row_Number__c != null && numbers.contains(found.Row_Number__c)) {
                byNumber.put(found.Row_Number__c, loaded);
            }
        }
        for (Integer i = 0; i < lines.size(); i++) {
            Line line = lines[i];
            Map<String, Id> original = byNumber.get(originalByLine.get(i));
            if (original != null) {
                line.loaded.putAll(original);
            }
            Map<String, Id> own = byId.get(line.row.Id);
            if (own != null) {
                line.loaded.putAll(own);
            }
        }
    }

    /** The original row a retry's fixed row names in its Row column, or null. */
    private static Decimal originalRowOf(Import_Row__c row) {
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(row.Raw_Values_JSON__c);
        } catch (Exception e) {
            return null;
        }
        if (!(parsed instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> raw = (Map<String, Object>) parsed;
        for (String column : raw.keySet()) {
            if (column == null || !column.trim().equalsIgnoreCase(Label.Core_Import_ResultsRow)) {
                continue;
            }
            String text = raw.get(column) == null ? '' : String.valueOf(raw.get(column)).trim();
            return text.isNumeric() ? Decimal.valueOf(text) : null;
        }
        return null;
    }

    /** A row's Loaded Records document as object to record ID; empty when blank or unreadable. */
    private static Map<String, Id> loadedOf(String document) {
        Map<String, Id> result = new Map<String, Id>();
        if (String.isBlank(document)) {
            return result;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(document);
            for (String entity : parsed.keySet()) {
                result.put(entity.toLowerCase(), Id.valueOf(String.valueOf(parsed.get(entity))));
            }
        } catch (Exception e) {
            // An unreadable document reuses nothing: the row loads as if for the first time.
            result.clear();
        }
        return result;
    }

    /**
     * Writes the update entries on Commit pages and each step's creations on its own Created
     * pages (R-IJ3), in load order, so the undo, which reads the newest page first, deletes a
     * child before the parents it points at (R-IT17, R-IT20).
     */
    private static Boolean journal(
        Id batchId,
        List<Map<String, Object>> updates,
        List<List<Map<String, Object>>> createdPages
    ) {
        Boolean written = ImportJournalService.write(
            batchId,
            ImportJournalService.PHASE_COMMIT,
            updates
        );
        for (List<Map<String, Object>> created : createdPages) {
            written =
                ImportJournalService.write(batchId, ImportJournalService.PHASE_CREATED, created) &&
                written;
        }
        return written;
    }

    /**
     * Loads one step's rows: Insert, Update by record Id, Update by a matching field or Upsert
     * by external ID, as a one-object template does (R-IT12 to R-IT19), each record linked to
     * its row's parents (R-IT17, R-IT20). A step that later steps link to groups repeated keys.
     */
    private static void load(
        Import_Batch__c batch,
        Step step,
        List<Item> items,
        Boolean dryRun,
        ImportRowProcessor.Outcome outcome,
        List<Map<String, Object>> created
    ) {
        if (items.isEmpty()) {
            return;
        }
        Import_Template__c template = step.template;
        Schema.SObjectType type = step.type;
        String operation = step.operation;
        Boolean mostRecent = ImportTemplateService.usesMostRecent(template);
        // With a later step linking to it, only a key's first row loads the parent (R-IT17).
        List<Item> loading = step.given.groupsRepeats ? groupByKey(batch, step, items) : items;
        // An empty cell clears its field only where the column says so, and never on insert
        // (R-IT19).
        Set<String> clearing = operation == ImportObjectSchema.OPERATION_INSERT
            ? new Set<String>()
            : step.given.mapping.clearingAttributes();
        Map<String, Plan> plans = plan(
            type,
            step.given.mapping,
            loading,
            clearing,
            outcome,
            ImportMapping.ENTITY_RECORD
        );
        planLinks(type, step.given, loading, plans, outcome);
        readValues(loading, plans, clearing);
        resolveLookups(
            loading,
            plans,
            ImportObjectSchema.leavesLookupEmpty(template),
            mostRecent,
            outcome,
            step.createdHere
        );
        findRecords(batch, step, loading);
        if (template.Use_Duplicate_Rules__c == true && createsRecords(operation)) {
            // Only rows that would create are asked: a record ID or key match wins (R-IT16).
            matchByDuplicateRules(batch, type, loading, plans, mostRecent, outcome);
        }
        readRecords(type, loading, plans);
        if (operation == ImportObjectSchema.OPERATION_UPSERT) {
            rejectKeyConflicts(type, ImportObjectSchema.keyFieldOf(template), loading);
        }
        link(loading, step.given, dryRun);
        for (Item item : loading) {
            if (item.error == null && item.creates && batch.Match_Only__c == true) {
                // A file that only matches creates nothing (R-IB15).
                item.error = Label.Core_Import_ErrorMatchOnlyWouldCreate;
            }
        }
        decide(type, loading, plans, outcome);
        for (Item item : loading) {
            // A dry run cannot know the ID of a parent the commit creates, yet it would link.
            item.changes = item.changes || (item.linksNew && item.error == null);
        }
        if (!dryRun) {
            save(type, loading, outcome, created);
        }
        if (step.given.groupsRepeats) {
            linkParents(step, items, dryRun);
        }
    }

    /** Prefixes the plan of a field the load fills with the row's parent (R-IT20). */
    private static final String LINK_PLAN = '#link:';

    /**
     * Plans each link field, so its value is compared, journaled and access checked like any
     * other. A row with a parent on the row takes it, not a column mapped to the field, which is
     * named once in the run log; a row without one still reads the column (R-IT17, R-IT20).
     */
    private static void planLinks(
        Schema.SObjectType type,
        ImportObjectSchema.Step step,
        List<Item> items,
        Map<String, Plan> plans,
        ImportRowProcessor.Outcome outcome
    ) {
        for (String fieldName : step.links.values()) {
            Schema.SObjectField token = fieldName == null
                ? null
                : ImportObjectSchema.fieldNamed(type, fieldName);
            if (token == null) {
                continue;
            }
            Plan linked = new Plan();
            linked.attribute = LINK_PLAN + fieldName;
            linked.field = token.getDescribe();
            for (Plan planned : plans.values()) {
                if (planned.field.getName() == linked.field.getName()) {
                    skipLinkedColumn(items, planned, outcome);
                }
            }
            plans.put(linked.attribute, linked);
        }
    }

    /** A column mapped to a link field is not read for the rows that have a parent on the row. */
    private static void skipLinkedColumn(
        List<Item> items,
        Plan planned,
        ImportRowProcessor.Outcome outcome
    ) {
        Boolean skipped = false;
        for (Item item : items) {
            if (
                item.held.containsKey(planned.attribute) &&
                item.parents.containsKey(planned.field.getName())
            ) {
                item.held.remove(planned.attribute);
                skipped = true;
            }
        }
        if (skipped) {
            outcome.notes.add(
                String.format(
                    Label.Core_Import_LogRelatedParentFieldSkipped,
                    new List<String>{ planned.field.getLabel() }
                )
            );
        }
    }

    /**
     * Links each record to its row's parents (R-IT17, R-IT20): a row whose parent was not saved
     * is rejected; a new record takes the parent, and an existing one only when its field is
     * empty, so a load never moves a record from one parent to another.
     */
    private static void link(List<Item> items, ImportObjectSchema.Step step, Boolean dryRun) {
        for (Item item : items) {
            for (String fieldName : item.parents.keySet()) {
                Item parent = item.parents.get(fieldName);
                if (item.error != null) {
                    break;
                }
                if (parent.error != null || (!dryRun && parent.recordId == null)) {
                    item.error = step.related
                        ? Label.Core_Import_ErrorRelatedParentFailed
                        : Label.Core_Import_ErrorParentNotSaved;
                    break;
                }
                Object held = item.stored == null
                    ? null
                    : item.stored.getPopulatedFieldsAsMap().get(fieldName);
                if (!item.creates && held != null) {
                    continue;
                }
                if (parent.recordId != null) {
                    item.values.put(fieldName, parent.recordId);
                } else {
                    item.linksNew = !item.creates;
                }
            }
        }
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
        ImportRowProcessor.Outcome outcome,
        Set<Schema.SObjectType> createdHere
    ) {
        for (Plan planned : plans.values()) {
            if (!planned.lookup) {
                continue;
            }
            // In a dry run of several objects, a parent this upload may create is not there yet
            // (R-IT20): a value that finds nothing leaves the lookup empty, and the commit finds it.
            Boolean pending = createdHere != null && createdHere.contains(planned.parentType);
            resolveLookup(items, planned, leaveEmpty, pending, mostRecent, outcome);
            if (pending) {
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogLookupLoadedHere,
                        new List<String>{ planned.field.getLabel() }
                    )
                );
            }
        }
    }

    private static void resolveLookup(
        List<Item> items,
        Plan planned,
        Boolean leaveEmpty,
        Boolean pending,
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
            } else if (pending) {
                continue;
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
    private static void findRecords(Import_Batch__c batch, Step step, List<Item> items) {
        Import_Template__c template = step.template;
        Schema.SObjectType type = step.type;
        String operation = step.operation;
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
        if (!step.given.groupsRepeats) {
            // A parent's repeated key is a later row of it (groupByKey), not a repeat.
            rejectRepeats(batch, items, step.given.keepsDigest);
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
        rejectRepeats(batch, items, true);
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
     * digest for the chunks after it, in the dry run and the commit alike. A row holds one
     * digest, so with several objects only the first keyed object's repeats are found across
     * chunks; the others' only within the chunk (R-IT20).
     */
    private static void rejectRepeats(
        Import_Batch__c batch,
        List<Item> items,
        Boolean keepsDigest
    ) {
        Set<String> digests = new Set<String>();
        for (Item item : items) {
            if (item.error == null && item.key != null) {
                digests.add(ImportValues.digest(RECORD_DIGEST, item.key));
            }
        }
        if (digests.isEmpty()) {
            return;
        }
        Set<String> earlier = keepsDigest
            ? ImportRowSelector.processorDigestsWrittenEarlier(batch, digests)
            : new Set<String>();
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
            if (keepsDigest) {
                item.row.Processor_Key__c = digest;
            }
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
    // Parents and the records linked to them (R-IT17, R-IT20)
    // -------------------------------------------------------------------------------------

    /**
     * Returns the chunk's parent rows: the first row of each key in the pass. A later row of a
     * key points at its parent row's item when that row is in this chunk, or follows one from
     * an earlier chunk, known by the digest that row wrote; a key whose parent row failed
     * rejects the row. A row without a key is rejected by `keyOf`. Only the step that keeps the
     * row's digest sees earlier chunks (R-IT20).
     */
    private static List<Item> groupByKey(Import_Batch__c batch, Step step, List<Item> items) {
        String keyField = ImportObjectSchema.keyFieldOf(step.template);
        Set<String> digests = new Set<String>();
        for (Item item : items) {
            if (item.error == null) {
                keyOf(item, step.type, step.operation, keyField);
            }
            if (item.error == null) {
                digests.add(ImportValues.digest(RECORD_DIGEST, item.key));
                digests.add(ImportValues.digest(FAILED_DIGEST, item.key));
            }
        }
        Set<String> earlier = digests.isEmpty() || !step.given.keepsDigest
            ? new Set<String>()
            : ImportRowSelector.processorDigestsWrittenEarlier(batch, digests);
        Map<String, Item> leaders = new Map<String, Item>();
        List<Item> parents = new List<Item>();
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            if (earlier.contains(ImportValues.digest(FAILED_DIGEST, item.key))) {
                item.error = firstRowFailed(step);
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
    private static void linkParents(Step step, List<Item> items, Boolean dryRun) {
        Import_Template__c template = step.template;
        String operation = step.operation;
        List<Item> earlier = new List<Item>();
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            if (item.leader != null) {
                item.recordId = item.leader.recordId;
                if (item.leader.error != null) {
                    item.error = firstRowFailed(step);
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
            step.type,
            ImportObjectSchema.keyFieldOf(template),
            ImportTemplateService.usesMostRecent(template)
        );
        for (Item item : earlier) {
            item.creates = false;
            if (item.error == null && item.recordId == null) {
                item.error = firstRowFailed(step);
            }
        }
    }

    /** Why a later row of a key whose first row failed loads nothing of that object. */
    private static String firstRowFailed(Step step) {
        return step.given.needsOwnValue
            ? Label.Core_Import_ErrorKeyFirstRowFailed
            : Label.Core_Import_ErrorRelatedParentFailed;
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
     * resulted in as its Resulting Record. With several objects (R-IT20) a row is Rejected when
     * any of its objects is, the reason naming the object, and otherwise Created when it created
     * any record, Updated when it changed any; its Resulting Record is its first object's.
     */
    private static void writeBack(
        List<Line> lines,
        List<ImportObjectSchema.Step> steps,
        ImportRowProcessor.Outcome outcome
    ) {
        writeBack(lines, steps, outcome, false);
    }

    /** As above; `records` also writes each row's Loaded Records after a commit (R-IT20). */
    private static void writeBack(
        List<Line> lines,
        List<ImportObjectSchema.Step> steps,
        ImportRowProcessor.Outcome outcome,
        Boolean records
    ) {
        List<Import_Row__c> rows = new List<Import_Row__c>();
        for (Line line : lines) {
            Import_Row__c row = line.row;
            Result result = new Result(line.error);
            for (Integer index = 0; line.error == null && index < steps.size(); index++) {
                Item item = line.items[index];
                if (item != null) {
                    result.add(item, steps[index], steps.size() > 1);
                }
            }
            String error = result.error;
            if (error != null) {
                row.Status__c = ImportRowProcessor.STATUS_REJECTED;
                row.Error_Message__c = error.abbreviate(4000);
                row.Processor_Key__c = null;
                outcome.rejected++;
            } else if (result.creates) {
                row.Status__c = ImportRowProcessor.STATUS_CREATED;
                outcome.created++;
            } else if (result.changes) {
                row.Status__c = ImportRowProcessor.STATUS_UPDATED;
                outcome.updated++;
            } else {
                row.Status__c = ImportRowProcessor.STATUS_MATCHED;
                outcome.matched++;
            }
            // Ticked so the rows a looser rule matched can be read before a commit (R-IT16).
            row.Duplicate_Rule_Match__c = result.ruleMatch && error == null;
            if (row.Duplicate_Rule_Match__c) {
                outcome.notes.add(Label.Core_Import_LogDuplicateRuleMatchesRecords);
            }
            // A parent saved for a row whose related record failed stays its resulting record.
            Item first = result.first;
            row.Gift_Id__c = first != null &&
                first.error == null &&
                first.recordId != null
                ? String.valueOf(first.recordId)
                : null;
            if (result.digest != null && result.digest.leads) {
                // Later chunks read whether this key's parent was saved (R-IT17).
                row.Processor_Key__c = ImportValues.digest(
                    result.digest.error == null ? RECORD_DIGEST : FAILED_DIGEST,
                    result.digest.key
                );
            }
            if (records && line.error == null) {
                recordLoaded(line, steps);
            }
            rows.add(row);
        }
        ImportRowProcessor.saveRows(rows, outcome, 'ImportObjectLoader.writeBack');
    }

    /**
     * Keeps on the row each record it created or reused, by object, over what earlier passes
     * kept, rejected or not: loading it again then creates only what is missing (R-IT20).
     */
    private static void recordLoaded(Line line, List<ImportObjectSchema.Step> steps) {
        Map<String, Id> loaded = new Map<String, Id>(line.loaded);
        for (Integer index = 0; index < steps.size(); index++) {
            Item item = line.items[index];
            if (
                item != null &&
                item.error == null &&
                item.recordId != null &&
                (item.reused || item.creates)
            ) {
                loaded.put(steps[index].entity.toLowerCase(), item.recordId);
            }
        }
        if (!loaded.isEmpty()) {
            line.row.Loaded_Records_JSON__c = JSON.serialize(loaded);
        }
    }

    /** One row's outcome over its steps (R-IT17, R-IT20). */
    private class Result {
        String error;
        Boolean creates = false;
        Boolean changes = false;
        Boolean ruleMatch = false;
        /** The row's first record, its Resulting Record. */
        Item first;
        /** The row's record of the step that keeps the row's digest. */
        Item digest;

        Result(String error) {
            this.error = error;
        }

        void add(Item item, ImportObjectSchema.Step step, Boolean several) {
            if (step.keepsDigest) {
                digest = item;
            }
            if (step.related) {
                addRelated(item);
                return;
            }
            if (first == null) {
                first = item;
            }
            if (item.error != null && error == null) {
                error = several && !step.everyRow
                    ? String.format(
                          Label.Core_Import_ErrorOnObject,
                          new List<String>{ step.label(), item.error }
                      )
                    : item.error;
            }
            creates = creates || (item.error == null && item.creates);
            changes = changes || (item.error == null && item.changes);
            ruleMatch = ruleMatch || item.ruleMatch;
        }

        /** The row's related record (R-IT17): a refusal rejects the row, not its parent. */
        void addRelated(Item item) {
            item.row.Related_Status__c = item.error == null
                ? ImportRowProcessor.STATUS_CREATED
                : ImportRowProcessor.STATUS_REJECTED;
            item.row.Soft_Credit_Id__c = item.error == null &&
                item.recordId != null
                ? String.valueOf(item.recordId)
                : null;
            if (error == null && item.error != null) {
                error = String.format(
                    Label.Core_Import_ErrorRelatedRecord,
                    new List<String>{ item.error }
                );
            }
        }
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
