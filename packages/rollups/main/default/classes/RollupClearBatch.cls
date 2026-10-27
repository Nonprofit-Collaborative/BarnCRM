/**
 * Clears the values a deleted rollup wrote (Rollup Builder ease of use U11, ADR-0136). When an
 * administrator deletes a rollup she chooses to keep what it wrote (the default: nothing
 * updates those values again) or to clear them. Clearing blanks the rollup's field on every
 * record of its target entity that meets its target conditions, in batches of `SCOPE`, through
 * the same changed-only write as a recalculation (`RollupWriter.writeTotals`), so a record
 * already blank is not saved and one locked record fails alone. The run's outcome is logged.
 *
 * The delete refuses to clear while another active rollup fills the same field for the same
 * records (`RollupConflicts.sharerOf`), since clearing would wipe that rollup's totals too.
 *
 * DOCUMENTED EXCEPTION to user mode reads and writes (plan Section 4.13, ADR-0021, as in
 * `RollupLargeParentBatch`): rollup fields are written in system mode, usually read-only to the
 * people who see them, so clearing them is too. Only someone with Manage BarnCRM Settings can
 * start it (`RollupController.deleteRollup`).
 */
public without sharing class RollupClearBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String CLASS_NAME = 'RollupClearBatch';
    @TestVisible
    private static final Integer SCOPE = 200;

    private final String targetObject;
    private final String targetField;
    private final String targetFilter;
    private final String rollupName;
    @TestVisible
    private Integer cleared = 0;
    @TestVisible
    private Integer refused = 0;

    public RollupClearBatch(Rollup_Definition__c definition) {
        this.targetObject = definition.Target_Object__c;
        this.targetField = definition.Target_Field__c;
        this.rollupName = definition.Name;
        this.targetFilter = RollupFilterParser.toWhereClause(
            definition.Target_Filter_JSON__c,
            SettingsService.typeByName(definition.Target_Object__c)
        );
    }

    /**
     * Starts clearing one rollup's field. The definition may already be deleted: the batch
     * holds what it needs.
     *
     * @param definition the rollup, with its target, field and target conditions
     * @return the batch job
     */
    public static Id begin(Rollup_Definition__c definition) {
        return Database.executeBatch(new RollupClearBatch(definition), SCOPE);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(query(), AccessLevel.SYSTEM_MODE);
    }

    /** The records to clear; none when the field is gone or cannot be written. */
    @TestVisible
    private String query() {
        Schema.SObjectType targetType = SettingsService.typeByName(this.targetObject);
        Schema.SObjectField field = fieldOf(targetType);
        if (field == null) {
            return 'SELECT Id FROM Rollup_Definition__c WHERE Id = null';
        }
        Schema.DescribeFieldResult described = field.getDescribe();
        List<String> conditions = new List<String>();
        // A long text field cannot be filtered; a record already blank is then read and skipped.
        if (described.isFilterable()) {
            conditions.add(described.getName() + ' != null');
        }
        if (String.isNotBlank(this.targetFilter)) {
            conditions.add('(' + this.targetFilter + ')');
        }
        // The entity and the field come from describe and the clause from RollupFilterParser,
        // which checks every name and escapes every value.
        return 'SELECT Id, ' +
            described.getName() +
            ' FROM ' +
            String.valueOf(targetType) +
            (conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND '));
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Schema.SObjectType targetType = SettingsService.typeByName(this.targetObject);
        Schema.SObjectField field = fieldOf(targetType);
        if (field == null) {
            return;
        }
        Map<Id, SObject> stored = new Map<Id, SObject>(scope);
        Map<Id, Map<Schema.SObjectField, Object>> blank = new Map<Id, Map<Schema.SObjectField, Object>>();
        for (Id recordId : stored.keySet()) {
            blank.put(recordId, new Map<Schema.SObjectField, Object>{ field => null });
        }
        RollupWriter.TotalsWrite write = RollupWriter.writeTotals(
            targetType,
            stored,
            blank,
            Datetime.now()
        );
        this.cleared += write.written.size();
        this.refused += write.failed.size();
    }

    public void finish(Database.BatchableContext context) {
        ErrorLogger.logMessage(
            String.format(
                Label.Core_RollupEase_ClearDone,
                new List<String>{ this.rollupName, this.cleared.format(), this.refused.format() }
            ),
            CLASS_NAME,
            this.refused > 0 ? ErrorLogger.SEVERITY_WARNING : ErrorLogger.SEVERITY_INFO
        );
    }

    /** The rollup's field, when it still exists and can be written. */
    private Schema.SObjectField fieldOf(Schema.SObjectType targetType) {
        if (targetType == null || String.isBlank(this.targetField)) {
            return null;
        }
        Schema.SObjectField field = targetType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .get(this.targetField);
        return field != null && field.getDescribe().isUpdateable() ? field : null;
    }
}
