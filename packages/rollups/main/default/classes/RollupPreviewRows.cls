/**
 * The Builder's live preview with sample records (Rollup Builder ease of use U4, ADR-0136). Step
 * 5 already calculates an unsaved rollup on one record the administrator picks (slice S12). This
 * class adds two things:
 *
 * - **Samples**: up to `MAX_SAMPLES` records the rollup would fill, chosen for her: records that
 *   recent source records point at and that meet the target's conditions, then the most recently
 *   changed records that meet them.
 * - **Rows**: for one record, up to `MAX_SHOWN` of the source records read for it, each said to be
 *   counted or left out, and why: the numbers of the conditions it does not meet, the year
 *   window, a blank ordering field, or the row limit.
 *
 * Both read in user mode, as the administrator. A path through a household reads the household's
 * members and their records (R-R1), so its rows are not listed and a note says so. Every query
 * is built from the plan `RollupPlanner` makes for the engine, so the preview reads what a
 * recalculation reads.
 */
public with sharing class RollupPreviewRows {
    @TestVisible
    private static final Integer MAX_SAMPLES = 5;
    @TestVisible
    private static final Integer MAX_SHOWN = 10;
    /** Source records read to find samples, newest first. */
    private static final Integer MAX_CANDIDATES = 200;
    /** Conditions tested one by one to say why a row is left out. */
    private static final Integer MAX_CONDITIONS = 10;

    /** One record the rollup would fill, with what it would write there. */
    public class Sample {
        @AuraEnabled
        public String recordId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String result { get; set; }
    }

    /** One source record read for the previewed record. */
    public class Row {
        @AuraEnabled
        public String recordId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public Boolean counted { get; set; }
        @AuraEnabled
        public String reason { get; set; }
    }

    /** The source records read for one record, as many as are shown, and how many there are. */
    public class Detail {
        @AuraEnabled
        public List<Row> rows { get; set; }
        @AuraEnabled
        public Integer total { get; set; }
        /** How many of them count, within the row limit (U5). */
        @AuraEnabled
        public Integer counted { get; set; }
        @AuraEnabled
        public String summary { get; set; }
        @AuraEnabled
        public String note { get; set; }
    }

    /**
     * Up to `MAX_SAMPLES` records of the target entity the rollup would fill, with their names. The
     * caller calculates each.
     *
     * @param definition the rollup, which need not be saved; its checks have passed
     */
    public static List<Sample> samplesOf(Rollup_Definition__c definition) {
        Schema.SObjectType targetType = SettingsService.typeByName(definition.Target_Object__c);
        RollupPlanner.Plan plan = RollupPlanner.plan(
            targetType,
            new List<Rollup_Definition__c>{ definition }
        );
        String targetFilter = plan.targetFilters.isEmpty() ? '' : plan.targetFilters[0];
        String admitted = String.isBlank(targetFilter) ? '' : ' AND (' + targetFilter + ')';
        Set<Id> candidates = new Set<Id>();
        for (RollupPlanner.SourceQuery query : plan.queries) {
            if (query.token == null) {
                candidates.addAll(recentKeys(query));
            }
        }
        String nameField = nameFieldOf(targetType);
        Map<String, Object> binds = new Map<String, Object>{
            'candidates' => candidates,
            'wanted' => MAX_SAMPLES
        };
        List<SObject> picked = new List<SObject>();
        if (!candidates.isEmpty()) {
            // The entity comes from describe and the clause from RollupFilterParser, which checks
            // every name and escapes every value.
            picked.addAll(
                Database.queryWithBinds(
                    'SELECT ' +
                        columns(nameField) +
                        ' FROM ' +
                        String.valueOf(targetType) +
                        ' WHERE Id IN :candidates' +
                        admitted +
                        ' LIMIT :wanted',
                    binds,
                    AccessLevel.USER_MODE
                )
            );
        }
        if (picked.size() < MAX_SAMPLES) {
            binds.put('chosen', new Map<Id, SObject>(picked).keySet());
            binds.put('rest', MAX_SAMPLES - picked.size());
            picked.addAll(
                Database.queryWithBinds(
                    'SELECT ' +
                        columns(nameField) +
                        ' FROM ' +
                        String.valueOf(targetType) +
                        ' WHERE Id NOT IN :chosen' +
                        admitted +
                        ' ORDER BY LastModifiedDate DESC LIMIT :rest',
                    binds,
                    AccessLevel.USER_MODE
                )
            );
        }
        List<Sample> samples = new List<Sample>();
        for (SObject record : picked) {
            Sample sample = new Sample();
            sample.recordId = record.Id;
            sample.name = nameOf(record, nameField);
            samples.add(sample);
        }
        return samples;
    }

    /** The records recent source records point at through one alternative of the path. */
    private static Set<Id> recentKeys(RollupPlanner.SourceQuery query) {
        List<String> conditions = new List<String>{ query.keyExpression + ' != null' };
        for (String earlier : query.earlierKeys) {
            conditions.add(earlier + ' = null');
        }
        if (String.isNotBlank(query.whereClause)) {
            conditions.add('(' + query.whereClause + ')');
        }
        Set<Id> keys = new Set<Id>();
        // The entity and the key come from the plan, which reads them from describe and the
        // checked path; the clause from RollupFilterParser.
        for (
            SObject row : Database.queryWithBinds(
                'SELECT ' +
                    query.keyExpression +
                    ' FROM ' +
                    query.sourceObject +
                    ' WHERE ' +
                    String.join(conditions, ' AND ') +
                    ' ORDER BY CreatedDate DESC LIMIT :candidates',
                new Map<String, Object>{ 'candidates' => MAX_CANDIDATES },
                AccessLevel.USER_MODE
            )
        ) {
            keys.add((Id) RollupAggregator.valueAt(row, query.keyExpression));
        }
        return keys;
    }

    /**
     * The source records read for one record of the target entity, up to `MAX_SHOWN`, each said to
     * be counted or left out.
     *
     * @param definition the rollup, which need not be saved; its checks have passed
     * @param targetId a record of its target entity
     */
    public static Detail of(Rollup_Definition__c definition, Id targetId) {
        Schema.SObjectType targetType = SettingsService.typeByName(definition.Target_Object__c);
        RollupPlanner.Plan plan = RollupPlanner.plan(
            targetType,
            new List<Rollup_Definition__c>{ definition }
        );
        Detail detail = new Detail();
        detail.rows = new List<Row>();
        detail.total = 0;
        detail.counted = 0;
        for (RollupPlanner.SourceQuery query : plan.queries) {
            if (query.token != null) {
                detail.note = Label.Core_RollupEase_RowsHousehold;
                continue;
            }
            readRows(definition, query, targetId, detail);
        }
        if (detail.total == 0 && detail.note == null) {
            detail.note = Label.Core_RollupEase_RowsNone;
        } else if (detail.total > 0) {
            detail.summary = String.format(
                Label.Core_RollupEase_RowsShown,
                new List<String>{ detail.rows.size().format(), detail.total.format() }
            );
        }
        return detail;
    }

    /** Adds one alternative of the path's rows for the record, as many as there is room for. */
    private static void readRows(
        Rollup_Definition__c definition,
        RollupPlanner.SourceQuery query,
        Id targetId,
        Detail detail
    ) {
        Schema.SObjectType sourceType = SettingsService.typeByName(query.sourceObject);
        String linked = ' WHERE ' + query.keyExpression + ' = :target';
        for (String earlier : query.earlierKeys) {
            linked += ' AND ' + earlier + ' = null';
        }
        String allRows = query.includeDeleted ? ' ALL ROWS' : '';
        Map<String, Object> binds = new Map<String, Object>{ 'target' => targetId };
        detail.total += Database.countQueryWithBinds(
            'SELECT COUNT() FROM ' + query.sourceObject + linked + allRows,
            binds,
            AccessLevel.USER_MODE
        );
        String counting = linked;
        if (String.isNotBlank(query.whereClause)) {
            counting += ' AND (' + query.whereClause + ')';
        }
        if (query.kind == RollupPlanner.KIND_ORDERED) {
            counting += ' AND ' + query.orderBy + ' != null';
        }
        Integer countedHere = Database.countQueryWithBinds(
            'SELECT COUNT() FROM ' + query.sourceObject + counting + allRows,
            binds,
            AccessLevel.USER_MODE
        );
        Integer rowLimit = query.measures[0].rowLimit;
        detail.counted += rowLimit == null ? countedHere : Math.min(countedHere, rowLimit);
        Integer room = MAX_SHOWN - detail.rows.size();
        if (room <= 0) {
            return;
        }
        String nameField = nameFieldOf(sourceType);
        Set<String> fields = new Set<String>{ 'Id', nameField };
        if (query.orderBy != null) {
            fields.add(query.orderBy);
        }
        binds.put('room', room);
        List<SObject> rows = Database.queryWithBinds(
            'SELECT ' +
                String.join(new List<String>(fields), ', ') +
                ' FROM ' +
                query.sourceObject +
                linked +
                ' ORDER BY ' +
                orderOf(query) +
                ' LIMIT :room' +
                allRows,
            binds,
            AccessLevel.USER_MODE
        );
        if (rows.isEmpty()) {
            return;
        }
        Set<Id> ids = new Map<Id, SObject>(rows).keySet();
        Set<Id> counted = passing(query, ids, query.whereClause, true);
        Map<Id, List<String>> failed = failedConditions(
            definition,
            query,
            sourceType,
            ids,
            counted
        );
        Integer limitLeft = query.measures[0].rowLimit;
        for (SObject source : rows) {
            Row row = new Row();
            row.recordId = source.Id;
            row.name = nameOf(source, nameField);
            row.counted = counted.contains(source.Id);
            if (row.counted && limitLeft != null && limitLeft <= 0) {
                row.counted = false;
                row.reason = String.format(
                    Label.Core_RollupEase_RowBeyondLimit,
                    new List<String>{ query.measures[0].rowLimit.format() }
                );
            } else if (row.counted) {
                row.reason = Label.Core_RollupEase_RowCounted;
                limitLeft = limitLeft == null ? null : limitLeft - 1;
            } else {
                row.reason = whyLeftOut(source, query, sourceType, failed.get(source.Id));
            }
            detail.rows.add(row);
        }
    }

    /** The order the engine reads in, or the newest first when the rollup has none. */
    private static String orderOf(RollupPlanner.SourceQuery query) {
        if (query.orderBy == null) {
            return 'CreatedDate DESC';
        }
        return query.orderBy + (query.descending ? ' DESC NULLS LAST' : ' ASC NULLS LAST');
    }

    /** Which of these rows meet a clause, and have a value to order by when that is asked. */
    private static Set<Id> passing(
        RollupPlanner.SourceQuery query,
        Set<Id> ids,
        String clause,
        Boolean ordered
    ) {
        List<String> conditions = new List<String>{ 'Id IN :ids' };
        if (String.isNotBlank(clause)) {
            conditions.add('(' + clause + ')');
        }
        if (ordered && query.kind == RollupPlanner.KIND_ORDERED) {
            conditions.add(query.orderBy + ' != null');
        }
        return new Map<Id, SObject>(
                Database.queryWithBinds(
                    'SELECT Id FROM ' +
                        query.sourceObject +
                        ' WHERE ' +
                        String.join(conditions, ' AND ') +
                        (query.includeDeleted ? ' ALL ROWS' : ''),
                    new Map<String, Object>{ 'ids' => ids },
                    AccessLevel.USER_MODE
                )
            )
            .keySet();
    }

    /**
     * For each row left out, the numbers of the conditions it does not meet, tested one by one:
     * one query per condition, for at most `MAX_CONDITIONS` conditions.
     */
    private static Map<Id, List<String>> failedConditions(
        Rollup_Definition__c definition,
        RollupPlanner.SourceQuery query,
        Schema.SObjectType sourceType,
        Set<Id> ids,
        Set<Id> counted
    ) {
        Map<Id, List<String>> failed = new Map<Id, List<String>>();
        if (counted.containsAll(ids) || String.isBlank(definition.Filter_JSON__c)) {
            return failed;
        }
        Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(
            definition.Filter_JSON__c
        );
        List<Object> conditions = (List<Object>) document.get('conditions');
        if (conditions == null) {
            return failed;
        }
        Integer position = 0;
        for (Object condition : conditions) {
            position++;
            if (position > MAX_CONDITIONS) {
                break;
            }
            Object conditionId = ((Map<String, Object>) condition).get('id');
            String conditionNumber = conditionId == null
                ? String.valueOf(position)
                : String.valueOf(conditionId);
            String clause = RollupFilterParser.toWhereClause(
                JSON.serialize(
                    new Map<String, Object>{
                        'version' => document.get('version'),
                        'conditions' => new List<Object>{ condition }
                    }
                ),
                sourceType
            );
            Set<Id> meeting = passing(query, ids, clause, false);
            for (Id rowId : ids) {
                if (!meeting.contains(rowId) && !counted.contains(rowId)) {
                    if (!failed.containsKey(rowId)) {
                        failed.put(rowId, new List<String>());
                    }
                    failed.get(rowId).add(conditionNumber);
                }
            }
        }
        return failed;
    }

    /** Why a row is left out: its conditions, a blank value to order by, or the year window. */
    private static String whyLeftOut(
        SObject row,
        RollupPlanner.SourceQuery query,
        Schema.SObjectType sourceType,
        List<String> failed
    ) {
        if (failed != null && !failed.isEmpty()) {
            return String.format(
                Label.Core_RollupEase_RowFails,
                new List<String>{ String.join(failed, ', ') }
            );
        }
        if (
            query.kind == RollupPlanner.KIND_ORDERED &&
            RollupAggregator.valueAt(row, query.orderBy) == null
        ) {
            return String.format(
                Label.Core_RollupEase_RowNoOrder,
                new List<String>{ fieldLabel(sourceType, query.orderBy) }
            );
        }
        return Label.Core_RollupEase_RowOutsideWindow;
    }

    /** A field's label, or the path as written when it walks to another entity. */
    private static String fieldLabel(Schema.SObjectType objectType, String path) {
        Schema.SObjectField field = path.contains('.')
            ? null
            : objectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().get(path);
        return field == null ? path : field.getDescribe().getLabel();
    }

    /** The entity's name field the administrator can read, or Id when it has none. */
    @TestVisible
    private static String nameFieldOf(Schema.SObjectType objectType) {
        for (
            Schema.SObjectField field : objectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .values()
        ) {
            Schema.DescribeFieldResult described = field.getDescribe();
            if (described.isNameField() && described.isAccessible()) {
                return described.getName();
            }
        }
        return 'Id';
    }

    private static String columns(String nameField) {
        return nameField == 'Id' ? 'Id' : 'Id, ' + nameField;
    }

    private static String nameOf(SObject record, String nameField) {
        Object name = record.get(nameField);
        return name == null || String.isBlank(String.valueOf(name))
            ? String.valueOf(record.Id)
            : String.valueOf(name);
    }
}
