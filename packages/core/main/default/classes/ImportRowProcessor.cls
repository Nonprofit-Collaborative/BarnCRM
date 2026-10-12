/**
 * Resolves one chunk of staged rows in dependency order, and is the only class that decides
 * what a row means (R-IR1): the organization, then the household, then the two people.
 *
 * Three rules shape everything here.
 *
 * **Bulk safe.** Every query and every save is over a whole chunk. There is no SOQL and no
 * DML inside a loop over rows, so the chunk size can be raised as far as an org's automation
 * allows without the processor being the thing that breaks.
 *
 * **A dry run makes the same decisions the commit will make** (R-IB1). The matching, the
 * validation and the status of every row are computed by the same code on both passes; the
 * only difference is that the dry run does not save. That is what makes the preview worth
 * trusting.
 *
 * **A failed row does not take the chunk with it** (R-IB5). Saves are partial-success, and a
 * row that fails carries the reason on itself, in words an administrator can act on. Nothing
 * fails silently: a row is Rejected with a message, or it is not Rejected.
 *
 * Membership is never reimplemented. A new person is inserted with no household and the
 * household trigger gives them one, which is the same path a person saved by hand takes.
 * Where a row's two people belong together, the second is joined to the first person's
 * household through `HouseholdService`, which is the only class that knows whether this org
 * writes membership as the person's account reference or as a membership row (R-M5).
 */
