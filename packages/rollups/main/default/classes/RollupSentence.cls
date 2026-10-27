/**
 * A rollup in one plain sentence, from the labels the org's describe gives (Rollup Builder ease
 * of use U1, ADR-0136): "Total of Amount from Gifts by Donor Contact, shown in Largest Gift on
 * each Contact." The rollup list and Explain This Number read a rollup the same way. An entity
 * or field the org lacks is named by its API name, so a rollup that no longer plans still reads.
 */
public with sharing class RollupSentence {
    private static final Set<String> READS_NO_FIELD = new Set<String>{ 'COUNT', 'ANY', 'NONE' };

    /** The calculation's words by aggregate; {0} is the counted field's label. */
    private static final Map<String, String> CALCULATION = new Map<String, String>{
        'SUM' => Label.Core_RollupEase_CalcSum,
        'COUNT' => Label.Core_RollupEase_CalcCount,
        'MIN' => Label.Core_RollupEase_CalcMin,
        'MAX' => Label.Core_RollupEase_CalcMax,
        'AVG' => Label.Core_RollupEase_CalcAvg,
        'FIRST' => Label.Core_RollupEase_CalcFirst,
        'LAST' => Label.Core_RollupEase_CalcLast,
        'COUNT_DISTINCT' => Label.Core_RollupEase_CalcCountDistinct,
        'ANY' => Label.Core_RollupEase_CalcAny,
        'NONE' => Label.Core_RollupEase_CalcNone,
        'TEXT_LIST' => Label.Core_RollupEase_CalcTextList,
        'TEXT_LIST_DISTINCT' => Label.Core_RollupEase_CalcTextListDistinct
    };

    /** The whole sentence, with what limits the records counted after it. */
    public static String of(Rollup_Definition__c definition) {
        Schema.SObjectType sourceType = SettingsService.typeByName(definition.Source_Object__c);
        Schema.SObjectType targetType = SettingsService.typeByName(definition.Target_Object__c);
        String aggregate = definition.Aggregate__c == null
            ? ''
            : definition.Aggregate__c.toUpperCase();
        Boolean readsField = !READS_NO_FIELD.contains(aggregate);
        String sentence = String.format(
            readsField ? Label.Core_RollupEase_Sentence : Label.Core_RollupEase_SentenceRecords,
            new List<String>{
                calculation(aggregate, fieldLabel(sourceType, definition.Source_Field__c)),
                sourceType == null
                    ? definition.Source_Object__c
                    : sourceType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural(),
                linkOf(sourceType, definition.Relationship_Path__c),
                fieldLabel(targetType, definition.Target_Field__c),
                targetType == null
                    ? definition.Target_Object__c
                    : targetType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel()
            }
        );
        List<String> parts = new List<String>{ sentence };
        if (String.isNotBlank(definition.Filter_JSON__c)) {
            parts.add(Label.Core_RollupEase_SentenceConditions);
        }
        if (definition.Fiscal_Year_Aware__c == true) {
            parts.add(windowOf(definition.Fiscal_Year_Offset__c));
        }
        if (definition.Row_Limit__c != null) {
            parts.add(
                String.format(
                    Label.Core_RollupEase_SentenceLimit,
                    new List<String>{ definition.Row_Limit__c.intValue().format() }
                )
            );
        }
        return String.join(parts, ' ');
    }

    /** "Total of Amount", "Number of", by the calculation's own words. */
    public static String calculation(String aggregate, String fieldLabel) {
        String words = CALCULATION.get(aggregate == null ? '' : aggregate.toUpperCase());
        if (words == null) {
            return aggregate;
        }
        return String.format(words, new List<String>{ fieldLabel == null ? '' : fieldLabel });
    }

    /**
     * How the counted records reach the record that shows the total, by field labels: "Donor
     * Contact", "Donor Contact's household", alternatives joined by "or".
     */
    @TestVisible
    private static String linkOf(Schema.SObjectType sourceType, String path) {
        if (String.isBlank(path)) {
            return '';
        }
        List<String> branches = new List<String>();
        try {
            for (RollupPath.Branch branch : RollupPath.parse(path).branches) {
                branches.add(branchLabel(sourceType, branch.segments));
            }
        } catch (RollupPath.RollupPathException unreadable) {
            return path;
        }
        return String.join(branches, ' ' + Label.Core_RollupEase_Or + ' ');
    }

    private static String branchLabel(Schema.SObjectType sourceType, List<String> segments) {
        String text = '';
        Schema.SObjectType reached = sourceType;
        for (String segment : segments) {
            if (RollupPath.isToken(segment)) {
                text = String.format(
                    segment == RollupPath.TOKEN_HOUSEHOLD
                        ? Label.Core_RollupEase_LinkHousehold
                        : Label.Core_RollupEase_LinkHouseholdMembers,
                    new List<String>{ text }
                );
                reached = null;
                continue;
            }
            Schema.SObjectField field = reached == null
                ? null
                : reached.getDescribe(SObjectDescribeOptions.DEFERRED)
                      .fields.getMap()
                      .get(segment.toLowerCase());
            String label = segment;
            reached = null;
            if (field != null) {
                Schema.DescribeFieldResult described = field.getDescribe();
                label = described.getLabel().removeEndIgnoreCase(' ID');
                reached = described.getReferenceTo().size() == 1
                    ? described.getReferenceTo()[0]
                    : null;
            }
            text = String.isBlank(text) ? label : text + ' > ' + label;
        }
        return text;
    }

    /** A field's label, or its API name when the org lacks it; blank for no field. */
    private static String fieldLabel(Schema.SObjectType type, String fieldName) {
        if (String.isBlank(fieldName)) {
            return '';
        }
        Schema.SObjectField field = type == null
            ? null
            : type.getDescribe(SObjectDescribeOptions.DEFERRED)
                  .fields.getMap()
                  .get(fieldName.toLowerCase());
        return field == null ? fieldName : field.getDescribe().getLabel();
    }

    private static String windowOf(Decimal offset) {
        Integer years = offset == null ? 0 : offset.intValue();
        if (years == -1) {
            return Label.Core_RollupEase_SentenceLastYear;
        }
        if (years == -2) {
            return Label.Core_RollupEase_SentenceTwoYearsAgo;
        }
        return Label.Core_RollupEase_SentenceThisYear;
    }
}
