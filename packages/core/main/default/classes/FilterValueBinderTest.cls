/**
 * The bound rendering of the R-R2 filter document (Find, C-34): fields from the user's describe,
 * operators that suit the type, values typed and bound, never concatenated.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
// runs-as: deploying user (pure logic: parses a filter document against describe, no DML or SOQL)
@IsTest
private class FilterValueBinderTest {
    private static FilterValueBinder bind(String objectName, String conditions, String logic) {
        String document =
            '{"version": 1, ' +
            (logic == null ? '' : '"logic": "' + logic + '", ') +
            '"conditions": [' +
            conditions +
            ']}';
        return RollupFilterParser.toBoundClause(document, objectName);
    }

    @IsTest
    static void everyValueIsABindVariableOfTheFieldsType() {
        FilterValueBinder bound = bind(
            'Affiliation__c',
            '{"id": 1, "field": "Role__c", "operator": "equals", "value": "O\'Brien"},' +
                '{"id": 2, "field": "Start_Date__c", "operator": "greater or equal", "value": "2026-01-01"},' +
                '{"id": 3, "field": "Is_Primary__c", "operator": "equals", "value": true}',
            null
        );

        System.Assert.areEqual(
            'Role__c = :fb0 AND Start_Date__c >= :fb1 AND Is_Primary__c = :fb2',
            bound.clause,
            'Nothing typed is in the clause'
        );
        System.Assert.areEqual('O\'Brien', bound.binds.get('fb0'), 'Text is bound as typed');
        System.Assert.areEqual(
            Date.newInstance(2026, 1, 1),
            bound.binds.get('fb1'),
            'A date is a Date'
        );
        System.Assert.areEqual(true, bound.binds.get('fb2'), 'A checkbox is a Boolean');
        System.Assert.areEqual(
            'Role__c = \'O\\\'Brien\' AND Start_Date__c >= 2026-01-01 AND Is_Primary__c = true',
            bound.display(),
            'The display rendering writes the values in, escaped'
        );
    }

    @IsTest
    static void listsLikeAndRelativeDatesRenderAsSoqlExpects() {
        FilterValueBinder bound = bind(
            'Error_Log__c',
            '{"id": 1, "field": "Severity__c", "operator": "not in", "value": ["Info", "Warning"]},' +
                '{"id": 2, "field": "Context__c", "operator": "does not contain", "value": "50%_off"},' +
                '{"id": 3, "field": "Timestamp__c", "operator": "last n days", "value": 30},' +
                '{"id": 4, "field": "User__r.Name", "operator": "starts with", "value": "Ma"}',
            '(1 OR 2) AND NOT 3 AND 4'
        );

        System.Assert.areEqual(
            '( (Severity__c NOT IN :fb0) OR ((NOT Context__c LIKE :fb1)) ) AND NOT ' +
            '(Timestamp__c = LAST_N_DAYS:30) AND (User__r.Name LIKE :fb2)',
            bound.clause,
            'The logic string shapes bound conditions as it shapes literal ones'
        );
        System.Assert.areEqual(
            new List<String>{ 'Info', 'Warning' },
            bound.binds.get('fb0'),
            'A list is bound as a typed list'
        );
        System.Assert.areEqual(
            '%50\\%\\_off%',
            bound.binds.get('fb1'),
            'Wildcards a person typed match themselves'
        );
    }

    @IsTest
    static void refusesAFieldTheUserCannotSeeOrAnOperatorThatDoesNotSuitIt() {
        Map<String, String> refused = new Map<String, String>{
            'unknown field' => '{"id": 1, "field": "No_Such__c", "operator": "equals", "value": "x"}',
            'contains on a date' => '{"id": 1, "field": "Timestamp__c", "operator": "contains", "value": "x"}',
            'long text' => '{"id": 1, "field": "Message__c", "operator": "equals", "value": "x"}',
            'not a datetime' => '{"id": 1, "field": "Timestamp__c", "operator": "equals", "value": "soon"}',
            'not an Id' => '{"id": 1, "field": "User__c", "operator": "equals", "value": "x OR Id != null"}',
            'empty list' => '{"id": 1, "field": "Severity__c", "operator": "in", "value": []}'
        };
        for (String reason : refused.keySet()) {
            try {
                bind('Error_Log__c', refused.get(reason), null);
                System.Assert.fail('Must be refused: ' + reason);
            } catch (RollupFilterParser.RollupFilterException expected) {
                System.Assert.isTrue(
                    String.isNotBlank(expected.getMessage()),
                    'The refusal says what to fix: ' + reason
                );
            }
        }
    }

    @IsTest
    static void anEmptyDocumentBindsNothing() {
        FilterValueBinder bound = RollupFilterParser.toBoundClause(null, 'Error_Log__c');

        System.Assert.areEqual('', bound.clause, 'No conditions means every record');
        System.Assert.isTrue(bound.binds.isEmpty(), 'Nothing to bind');
    }
}
