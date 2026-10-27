/**
 * Import from DLRS (canonical model R-R16, plan D-124 item 6): each active DLRS rollup read by
 * `RollupDlrs`, mapped to a BarnCRM rollup, copied switched off, compared on sample records and
 * then turned on with the administrator's word that she will switch the DLRS one off.
 *
 * Nothing here edits, switches off or deletes anything in DLRS. A copy is saved through the
 * Builder's own checks (`RollupBuilderController.checkedRecord`, as the file import of ADR-0136
 * does), with the Definition Key `DLRS_` and the DLRS rollup's name, so importing again updates
 * the copy rather than adding a second. What BarnCRM cannot express stays in DLRS, and the
 * candidate says why in words; what changes in the copy is said as a note.
 */
public with sharing class RollupDlrsImport {
    /** What a copy's Definition Key starts with, before the DLRS rollup's name. */
    public static final String KEY_PREFIX = 'DLRS_';
    public static final String CREATED = 'created';
    public static final String UPDATED = 'updated';
    public static final String REFUSED = 'refused';
    public static final String NOT_REACHED = 'notReached';
    public static final String ACTIVE = 'active';

    /** How many target records the compare step shows. */
    @TestVisible
    private static final Integer SAMPLE_SIZE = 5;
    private static final Integer QUERIES_PER_ROLLUP = 15;
    private static final Integer DML_PER_ROLLUP = 5;
    private static final Integer CUSTOM_DELIMITER_LENGTH = 10;

    /** DLRS's operations (its custom metadata holds them as text), by BarnCRM aggregate. */
    private static final Map<String, String> AGGREGATE_BY_OPERATION = new Map<String, String>{
        'sum' => 'SUM',
        'max' => 'MAX',
        'min' => 'MIN',
        'avg' => 'AVG',
        'count' => 'COUNT',
        'count distinct' => 'COUNT_DISTINCT',
        'concatenate' => 'TEXT_LIST',
        'concatenate distinct' => 'TEXT_LIST_DISTINCT',
        'first' => 'FIRST',
        'last' => 'LAST'
    };
    private static final Map<String, String> DELIMITER_BY_TEXT = new Map<String, String>{
        ', ' => 'Comma',
        '; ' => 'Semicolon',
        ' | ' => 'Pipe',
        'BR()' => 'New line'
    };
    private static final Set<String> LISTS = new Set<String>{ 'TEXT_LIST', 'TEXT_LIST_DISTINCT' };
    private static final Set<String> ORDERED = new Set<String>{ 'FIRST', 'LAST' };

    /** One active DLRS rollup, and the BarnCRM rollup it becomes or why it cannot. */
    public class Candidate {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String parentObject { get; set; }
        @AuraEnabled
        public String targetField { get; set; }
        @AuraEnabled
        public String childObject { get; set; }
        @AuraEnabled
        public String operation { get; set; }
        /** True when it can be copied; otherwise it stays in DLRS for the reasons given. */
        @AuraEnabled
        public Boolean importable { get; set; }
        @AuraEnabled
        public List<String> reasons { get; set; }
        /** What the copy does differently, in words. */
        @AuraEnabled
        public List<String> notes { get; set; }
        /** The copy as the Builder edits it, switched off. */
        @AuraEnabled
        public RollupBuilderController.Draft draft { get; set; }
        /** An earlier copy, matched by Definition Key. */
        @AuraEnabled
        public Id existingId { get; set; }
    }

    /** What happened to one rollup. */
    public class ImportRow {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public String name { get; set; }
        /** created, updated, refused, notReached or active. */
        @AuraEnabled
        public String outcome { get; set; }
        @AuraEnabled
        public String reason { get; set; }
        @AuraEnabled
        public Id recordId { get; set; }
    }

    /** One sample record: the value DLRS wrote beside the value BarnCRM calculates. */
    public class Comparison {
        @AuraEnabled
        public Id recordId { get; set; }
        @AuraEnabled
        public String recordName { get; set; }
        @AuraEnabled
        public String dlrsValue { get; set; }
        @AuraEnabled
        public String barncrmValue { get; set; }
        @AuraEnabled
        public Boolean agree { get; set; }
        /** Why the two differ, or null when they agree. */
        @AuraEnabled
        public String difference { get; set; }
    }

    // ---------------------------------------------------------------------------- the steps

    /** Steps 1 and 2: every active DLRS rollup, with its copy or why it stays in DLRS. */
    @AuraEnabled
    public static List<Candidate> getCandidates() {
        try {
            requirePermission();
            return candidates(null);
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Step 3: copies the chosen DLRS rollups, switched off. Each goes through the Builder's
     * checks on its own, so one that fails stops nothing else.
     *
     * @param keys the chosen DLRS rollups' keys
     */
    @AuraEnabled
    public static List<ImportRow> importRollups(List<String> keys) {
        try {
            requirePermission();
            Set<String> wanted = new Set<String>();
            for (String key : keys == null ? new List<String>() : keys) {
                if (String.isNotBlank(key)) {
                    wanted.add(key.toLowerCase());
                }
            }
            List<ImportRow> rows = new List<ImportRow>();
            for (Candidate candidate : candidates(wanted)) {
                rows.add(copy(candidate));
            }
            return rows;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Step 4: a few records of the copy's target, the value on each now (which DLRS wrote) beside
     * the value the copy calculates. Writes nothing.
     */
    @AuraEnabled
    public static List<Comparison> compare(Id definitionId) {
        try {
            requirePermission();
            Rollup_Definition__c definition = require(definitionId);
            List<Comparison> comparisons = new List<Comparison>();
            for (SObject record : sample(definition)) {
                comparisons.add(comparison(definition, record));
            }
            return comparisons;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Step 5: turns a copy on, once the administrator confirmed she will switch the DLRS rollup
     * off; the Builder's checks run again and the answer is recorded (R-R16). DLRS is untouched.
     */
    @AuraEnabled
    public static ImportRow turnOn(Id definitionId, Boolean dlrsOffConfirmed) {
        try {
            requirePermission();
            if (dlrsOffConfirmed != true) {
                throw refusal(Label.Core_RollupBuilder_DlrsActivateNeedsConfirm);
            }
            Rollup_Definition__c definition = require(definitionId);
            RollupBuilderController.Draft draft = RollupBuilderController.toDraft(definition);
            draft.active = true;
            Rollup_Definition__c record = RollupBuilderController.checkedRecord(draft, true);
            RollupWriter.saveAsUser(record);
            RollupDlrs.recordSwitchOff(
                definition.Name,
                definition.Target_Object__c,
                definition.Target_Field__c
            );
            ImportRow row = new ImportRow();
            row.key = definition.Definition_Key__c;
            row.name = definition.Name;
            row.recordId = definition.Id;
            row.outcome = ACTIVE;
            return row;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    // ------------------------------------------------------------------------------ mapping

    /** The active DLRS rollups, all or those keyed in `keys` (lower case), as candidates. */
    @TestVisible
    private static List<Candidate> candidates(Set<String> keys) {
        List<Rollup_Definition__c> existing = RollupSelector.selectAllAsUser();
        Map<String, Rollup_Definition__c> byKey = new Map<String, Rollup_Definition__c>();
        for (Rollup_Definition__c definition : existing) {
            if (definition.Definition_Key__c != null) {
                byKey.put(definition.Definition_Key__c.toLowerCase(), definition);
            }
        }
        Map<String, List<RollupBuilderController.SourceOption>> sourcesByParent = new Map<String, List<RollupBuilderController.SourceOption>>();
        List<Candidate> found = new List<Candidate>();
        for (RollupDlrs.Definition dlrs : RollupDlrs.definitions()) {
            if (dlrs.active == true && (keys == null || keys.contains(dlrs.key.toLowerCase()))) {
                Candidate candidate = toCandidate(dlrs);
                checkAgainstOrg(candidate, dlrs, byKey, existing, sourcesByParent);
                found.add(candidate);
            }
        }
        return found;
    }

    /** The copy a DLRS rollup becomes, from its own values alone. */
    @TestVisible
    private static Candidate toCandidate(RollupDlrs.Definition dlrs) {
        Candidate candidate = new Candidate();
        candidate.key = dlrs.key;
        candidate.label = dlrs.label;
        candidate.parentObject = dlrs.parentObject;
        candidate.targetField = dlrs.aggregateResultField;
        candidate.childObject = dlrs.childObject;
        candidate.operation = dlrs.aggregateOperation;
        candidate.reasons = new List<String>();
        candidate.notes = new List<String>();

        RollupBuilderController.Draft draft = new RollupBuilderController.Draft();
        candidate.draft = draft;
        draft.name = dlrs.label.left(80);
        String imported = String.format(
            Label.Core_RollupBuilder_DlrsImportedFrom,
            new List<String>{ dlrs.key }
        );
        draft.description = (String.isBlank(dlrs.description)
                ? imported
                : imported + ' ' + dlrs.description)
            .left(1000);
        draft.targetObject = dlrs.parentObject;
        draft.targetField = dlrs.aggregateResultField;
        draft.sourceObject = dlrs.childObject;
        draft.relationshipPath = dlrs.relationshipField;
        draft.includeDeleted = dlrs.allRows == true;
        draft.bypassPermission = dlrs.bypassPermission;
        draft.active = false;
        mapMode(dlrs, candidate);
        if ('user'.equalsIgnoreCase(dlrs.calculationSharingMode)) {
            candidate.notes.add(Label.Core_RollupBuilder_DlrsNoteSystemMode);
        }

        String aggregate = AGGREGATE_BY_OPERATION.get(normalized(dlrs.aggregateOperation));
        if (aggregate == null) {
            reason(
                candidate,
                Label.Core_RollupBuilder_DlrsReasonOperation,
                dlrs.aggregateOperation
            );
            return candidate;
        }
        draft.aggregate = aggregate;
        List<Map<String, Object>> required = new List<Map<String, Object>>();
        Boolean countsAField =
            aggregate == 'COUNT' &&
            String.isNotBlank(dlrs.fieldToAggregate) &&
            !'Id'.equalsIgnoreCase(dlrs.fieldToAggregate);
        if (countsAField) {
            // DLRS counts the records with the field filled; BarnCRM counts records, so filter.
            required.add(
                new Map<String, Object>{
                    'field' => dlrs.fieldToAggregate,
                    'operator' => 'is not null'
                }
            );
            note(candidate, Label.Core_RollupBuilder_DlrsNoteCountField, dlrs.fieldToAggregate);
        } else if (aggregate != 'COUNT') {
            draft.sourceField = dlrs.fieldToAggregate;
        }
        mapOrder(dlrs, aggregate, candidate);
        mapRowLimit(dlrs, aggregate, candidate);
        if (LISTS.contains(aggregate)) {
            mapDelimiter(dlrs, candidate);
        }
        try {
            draft.filterJson = RollupDlrsCriteria.toFilter(dlrs.relationshipCriteria, required);
        } catch (RollupDlrsCriteria.CriteriaException unreadable) {
            reason(candidate, Label.Core_RollupBuilder_DlrsReasonCriteria, unreadable.getMessage());
        }
        return candidate;
    }

    /** Realtime and the modes run by code become Both; Scheduled stays nightly. */
    private static void mapMode(RollupDlrs.Definition dlrs, Candidate candidate) {
        String mode = normalized(dlrs.calculationMode);
        candidate.draft.mode = mode == 'scheduled'
            ? RollupService.MODE_SCHEDULED
            : RollupService.MODE_BOTH;
        if (mode == 'developer' || mode == 'process builder') {
            note(candidate, Label.Core_RollupBuilder_DlrsNoteCalledByCode, dlrs.calculationMode);
        }
        if (
            candidate.draft.mode == RollupService.MODE_BOTH &&
            String.isNotBlank(dlrs.childObject) &&
            !RollupService.hasInstantUpdates(dlrs.childObject)
        ) {
            note(candidate, Label.Core_RollupBuilder_DlrsNoteNightly, dlrs.childObject);
        }
    }

    /**
     * DLRS's Field to Order By: one field, optionally ASC or DESC and NULLS LAST. A descending
     * First is BarnCRM's Last and the other way round; a text list or row limit keeps the
     * direction. BarnCRM always puts blanks last, so NULLS FIRST stays in DLRS.
     */
    private static void mapOrder(
        RollupDlrs.Definition dlrs,
        String aggregate,
        Candidate candidate
    ) {
        RollupBuilderController.Draft draft = candidate.draft;
        Boolean limited = dlrs.rowLimit != null && dlrs.rowLimit > 0;
        if (String.isBlank(dlrs.fieldToOrderBy)) {
            if (ORDERED.contains(aggregate)) {
                draft.orderByField = dlrs.fieldToAggregate;
                note(candidate, Label.Core_RollupBuilder_DlrsNoteNoOrder, dlrs.fieldToAggregate);
            }
            return;
        }
        if (!ORDERED.contains(aggregate) && !LISTS.contains(aggregate) && !limited) {
            return;
        }
        List<String> words = dlrs.fieldToOrderBy.trim().split('\\s+');
        Boolean descending = false;
        Boolean blanksFirst = null;
        Boolean readable = !dlrs.fieldToOrderBy.contains(',') && words.size() <= 4;
        for (Integer index = 1; readable && index < words.size(); index++) {
            String word = words[index].toUpperCase();
            if (word == 'ASC' || word == 'DESC') {
                descending = word == 'DESC';
            } else if (word == 'NULLS' && index + 1 < words.size()) {
                index++;
                blanksFirst = words[index].equalsIgnoreCase('FIRST');
                readable = blanksFirst || words[index].equalsIgnoreCase('LAST');
            } else {
                readable = false;
            }
        }
        if (!readable || blanksFirst == true) {
            reason(candidate, Label.Core_RollupBuilder_DlrsReasonOrder, dlrs.fieldToOrderBy);
            return;
        }
        draft.orderByField = words[0];
        if (ORDERED.contains(aggregate)) {
            if (descending) {
                draft.aggregate = aggregate == 'FIRST' ? 'LAST' : 'FIRST';
            }
        } else {
            draft.orderDirection = descending ? 'Descending' : 'Ascending';
        }
        // SOQL sorts blanks first when ascending unless told otherwise.
        if (blanksFirst == null && !descending) {
            candidate.notes.add(Label.Core_RollupBuilder_DlrsNoteBlanksLast);
        }
    }

    /** A row limit on a sum, average, minimum, maximum or text list; dropped from First. */
    private static void mapRowLimit(
        RollupDlrs.Definition dlrs,
        String aggregate,
        Candidate candidate
    ) {
        if (dlrs.rowLimit == null || dlrs.rowLimit <= 0) {
            return;
        }
        if (aggregate == 'FIRST') {
            candidate.notes.add(Label.Core_RollupBuilder_DlrsNoteRowLimitFirst);
        } else if (RollupPlanner.ROW_LIMITED.contains(aggregate)) {
            candidate.draft.rowLimit = dlrs.rowLimit;
        } else {
            reason(candidate, Label.Core_RollupBuilder_DlrsReasonRowLimit, dlrs.aggregateOperation);
        }
    }

    /** DLRS's delimiter text as one of BarnCRM's, or Custom up to ten characters on one line. */
    private static void mapDelimiter(RollupDlrs.Definition dlrs, Candidate candidate) {
        String raw = dlrs.concatenateDelimiter;
        RollupBuilderController.Draft draft = candidate.draft;
        if (String.isEmpty(raw)) {
            draft.delimiter = 'Comma';
            candidate.notes.add(Label.Core_RollupBuilder_DlrsNoteNoDelimiter);
        } else if (DELIMITER_BY_TEXT.containsKey(raw)) {
            draft.delimiter = DELIMITER_BY_TEXT.get(raw);
        } else {
            String text = raw.replace('BR()', '\n').replace('SP()', ' ').replace('TB()', '\t');
            if (text.contains('\n') || text.length() > CUSTOM_DELIMITER_LENGTH) {
                reason(candidate, Label.Core_RollupBuilder_DlrsReasonDelimiter, raw);
            } else {
                draft.delimiter = RollupPlanner.CUSTOM_DELIMITER;
                draft.customDelimiter = text;
            }
        }
    }

    /**
     * What only this org can say: whether the Builder offers the records and lookup, an earlier
     * copy, another BarnCRM rollup already filling the field, and the Builder's own checks.
     */
    private static void checkAgainstOrg(
        Candidate candidate,
        RollupDlrs.Definition dlrs,
        Map<String, Rollup_Definition__c> byKey,
        List<Rollup_Definition__c> existing,
        Map<String, List<RollupBuilderController.SourceOption>> sourcesByParent
    ) {
        RollupBuilderController.SourceOption source = offered(dlrs, sourcesByParent);
        if (source != null) {
            // The Builder's own spelling of the records and lookup.
            candidate.draft.sourceObject = source.sourceObject;
            candidate.draft.relationshipPath = source.relationshipPath;
        } else {
            candidate.reasons.add(
                String.format(
                    Label.Core_RollupBuilder_DlrsReasonPath,
                    new List<String>{
                        String.valueOf(dlrs.childObject),
                        String.valueOf(dlrs.relationshipField),
                        String.valueOf(dlrs.parentObject)
                    }
                )
            );
        }
        Rollup_Definition__c earlier = byKey.get(definitionKey(dlrs.key).toLowerCase());
        if (earlier != null) {
            candidate.existingId = earlier.Id;
            candidate.draft.recordId = earlier.Id;
            if (earlier.Active__c == true) {
                candidate.reasons.add(Label.Core_RollupBuilder_DlrsReasonAlreadyOn);
            }
        }
        for (Rollup_Definition__c other : existing) {
            if (
                other.Active__c == true &&
                other.Id != candidate.existingId &&
                other.Target_Object__c != null &&
                other.Target_Object__c.equalsIgnoreCase(dlrs.parentObject) &&
                other.Target_Field__c != null &&
                other.Target_Field__c.equalsIgnoreCase(dlrs.aggregateResultField)
            ) {
                reason(candidate, Label.Core_RollupBuilder_DlrsReasonFilled, other.Name);
            }
        }
        if (candidate.reasons.isEmpty()) {
            try {
                RollupBuilderController.checkedRecord(candidate.draft);
            } catch (RollupService.RollupServiceException refused) {
                candidate.reasons.add(refused.getMessage());
            }
        }
        candidate.importable = candidate.reasons.isEmpty();
    }

    /** The Builder's choice of these records by this lookup for this target, or null. */
    private static RollupBuilderController.SourceOption offered(
        RollupDlrs.Definition dlrs,
        Map<String, List<RollupBuilderController.SourceOption>> sourcesByParent
    ) {
        if (
            String.isBlank(dlrs.parentObject) ||
            String.isBlank(dlrs.childObject) ||
            String.isBlank(dlrs.relationshipField)
        ) {
            return null;
        }
        String parent = dlrs.parentObject.toLowerCase();
        if (!sourcesByParent.containsKey(parent)) {
            List<RollupBuilderController.SourceOption> sources;
            try {
                sources = RollupBuilderController.getSources(dlrs.parentObject);
            } catch (AuraHandledException unknownObject) {
                sources = new List<RollupBuilderController.SourceOption>();
            }
            sourcesByParent.put(parent, sources);
        }
        for (RollupBuilderController.SourceOption source : sourcesByParent.get(parent)) {
            if (
                source.sourceObject.equalsIgnoreCase(dlrs.childObject) &&
                source.relationshipPath.equalsIgnoreCase(dlrs.relationshipField)
            ) {
                return source;
            }
        }
        return null;
    }

    // ------------------------------------------------------------------------------- copying

    private static ImportRow copy(Candidate candidate) {
        ImportRow row = new ImportRow();
        row.key = candidate.key;
        row.name = candidate.draft.name;
        if (candidate.importable != true) {
            row.outcome = REFUSED;
            row.reason = String.join(candidate.reasons, ' ');
            return row;
        }
        if (
            Limits.getQueries() + QUERIES_PER_ROLLUP > Limits.getLimitQueries() ||
            Limits.getDmlStatements() + DML_PER_ROLLUP > Limits.getLimitDmlStatements()
        ) {
            row.outcome = NOT_REACHED;
            return row;
        }
        try {
            Rollup_Definition__c record = RollupBuilderController.checkedRecord(candidate.draft);
            if (candidate.existingId == null) {
                record.Definition_Key__c = definitionKey(candidate.key);
            }
            RollupWriter.saveAsUser(record);
            row.recordId = record.Id;
            row.outcome = candidate.existingId == null ? CREATED : UPDATED;
        } catch (RollupService.RollupServiceException checkFailed) {
            row.outcome = REFUSED;
            row.reason = checkFailed.getMessage();
        } catch (DmlException saveFailed) {
            row.outcome = REFUSED;
            row.reason = saveFailed.getDmlMessage(0);
        }
        return row;
    }

    @TestVisible
    private static String definitionKey(String dlrsKey) {
        return (KEY_PREFIX + dlrsKey).left(80);
    }

    // ----------------------------------------------------------------------------- comparing

    /**
     * Up to five records of the target, those with a value first (DLRS wrote one), most
     * recently changed first, in the running user's access.
     */
    private static List<SObject> sample(Rollup_Definition__c definition) {
        Schema.SObjectType targetType = SettingsService.typeByName(definition.Target_Object__c);
        if (targetType == null || String.isBlank(definition.Target_Field__c)) {
            throw refusal(Label.Core_Rollups_ErrorUnknownObject);
        }
        Map<String, Schema.SObjectField> fields = targetType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .fields.getMap();
        Schema.SObjectField target = fields.get(definition.Target_Field__c.toLowerCase());
        if (target == null) {
            throw refusal(Label.Core_Rollups_ErrorTargetNotWritable);
        }
        String nameField = nameFieldOf(fields);
        String query =
            'SELECT Id' +
            (nameField == null ? '' : ', ' + nameField) +
            ' FROM ' +
            String.valueOf(targetType);
        String recent = fields.containsKey('lastmodifieddate')
            ? ' ORDER BY LastModifiedDate DESC'
            : '';
        List<SObject> records = new List<SObject>();
        if (target.getDescribe().isFilterable()) {
            records.addAll(
                Database.query(
                    query +
                        ' WHERE ' +
                        String.valueOf(target) +
                        ' != null' +
                        recent +
                        ' LIMIT ' +
                        SAMPLE_SIZE,
                    AccessLevel.USER_MODE
                )
            );
        }
        if (records.size() < SAMPLE_SIZE) {
            Set<Id> seen = new Map<Id, SObject>(records).keySet();
            records.addAll(
                Database.queryWithBinds(
                    query +
                        ' WHERE Id NOT IN :seen' +
                        recent +
                        ' LIMIT ' +
                        (SAMPLE_SIZE - records.size()),
                    new Map<String, Object>{ 'seen' => seen },
                    AccessLevel.USER_MODE
                )
            );
        }
        return records;
    }

    private static String nameFieldOf(Map<String, Schema.SObjectField> fields) {
        for (Schema.SObjectField field : fields.values()) {
            Schema.DescribeFieldResult described = field.getDescribe();
            if (described.isNameField() && described.isAccessible()) {
                return described.getName();
            }
        }
        return null;
    }

    private static Comparison comparison(Rollup_Definition__c definition, SObject record) {
        Comparison compared = new Comparison();
        compared.recordId = record.Id;
        Map<String, Object> populated = record.getPopulatedFieldsAsMap();
        compared.recordName = String.valueOf(record.Id);
        for (String field : populated.keySet()) {
            if (field != 'Id' && populated.get(field) != null) {
                compared.recordName = String.valueOf(populated.get(field));
            }
        }
        RollupEngine.Preview preview = RollupEngine.preview(definition, record.Id);
        compared.dlrsValue = RollupBuilderController.display(preview.current);
        compared.barncrmValue = RollupBuilderController.display(preview.calculated);
        compared.difference = differenceOf(preview);
        compared.agree = compared.difference == null;
        return compared;
    }

    /** Why the two values differ, in words, or null when they agree. */
    @TestVisible
    private static String differenceOf(RollupEngine.Preview preview) {
        if (preview.planned != true) {
            return Label.Core_RollupBuilder_DlrsCompareNotCalculated;
        }
        Object mine = blankAsNull(preview.calculated);
        Object theirs = blankAsNull(preview.current);
        if (mine == theirs || (mine != null && theirs != null && same(mine, theirs))) {
            return null;
        }
        if ((isZero(mine) && theirs == null) || (isZero(theirs) && mine == null)) {
            return Label.Core_RollupBuilder_DlrsCompareBlankZero;
        }
        return Label.Core_RollupBuilder_DlrsCompareDiffer;
    }

    private static Object blankAsNull(Object value) {
        return value instanceof String && String.isBlank((String) value) ? null : value;
    }

    /** Numbers by value (2 and 2.0 agree); anything else by its text. */
    private static Boolean same(Object mine, Object theirs) {
        Decimal myNumber = asNumber(mine);
        Decimal theirNumber = asNumber(theirs);
        if (myNumber != null && theirNumber != null) {
            return myNumber == theirNumber;
        }
        return String.valueOf(mine) == String.valueOf(theirs);
    }

    private static Boolean isZero(Object value) {
        Decimal amount = asNumber(value);
        return amount != null && amount == 0;
    }

    private static Decimal asNumber(Object value) {
        if (
            value instanceof Decimal ||
            value instanceof Integer ||
            value instanceof Long ||
            value instanceof Double
        ) {
            return Decimal.valueOf(String.valueOf(value));
        }
        return null;
    }

    // ------------------------------------------------------------------------------- helpers

    private static String normalized(String text) {
        return text == null ? '' : text.trim().toLowerCase().replaceAll('\\s+', ' ');
    }

    private static void reason(Candidate candidate, String template, String value) {
        candidate.reasons.add(
            String.format(template, new List<String>{ value == null ? '' : value })
        );
    }

    private static void note(Candidate candidate, String template, String value) {
        candidate.notes.add(
            String.format(template, new List<String>{ value == null ? '' : value })
        );
    }

    private static Rollup_Definition__c require(Id definitionId) {
        Rollup_Definition__c definition = RollupSelector.selectById(definitionId);
        if (definition == null) {
            throw refusal(Label.Core_Rollups_ErrorUnknownDefinition);
        }
        return definition;
    }

    private static RollupService.RollupServiceException refusal(String message) {
        return new RollupService.RollupServiceException(message);
    }

    private static void requirePermission() {
        if (!BarnCRMPermissions.canManageSettings()) {
            throw refusal(Label.Core_Rollups_ErrorNoPermission);
        }
    }

    /** A message the page can show; anything it cannot explain is logged. */
    private static AuraHandledException asUserError(Exception caught) {
        String message = caught.getMessage();
        if (!(caught instanceof RollupService.RollupServiceException)) {
            ErrorLogger.log(caught, 'RollupDlrsImport');
            message = Label.Core_Rollups_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
