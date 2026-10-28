/**
 * Explain This Number (Rollup Builder ease of use U5, ADR-0136): on a record page, each total a
 * BarnCRM rollup fills there, with what it counts in plain words, how many records counted and
 * how many were left out and why, when it was last calculated, and links to the records read.
 * An administrator also sees what the rollup would calculate now.
 *
 * Everything is read in user mode, as the person looking: the rollups (Rollup Builder User or
 * Admin gives read access), the record's fields (a total whose field they cannot read is not
 * listed), and the records counted (they see the ones they can open; the counts say so).
 * Nothing is written.
 */
public with sharing class RollupExplainController {
    /** One total on the record, explained. */
    public class Explanation {
        @AuraEnabled
        public String definitionId { get; set; }
        @AuraEnabled
        public String fieldLabel { get; set; }
        @AuraEnabled
        public String value { get; set; }
        @AuraEnabled
        public String sentence { get; set; }
        @AuraEnabled
        public String counts { get; set; }
        @AuraEnabled
        public String lastCalculated { get; set; }
        @AuraEnabled
        public RollupPreviewRows.Detail rows { get; set; }
        /** For an administrator only: what the rollup would write now. */
        @AuraEnabled
        public String calculatedNow { get; set; }
    }

    /**
     * Each active rollup that fills a field of this record, explained.
     *
     * @param recordId the record the page shows
     */
    @AuraEnabled
    public static List<Explanation> explain(Id recordId) {
        try {
            List<Explanation> explained = new List<Explanation>();
            if (recordId == null) {
                return explained;
            }
            Schema.SObjectType recordType = recordId.getSObjectType();
            Map<String, Schema.SObjectField> fields = recordType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .fields.getMap();
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>();
            Set<String> columns = new Set<String>{ 'Id' };
            for (Rollup_Definition__c definition : RollupSelector.selectAllAsUser()) {
                Schema.SObjectField field = String.isBlank(definition.Target_Field__c)
                    ? null
                    : fields.get(definition.Target_Field__c);
                if (
                    definition.Active__c == true &&
                    SettingsService.typeByName(definition.Target_Object__c) == recordType &&
                    field != null &&
                    field.getDescribe().isAccessible()
                ) {
                    definitions.add(definition);
                    columns.add(field.getDescribe().getName());
                }
            }
            if (definitions.isEmpty()) {
                return explained;
            }
            Schema.SObjectField stamp = fields.get(RollupService.FRESHNESS_FIELD);
            if (stamp != null && stamp.getDescribe().isAccessible()) {
                columns.add(stamp.getDescribe().getName());
            }
            // The entity and the fields come from describe.
            List<SObject> found = Database.queryWithBinds(
                'SELECT ' +
                    String.join(new List<String>(columns), ', ') +
                    ' FROM ' +
                    String.valueOf(recordType) +
                    ' WHERE Id = :recordId',
                new Map<String, Object>{ 'recordId' => recordId },
                AccessLevel.USER_MODE
            );
            // A record the person cannot open, or one deleted since the page loaded, has no
            // totals to explain to them.
            if (found.isEmpty()) {
                return explained;
            }
            SObject record = found[0];
            Boolean admin = FeatureManagement.checkPermission('Manage_BarnCRM_Settings');
            for (Rollup_Definition__c definition : definitions) {
                if (fills(definition, recordType, recordId)) {
                    explained.add(explanationOf(definition, fields, record, stamp, admin));
                }
            }
            return explained;
        } catch (Exception caught) {
            String message = caught instanceof RollupService.RollupServiceException
                ? caught.getMessage()
                : Label.Core_Rollups_UnexpectedError;
            if (!(caught instanceof RollupService.RollupServiceException)) {
                ErrorLogger.log(caught, 'RollupExplainController');
            }
            AuraHandledException reported = new AuraHandledException(message);
            reported.setMessage(message);
            throw reported;
        }
    }

    /** Whether the record meets the rollup's target conditions, so the rollup fills it. */
    private static Boolean fills(
        Rollup_Definition__c definition,
        Schema.SObjectType recordType,
        Id recordId
    ) {
        String condition = RollupFilterParser.toWhereClause(
            definition.Target_Filter_JSON__c,
            recordType
        );
        if (String.isBlank(condition)) {
            return true;
        }
        // The entity comes from describe and the clause from RollupFilterParser, which checks
        // every name and escapes every value.
        return Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' +
                    String.valueOf(recordType) +
                    ' WHERE Id = :recordId AND (' +
                    condition +
                    ')',
                new Map<String, Object>{ 'recordId' => recordId },
                AccessLevel.USER_MODE
            ) > 0;
    }

    private static Explanation explanationOf(
        Rollup_Definition__c definition,
        Map<String, Schema.SObjectField> fields,
        SObject record,
        Schema.SObjectField stamp,
        Boolean admin
    ) {
        Schema.DescribeFieldResult target = fields.get(definition.Target_Field__c).getDescribe();
        Explanation explanation = new Explanation();
        explanation.definitionId = definition.Id;
        explanation.fieldLabel = target.getLabel();
        explanation.value = RollupBuilderController.display(record.get(target.getName()));
        explanation.sentence = RollupSentence.of(definition);
        explanation.rows = RollupPreviewRows.of(definition, record.Id);
        explanation.counts = String.format(
            Label.Core_RollupEase_ExplainCounts,
            new List<String>{
                explanation.rows.counted.format(),
                explanation.rows.total.format(),
                (explanation.rows.total - explanation.rows.counted).format()
            }
        );
        Object stamped = stamp == null || !stamp.getDescribe().isAccessible()
            ? null
            : record.get(stamp.getDescribe().getName());
        Datetime calculatedAt = stamped instanceof Datetime
            ? (Datetime) stamped
            : definition.Last_Calculated__c;
        explanation.lastCalculated = calculatedAt == null
            ? Label.Core_RollupEase_ExplainNever
            : String.format(
                  Label.Core_RollupEase_ExplainLast,
                  new List<String>{ calculatedAt.format() }
              );
        if (admin) {
            explanation.calculatedNow = RollupBuilderController.describe(
                RollupEngine.preview(definition, record.Id)
            );
        }
        return explanation;
    }
}