@NamespaceAccessible
public with sharing class ImportRowProcessor {
    @NamespaceAccessible
    public static final String STATUS_PENDING = 'Pending';
    @NamespaceAccessible
    public static final String STATUS_MATCHED = 'Matched';
    @NamespaceAccessible
    public static final String STATUS_CREATED = 'Created';
    @NamespaceAccessible
    public static final String STATUS_UPDATED = 'Updated';
    @NamespaceAccessible
    public static final String STATUS_REJECTED = 'Rejected';
    @NamespaceAccessible
    public static final String STATUS_SKIPPED = 'Skipped';

    /** The class name a dependent package registers to resolve the rest of a row (R-IR6). */
    @NamespaceAccessible
    public static final String ENTITY_PROCESSOR_CLASS = ImportEntityProcessors.CLASS_NAME;

    private static final String ORGANIZATION_RECORD_TYPE = 'Organization';

    /** What a person account puts before a contact field's name (see `storedName`). */
    private static final String PERSON_FIELD_PREFIX = 'Person';

    /** Prefixes a matching key before its digest, so a person and an organization never share one. */
    private static final String PERSON_DIGEST = 'person:';
    private static final String ORGANIZATION_DIGEST = 'organization:';

    /**
     * In a commit, the matching keys of the people this chunk has set out to create, the
     * people created under each, and why any could not be, so a second row naming the same
     * new person shares the first row's record rather than making another (R-IB4, R-IB12).
     */
    private static ChunkPeople keysBeingCreated = new ChunkPeople();

    /**
     * The new people of one chunk: how many are created under each key, and the couples'
     * second people still to be created, so a row naming one of them alone waits for them
     * rather than creating them twice (R-IB12).
     */
    private class ChunkPeople {
        Map<String, Integer> created = new Map<String, Integer>();
        /** The first-name keys of couples' second people the chunk has yet to create. */
        Set<String> waitingSeconds = new Set<String>();
    }

    /** Notes the couples' second people of the chunk, found by nobody yet, before any save. */
    private static ChunkPeople chunkPeople(List<Working> working) {
        ChunkPeople chunk = new ChunkPeople();
        for (Working item : working) {
            String key = item.personKey2;
            if (
                item.error == null &&
                key != null &&
                ImportMatcher.baseKey(key) != key &&
                item.person2Id == null &&
                !item.comingPerson2
            ) {
                chunk.waitingSeconds.add(key);
            }
        }
        return chunk;
    }
    private static Map<String, Id> createdByKey = new Map<String, Id>();
    private static Map<String, String> failedByKey = new Map<String, String>();

    /**
     * How this chunk matches, read from the template once by `readMatchingChoices`: the field
     * people and organizations are matched on under External ID (R-IT8; null when the rule
     * uses none or the chosen field no longer qualifies), whether organizations are matched by
     * that field rather than by name (R-IT2), and whether a key several records hold takes the
     * most recently changed of them rather than rejecting the row (R-IT9).
     */
    private static String personMatchField;
    private static Boolean organizationsByField = false;
    private static String organizationMatchField;
    private static Boolean mostRecent = false;
    /** Whether the org's duplicate rules are asked about whom the rule found nobody for (R-IT16). */
    private static Boolean useDuplicateRules = false;

    /**
     * The attributes that can name or find a person. A full name column is not listed because
     * `splitFullNames` has already turned one into a first and last name by the time anything
     * asks this question.
     */
    private static final List<String> IDENTIFYING_ATTRIBUTES = new List<String>{
        'LastName',
        'FirstName',
        'Email'
    };

    /** What one chunk did, added up by the batch. */
    @NamespaceAccessible
    public class Outcome {
        @NamespaceAccessible
        public Integer created = 0;
        @NamespaceAccessible
        public Integer updated = 0;
        @NamespaceAccessible
        public Integer matched = 0;
        @NamespaceAccessible
        public Integer rejected = 0;
        @NamespaceAccessible
        public Integer skipped = 0;
        /** Anything the run log should say once, not once per row. */
        @NamespaceAccessible
        public Set<String> notes = new Set<String>();
        /**
         * The changes this chunk made to records it did not create, for the import journal
         * (canonical model Section 17A). Written by `process` at the end of a commit.
         */
        @NamespaceAccessible
        public List<Map<String, Object>> journal = new List<Map<String, Object>>();
        /**
         * The total of the gift amounts the entity processor read in this chunk, for the control
         * totals (R-IB10); null when no processor read any.
         */
        @NamespaceAccessible
        public Decimal fileAmount;
        /** The settings the entity processor ran this chunk under, in a dry run (R-IB11). */
        @NamespaceAccessible
        public String processorSettings;
    }

    /** One row's working state while the chunk is resolved. */
    private class Working {
        Import_Row__c row;
        Map<String, String> values;
        Map<String, Map<String, String>> byEntity;
        /** The organization's name, and the key it is matched by under the template's rule. */
        String organizationName;
        String organizationKey;
        /** The row's organization among those this chunk creates: its key, or the row's own. */
        String organizationGroup;
        /** True when a key this row was looked for by found several records (R-IT9). */
        Boolean severalMatches = false;
        /** True when the org's duplicate rules matched a person or the organization (R-IT16). */
        Boolean duplicateRuleMatch = false;
        /** The record IDs the row gives, as typed, taken out of its values (R-IT10). */
        String givenOrganizationId;
        String givenPerson1Id;
        String givenPerson2Id;
        /** True when a person was matched by the record ID the row gives (R-IT10). */
        Boolean givenPerson1 = false;
        Boolean givenPerson2 = false;
        String personKey1;
        String personKey2;
        Id organizationId;
        Id person1Id;
        Id person2Id;
        Boolean createdAnything = false;
        Boolean updatedAnything = false;
        /** True when this run created the row's first person, whose household is therefore new. */
        Boolean createdPerson1 = false;
        /** True when this run created the row's second person, who is joined to a household. */
        Boolean createdPerson2 = false;
        /** In a dry run, true when an earlier chunk would create the row's first person. */
        Boolean comingPerson1 = false;
        /** In a dry run, true when an earlier chunk would create the row's second person. */
        Boolean comingPerson2 = false;
        /** Whether a first name narrows the key, as it does under the Email and Name + Postal rules. */
        Boolean byName = false;
        /** How many records already hold each person's shared key: none, one, or several (2). */
        Integer heldBefore1 = 0;
        Integer heldBefore2 = 0;
        String error;
    }

    /**
     * Resolves a chunk. Writes nothing when dryRun is true. The rows are updated in place
     * with their status, their resolved lookups and any error, and are saved here.
     */
    @NamespaceAccessible
    public static Outcome process(
        Import_Batch__c batch,
        Import_Template__c template,
        ImportMapping mapping,
        List<Import_Row__c> rows,
        Boolean dryRun
    ) {
        Outcome outcome = new Outcome();
        if (rows == null || rows.isEmpty()) {
            return outcome;
        }
        if (ImportObjectSchema.loadsOneObject(template)) {
            // A row of a one-object template is one record of that object (R-IT12).
            return ImportObjectLoader.process(batch, template, mapping, rows, dryRun);
        }
        Boolean personAccounts = ImportTemplateService.isPersonAccountMode(template);
        String rule = ImportTemplateService.normalizedRule(template.Matching_Rule__c);
        readMatchingChoices(template, rule, outcome);
        noteFieldsWithoutAccess(mapping, personAccounts, outcome);

        List<Working> working = read(batch, rows, mapping, outcome);
        resolveGivenIds(working, personAccounts);
        resolveOrganizations(working, batch, dryRun, outcome);
        resolvePeople(working, rule, batch, personAccounts, dryRun, outcome);
        tagAndNameHouseholds(working, batch, dryRun, outcome);
        offerToEntityProcessor(batch, template, mapping, working, dryRun, outcome);
        writeBack(working, outcome);
        if (
            !dryRun &&
            !ImportJournalService.write(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                outcome.journal
            )
        ) {
            // The records are saved; what is lost is the ability to put these updates back,
            // and the run log is where the administrator is told (R-IJ4).
            outcome.notes.add(Label.Core_Import_LogJournalFailed);
        }
        return outcome;
    }

    /**
     * Reads how the template matches (R-IT2, R-IT8, R-IT9) into this chunk's settings. A chosen
     * field is used only while describe still offers it for matching; one that is gone, or no
     * field at all, matches nobody under its rule, and the run log says which.
     */
    private static void readMatchingChoices(
        Import_Template__c template,
        String rule,
        Outcome outcome
    ) {
        mostRecent = ImportTemplateService.usesMostRecent(template);
        useDuplicateRules = template.Use_Duplicate_Rules__c == true;
        ImportMatcher.keepMostRecent(mostRecent);
        personMatchField = null;
        if (ImportTemplateService.RULE_EXTERNAL_ID.equals(rule)) {
            personMatchField = ImportMatcher.matchField(
                ImportTemplateService.personType(template),
                template.Person_Match_Field__c
            );
            noteMissingField(personMatchField, template.Person_Match_Field__c, outcome);
        }
        organizationsByField = ImportTemplateService.ORGANIZATION_RULE_EXTERNAL_ID.equals(
            ImportTemplateService.normalizedOrganizationRule(template.Organization_Matching_Rule__c)
        );
        organizationMatchField = null;
        if (organizationsByField) {
            organizationMatchField = ImportMatcher.matchField(
                Account.SObjectType,
                template.Organization_Match_Field__c
            );
            noteMissingField(organizationMatchField, template.Organization_Match_Field__c, outcome);
        }
    }

    /** The run log line for an External ID rule that has no field to match on. */
    private static void noteMissingField(String field, String chosen, Outcome outcome) {
        if (field != null) {
            return;
        }
        outcome.notes.add(
            String.isBlank(chosen)
                ? Label.Core_Import_LogNoExternalIdField
                : String.format(
                      Label.Core_Import_LogMatchFieldUnavailable,
                      new List<String>{ chosen.trim() }
                  )
        );
    }

    /** A value from a row entity's attributes by field name, ignoring case. */
    private static String valueOf(Map<String, String> held, String fieldName) {
        if (held == null || fieldName == null) {
            return null;
        }
        for (String attributeName : held.keySet()) {
            if (attributeName.equalsIgnoreCase(fieldName)) {
                return held.get(attributeName);
            }
        }
        return null;
    }

    // -------------------------------------------------------------------------------------
    // Reading
    // -------------------------------------------------------------------------------------

    /** Parses every row's raw values into the entities they describe, and validates them. */
    private static List<Working> read(
        Import_Batch__c batch,
        List<Import_Row__c> rows,
        ImportMapping mapping,
        Outcome outcome
    ) {
        Map<String, String> targets = mapping.targetsBySourceKey();
        Map<String, List<DataTransform.Step>> transforms = mapping.transformsBySourceKey();
        List<Working> working = new List<Working>();
        for (Import_Row__c row : rows) {
            startPass(row, ImportRowSelector.passOf(batch));
            Working item = new Working();
            item.row = row;
            item.values = rawValues(row);
            item.byEntity = groupByEntity(item.values, targets, transforms, mapping.defaults);
            splitFullNames(item.byEntity);
            // A record ID matches and is never written to a field (R-IT10).
            item.givenOrganizationId = takeId(item.byEntity, ImportMapping.ENTITY_ORGANIZATION);
            item.givenPerson1Id = takeId(item.byEntity, ImportMapping.ENTITY_CONTACT_1);
            item.givenPerson2Id = takeId(item.byEntity, ImportMapping.ENTITY_CONTACT_2);
            String name = attribute(item.byEntity, ImportMapping.ENTITY_ORGANIZATION, 'Name');
            item.organizationName = String.isBlank(name) ? null : name;
            // A blank key is never looked up, so a row without one is never matched (R-IT8).
            item.organizationKey = organizationsByField
                ? ImportMatcher.nameKey(
                      valueOf(
                          item.byEntity.get(ImportMapping.ENTITY_ORGANIZATION),
                          organizationMatchField
                      )
                  )
                : ImportMatcher.nameKey(name);
            item.organizationGroup = item.organizationKey == null
                ? 'row:' + working.size()
                : item.organizationKey;
            working.add(item);
        }
        return working;
    }

    /**
     * A row's values by entity and attribute, after each column's changes (R-IT15), with the
     * mapping's values for every row filled in where the row has none: what the one-object
     * loader reads a row as (R-IT12).
     */
    @NamespaceAccessible
    public static Map<String, Map<String, String>> valuesByEntity(
        Import_Row__c row,
        ImportMapping mapping
    ) {
        return groupByEntity(
            rawValues(row),
            mapping.targetsBySourceKey(),
            mapping.transformsBySourceKey(),
            mapping.defaults
        );
    }

    /**
     * Each changed cell of a row, before and after its column's changes (R-IT15), keyed by the
     * column as the mapping names it, in the mapping's order. What the dry run shows.
     */
    @NamespaceAccessible
    public static List<List<String>> changedValues(Import_Row__c row, ImportMapping mapping) {
        List<List<String>> result = new List<List<String>>();
        Map<String, String> values = rawValues(row);
        Map<String, List<DataTransform.Step>> transforms = mapping.transformsBySourceKey();
        for (ImportMapping.Column column : mapping.columns) {
            String sourceKey = column == null ? null : ImportMapping.key(column.source);
            if (sourceKey == null || !transforms.containsKey(sourceKey)) {
                continue;
            }
            String before = values.get(sourceKey);
            String after = DataTransform.apply(transforms.get(sourceKey), before, values);
            // equals, not ==, which ignores capitals and would hide a change to them.
            if (before == null ? after != null : !before.equals(after)) {
                result.add(new List<String>{ column.source, before, after });
            }
        }
        return result;
    }

    /** The row's uploaded values, keyed the way a mapping's source columns are keyed. */
    private static Map<String, String> rawValues(Import_Row__c row) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(row.Raw_Values_JSON__c)) {
            return result;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
                row.Raw_Values_JSON__c
            );
            for (String column : parsed.keySet()) {
                Object value = parsed.get(column);
                result.put(
                    ImportMapping.key(column),
                    value == null ? null : String.valueOf(value).trim()
                );
            }
        } catch (Exception ignored) {
            // A row whose staged values cannot be read is rejected below, not thrown from.
            return new Map<String, String>();
        }
        return result;
    }

    /**
     * entity to attribute to value, after each column's changes, with the template's defaults
     * filled in where empty. The changes read the row's uploaded values, never each other's
     * output, so the order of the columns does not matter (R-IT15).
     */
    private static Map<String, Map<String, String>> groupByEntity(
        Map<String, String> values,
        Map<String, String> targets,
        Map<String, List<DataTransform.Step>> transforms,
        List<ImportMapping.Assignment> defaults
    ) {
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();
        for (String sourceKey : targets.keySet()) {
            String value = values.get(sourceKey);
            List<DataTransform.Step> steps = transforms.get(sourceKey);
            if (steps != null) {
                value = DataTransform.apply(steps, value, values);
            }
            if (String.isBlank(value)) {
                continue;
            }
            put(result, targets.get(sourceKey), value);
        }
        for (ImportMapping.Assignment assignment : defaults) {
            if (assignment == null || ImportMapping.isIgnored(assignment.target)) {
                continue;
            }
            String entity = ImportMapping.entityOf(assignment.target);
            String attribute = ImportMapping.attributeOf(assignment.target);
            Map<String, String> held = result.get(entity);
            if (held == null || String.isBlank(held.get(attribute))) {
                put(result, assignment.target, assignment.value);
            }
        }
        return result;
    }

    private static void put(Map<String, Map<String, String>> target, String path, String value) {
        String entity = ImportMapping.entityOf(path);
        String attribute = ImportMapping.attributeOf(path);
        if (entity == null || attribute == null) {
            return;
        }
        if (!target.containsKey(entity)) {
            target.put(entity, new Map<String, String>());
        }
        target.get(entity).put(attribute, value);
    }

    private static String attribute(
        Map<String, Map<String, String>> byEntity,
        String entity,
        String name
    ) {
        Map<String, String> held = byEntity.get(entity);
        return held == null ? null : held.get(name);
    }

    /**
     * Turns a single whole-name column into a first and a last name, because a great many
     * contact lists have only one. "Ramirez, Ana" and "Ana Ramirez" both read the same way.
     */
    private static void splitFullNames(Map<String, Map<String, String>> byEntity) {
        for (
            String entity : new List<String>{
                ImportMapping.ENTITY_CONTACT_1,
                ImportMapping.ENTITY_CONTACT_2
            }
        ) {
            Map<String, String> held = byEntity.get(entity);
            if (held == null) {
                continue;
            }
            String full = held.remove(ImportMapping.ATTRIBUTE_FULL_NAME);
            if (String.isBlank(full)) {
                continue;
            }
            full = full.trim().replaceAll('\\s+', ' ');
            String first;
            String last;
            if (full.contains(',')) {
                last = full.substringBefore(',').trim();
                first = full.substringAfter(',').trim();
            } else if (full.contains(' ')) {
                last = full.substringAfterLast(' ').trim();
                first = full.substringBeforeLast(' ').trim();
            } else {
                last = full;
                first = null;
            }
            if (String.isBlank(held.get('LastName')) && String.isNotBlank(last)) {
                held.put('LastName', last);
            }
            if (String.isBlank(held.get('FirstName')) && String.isNotBlank(first)) {
                held.put('FirstName', first);
            }
        }
    }

    /** Removes an entity's record ID from its values and returns it, or null when blank. */
    private static String takeId(Map<String, Map<String, String>> byEntity, String entity) {
        Map<String, String> held = byEntity.get(entity);
        if (held == null) {
            return null;
        }
        String given;
        for (String attributeName : new List<String>(held.keySet())) {
            if ('Id'.equalsIgnoreCase(attributeName)) {
                String value = held.remove(attributeName);
                given = String.isBlank(value) ? given : value.trim();
            }
        }
        return given;
    }

    // -------------------------------------------------------------------------------------
    // Record IDs
    // -------------------------------------------------------------------------------------

    /**
     * Matches each row's people and organization by the record IDs it gives (R-IT10), before
     * any rule is asked. An ID must be a record ID of the object the entity is stored on, of a
     * record the user can see, with the right record type for an account; any other ID
     * rejects the row with the reason, and nothing is created for it. One query per object
     * for the whole chunk.
     */
    private static void resolveGivenIds(List<Working> working, Boolean personAccounts) {
        Schema.SObjectType personType = personAccounts ? Account.SObjectType : Contact.SObjectType;
        Set<Id> personIds = new Set<Id>();
        Set<Id> organizationIds = new Set<Id>();
        for (Working item : working) {
            for (Integer which = 0; which <= 2; which++) {
                String given = which == 0
                    ? item.givenOrganizationId
                    : which == 1 ? item.givenPerson1Id : item.givenPerson2Id;
                if (given == null || item.error != null) {
                    continue;
                }
                Id parsed = parsedId(given);
                Schema.SObjectType expected = which == 0 ? Account.SObjectType : personType;
                if (parsed == null) {
                    item.error = String.format(
                        Label.Core_Import_ErrorRecordIdInvalid,
                        new List<String>{ given }
                    );
                } else if (parsed.getSObjectType() != expected) {
                    item.error = wrongKind(which, given);
                } else {
                    (which == 0 ? organizationIds : personIds).add(parsed);
                }
            }
        }
        if (personIds.isEmpty() && organizationIds.isEmpty()) {
            return;
        }
        Map<Id, Id> recordTypeById = visibleRecords(personIds, organizationIds, personAccounts);
        Id organizationType = recordTypeId(ORGANIZATION_RECORD_TYPE);
        for (Working item : working) {
            for (Integer which = 0; which <= 2; which++) {
                String given = which == 0
                    ? item.givenOrganizationId
                    : which == 1 ? item.givenPerson1Id : item.givenPerson2Id;
                if (given == null || item.error != null) {
                    continue;
                }
                Id parsed = parsedId(given);
                if (!recordTypeById.containsKey(parsed)) {
                    item.error = String.format(
                        Label.Core_Import_ErrorRecordIdNotFound,
                        new List<String>{ given }
                    );
                    continue;
                }
                Id recordType = recordTypeById.get(parsed);
                Boolean rightKind = which == 0
                    ? recordType != null && recordType == organizationType
                    : !personAccounts || personRecordTypeIds().contains(recordType);
                if (!rightKind) {
                    item.error = wrongKind(which, given);
                } else if (which == 0) {
                    item.organizationId = parsed;
                    item.organizationKey = null;
                } else if (which == 1) {
                    item.person1Id = parsed;
                    item.givenPerson1 = true;
                } else {
                    item.person2Id = parsed;
                    item.givenPerson2 = true;
                }
            }
        }
    }

    /** A record ID as typed, or null when it is not one. */
    private static Id parsedId(String given) {
        try {
            return Id.valueOf(given);
        } catch (Exception notAnId) {
            return null;
        }
    }

    /** The rejection for an ID of the wrong kind of record: 0 the organization, else a person. */
    private static String wrongKind(Integer which, String given) {
        return String.format(
            which == 0
                ? Label.Core_Import_ErrorRecordIdNotOrganization
                : Label.Core_Import_ErrorRecordIdNotPerson,
            new List<String>{ given }
        );
    }

    /**
     * The given records the user can see, each with its account record type (null for a
     * contact). Read in user mode, so a record the user may not see reads as not found.
     */
    private static Map<Id, Id> visibleRecords(
        Set<Id> personIds,
        Set<Id> organizationIds,
        Boolean personAccounts
    ) {
        Map<Id, Id> result = new Map<Id, Id>();
        Set<Id> accountIds = new Set<Id>(organizationIds);
        if (personAccounts) {
            accountIds.addAll(personIds);
        } else if (!personIds.isEmpty()) {
            for (Contact person : [
                SELECT Id
                FROM Contact
                WHERE Id IN :personIds
                WITH USER_MODE
                LIMIT 2000
            ]) {
                result.put(person.Id, null);
            }
        }
        if (!accountIds.isEmpty()) {
            for (Account record : [
                SELECT Id, RecordTypeId
                FROM Account
                WHERE Id IN :accountIds
                WITH USER_MODE
                LIMIT 2000
            ]) {
                result.put(record.Id, record.RecordTypeId);
            }
        }
        return result;
    }

    // -------------------------------------------------------------------------------------
    // Organizations
    // -------------------------------------------------------------------------------------

    /**
     * Finds or creates each row's organization by the template's organization rule: its name,
     * or the chosen matching field, among organization accounts only (R-IT2, R-IT8). A key
     * several organizations hold is a several-matches case (R-IT9). A row whose organization
     * has no key under the rule is not matched, and creates its own organization, which needs
     * a name; rows naming one new organization by the same key share the first one's (R-IB4).
     */
    private static void resolveOrganizations(
        List<Working> working,
        Import_Batch__c batch,
        Boolean dryRun,
        Outcome outcome
    ) {
        Set<String> keys = new Set<String>();
        Boolean namesOne = false;
        for (Working item : working) {
            if (!looksForOrganization(item)) {
                continue;
            }
            if (item.organizationKey != null) {
                keys.add(item.organizationKey);
            }
            namesOne = true;
        }
        if (!namesOne) {
            return;
        }
        Id recordTypeId = recordTypeId(ORGANIZATION_RECORD_TYPE);
        if (recordTypeId == null) {
            outcome.notes.add(Label.Core_Import_LogOrganizationRecordTypeMissing);
            return;
        }
        ImportMatcher.forgetHeldKeys();
        Map<String, Id> existing = organizationsByField
            ? ImportMatcher.byMatchField(
                  Account.SObjectType,
                  organizationMatchField,
                  keys,
                  new Set<Id>{ recordTypeId }
              )
            : ImportMatcher.accountsByName(keys, recordTypeId);
        if (useDuplicateRules) {
            matchOrganizationsByDuplicateRules(
                working,
                existing,
                recordTypeId,
                batch,
                dryRun,
                outcome
            );
        }

        Map<String, Working> firstRowByKey = new Map<String, Working>();
        List<Account> toCreate = new List<Account>();
        List<String> createdKeys = new List<String>();
        for (Working item : working) {
            if (!looksForOrganization(item)) {
                continue;
            }
            Id found = item.organizationKey == null ? null : existing.get(item.organizationKey);
            if (found != null) {
                if (ImportMatcher.isHeldByMany(item.organizationKey)) {
                    item.severalMatches = true;
                    if (!mostRecent) {
                        item.error = Label.Core_Import_ErrorSeveralOrganizationsMatch;
                        continue;
                    }
                }
                item.organizationId = found;
                continue;
            }
            if (batch.Match_Only__c == true) {
                // A file that only matches creates no organization (R-IB15).
                item.error = Label.Core_Import_ErrorMatchOnlyNoMatch;
                continue;
            }
            if (item.organizationName == null) {
                item.error = Label.Core_Import_ErrorOrganizationNameMissing;
                continue;
            }
            if (firstRowByKey.containsKey(item.organizationGroup)) {
                // A second row naming the same new organization waits for the first one's
                // record, so one file never creates the same organization twice (R-IB4).
                continue;
            }
            firstRowByKey.put(item.organizationGroup, item);
            Account organization = new Account(
                Name = item.organizationName,
                RecordTypeId = recordTypeId,
                Created_By_Import_Batch__c = batch.Id
            );
            applyValues(
                organization,
                Account.SObjectType,
                item.byEntity.get(ImportMapping.ENTITY_ORGANIZATION),
                new Set<String>{ 'Name' },
                outcome
            );
            toCreate.add(organization);
            createdKeys.add(item.organizationGroup);
        }
        if (toCreate.isEmpty()) {
            return;
        }
        if (dryRun) {
            previewOrganizations(working, firstRowByKey, batch);
            return;
        }
        Map<String, Id> newIds = new Map<String, Id>();
        List<Database.SaveResult> results = Database.insert(
            toCreate,
            saveOptions(),
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            Working owner = firstRowByKey.get(createdKeys[i]);
            if (results[i].isSuccess()) {
                newIds.put(createdKeys[i], results[i].getId());
                owner.createdAnything = true;
            } else {
                owner.error = message(results[i]);
            }
        }
        for (Working item : working) {
            if (!createsOrganization(item)) {
                continue;
            }
            Id created = newIds.get(item.organizationGroup);
            if (created != null) {
                item.organizationId = created;
                item.createdAnything = true;
            } else if (item.error == null) {
                item.error = Label.Core_Import_ErrorOrganizationNotSaved;
            }
        }
    }

    /**
     * Whether the row's organization is still to be found by its rule: it names one, was not
     * given by record ID (R-IT10), and the row is not already rejected.
     */
    private static Boolean looksForOrganization(Working item) {
        return item.error == null &&
            item.organizationId == null &&
            (item.organizationKey != null ||
            item.organizationName != null);
    }

    /** Whether the row's organization is one this chunk creates. */
    private static Boolean createsOrganization(Working item) {
        return item.organizationId == null && item.error == null && item.organizationName != null;
    }

    /**
     * In a dry run, counts the rows that would create an organization, except where an
     * earlier chunk would create it, which the commit finds here (R-IB12), and writes each
     * new organization's digest on its first row for later chunks. A row with no key creates
     * its own organization and leaves nothing for a later chunk to find.
     */
    private static void previewOrganizations(
        List<Working> working,
        Map<String, Working> firstRowByKey,
        Import_Batch__c batch
    ) {
        Set<String> digests = new Set<String>();
        for (Working item : firstRowByKey.values()) {
            if (item.organizationKey != null) {
                digests.add(digest(ORGANIZATION_DIGEST, item.organizationKey));
            }
        }
        Set<String> earlier = digests.isEmpty()
            ? new Set<String>()
            : ImportRowSelector.createdDigestsWrittenEarlier(batch, digests);
        for (Working item : working) {
            if (!createsOrganization(item)) {
                continue;
            }
            if (
                item.organizationKey == null ||
                !earlier.contains(digest(ORGANIZATION_DIGEST, item.organizationKey))
            ) {
                item.createdAnything = true;
            }
        }
        for (Working item : firstRowByKey.values()) {
            if (item.organizationKey == null) {
                continue;
            }
            String digest = digest(ORGANIZATION_DIGEST, item.organizationKey);
            if (!earlier.contains(digest)) {
                item.row.Organization_Key__c = digest;
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // People
    // -------------------------------------------------------------------------------------

    private static void resolvePeople(
        List<Working> working,
        String rule,
        Import_Batch__c batch,
        Boolean personAccounts,
        Boolean dryRun,
        Outcome outcome
    ) {
        // Both people on a row are matched from the same key sets, in one pass each.
        Set<String> emailKeys = new Set<String>();
        Set<String> namePostalKeys = new Set<String>();
        Set<String> externalIds = new Set<String>();
        // The External ID rule matches on the field the template chose, or the first external
        // identifier where it chose none (R-IT8); a rule with no field matches nobody.
        String externalIdField = personMatchField;
        for (Working item : working) {
            item.personKey1 = personKey(
                item,
                ImportMapping.ENTITY_CONTACT_1,
                rule,
                externalIdField
            );
            item.personKey2 = personKey(
                item,
                ImportMapping.ENTITY_CONTACT_2,
                rule,
                externalIdField
            );
            // A person given by record ID is matched already, and no rule is asked (R-IT10).
            if (item.givenPerson1) {
                item.personKey1 = null;
            }
            if (item.givenPerson2) {
                item.personKey2 = null;
            }
            item.byName = !ImportTemplateService.RULE_EXTERNAL_ID.equals(rule);
            tellApartByFirstName(item, rule);
            collect(
                ImportMatcher.baseKey(item.personKey1),
                rule,
                emailKeys,
                namePostalKeys,
                externalIds
            );
            collect(
                ImportMatcher.baseKey(item.personKey2),
                rule,
                emailKeys,
                namePostalKeys,
                externalIds
            );
        }

        ImportMatcher.forgetHeldKeys();
        Map<String, Id> matches = matchPeople(
            rule,
            personAccounts,
            emailKeys,
            namePostalKeys,
            externalIds,
            outcome
        );
        // A matching field the user may not read would fail the chunk's query, so it was not
        // matched on; the run log says so, because everybody then counts as new (R-IB5).
        for (String fieldLabel : ImportMatcher.unreadableFields()) {
            outcome.notes.add(
                String.format(
                    Label.Core_Import_LogMatchFieldNoAccess,
                    new List<String>{ fieldLabel }
                )
            );
        }

        Map<String, Integer> earlier = dryRun
            ? ImportRowSelector.createdDigestCounts(batch, digestsToAsk(working))
            : new Map<String, Integer>();
        findPerson(working, matches, earlier, true);
        findPerson(working, matches, earlier, false);
        if (useDuplicateRules) {
            matchPeopleByDuplicateRules(working, personAccounts, outcome);
        }
        validate(working);
        if (batch.Match_Only__c == true) {
            rejectUnmatchedPeople(working);
        }

        if (dryRun) {
            countUpdatesInPreview(working, personAccounts, rule);
            // Read, not written: an entity processor matching a gift to a household's pledge
            // needs the household a matched person is in, in the preview as in the commit.
            resolveHouseholds(working, personAccounts);
            return;
        }
        savePeople(working, batch, personAccounts, outcome);
    }

    /**
     * In a file that only matches, rejects a row whose first or second person matched nobody,
     * before anything is saved, so the dry run and the commit reject the same rows (R-IB15).
     */
    private static void rejectUnmatchedPeople(List<Working> working) {
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            Boolean newFirst =
                item.person1Id == null &&
                !item.comingPerson1 &&
                describesPerson(item, ImportMapping.ENTITY_CONTACT_1);
            Boolean newSecond =
                item.person2Id == null &&
                !item.comingPerson2 &&
                describesPerson(item, ImportMapping.ENTITY_CONTACT_2);
            if (newFirst || newSecond) {
                item.error = Label.Core_Import_ErrorMatchOnlyNoMatch;
            }
        }
    }

    /**
     * A row's two people are two people, even when the rule gives them one key (a couple with
     * one surname and postal code, or one email). Each is then matched, shared and remembered
     * by the shared key narrowed to their own first name, so neither is taken for the other,
     * in this file or when it is loaded again (R-IB12). Two with one first name as well cannot
     * be told apart, and the row is refused rather than guessed at.
     */
    private static void tellApartByFirstName(Working item, String rule) {
        if (
            item.personKey1 == null ||
            item.personKey1 != item.personKey2 ||
            ImportTemplateService.RULE_EXTERNAL_ID.equals(rule)
        ) {
            return;
        }
        String first1 = ImportMatcher.comparableFirstName(
            attribute(item.byEntity, ImportMapping.ENTITY_CONTACT_1, 'FirstName')
        );
        String first2 = ImportMatcher.comparableFirstName(
            attribute(item.byEntity, ImportMapping.ENTITY_CONTACT_2, 'FirstName')
        );
        if (first1 == first2) {
            item.error = Label.Core_Import_ErrorTwoPeopleOneKey;
            return;
        }
        item.personKey1 = ImportMatcher.firstNameKey(item.personKey1, first1);
        item.personKey2 = ImportMatcher.firstNameKey(item.personKey2, first2);
    }

    /**
     * Every key that finds a person this row creates: the shared key, and the same narrowed
     * to their first name, so a later row finds them by whichever it holds (R-IB12).
     */
    private static List<String> keysFinding(Working item, Boolean isFirst) {
        String key = ImportMatcher.baseKey(isFirst ? item.personKey1 : item.personKey2);
        if (key == null) {
            return new List<String>();
        }
        String entity = isFirst ? ImportMapping.ENTITY_CONTACT_1 : ImportMapping.ENTITY_CONTACT_2;
        return new List<String>{
            key,
            ImportMatcher.firstNameKey(key, attribute(item.byEntity, entity, 'FirstName'))
        };
    }

    private static void collect(
        String key,
        String rule,
        Set<String> emailKeys,
        Set<String> namePostalKeys,
        Set<String> externalIds
    ) {
        if (key == null) {
            return;
        }
        if (ImportTemplateService.RULE_EMAIL.equals(rule)) {
            emailKeys.add(key);
        } else if (ImportTemplateService.RULE_NAME_POSTAL.equals(rule)) {
            namePostalKeys.add(key);
        } else {
            externalIds.add(key);
        }
    }

    /** The value this row is matched on for one person, or null when it cannot be matched. */
    private static String personKey(
        Working item,
        String entity,
        String rule,
        String externalIdField
    ) {
        Map<String, String> held = item.byEntity.get(entity);
        if (held == null || held.isEmpty()) {
            return null;
        }
        if (ImportTemplateService.RULE_EMAIL.equals(rule)) {
            return ImportMatcher.emailKey(held.get('Email'));
        }
        if (ImportTemplateService.RULE_NAME_POSTAL.equals(rule)) {
            String postal = held.get('MailingPostalCode');
            if (String.isBlank(postal)) {
                postal = attribute(
                    item.byEntity,
                    ImportMapping.ENTITY_HOUSEHOLD,
                    'BillingPostalCode'
                );
            }
            return ImportMatcher.nameAndPostalKey(held.get('LastName'), postal);
        }
        return externalIdField == null
            ? null
            : ImportMatcher.nameKey(valueOf(held, externalIdField));
    }

    private static Map<String, Id> matchPeople(
        String rule,
        Boolean personAccounts,
        Set<String> emailKeys,
        Set<String> namePostalKeys,
        Set<String> externalIds,
        Outcome outcome
    ) {
        if (ImportTemplateService.RULE_EMAIL.equals(rule)) {
            return personAccounts
                ? ImportMatcher.personAccountsByEmail(emailKeys, personRecordTypeIds())
                : ImportMatcher.contactsByEmail(emailKeys);
        }
        if (ImportTemplateService.RULE_NAME_POSTAL.equals(rule)) {
            return personAccounts
                ? ImportMatcher.personAccountsByNameAndPostalCode(
                      namePostalKeys,
                      personRecordTypeIds()
                  )
                : ImportMatcher.contactsByNameAndPostalCode(namePostalKeys);
        }
        // A rule with no field to match on was named in the run log by readMatchingChoices.
        return ImportMatcher.byMatchField(
            personAccounts ? Account.SObjectType : Contact.SObjectType,
            personMatchField,
            externalIds,
            personAccounts ? personRecordTypeIds() : null
        );
    }

    /**
     * The key that finds this person by their first name: their own key when the row's two
     * people share one (it is narrowed already), else the shared key narrowed to the first
     * name the row gives. Null when the row gives none, or the rule does not use names.
     */
    private static String namedKey(Working item, Boolean isFirst) {
        String key = isFirst ? item.personKey1 : item.personKey2;
        if (key == null || !item.byName) {
            return null;
        }
        if (ImportMatcher.baseKey(key) != key) {
            return key;
        }
        String entity = isFirst ? ImportMapping.ENTITY_CONTACT_1 : ImportMapping.ENTITY_CONTACT_2;
        String first = ImportMatcher.comparableFirstName(
            attribute(item.byEntity, entity, 'FirstName')
        );
        return first == null ? null : ImportMatcher.firstNameKey(key, first);
    }

    /** In a dry run, the digests of every key this chunk's people could be found by. */
    private static Set<String> digestsToAsk(List<Working> working) {
        Set<String> digests = new Set<String>();
        for (Working item : working) {
            for (Integer which = 1; which <= 2; which++) {
                String key = which == 1 ? item.personKey1 : item.personKey2;
                String named = namedKey(item, which == 1);
                if (key != null) {
                    digests.add(digest(PERSON_DIGEST, ImportMatcher.baseKey(key)));
                }
                if (named != null) {
                    digests.add(digest(PERSON_DIGEST, named));
                }
            }
        }
        return digests;
    }

    private static Integer count(Map<String, Integer> counts, String key) {
        Integer found = key == null ? null : counts.get(key);
        return found == null ? 0 : found;
    }

    /**
     * Finds one person of each row among those already there: in the org, and in a dry run
     * among the people earlier chunks would create, which the commit will have created by the
     * time it reaches this chunk (R-IB12). A row giving a first name finds only a person with
     * that first name: one holding the shared key under another first name, or under none, is
     * taken to be somebody else, so the row's person is created unless an earlier row of the
     * chunk creates them, and nobody is renamed. The shared key alone finds a person only when
     * the row gives no first name (the earliest holder then), and a blank renames nobody. In a
     * dry run the earlier chunks' people are asked for by digest, for this chunk's keys only.
     */
    private static void findPerson(
        List<Working> working,
        Map<String, Id> matches,
        Map<String, Integer> earlier,
        Boolean isFirst
    ) {
        for (Working item : working) {
            String key = isFirst ? item.personKey1 : item.personKey2;
            if (key == null) {
                continue;
            }
            String shared = ImportMatcher.baseKey(key);
            String named = namedKey(item, isFirst);
            Integer heldEarlier = count(earlier, digest(PERSON_DIGEST, shared));
            Integer held =
                (matches.containsKey(shared) ? (ImportMatcher.isHeldByMany(shared) ? 2 : 1) : 0) +
                heldEarlier;
            Id found = named == null ? null : matches.get(named);
            // Several records holding the key the row is looked for by (R-IT9).
            Boolean several = found != null && ImportMatcher.isHeldByMany(named);
            Boolean coming =
                found == null &&
                named != null &&
                count(earlier, digest(PERSON_DIGEST, named)) > 0;
            // A row giving a first name is found by it or created, never given whoever else
            // holds the shared key (R-IB12). A key whose lookup stopped at the row cap may have
            // a holder unseen, so it finds nobody by itself either.
            if (
                found == null &&
                !coming &&
                shared == key &&
                named == null &&
                !ImportMatcher.wasCutOff(shared)
            ) {
                found = matches.get(shared);
                // In a dry run, a person an earlier chunk would create holds the key too, as
                // the commit will find (R-IB12).
                several =
                    (found != null && (ImportMatcher.isHeldByMany(shared) || heldEarlier > 0)) ||
                    (found == null &&
                    heldEarlier > 1);
                coming = found == null && heldEarlier > 0;
            }
            if (several) {
                item.severalMatches = true;
                if (!mostRecent) {
                    // Rejected rather than guessed: a row loaded into the wrong one of two
                    // records is harder to notice than a rejected row (R-IT9).
                    found = null;
                    coming = false;
                    if (item.error == null) {
                        item.error = Label.Core_Import_ErrorSeveralPeopleMatch;
                    }
                }
            }
            if (isFirst) {
                item.person1Id = found;
                item.comingPerson1 = coming;
                item.heldBefore1 = Math.min(held, 2);
            } else {
                item.person2Id = found;
                item.comingPerson2 = coming;
                item.heldBefore2 = Math.min(held, 2);
            }
        }
    }

    /**
     * Which person an earlier row of this chunk creates is this one, by the key to share, or
     * null when this row creates them. A row giving a first name shares only a person of that
     * first name; one giving none shares by the shared key alone, when nobody held it before
     * the chunk. `created` counts the people of the chunk holding each key (R-IB12).
     */
    private static String keyToShare(Working item, Boolean isFirst, ChunkPeople chunk) {
        String key = isFirst ? item.personKey1 : item.personKey2;
        if (key == null) {
            return null;
        }
        String named = namedKey(item, isFirst);
        if (named != null) {
            return count(chunk.created, named) > 0 ? named : null;
        }
        String shared = ImportMatcher.baseKey(key);
        Integer heldBefore = isFirst ? item.heldBefore1 : item.heldBefore2;
        return shared == key && heldBefore == 0 && count(chunk.created, shared) > 0 ? shared : null;
    }

    /**
     * Whether a row's first person is a couple's second person this chunk has yet to create,
     * named alone. Every first person is saved before any second person, so such a row waits
     * and shares the partner once the couple is saved, and so is in the couple's household
     * rather than one of their own (R-IB12).
     */
    private static Boolean waitsForPartner(Working item, ChunkPeople chunk) {
        String named = namedKey(item, true);
        return named != null &&
            ImportMatcher.baseKey(item.personKey1) == item.personKey1 &&
            item.person1Id == null &&
            !item.comingPerson1 &&
            chunk.waitingSeconds.contains(named) &&
            count(chunk.created, named) == 0;
    }

    /** First people waiting for a couple of the chunk to be saved, in a commit. */
    private static List<Working> waitingFirst = new List<Working>();

    /** Counts a person this chunk creates under every key that finds them. */
    private static List<String> countCreated(Working item, Boolean isFirst, ChunkPeople chunk) {
        List<String> finding = keysFinding(item, isFirst);
        for (String key : finding) {
            chunk.created.put(key, count(chunk.created, key) + 1);
        }
        return finding;
    }

    /**
     * A matching key as sixteen hex digits: the first eight bytes of its MD5 digest, so 64
     * bits keep two keys well clear of sharing one. It is kept on the row (Person 1 Key,
     * Person 2 Key, Organization Key), compared only and never shown.
     */
    private static String digest(String kind, String key) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(kind + key)))
            .left(16);
    }

    /**
     * Clears what an earlier pass left on a row and stamps it with this one (R-IB13). There is
     * no reset of the rows before a pass, which for a large file would be more writes than one
     * transaction allows, so each chunk does it for its own rows before working them out. What
     * a pass resolved is its own answer: a commit never acts on a gift or a household a dry
     * run only described, and a key is read only by the pass that wrote it (R-IB12).
     */
    @NamespaceAccessible
    public static void startPass(Import_Row__c row, Decimal pass) {
        row.Pass_Number__c = pass;
        row.Status__c = STATUS_PENDING;
        row.Error_Message__c = null;
        row.Household__c = null;
        row.Contact_1__c = null;
        row.Contact_2__c = null;
        row.Person_1_Account__c = null;
        row.Person_2_Account__c = null;
        row.Organization__c = null;
        row.Gift_Id__c = null;
        row.Soft_Credit_Id__c = null;
        row.Person_1_Key__c = null;
        row.Person_2_Key__c = null;
        row.Person_1_Name_Key__c = null;
        row.Person_2_Name_Key__c = null;
        row.Organization_Key__c = null;
        row.Processor_Key__c = null;
        row.Several_Matches__c = false;
        row.Duplicate_Rule_Match__c = false;
    }

    /** A row has to describe somebody. One that does not is rejected before anything is saved. */
    private static void validate(List<Working> working) {
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            if (item.values.isEmpty()) {
                item.error = Label.Core_Import_ErrorRowUnreadable;
                continue;
            }
            Boolean hasOrganization = item.organizationKey != null || item.organizationName != null;
            Boolean hasPerson1 = describesPerson(item, ImportMapping.ENTITY_CONTACT_1);
            Boolean hasPerson2 = describesPerson(item, ImportMapping.ENTITY_CONTACT_2);
            Boolean identifiesSomebody =
                hasOrganization ||
                item.organizationId != null ||
                item.givenPerson1 ||
                item.givenPerson2 ||
                identifiesPerson(item, ImportMapping.ENTITY_CONTACT_1) ||
                identifiesPerson(item, ImportMapping.ENTITY_CONTACT_2);
            if (!identifiesSomebody) {
                item.error = Label.Core_Import_ErrorRowIdentifiesNobody;
                continue;
            }
            if (
                hasPerson1 &&
                item.person1Id == null &&
                !item.comingPerson1 &&
                !hasLastName(item, ImportMapping.ENTITY_CONTACT_1)
            ) {
                item.error = Label.Core_Import_ErrorLastNameMissing;
            } else if (
                hasPerson2 &&
                item.person2Id == null &&
                !item.comingPerson2 &&
                !hasLastName(item, ImportMapping.ENTITY_CONTACT_2)
            ) {
                item.error = Label.Core_Import_ErrorLastNameMissing;
            }
        }
    }

    /**
     * Whether the row carries a value that could name or find this person: a name part or an
     * email. This is a narrower question than `describesPerson`, and deliberately so. A row that
     * maps only an address puts a value on the entity, so `describesPerson` says yes, but an
     * address on its own cannot create a person and cannot match one either, which is exactly what
     * `Core_Import_ErrorRowIdentifiesNobody` tells the administrator: no name, no email and no
     * organization means there is nothing to create or match. The organization side of that
     * sentence is the organization's name or its matching key.
     */
    private static Boolean identifiesPerson(Working item, String entity) {
        Map<String, String> held = item.byEntity.get(entity);
        if (held == null) {
            return false;
        }
        for (String attribute : IDENTIFYING_ATTRIBUTES) {
            if (String.isNotBlank(held.get(attribute))) {
                return true;
            }
        }
        return false;
    }

    private static Boolean describesPerson(Working item, String entity) {
        Map<String, String> held = item.byEntity.get(entity);
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

    private static Boolean hasLastName(Working item, String entity) {
        return String.isNotBlank(attribute(item.byEntity, entity, 'LastName'));
    }

    /**
     * On a dry run there is nothing to compare a matched person's stored values against
     * without reading them, so the preview reads them: the counts an administrator sees are
     * the counts the commit will produce. A person an earlier chunk would create counts as
     * matched, and a person this chunk would create is remembered for the chunks after it
     * (R-IB12).
     */
    private static void countUpdatesInPreview(
        List<Working> working,
        Boolean personAccounts,
        String rule
    ) {
        Set<Id> matchedIds = new Set<Id>();
        for (Working item : working) {
            if (item.person1Id != null) {
                matchedIds.add(item.person1Id);
            }
            if (item.person2Id != null) {
                matchedIds.add(item.person2Id);
            }
        }
        Map<Id, SObject> stored = readStored(matchedIds, personAccounts, working);
        // The commit saves every row's first person before any second person, and a second
        // person whose row has a first person before one whose row has not; the first row it
        // saves a new person for creates them and the rest share them. The preview walks the
        // chunk in the same order so it names the same row as the one that creates (R-IB12).
        ChunkPeople keysInChunk = chunkPeople(working);
        List<Working> withFirst = new List<Working>();
        List<Working> withoutFirst = new List<Working>();
        List<Working> waiting = new List<Working>();
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            if (
                describesPerson(item, ImportMapping.ENTITY_CONTACT_1) &&
                waitsForPartner(item, keysInChunk)
            ) {
                waiting.add(item);
            } else {
                previewPerson(item, true, stored, keysInChunk, rule, personAccounts);
            }
            Boolean hasFirst =
                item.person1Id != null ||
                item.comingPerson1 ||
                describesPerson(item, ImportMapping.ENTITY_CONTACT_1);
            (hasFirst ? withFirst : withoutFirst).add(item);
        }
        withFirst.addAll(withoutFirst);
        for (Working item : withFirst) {
            previewPerson(item, false, stored, keysInChunk, rule, personAccounts);
        }
        for (Working item : waiting) {
            previewPerson(item, true, stored, keysInChunk, rule, personAccounts);
        }
    }

    /**
     * One person of a row in the preview: created, unless an earlier chunk or an earlier row of
     * this chunk would create them; otherwise updated when the row changes their stored values.
     */
    private static void previewPerson(
        Working item,
        Boolean isFirst,
        Map<Id, SObject> stored,
        ChunkPeople keysInChunk,
        String rule,
        Boolean personAccounts
    ) {
        String entity = isFirst ? ImportMapping.ENTITY_CONTACT_1 : ImportMapping.ENTITY_CONTACT_2;
        Id personId = isFirst ? item.person1Id : item.person2Id;
        Boolean coming = isFirst ? item.comingPerson1 : item.comingPerson2;
        if (personId == null && !coming && describesPerson(item, entity)) {
            if (keyToShare(item, isFirst, keysInChunk) != null) {
                return;
            }
            item.createdAnything = true;
            countCreated(item, isFirst, keysInChunk);
            rememberCreated(item, entity, rule, personAccounts);
        } else if (
            changes(stored.get(personId), asStored(item.byEntity.get(entity), personAccounts))
        ) {
            item.updatedAnything = true;
        }
    }

    /**
     * Remembers a person a dry run would create, for later chunks to match, but only when the
     * commit could find them again by the same key: the record it creates must carry the value
     * the matcher reads. An email is written to a contact's Email and to a person account's
     * PersonEmail, and a postal code only to a person whose own column gave it (MailingPostalCode
     * or PersonMailingPostalCode), and each only where the importing user may write that field;
     * an external ID is written to either. A person the commit could not find again is created
     * again, and the dry run says so too.
     */
    private static void rememberCreated(
        Working item,
        String entity,
        String rule,
        Boolean personAccounts
    ) {
        String key = entity == ImportMapping.ENTITY_CONTACT_1 ? item.personKey1 : item.personKey2;
        Boolean findable =
            ImportTemplateService.RULE_EXTERNAL_ID.equals(rule) ||
            (ImportTemplateService.RULE_EMAIL.equals(rule)
                ? writes('Email', personAccounts)
                : String.isNotBlank(attribute(item.byEntity, entity, 'MailingPostalCode')) &&
                  writes('MailingPostalCode', personAccounts));
        if (key == null || !findable) {
            return;
        }
        // Under the shared key and under the same narrowed to the first name, so a later row
        // finds them by whichever it holds (R-IB12).
        List<String> finding = keysFinding(item, entity == ImportMapping.ENTITY_CONTACT_1);
        String shared = digest(PERSON_DIGEST, finding[0]);
        String named = digest(PERSON_DIGEST, finding[1]);
        if (entity == ImportMapping.ENTITY_CONTACT_1) {
            item.row.Person_1_Key__c = shared;
            item.row.Person_1_Name_Key__c = named;
        } else {
            item.row.Person_2_Key__c = shared;
            item.row.Person_2_Name_Key__c = named;
        }
    }

    /**
     * Inserts the new people and updates the matched ones.
     *
     * The order is load bearing. The first person is saved first, because the household
     * trigger gives them a household on that save and the second person's household is the
     * one the first person ended up in: `resolveHouseholds` reads it back before the second
     * person is saved at all.
     *
     * The second person is then saved in two passes over the chunk, which is two saves and
     * not one per row. The people who are joining a household their row already knows are
     * saved with automatic creation suspended, so that nobody is given a household of their
     * own and then taken out of it again, and `joinSecondPeople` joins them afterwards.
     * Everybody else (a row whose first person is missing, or failed) is saved normally and
     * gets a household of their own, which is what a row describing one person means.
     */
    private static void savePeople(
        List<Working> working,
        Import_Batch__c batch,
        Boolean personAccounts,
        Outcome outcome
    ) {
        keysBeingCreated = chunkPeople(working);
        createdByKey = new Map<String, Id>();
        failedByKey = new Map<String, String>();
        waitingFirst = new List<Working>();
        insertPeople(
            working,
            batch,
            personAccounts,
            ImportMapping.ENTITY_CONTACT_1,
            true,
            null,
            outcome
        );
        resolveHouseholds(working, personAccounts);
        HouseholdService.suspendAutomaticCreation();
        try {
            insertPeople(
                working,
                batch,
                personAccounts,
                ImportMapping.ENTITY_CONTACT_2,
                false,
                true,
                outcome
            );
        } finally {
            HouseholdService.resumeAutomaticCreation();
        }
        joinSecondPeople(working, outcome);
        insertPeople(
            working,
            batch,
            personAccounts,
            ImportMapping.ENTITY_CONTACT_2,
            false,
            false,
            outcome
        );
        // The first people who waited for a couple now share the partner it saved, or are
        // created after all where the couple's row failed (R-IB12).
        List<Working> waited = waitingFirst;
        waitingFirst = null;
        insertPeople(
            waited,
            batch,
            personAccounts,
            ImportMapping.ENTITY_CONTACT_1,
            true,
            null,
            outcome
        );
        resolveHouseholds(working, personAccounts);
        updateMatchedPeople(working, personAccounts, outcome);
    }

    /**
     * Joins each row's second person to the household its first person is in.
     *
     * Membership is never reimplemented here (R-M5). `HouseholdService.addMembers` is what
     * joining an existing household means, and it is the only thing that knows how this org
     * writes membership down: the person's own account reference in contact mode, a
     * `Household_Member__c` row in junction mode, for a person stored as a contact and for a
     * person stored as an account alike. The whole chunk is joined in one call, and the
     * write fires the trigger that recounts and renames the households it touched, exactly
     * as a join made by hand does.
     *
     * Only a person this run created is joined. A second person who matched somebody the org
     * already has keeps the household they already belong to: an import that names two
     * existing people on one line is not a licence to move one of them.
     */
    private static void joinSecondPeople(List<Working> working, Outcome outcome) {
        Map<Id, Set<Id>> peopleByHousehold = new Map<Id, Set<Id>>();
        for (Working item : working) {
            if (item.error != null || !item.createdPerson2 || item.person2Id == null) {
                continue;
            }
            if (item.row.Household__c == null) {
                continue;
            }
            if (!peopleByHousehold.containsKey(item.row.Household__c)) {
                peopleByHousehold.put(item.row.Household__c, new Set<Id>());
            }
            peopleByHousehold.get(item.row.Household__c).add(item.person2Id);
        }
        if (peopleByHousehold.isEmpty()) {
            return;
        }
        try {
            HouseholdService.addMembers(peopleByHousehold);
        } catch (Exception e) {
            // The people are saved and the rows say so. A household that could not be joined
            // is reported in the run log and in the Error Log rather than thrown, so one bad
            // household does not take the chunk with it (R-IB5).
            ErrorLogger.log(e, 'ImportRowProcessor.joinSecondPeople');
            outcome.notes.add(e.getMessage());
        }
    }

    /**
     * Inserts the people this chunk has to create for one entity.
     *
     * `joiningAHousehold` selects which of them: true is the people whose row already knows
     * the household they belong to, false is the people whose row does not, and null is
     * everybody, which is what the first person of a row always is.
     *
     * A new person named on several rows of the chunk, by the same matching key in either
     * person column, is created once, for the first of them; the others share that record, as
     * a later chunk would find it, and are not joined to a household for it (R-IB12). When it
     * cannot be saved, those rows are rejected with the reason.
     */
    private static void insertPeople(
        List<Working> working,
        Import_Batch__c batch,
        Boolean personAccounts,
        String entity,
        Boolean isFirst,
        Boolean joiningAHousehold,
        Outcome outcome
    ) {
        List<SObject> toCreate = new List<SObject>();
        List<Working> owners = new List<Working>();
        List<List<String>> ownerKeys = new List<List<String>>();
        List<Working> sharing = new List<Working>();
        List<String> sharedKeys = new List<String>();
        Id personRecordTypeId = personAccounts ? anyPersonRecordTypeId() : null;
        if (personAccounts && personRecordTypeId == null) {
            outcome.notes.add(Label.Core_Import_LogPersonRecordTypeMissing);
            return;
        }
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            Id already = isFirst ? item.person1Id : item.person2Id;
            if (already != null || !describesPerson(item, entity)) {
                continue;
            }
            if (joiningAHousehold != null && joiningAHousehold != (item.row.Household__c != null)) {
                continue;
            }
            if (isFirst && waitingFirst != null && waitsForPartner(item, keysBeingCreated)) {
                waitingFirst.add(item);
                continue;
            }
            String shareKey = keyToShare(item, isFirst, keysBeingCreated);
            if (shareKey != null) {
                sharing.add(item);
                sharedKeys.add(shareKey);
                continue;
            }
            List<String> finding = countCreated(item, isFirst, keysBeingCreated);
            SObject person = personAccounts
                ? (SObject) new Account(RecordTypeId = personRecordTypeId)
                : (SObject) new Contact();
            Schema.SObjectType type = personAccounts ? Account.SObjectType : Contact.SObjectType;
            applyValues(
                person,
                type,
                asStored(item.byEntity.get(entity), personAccounts),
                notWrittenToPeople(type),
                outcome
            );
            person.put('Created_By_Import_Batch__c', batch.Id);
            // Nobody is saved into a household here. A person saved straight into a household
            // account is saying "contact mode", which is one of two ways an org can hold
            // membership, and the importer does not get to pick. The household itself is made
            // by the household trigger, and the second person is joined to the first person's
            // household by joinSecondPeople, through the service that knows which way this org
            // writes membership down.
            toCreate.add(person);
            owners.add(item);
            ownerKeys.add(finding);
        }
        List<Database.SaveResult> results = toCreate.isEmpty()
            ? new List<Database.SaveResult>()
            : Database.insert(toCreate, saveOptions(), AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            Working owner = owners[i];
            for (String key : ownerKeys[i]) {
                // The first person saved under a key is the one a later row shares.
                if (results[i].isSuccess() && !createdByKey.containsKey(key)) {
                    createdByKey.put(key, results[i].getId());
                } else if (!results[i].isSuccess() && !failedByKey.containsKey(key)) {
                    failedByKey.put(key, message(results[i]));
                }
            }
            if (results[i].isSuccess()) {
                if (isFirst) {
                    owner.person1Id = results[i].getId();
                    owner.createdPerson1 = true;
                } else {
                    owner.person2Id = results[i].getId();
                    owner.createdPerson2 = true;
                }
                owner.createdAnything = true;
            } else {
                owner.error = message(results[i]);
            }
        }
        shareCreatedPeople(sharing, sharedKeys, isFirst);
    }

    /** Gives rows naming a person an earlier row of the chunk created that person's record. */
    private static void shareCreatedPeople(
        List<Working> sharing,
        List<String> sharedKeys,
        Boolean isFirst
    ) {
        for (Integer i = 0; i < sharing.size(); i++) {
            Id created = createdByKey.get(sharedKeys[i]);
            if (created == null) {
                String reason = failedByKey.get(sharedKeys[i]);
                sharing[i].error = String.format(
                    Label.Core_Import_ErrorSamePersonNotSaved,
                    new List<String>{ reason == null ? Label.Core_Import_ErrorSaveFailed : reason }
                );
            } else if (isFirst) {
                sharing[i].person1Id = created;
            } else {
                sharing[i].person2Id = created;
            }
        }
    }

    /** Asks the household service which household each new person ended up in. */
    private static void resolveHouseholds(List<Working> working, Boolean personAccounts) {
        Set<Id> personIds = new Set<Id>();
        for (Working item : working) {
            if (item.row.Household__c == null && item.person1Id != null) {
                personIds.add(item.person1Id);
            }
        }
        if (personIds.isEmpty()) {
            return;
        }
        Map<Id, Id> households = HouseholdService.getHouseholdIdsFor(personIds);
        for (Working item : working) {
            if (item.row.Household__c == null && item.person1Id != null) {
                item.row.Household__c = households.get(item.person1Id);
            }
        }
    }

    private static void updateMatchedPeople(
        List<Working> working,
        Boolean personAccounts,
        Outcome outcome
    ) {
        Set<Id> matchedIds = new Set<Id>();
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            if (item.person1Id != null && (item.personKey1 != null || item.givenPerson1)) {
                matchedIds.add(item.person1Id);
            }
            if (item.person2Id != null && (item.personKey2 != null || item.givenPerson2)) {
                matchedIds.add(item.person2Id);
            }
        }
        Map<Id, SObject> stored = readStored(matchedIds, personAccounts, working);
        Map<Id, SObject> toUpdate = new Map<Id, SObject>();
        Map<Id, List<Working>> ownersByRecord = new Map<Id, List<Working>>();
        Schema.SObjectType type = personAccounts ? Account.SObjectType : Contact.SObjectType;
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            for (Integer which = 1; which <= 2; which++) {
                Id personId = which == 1 ? item.person1Id : item.person2Id;
                if (which == 2 && personId == item.person1Id) {
                    // Never write the second person's values over the first person (R-IB12).
                    continue;
                }
                String entity = which == 1
                    ? ImportMapping.ENTITY_CONTACT_1
                    : ImportMapping.ENTITY_CONTACT_2;
                Map<String, String> held = asStored(item.byEntity.get(entity), personAccounts);
                SObject existing = stored.get(personId);
                if (personId == null || existing == null || !changes(existing, held)) {
                    continue;
                }
                SObject change = toUpdate.get(personId);
                if (change == null) {
                    change = type.newSObject(personId);
                    toUpdate.put(personId, change);
                }
                applyChanges(change, existing, type, held, outcome);
                if (!ownersByRecord.containsKey(personId)) {
                    ownersByRecord.put(personId, new List<Working>());
                }
                ownersByRecord.get(personId).add(item);
            }
        }
        if (toUpdate.isEmpty()) {
            return;
        }
        List<SObject> records = toUpdate.values();
        List<Database.SaveResult> results = Database.update(
            records,
            saveOptions(),
            AccessLevel.USER_MODE
        );
        String objectName = personAccounts ? 'Account' : 'Contact';
        for (Integer i = 0; i < results.size(); i++) {
            List<Working> owners = ownersByRecord.get(records[i].Id);
            for (Working owner : owners) {
                if (results[i].isSuccess()) {
                    owner.updatedAnything = true;
                } else if (owner.error == null) {
                    owner.error = message(results[i]);
                }
            }
            if (results[i].isSuccess()) {
                journalUpdate(
                    outcome,
                    objectName,
                    records[i],
                    stored.get(records[i].Id),
                    rowNumber(owners[0].row)
                );
            }
        }
    }

    /**
     * Records one saved update in the journal: every attribute the save wrote, with the value
     * the record held before and the value written (R-IJ3). The value before is the one
     * nobody could recover anywhere else, which is why it is kept in full.
     */
    private static void journalUpdate(
        Outcome outcome,
        String objectName,
        SObject written,
        SObject before,
        Integer row
    ) {
        Map<String, Object> beforeByField = new Map<String, Object>();
        Map<String, Object> afterByField = new Map<String, Object>();
        for (String field : written.getPopulatedFieldsAsMap().keySet()) {
            if ('Id'.equalsIgnoreCase(field)) {
                continue;
            }
            afterByField.put(field, written.get(field));
            beforeByField.put(field, before == null ? null : before.get(field));
        }
        if (!afterByField.isEmpty()) {
            outcome.journal.add(
                ImportJournalService.updated(
                    objectName,
                    written.Id,
                    row,
                    beforeByField,
                    afterByField
                )
            );
        }
    }

    private static Integer rowNumber(Import_Row__c row) {
        return row == null || row.Row_Number__c == null ? null : row.Row_Number__c.intValue();
    }

    /**
     * The mapped attributes as they currently stand on the matched records. Only the
     * attributes this mapping names are selected, and only those the object actually has, so
     * a template written for another org cannot produce an invalid query.
     */
    private static Map<Id, SObject> readStored(
        Set<Id> ids,
        Boolean personAccounts,
        List<Working> working
    ) {
        Map<Id, SObject> result = new Map<Id, SObject>();
        if (ids == null || ids.isEmpty()) {
            return result;
        }
        Schema.SObjectType type = personAccounts ? Account.SObjectType : Contact.SObjectType;
        Map<String, Schema.SObjectField> fields = fieldsOf(type);
        Set<String> selected = new Set<String>{ 'Id' };
        for (Working item : working) {
            for (
                String entity : new List<String>{
                    ImportMapping.ENTITY_CONTACT_1,
                    ImportMapping.ENTITY_CONTACT_2
                }
            ) {
                Map<String, String> held = item.byEntity.get(entity);
                if (held == null) {
                    continue;
                }
                for (String attributeName : held.keySet()) {
                    Schema.SObjectField field = fields.get(
                        storedName(attributeName, personAccounts).toLowerCase()
                    );
                    if (field != null && field.getDescribe().isAccessible()) {
                        selected.add(field.getDescribe().getName());
                    }
                }
            }
        }
        String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        String query =
            'SELECT ' +
            String.join(new List<String>(selected), ', ') +
            ' FROM ' +
            objectName +
            ' WHERE Id IN :ids LIMIT 2000';
        for (
            SObject record : Database.queryWithBinds(
                query,
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        ) {
            result.put((Id) record.get('Id'), record);
        }
        return result;
    }

    /** True when any mapped attribute would change the stored record. */
    private static Boolean changes(SObject stored, Map<String, String> held) {
        return !differences(stored, held).isEmpty();
    }

    /**
     * The mapped attributes whose incoming value differs from what is stored. A blank
     * incoming value never clears a stored one: an import adds what the file knows and does
     * not erase what it is silent about.
     */
    private static Map<String, String> differences(SObject stored, Map<String, String> held) {
        Map<String, String> result = new Map<String, String>();
        if (stored == null || held == null || held.isEmpty()) {
            return result;
        }
        Map<String, Object> populated = new Map<String, Object>();
        for (String name : stored.getPopulatedFieldsAsMap().keySet()) {
            populated.put(name.toLowerCase(), stored.getPopulatedFieldsAsMap().get(name));
        }
        for (String attributeName : held.keySet()) {
            String incoming = held.get(attributeName);
            String lookupKey = attributeName.toLowerCase();
            // A field that was not selected cannot be compared, so it is not claimed as a
            // change: saying "would update" about something unread would be a lie.
            if (String.isBlank(incoming) || !populated.containsKey(lookupKey)) {
                continue;
            }
            Object current = populated.get(lookupKey);
            if (isCheckbox(stored, lookupKey)) {
                // A checkbox is compared as the value the save would write: "Yes" in the file
                // is the true already stored, not a change to journal on every re-import.
                if ((Boolean) convertCheckbox(incoming) != (current == true)) {
                    result.put(attributeName, incoming);
                }
                continue;
            }
            String currentText = current == null ? '' : String.valueOf(current);
            if (!currentText.equalsIgnoreCase(incoming)) {
                result.put(attributeName, incoming);
            }
        }
        return result;
    }

    private static void applyChanges(
        SObject change,
        SObject stored,
        Schema.SObjectType type,
        Map<String, String> held,
        Outcome outcome
    ) {
        applyValues(change, type, differences(stored, held), notWrittenToPeople(type), outcome);
    }

    /**
     * Attributes a person record never takes from a row. A person stored as an account in an
     * org with person accounts is named by its own first and last name fields, and the
     * business account Name is not one of its fields, so a column mapped to Name is left to
     * the name parts beside it rather than failing the person's save. Where Account has no
     * person name fields (a Platform only org) nothing is left out.
     */
    private static Set<String> notWrittenToPeople(Schema.SObjectType type) {
        Set<String> skipped = new Set<String>();
        if (type == Account.SObjectType && fieldsOf(type).containsKey('lastname')) {
            skipped.add('Name');
        }
        return skipped;
    }

    /**
     * A person's attributes under the names of the fields that hold them. A row describes a
     * person in contact terms (Email, MailingPostalCode, HasOptedOutOfEmail), because a
     * template is written once for every org (R-IT1). A person stored as an account holds
     * those in its person fields (PersonEmail, PersonMailingPostalCode,
     * PersonHasOptedOutOfEmail), so written under the contact names they were unknown to the
     * account and only the name and phone stuck. The names are translated here, for the
     * save, the comparison and the read alike; matching keys are still read from the row's
     * contact names.
     */
    private static Map<String, String> asStored(Map<String, String> held, Boolean personAccounts) {
        if (!personAccounts || held == null) {
            return held;
        }
        Map<String, String> result = new Map<String, String>();
        for (String attributeName : held.keySet()) {
            result.put(storedName(attributeName, personAccounts), held.get(attributeName));
        }
        return result;
    }

    /**
     * The field a person attribute is held in. For a person stored as an account that is the
     * person field the org has for it: the contact name prefixed with Person for a standard
     * field (PersonEmail, PersonMailingStreet, PersonDoNotCall, PersonBirthdate, PersonTitle),
     * or a contact custom field's account form ending in __pc. An attribute with neither (the
     * name parts, Phone) is the account's own field of that name. Only names read from the
     * org's own describe are used, never a person field written into the source: Core runs on
     * orgs that do not have them (ADR-0013, plan Section 4.2).
     */
    private static String storedName(String attributeName, Boolean personAccounts) {
        if (!personAccounts || String.isBlank(attributeName)) {
            return attributeName;
        }
        if (!storedNames.containsKey(attributeName)) {
            storedNames.put(attributeName, personFieldFor(attributeName));
        }
        return storedNames.get(attributeName);
    }

    /** Each attribute's person account field, worked out once per transaction. */
    private static Map<String, String> storedNames = new Map<String, String>();

    private static String personFieldFor(String attributeName) {
        Map<String, Schema.SObjectField> fields = fieldsOf(Account.SObjectType);
        String person = PERSON_FIELD_PREFIX + attributeName;
        if (fields.containsKey(person.toLowerCase())) {
            return fields.get(person.toLowerCase()).getDescribe().getName();
        }
        if (attributeName.toLowerCase().endsWith('__c')) {
            String custom = attributeName.left(attributeName.length() - 1) + 'pc';
            if (fields.containsKey(custom.toLowerCase())) {
                return fields.get(custom.toLowerCase()).getDescribe().getName();
            }
        }
        return attributeName;
    }

    /** Whether a new person saved by this user carries this attribute (R-IB12). */
    private static Boolean writes(String attributeName, Boolean personAccounts) {
        Schema.SObjectType type = personAccounts ? Account.SObjectType : Contact.SObjectType;
        Schema.SObjectField field = fieldsOf(type)
            .get(storedName(attributeName, personAccounts).toLowerCase());
        return field != null && field.getDescribe().isCreateable();
    }

    // -------------------------------------------------------------------------------------
    // Households
    // -------------------------------------------------------------------------------------

    /**
     * Tags the households this chunk's new people were given, and applies the row's household
     * attributes to the household its first person is in, in one save.
     *
     * A household is made by the household automation, not by the importer, so it cannot be
     * tagged when it is inserted; it is tagged straight afterwards instead, and only when it
     * was made for a person this import created (R-IB3). A household an existing person
     * already had is never tagged, so an undo can never delete it. A name written to such a
     * household is an update to a record the import did not create, and is journaled so an
     * undo can put the old name back.
     */
    private static void tagAndNameHouseholds(
        List<Working> working,
        Import_Batch__c batch,
        Boolean dryRun,
        Outcome outcome
    ) {
        if (dryRun) {
            return;
        }
        Set<Id> created = householdsCreatedFor(working);
        Map<Id, String> names = new Map<Id, String>();
        Map<Id, Integer> firstRowByHousehold = new Map<Id, Integer>();
        for (Working item : working) {
            Map<String, String> held = item.byEntity.get(ImportMapping.ENTITY_HOUSEHOLD);
            if (item.error != null || item.row.Household__c == null || held == null) {
                continue;
            }
            String name = held.get('Name');
            if (String.isBlank(name)) {
                continue;
            }
            // Naming the household by hand is exactly what the custom name flag means, so the
            // naming service leaves it alone from here on.
            names.put(item.row.Household__c, name);
            if (!firstRowByHousehold.containsKey(item.row.Household__c)) {
                firstRowByHousehold.put(item.row.Household__c, rowNumber(item.row));
            }
        }
        if (created.isEmpty() && names.isEmpty()) {
            return;
        }
        Set<Id> existing = new Set<Id>(names.keySet());
        existing.removeAll(created);
        Map<Id, Account> before = readHouseholds(existing);

        Map<Id, Account> byHousehold = new Map<Id, Account>();
        for (Id householdId : created) {
            byHousehold.put(
                householdId,
                new Account(Id = householdId, Created_By_Import_Batch__c = batch.Id)
            );
        }
        for (Id householdId : names.keySet()) {
            Account household = byHousehold.containsKey(householdId)
                ? byHousehold.get(householdId)
                : new Account(Id = householdId);
            household.Name = names.get(householdId);
            household.Custom_Name__c = true;
            byHousehold.put(householdId, household);
        }
        List<Account> records = byHousehold.values();
        List<Database.SaveResult> results = Database.update(
            records,
            saveOptions(),
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            Account household = records[i];
            if (results[i].isSuccess()) {
                if (before.containsKey(household.Id)) {
                    journalRename(
                        outcome,
                        household,
                        before.get(household.Id),
                        firstRowByHousehold
                    );
                }
                continue;
            }
            if (!names.containsKey(household.Id)) {
                // Only the tag failed. The people are saved and the rows are right, so this
                // is a note for the run log rather than a rejected row (R-IB5).
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogHouseholdNotTagged,
                        new List<String>{ message(results[i]) }
                    )
                );
                continue;
            }
            for (Working item : working) {
                if (item.row.Household__c == household.Id && item.error == null) {
                    item.error = message(results[i]);
                }
            }
        }
    }

    /** A rename of a household the import did not create, for the journal (R-IJ3). */
    private static void journalRename(
        Outcome outcome,
        Account household,
        Account was,
        Map<Id, Integer> firstRowByHousehold
    ) {
        outcome.journal.add(
            ImportJournalService.updated(
                'Account',
                household.Id,
                firstRowByHousehold.get(household.Id),
                new Map<String, Object>{
                    'Name' => was.Name,
                    'Custom_Name__c' => was.Custom_Name__c
                },
                new Map<String, Object>{ 'Name' => household.Name, 'Custom_Name__c' => true }
            )
        );
    }

    /**
     * The households made for people this chunk created: the first person's, which the row
     * already knows, and the own household of a second person whose row had nobody first. A
     * second person joined to somebody else's household is not counted here, because that
     * household may be one an existing person already had.
     */
    private static Set<Id> householdsCreatedFor(List<Working> working) {
        Set<Id> result = new Set<Id>();
        Set<Id> onTheirOwn = new Set<Id>();
        for (Working item : working) {
            if (item.createdPerson1 && item.row.Household__c != null) {
                result.add(item.row.Household__c);
            } else if (item.createdPerson2 && item.person1Id == null && item.person2Id != null) {
                onTheirOwn.add(item.person2Id);
            }
        }
        if (!onTheirOwn.isEmpty()) {
            for (Id householdId : HouseholdService.getHouseholdIdsFor(onTheirOwn).values()) {
                if (householdId != null) {
                    result.add(householdId);
                }
            }
        }
        return result;
    }

    /** The name and custom name flag of households the import is about to rename. */
    private static Map<Id, Account> readHouseholds(Set<Id> householdIds) {
        if (householdIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>(
            [
                SELECT Id, Name, Custom_Name__c
                FROM Account
                WHERE Id IN :householdIds
                WITH USER_MODE
            ]
        );
    }

    // -------------------------------------------------------------------------------------
    // The rest of the row
    // -------------------------------------------------------------------------------------

    /**
     * Offers the chunk to the entity processor a dependent package may have registered
     * (R-IR6), and folds what it did into each row (R-IR7). Nothing here fails an import: an
     * absent processor is the normal case, and says so in the run log, and a processor that
     * throws is logged and reported in the run log, not raised.
     */
    private static void offerToEntityProcessor(
        Import_Batch__c batch,
        Import_Template__c template,
        ImportMapping mapping,
        List<Working> working,
        Boolean dryRun,
        Outcome outcome
    ) {
        Set<String> deferred = mapping.deferredEntities();
        if (deferred.isEmpty()) {
            return;
        }
        ImportEntityProcessor processor = ImportEntityProcessors.find();
        if (processor == null) {
            outcome.notes.add(
                String.format(
                    Label.Core_Import_LogEntitiesNotLoaded,
                    new List<String>{ String.join(new List<String>(deferred), ', ') }
                )
            );
            return;
        }
        List<Import_Row__c> rows = new List<Import_Row__c>();
        Map<Id, Map<String, Map<String, String>>> entitiesByRowId = new Map<Id, Map<String, Map<String, String>>>();
        for (Working item : working) {
            // The processor reads what Core resolved from the row itself (R-IR6).
            stampResolved(item);
            item.row.Status__c = item.error == null ? STATUS_PENDING : STATUS_REJECTED;
            item.row.Error_Message__c = item.error == null ? null : item.error.abbreviate(4000);
            rows.add(item.row);
            entitiesByRowId.put(item.row.Id, item.byEntity);
        }
        try {
            ImportEntityResult result = processor.resolve(
                batch,
                template,
                rows,
                entitiesByRowId,
                dryRun
            );
            if (result != null && String.isNotBlank(result.note)) {
                outcome.notes.add(result.note);
            }
            if (result != null && result.fileAmount != null) {
                outcome.fileAmount = result.fileAmount;
            }
            if (result != null && String.isNotBlank(result.settings)) {
                outcome.processorSettings = result.settings;
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportRowProcessor.offerToEntityProcessor');
            outcome.notes.add(e.getMessage());
        }
        foldProcessorOutcome(working);
    }

    /**
     * A rejection by the processor wins over anything Core did with the row, and a creation
     * makes the row one that created something; a match leaves Core's own outcome (R-IR7).
     */
    private static void foldProcessorOutcome(List<Working> working) {
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            if (STATUS_REJECTED.equals(item.row.Status__c)) {
                item.error = String.isBlank(item.row.Error_Message__c)
                    ? Label.Core_Import_ErrorSaveFailed
                    : item.row.Error_Message__c;
            } else if (STATUS_CREATED.equals(item.row.Status__c)) {
                item.createdAnything = true;
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // The org's duplicate rules (R-IT16)
    // -------------------------------------------------------------------------------------

    /**
     * Asks the org's duplicate rules about each person the rule found nobody for: not given by
     * record ID, not created by an earlier chunk, on a row not already rejected. A person they
     * match is loaded into that record; several follow Several Matches (R-IT9). A row whose two
     * people they match to one record is rejected, since one record cannot be both.
     */
    private static void matchPeopleByDuplicateRules(
        List<Working> working,
        Boolean personAccounts,
        Outcome outcome
    ) {
        Schema.SObjectType type = personAccounts ? Account.SObjectType : Contact.SObjectType;
        Id recordTypeId = personAccounts ? anyPersonRecordTypeId() : null;
        List<SObject> probes = new List<SObject>();
        List<Working> owners = new List<Working>();
        List<Boolean> isFirst = new List<Boolean>();
        for (Working item : working) {
            for (Integer which = 1; which <= 2; which++) {
                String entity = which == 1
                    ? ImportMapping.ENTITY_CONTACT_1
                    : ImportMapping.ENTITY_CONTACT_2;
                Boolean unmatched = which == 1
                    ? item.person1Id == null && !item.comingPerson1
                    : item.person2Id == null && !item.comingPerson2;
                if (item.error != null || !unmatched || !describesPerson(item, entity)) {
                    continue;
                }
                probes.add(
                    ImportDuplicateRuleMatcher.probe(
                        type,
                        asStored(item.byEntity.get(entity), personAccounts),
                        recordTypeId
                    )
                );
                owners.add(item);
                isFirst.add(which == 1);
            }
        }
        if (probes.isEmpty()) {
            return;
        }
        List<List<SObject>> found = ImportDuplicateRuleMatcher.matchesFor(
            probes,
            personAccounts ? personRecordTypeIds() : null
        );
        if (found == null) {
            outcome.notes.add(Label.Core_Import_LogNoDuplicateRulePeople);
            return;
        }
        for (Integer i = 0; i < probes.size(); i++) {
            Working item = owners[i];
            Id matched = chosenByRule(item, found[i], Label.Core_Import_ErrorSeveralPeopleMatch);
            if (matched == null) {
                continue;
            }
            if (isFirst[i]) {
                item.person1Id = matched;
            } else {
                item.person2Id = matched;
            }
            if (item.person1Id == item.person2Id) {
                item.error = Label.Core_Import_ErrorDuplicateRuleOnePerson;
            }
        }
    }

    /**
     * Asks the org's duplicate rules about each organization the rule found nobody for. In a
     * dry run an organization an earlier chunk would create is left out, because the commit
     * finds that one by its key (R-IB12).
     */
    private static void matchOrganizationsByDuplicateRules(
        List<Working> working,
        Map<String, Id> existing,
        Id recordTypeId,
        Import_Batch__c batch,
        Boolean dryRun,
        Outcome outcome
    ) {
        List<Working> owners = new List<Working>();
        Set<String> digests = new Set<String>();
        for (Working item : working) {
            if (
                looksForOrganization(item) &&
                (item.organizationKey == null || !existing.containsKey(item.organizationKey))
            ) {
                owners.add(item);
                if (dryRun && item.organizationKey != null) {
                    digests.add(digest(ORGANIZATION_DIGEST, item.organizationKey));
                }
            }
        }
        Set<String> earlier = digests.isEmpty()
            ? new Set<String>()
            : ImportRowSelector.createdDigestsWrittenEarlier(batch, digests);
        List<SObject> probes = new List<SObject>();
        List<Working> asked = new List<Working>();
        for (Working item : owners) {
            if (
                item.organizationKey != null &&
                earlier.contains(digest(ORGANIZATION_DIGEST, item.organizationKey))
            ) {
                continue;
            }
            Map<String, String> values = new Map<String, String>(
                item.byEntity.containsKey(ImportMapping.ENTITY_ORGANIZATION)
                    ? item.byEntity.get(ImportMapping.ENTITY_ORGANIZATION)
                    : new Map<String, String>()
            );
            values.put('Name', item.organizationName);
            probes.add(ImportDuplicateRuleMatcher.probe(Account.SObjectType, values, recordTypeId));
            asked.add(item);
        }
        if (probes.isEmpty()) {
            return;
        }
        List<List<SObject>> found = ImportDuplicateRuleMatcher.matchesFor(
            probes,
            new Set<Id>{ recordTypeId }
        );
        if (found == null) {
            outcome.notes.add(Label.Core_Import_LogNoDuplicateRuleOrganizations);
            return;
        }
        for (Integer i = 0; i < asked.size(); i++) {
            Id matched = chosenByRule(
                asked[i],
                found[i],
                Label.Core_Import_ErrorSeveralOrganizationsMatch
            );
            if (matched != null) {
                asked[i].organizationId = matched;
            }
        }
    }

    /**
     * The record the duplicate rules matched for one person or organization, or null: none
     * matched, or several did and Several Matches rejects the row (R-IT9).
     */
    private static Id chosenByRule(Working item, List<SObject> found, String severalError) {
        if (found.isEmpty() || item.error != null) {
            return null;
        }
        if (found.size() > 1) {
            item.severalMatches = true;
            if (!mostRecent) {
                item.error = severalError;
                return null;
            }
        }
        item.duplicateRuleMatch = true;
        return ImportDuplicateRuleMatcher.mostRecent(found).Id;
    }

    // -------------------------------------------------------------------------------------
    // Writing the rows back
    // -------------------------------------------------------------------------------------

    private static void writeBack(List<Working> working, Outcome outcome) {
        List<Import_Row__c> rows = new List<Import_Row__c>();
        for (Working item : working) {
            Import_Row__c row = item.row;
            // Ticked whether the row was rejected for it or not, so every such row can be
            // listed (R-IT9); the run log says once that some were loaded anyway.
            row.Several_Matches__c = item.severalMatches;
            // Ticked so the rows a looser rule matched can be read before a commit (R-IT16).
            row.Duplicate_Rule_Match__c = item.duplicateRuleMatch && item.error == null;
            if (row.Duplicate_Rule_Match__c) {
                outcome.notes.add(Label.Core_Import_LogDuplicateRuleMatches);
            }
            if (item.severalMatches && item.error == null) {
                outcome.notes.add(Label.Core_Import_LogSeveralMatchesUsedRecent);
            }
            if (item.error != null) {
                row.Status__c = STATUS_REJECTED;
                row.Error_Message__c = item.error.abbreviate(4000);
                outcome.rejected++;
            } else {
                row.Error_Message__c = null;
                stampResolved(item);
                if (item.createdAnything) {
                    row.Status__c = STATUS_CREATED;
                    outcome.created++;
                } else if (item.updatedAnything) {
                    row.Status__c = STATUS_UPDATED;
                    outcome.updated++;
                } else {
                    row.Status__c = STATUS_MATCHED;
                    outcome.matched++;
                }
            }
            rows.add(row);
        }
        if (rows.isEmpty()) {
            return;
        }
        // The staged rows are the package's own bookkeeping and must record what happened even
        // where the running user cannot edit them, for the reason ADR-0021 gives.
        Database.update(rows, false, AccessLevel.SYSTEM_MODE);
    }

    /** Writes the people and the organization the row resolved to onto the row. */
    private static void stampResolved(Working item) {
        Import_Row__c row = item.row;
        Boolean personAccountRow =
            item.person1Id != null &&
            item.person1Id.getSObjectType() == Account.SObjectType;
        if (personAccountRow) {
            row.Person_1_Account__c = item.person1Id;
            row.Person_2_Account__c = item.person2Id;
        } else {
            row.Contact_1__c = item.person1Id;
            row.Contact_2__c = item.person2Id;
        }
        row.Organization__c = item.organizationId;
    }

    // -------------------------------------------------------------------------------------
    // Shared helpers
    // -------------------------------------------------------------------------------------

    /**
     * Says in the run log, once per field and in the dry run as in the commit, which mapped
     * fields the importing user may not write. `applyValues` skips such a field's values, and
     * skipping them quietly is how a migration file's Email Opt Out and Do Not Call columns
     * could read as loaded and not be, so an opted-out person was then emailed or called. The
     * note names the field by the label the administrator knows it by.
     */
    private static void noteFieldsWithoutAccess(
        ImportMapping mapping,
        Boolean personAccounts,
        Outcome outcome
    ) {
        Set<String> targets = new Set<String>(mapping.targetsBySourceKey().values());
        for (ImportMapping.Assignment assignment : mapping.defaults) {
            if (assignment != null && !ImportMapping.isIgnored(assignment.target)) {
                targets.add(assignment.target.trim());
            }
        }
        Schema.SObjectType personType = personAccounts ? Account.SObjectType : Contact.SObjectType;
        for (String target : targets) {
            String entity = ImportMapping.entityOf(target);
            Schema.SObjectType type;
            if (ImportMapping.ENTITY_ORGANIZATION.equals(entity)) {
                type = Account.SObjectType;
            } else if (
                ImportMapping.ENTITY_CONTACT_1.equals(entity) ||
                ImportMapping.ENTITY_CONTACT_2.equals(entity)
            ) {
                type = personType;
            } else {
                // A household takes only its name from a row, and the rest of a row is the
                // entity processor's to report (R-IR6).
                continue;
            }
            String attribute = ImportMapping.attributeOf(target);
            if ('Id'.equalsIgnoreCase(attribute)) {
                // A record ID matches and is never written (R-IT10).
                continue;
            }
            // Only a person's attributes are contact names to translate; an organization's
            // are the account's own, whatever the person mode.
            if (!ImportMapping.ENTITY_ORGANIZATION.equals(entity)) {
                attribute = storedName(attribute, personAccounts);
            }
            Schema.SObjectField field = fieldsOf(type).get(attribute.toLowerCase());
            if (field == null) {
                // An attribute the object does not have is reported by applyValues.
                continue;
            }
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (!describe.isCreateable() && !describe.isUpdateable()) {
                outcome.notes.add(noAccessNote(describe));
            }
        }
    }

    /**
     * Copies the mapped attributes onto a record, skipping any the object does not have or
     * the user may not write. Both are reported once in the run log rather than failing the
     * row: a template written for another org should not stop this one, and a field the user
     * cannot write is named by `noteFieldsWithoutAccess`.
     */
    private static void applyValues(
        SObject record,
        Schema.SObjectType type,
        Map<String, String> held,
        Set<String> alreadySet,
        Outcome outcome
    ) {
        if (held == null || held.isEmpty()) {
            return;
        }
        Map<String, Schema.SObjectField> fields = fieldsOf(type);
        for (String attributeName : held.keySet()) {
            if (alreadySet.contains(attributeName)) {
                continue;
            }
            String value = held.get(attributeName);
            if (String.isBlank(value)) {
                continue;
            }
            Schema.SObjectField field = fields.get(attributeName.toLowerCase());
            if (field == null) {
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogAttributeUnknown,
                        new List<String>{ attributeName }
                    )
                );
                continue;
            }
            Schema.DescribeFieldResult describe = field.getDescribe();
            // A new record needs the field creatable and a saved one needs it updatable: a
            // field the user may set on a new person but not change on a matched one is
            // skipped on the update, and said so, as much as one they may not touch at all.
            if (record.Id == null ? !describe.isCreateable() : !describe.isUpdateable()) {
                outcome.notes.add(noAccessNote(describe));
                continue;
            }
            try {
                record.put(describe.getSObjectField(), convert(value, describe));
            } catch (Exception ignored) {
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogValueNotAccepted,
                        new List<String>{ attributeName, value }
                    )
                );
            }
        }
    }

    /** The run log line for a field the importing user may not write. */
    private static String noAccessNote(Schema.DescribeFieldResult describe) {
        return String.format(
            Label.Core_Import_LogAttributeNoAccess,
            new List<String>{ describe.getLabel() }
        );
    }

    /** Each object's fields, described once per transaction however many rows ask. */
    private static Map<Schema.SObjectType, Map<String, Schema.SObjectField>> fieldMaps = new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();

    private static Map<String, Schema.SObjectField> fieldsOf(Schema.SObjectType type) {
        if (!fieldMaps.containsKey(type)) {
            fieldMaps.put(type, type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap());
        }
        return fieldMaps.get(type);
    }

    /** Whether a stored record's field is a checkbox. */
    private static Boolean isCheckbox(SObject stored, String lowerCaseName) {
        Schema.SObjectField field = fieldsOf(stored.getSObjectType()).get(lowerCaseName);
        return field != null && field.getDescribe().getType() == Schema.DisplayType.BOOLEAN;
    }

    /** A checkbox column's value as the save writes it; the one reading for both. */
    private static Boolean convertCheckbox(String value) {
        return 'true'.equalsIgnoreCase(value) || 'yes'.equalsIgnoreCase(value) || '1'.equals(value);
    }

    /** A column value as the field's type, for the few types a spreadsheet carries. */
    private static Object convert(String value, Schema.DescribeFieldResult describe) {
        Schema.DisplayType kind = describe.getType();
        if (kind == Schema.DisplayType.BOOLEAN) {
            return convertCheckbox(value);
        }
        if (
            kind == Schema.DisplayType.CURRENCY ||
            kind == Schema.DisplayType.DOUBLE ||
            kind == Schema.DisplayType.PERCENT
        ) {
            return Decimal.valueOf(value.replaceAll('[^0-9\\.\\-]', ''));
        }
        if (kind == Schema.DisplayType.INTEGER) {
            return Integer.valueOf(value.replaceAll('[^0-9\\-]', ''));
        }
        if (kind == Schema.DisplayType.DATE) {
            return Date.valueOf(value);
        }
        if (kind == Schema.DisplayType.DATETIME) {
            return Datetime.valueOf(value);
        }
        Integer length = describe.getLength();
        return length > 0 ? value.abbreviate(Math.max(length, 4)) : value;
    }

    /**
     * Each record saved or refused on its own, and saved past a duplicate rule that only
     * alerts, as an administrator's bulk load would be (R-IB12). An import is people the
     * organization already decided to add, and an alert stopping them would fail every row
     * that resembles someone; the pair is left for the duplicate scan to find (R-DP3). A rule
     * the org set to block still blocks, and the row reports the rule's message.
     */
    @NamespaceAccessible
    public static Database.DMLOptions saveOptions() {
        Database.DMLOptions options = new Database.DMLOptions();
        options.OptAllOrNone = false;
        options.DuplicateRuleHeader.AllowSave = true;
        return options;
    }

    /** The failure of a save, in the words the platform used, so nothing is lost in paraphrase. */
    @NamespaceAccessible
    public static String message(Database.SaveResult result) {
        List<String> parts = new List<String>();
        for (Database.Error error : result.getErrors()) {
            parts.add(error.getMessage());
        }
        return parts.isEmpty() ? Label.Core_Import_ErrorSaveFailed : String.join(parts, ' ');
    }

    private static Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        return info == null || !info.isAvailable() ? null : info.getRecordTypeId();
    }

    private static Set<Id> personRecordTypeIds() {
        return OrgShapeDetector.detect().personAccountRecordTypeIds;
    }

    private static Id anyPersonRecordTypeId() {
        for (Id recordTypeId : personRecordTypeIds()) {
            return recordTypeId;
        }
        return null;
    }
}
