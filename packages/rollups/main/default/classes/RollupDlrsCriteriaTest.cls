/**
 * A DLRS Relationship Criteria read into the filter document (canonical model R-R16): the
 * shapes the filter builder holds are read with SOQL's grouping, and anything else is refused
 * with the part that could not be read.
 */
// runs-as: deploying user (pure logic, no records and no sharing)
@IsTest(testFor='ApexClass:RollupDlrsCriteria')
private class RollupDlrsCriteriaTest {
    private static Map<String, Object> read(String criteria) {
        return (Map<String, Object>) JSON.deserializeUntyped(
            RollupDlrsCriteria.toFilter(criteria, null)
        );
    }

    private static Map<String, Object> condition(Map<String, Object> filter, Integer index) {
        return (Map<String, Object>) ((List<Object>) filter.get('conditions'))[index];
    }

    private static String refusal(String criteria) {
        try {
            RollupDlrsCriteria.toFilter(criteria, null);
        } catch (RollupDlrsCriteria.CriteriaException refused) {
            return refused.getMessage();
        }
        return null;
    }

    @IsTest
    static void blankCriteriaIsNoFilter() {
        Assert.isNull(RollupDlrsCriteria.toFilter(null, null), 'Nothing to filter on');
        Assert.isNull(RollupDlrsCriteria.toFilter('  ', new List<Map<String, Object>>()), 'Blank');
    }

    @IsTest
    static void comparisonsBecomeConditionsWithTheirOperators() {
        Map<String, String> operatorByComparison = new Map<String, String>{
            '=' => 'equals',
            '!=' => 'not equals',
            '<>' => 'not equals',
            '<' => 'less than',
            '<=' => 'less or equal',
            '>' => 'greater than',
            '>=' => 'greater or equal'
        };
        for (String comparison : operatorByComparison.keySet()) {
            Map<String, Object> only = condition(read('Amount__c ' + comparison + ' 100.5'), 0);
            Assert.areEqual('Amount__c', only.get('field'), comparison);
            Assert.areEqual(operatorByComparison.get(comparison), only.get('operator'), comparison);
            Assert.areEqual('100.5', String.valueOf(only.get('value')), comparison);
        }
    }

    @IsTest
    static void groupingFollowsSoql() {
        Map<String, Object> filter = read(
            'Amount__c > 100 and (Type__c = \'Gift\' OR Type__c = \'Pledge\')'
        );
        Assert.areEqual('(1) AND ((2) OR (3))', filter.get('logic'), 'Brackets are kept');
        Assert.areEqual(3, ((List<Object>) filter.get('conditions')).size(), 'Three conditions');
        Assert.areEqual('Pledge', condition(filter, 2).get('value'), 'Text stays text');

        Assert.areEqual(
            '(1) OR ((2) AND (3))',
            read('A__c = 1 OR B__c = 2 AND C__c = 3').get('logic'),
            'AND binds tighter than OR'
        );
        Assert.areEqual('NOT (1)', read('NOT Closed__c = true').get('logic'), 'NOT is kept');
        Assert.areEqual(true, condition(read('Closed__c = TRUE'), 0).get('value'), 'A boolean');
    }

    @IsTest
    static void blanksDatesListsAndPatternsAreRead() {
        Assert.areEqual('is null', condition(read('Date__c = null'), 0).get('operator'), '= null');
        Assert.areEqual(
            'is not null',
            condition(read('Date__c != NULL'), 0).get('operator'),
            '!= null'
        );
        Assert.areEqual(
            'this year',
            condition(read('Date__c = THIS_YEAR'), 0).get('operator'),
            'This year'
        );
        Assert.areEqual(
            'last year',
            condition(read('Date__c = last_year'), 0).get('operator'),
            'Last year, in any case'
        );
        Map<String, Object> recent = condition(read('Date__c = LAST_N_DAYS:30'), 0);
        Assert.areEqual('last n days', recent.get('operator'), 'Last n days');
        Assert.areEqual(30, recent.get('value'), 'The number of days');
        Assert.areEqual(
            '2024-01-31',
            condition(read('Date__c >= 2024-01-31'), 0).get('value'),
            'A date'
        );

        Map<String, Object> inList = condition(read('Stage__c IN (\'A\', \'B\')'), 0);
        Assert.areEqual('in', inList.get('operator'), 'IN');
        Assert.areEqual(2, ((List<Object>) inList.get('value')).size(), 'Both values');
        Assert.areEqual(
            'not in',
            condition(read('Stage__c NOT IN (\'A\')'), 0).get('operator'),
            'NOT IN'
        );

        Map<String, Object> starts = condition(read('Name LIKE \'Smith%\''), 0);
        Assert.areEqual('starts with', starts.get('operator'), 'LIKE x%');
        Assert.areEqual('Smith', starts.get('value'), 'Without the wildcard');
        Assert.areEqual(
            'contains',
            condition(read('Name LIKE \'%Smith%\''), 0).get('operator'),
            'LIKE %x%'
        );
        Assert.areEqual(
            'O\'Brien AND Sons',
            condition(read('Name = \'O\\\'Brien AND Sons\''), 0).get('value'),
            'An escaped quote, and AND inside quotes, stay text'
        );
        Assert.areEqual(
            'Fund__r.Type__c',
            condition(read('Fund__r.Type__c = \'General\''), 0).get('field'),
            'One lookup away'
        );
    }

    @IsTest
    static void requiredConditionsAreAddedWithAnd() {
        List<Map<String, Object>> required = new List<Map<String, Object>>{
            new Map<String, Object>{ 'field' => 'Amount__c', 'operator' => 'is not null' }
        };
        Map<String, Object> alone = (Map<String, Object>) JSON.deserializeUntyped(
            RollupDlrsCriteria.toFilter(null, required)
        );
        Assert.areEqual('1', alone.get('logic'), 'Alone');
        Map<String, Object> joined = (Map<String, Object>) JSON.deserializeUntyped(
            RollupDlrsCriteria.toFilter('A__c = 1 OR B__c = 2', required)
        );
        Assert.areEqual('((1) OR (2)) AND 3', joined.get('logic'), 'Must hold as well');
        Assert.areEqual('3', condition(joined, 2).get('id'), 'Numbered after the criteria');
    }

    @IsTest
    static void whatTheFilterCannotHoldIsRefusedNamingThePart() {
        Map<String, String> partByCriteria = new Map<String, String>{
            'Id IN (SELECT Parent__c FROM Other__c)' => 'Id IN ( SELECT',
            'CALENDAR_YEAR(Date__c) = 2024' => 'CALENDAR_YEAR (',
            'Amount__c > Other__c' => 'Amount__c > Other__c',
            'Name LIKE \'%Smith\'' => 'Name LIKE \'%Smith\'',
            'Name LIKE \'Sm_th%\'' => 'Name LIKE \'Sm_th%\'',
            'Date__c > THIS_YEAR' => 'Date__c > THIS_YEAR',
            'A__c.B__r.C__c = 1' => 'A__c.B__r.C__c',
            'A__c = 1 B__c' => 'B__c',
            '(A__c = 1' => 'A__c = 1',
            'Name = \'unclosed' => 'unclosed',
            'Stage__c INCLUDES (\'A\')' => 'Stage__c INCLUDES'
        };
        for (String criteria : partByCriteria.keySet()) {
            String message = refusal(criteria);
            Assert.isNotNull(message, 'Refused: ' + criteria);
            Assert.isTrue(
                message.contains(partByCriteria.get(criteria)),
                criteria + ' names its part, not: ' + message
            );
        }
    }
}
