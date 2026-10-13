/**
 * The filter document format of canonical model R-R2, read.
 *
 * These tests have not been executed: no Salesforce org exists in this environment, so nothing
 * here has run. They are written against the format the canonical model states and the behaviour
 * the class documents.
 */
// runs-as: deploying user (pure logic: parses a filter document, no DML or SOQL)
@IsTest
private class RollupFilterParserTest {
    @IsTest
    static void emptyDocumentMeansEveryRecord() {
        System.Assert.areEqual(
            '',
            RollupFilterParser.toWhereClause(null),
            'A blank filter counts everything'
        );
        System.Assert.areEqual(
            '',
            RollupFilterParser.toWhereClause('   '),
            'A blank filter counts everything'
        );
        System.Assert.areEqual(
            '',
            RollupFilterParser.toWhereClause('{"version": 1, "conditions": []}'),
            'A filter with no conditions counts everything'
        );
    }

    @IsTest
    static void conditionsJoinWithAndWhenNoLogicIsGiven() {
        String document =
            '{"version": 1, "conditions": [' +
            '{"id": 1, "field": "Status__c", "operator": "equals", "value": "Received"},' +
            '{"id": 2, "field": "Amount__c", "operator": "greater than", "value": 0}]}';

        String clause = RollupFilterParser.toWhereClause(document);

        System.Assert.areEqual(
            'Status__c = \'Received\' AND Amount__c > 0',
            clause,
            'Conditions join with AND and a number goes in unquoted'
        );
    }

    @IsTest
    static void logicStringDecidesHowConditionsCombine() {
        String document =
            '{"version": 1, "logic": "1 AND (2 OR 3)", "conditions": [' +
            '{"id": 1, "field": "Status__c", "operator": "equals", "value": "Received"},' +
            '{"id": 2, "field": "Type__c", "operator": "equals", "value": "Grant"},' +
            '{"id": 3, "field": "Type__c", "operator": "equals", "value": "Stock"}]}';

        String clause = RollupFilterParser.toWhereClause(document);

        System.Assert.areEqual(
            '(Status__c = \'Received\') AND ( (Type__c = \'Grant\') OR (Type__c = \'Stock\') )',
            clause,
            'The logic string decides the shape'
        );
    }

    @IsTest
    static void everyOperatorRendersTheComparisonItMeans() {
        System.Assert.areEqual(
            'Type__c in (\'Grant\',\'Stock\')',
            RollupFilterParser.toWhereClause(
                '{"version": 1, "conditions": [{"id": 1, "field": "Type__c", "operator": "in", "value": ["Grant", "Stock"]}]}'
            ),
            'A list operator renders a bracketed list'
        );
        System.Assert.areEqual(
            'Name like \'%Trust%\'',
            RollupFilterParser.toWhereClause(
                '{"version": 1, "conditions": [{"id": 1, "field": "Name", "operator": "contains", "value": "Trust"}]}'
            ),
            'Contains wraps the value in wildcards'
        );
        System.Assert.areEqual(
            'Closed_Date__c = null',
            RollupFilterParser.toWhereClause(
                '{"version": 1, "conditions": [{"id": 1, "field": "Closed_Date__c", "operator": "is null"}]}'
            ),
            'Is null takes no value'
        );
    }

    @IsTest
    static void relationshipQualifiedFieldsArePermitted() {
        String clause = RollupFilterParser.toWhereClause(
            '{"version": 1, "conditions": [{"id": 1, "field": "Gift__r.Status__c", "operator": "equals", "value": "Received"}]}'
        );

        System.Assert.areEqual(
            'Gift__r.Status__c = \'Received\'',
            clause,
            'A fund rollup filters on the parent gift, which Section 26 requires'
        );
    }

    @IsTest
    static void datesGoInUnquotedSoTheEngineReadsThemAsDates() {
        String clause = RollupFilterParser.toWhereClause(
            '{"version": 1, "conditions": [{"id": 1, "field": "Gift_Date__c", "operator": "greater or equal", "value": "2026-01-01"}]}'
        );

        System.Assert.areEqual('Gift_Date__c >= 2026-01-01', clause, 'A date is not a string');
    }

    @IsTest
    static void relativeDatesRenderAsDateLiterals() {
        System.Assert.areEqual(
            'Gift_Date__c = THIS_YEAR',
            RollupFilterParser.toWhereClause(
                '{"version": 1, "conditions": [{"id": 1, "field": "Gift_Date__c", "operator": "this year"}]}'
            ),
            'This year takes no value'
        );
        System.Assert.areEqual(
            'Gift_Date__c = LAST_YEAR',
            RollupFilterParser.toWhereClause(
                '{"version": 1, "conditions": [{"id": 1, "field": "Gift_Date__c", "operator": "last year"}]}'
            ),
            'Last year takes no value'
        );
        System.Assert.areEqual(
            'Gift_Date__c = LAST_N_DAYS:30',
            RollupFilterParser.toWhereClause(
                '{"version": 1, "conditions": [{"id": 1, "field": "Gift_Date__c", "operator": "last n days", "value": 30}]}'
            ),
            'The day count is written back from a whole number'
        );
        System.Assert.areEqual(
            'Gift_Date__c = LAST_N_DAYS:7',
            RollupFilterParser.toWhereClause(
                '{"version": 1, "conditions": [{"id": 1, "field": "Gift_Date__c", "operator": "last n days", "value": "7"}]}'
            ),
            'A day count saved as text is still read as a number'
        );
    }

    @IsTest
    static void aDayCountThatIsNotAWholeNumberInRangeIsRefused() {
        for (String value : new List<String>{ '0', '3651', '2.5', '"30 OR Id != null"', 'null' }) {
            try {
                RollupFilterParser.toWhereClause(
                    '{"version": 1, "conditions": [{"id": 1, "field": "Gift_Date__c", "operator": "last n days", "value": ' +
                        value +
                        '}]}'
                );
                System.Assert.fail('A day count must be a whole number from 1 to 3650: ' + value);
            } catch (RollupFilterParser.RollupFilterException expected) {
                System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
            }
        }
    }

    @IsTest
    static void quotesInAValueAreEscaped() {
        String clause = RollupFilterParser.toWhereClause(
            '{"version": 1, "conditions": [{"id": 1, "field": "Name", "operator": "equals", "value": "O\'Brien"}]}'
        );

        System.Assert.areEqual(
            'Name = \'O\\\'Brien\'',
            clause,
            'The only place typing reaches a query is escaped'
        );
    }

    @IsTest
    static void anUnknownOperatorIsRefused() {
        try {
            RollupFilterParser.toWhereClause(
                '{"version": 1, "conditions": [{"id": 1, "field": "Name", "operator": "sounds like", "value": "x"}]}'
            );
            System.Assert.fail('An operator the builder does not offer must be refused');
        } catch (RollupFilterParser.RollupFilterException expected) {
            System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
        }
    }

    @IsTest
    static void aFieldNameThatIsNotAFieldNameIsRefused() {
        try {
            RollupFilterParser.toWhereClause(
                '{"version": 1, "conditions": [{"id": 1, "field": "Name FROM Account WHERE", "operator": "equals", "value": "x"}]}'
            );
            System.Assert.fail('Anything but an attribute name must be refused');
        } catch (RollupFilterParser.RollupFilterException expected) {
            System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
        }
    }

    @IsTest
    static void aLogicStringWithSomethingElseInItIsRefused() {
        try {
            RollupFilterParser.toWhereClause(
                '{"version": 1, "logic": "1 AND Name = 2", "conditions": ' +
                '[{"id": 1, "field": "Name", "operator": "equals", "value": "x"}]}'
            );
            System.Assert.fail(
                'Only condition numbers, brackets, AND, OR and NOT belong in the logic'
            );
        } catch (RollupFilterParser.RollupFilterException expected) {
            System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
        }
    }

    /** A part of the right name but the wrong shape is refused with the filter message. */
    @IsTest
    static void aDocumentOfTheWrongShapeIsRefused() {
        for (
            String document : new List<String>{
                'null',
                '{"conditions": ["Status__c"]}',
                '{"conditions": {"id": 1}}',
                '{"logic": 1, "conditions": [{"id": 1, "field": "Status__c", "operator": "equals", "value": "Open"}]}'
            }
        ) {
            try {
                RollupFilterParser.toWhereClause(document);
                System.Assert.fail('Must be refused: ' + document);
            } catch (RollupFilterParser.RollupFilterException expected) {
                System.Assert.areEqual(
                    System.Label.Core_Rollups_ErrorInvalidFilter,
                    expected.getMessage(),
                    document
                );
            }
        }
    }

    @IsTest
    static void aVersionThisPackageDoesNotKnowIsRefused() {
        try {
            RollupFilterParser.toWhereClause('{"version": 99, "conditions": []}');
            System.Assert.fail(
                'The version key exists so an unknown format is refused rather than guessed'
            );
        } catch (RollupFilterParser.RollupFilterException expected) {
            System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
        }
    }
}
