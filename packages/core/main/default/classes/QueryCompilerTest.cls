/**
 * The Find query compiler (canonical model R-SQ1 and R-SQ2): names from describe, values bound,
 * user mode, export pages in Id order.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest
private class QueryCompilerTest {
    private static String query(String filter, String orderBy, Object rowLimit) {
        Map<String, Object> document = new Map<String, Object>{
            'version' => 1,
            'object' => 'Error_Log__c',
            'fields' => new List<Object>{ 'Context__c', 'Severity__c', 'User__r.Name' }
        };
        if (filter != null) {
            document.put('filter', JSON.deserializeUntyped(filter));
        }
        if (orderBy != null) {
            document.put('orderBy', JSON.deserializeUntyped(orderBy));
        }
        if (rowLimit != null) {
            document.put('limit', rowLimit);
        }
        return JSON.serialize(document);
    }

    private static final String ERRORS_ONLY = '{"version": 1, "conditions": [{"id": 1, "field": "Severity__c", "operator": "equals", "value": "Error"}]}';

    private static void makeLogs(Integer errors, Integer warnings) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer index = 0; index < errors + warnings; index++) {
            logs.add(
                new Error_Log__c(
                    Timestamp__c = System.now(),
                    Context__c = 'Find test ' + String.valueOf(index).leftPad(4, '0'),
                    Message__c = 'A test entry.',
                    Severity__c = index < errors ? 'Error' : 'Warning',
                    Status__c = 'New'
                )
            );
        }
        insert logs;
    }

    @IsTest
    static void compilesSelectWhereOrderAndLimitWithBinds() {
        QueryCompiler.Compiled compiled = QueryCompiler.compile(
            query(ERRORS_ONLY, '[{"field": "Context__c", "direction": "desc"}]', 50)
        );

        System.Assert.isTrue(
            compiled.soql.startsWith('SELECT Id, Context__c, Severity__c, User__r.Name FROM '),
            'Id comes first, then the columns in order: ' + compiled.soql
        );
        System.Assert.isTrue(
            compiled.soql.endsWith(
                'WHERE (Severity__c = :fb0) ORDER BY Context__c DESC NULLS LAST LIMIT :rowLimit'
            ),
            'The value and the row count are binds: ' + compiled.soql
        );
        System.Assert.areEqual('Error', compiled.binds.get('fb0'), 'The value is bound');
        System.Assert.areEqual(50, compiled.binds.get('rowLimit'), 'The row count is bound');
        System.Assert.isTrue(
            compiled.display.endsWith(
                'WHERE (Severity__c = \'Error\') ORDER BY Context__c DESC NULLS LAST LIMIT 50'
            ),
            'The display rendering writes the values in: ' + compiled.display
        );
    }

    @IsTest
    static void runsInUserModeOverTwoHundredRecords() {
        makeLogs(200, 20);

        Test.startTest();
        List<SObject> rows = QueryCompiler.run(
            QueryCompiler.compile(query(ERRORS_ONLY, null, 2000))
        );
        Test.stopTest();

        System.Assert.areEqual(200, rows.size(), 'Only the matching records come back');
        for (SObject row : rows) {
            System.Assert.areEqual('Error', row.get('Severity__c'), 'Each row matches the filter');
        }
    }

    @IsTest
    static void exportPagesInIdOrderAfterTheLastIdRead() {
        makeLogs(200, 0);
        String document = query(null, '[{"field": "Context__c", "direction": "DESC"}]', 10);

        List<SObject> firstPage = QueryCompiler.run(
            QueryCompiler.compileExportPage(document, null)
        );
        Id lastRead = firstPage[99].Id;
        List<SObject> rest = QueryCompiler.run(QueryCompiler.compileExportPage(document, lastRead));

        System.Assert.areEqual(200, firstPage.size(), 'A page ignores the grid row count');
        System.Assert.areEqual(100, rest.size(), 'The next page starts after the last Id read');
        System.Assert.isTrue(
            QueryCompiler.compileExportPage(document, lastRead)
                .soql.endsWith('WHERE Id > :afterId ORDER BY Id LIMIT :pageSize'),
            'Export pages order by Id, whatever the grid order is'
        );
    }

    @IsTest
    static void bulkUpdateCountsAtMostTheCapAndReadsChosenRecordsWithTheFilter() {
        makeLogs(200, 20);
        String document = query(ERRORS_ONLY, null, 10);

        System.Assert.areEqual(200, QueryCompiler.count(document, 1000), 'Only matches count');
        System.Assert.areEqual(150, QueryCompiler.count(document, 150), 'A count stops at the cap');

        Set<Id> chosen = new Map<Id, Error_Log__c>([SELECT Id FROM Error_Log__c]).keySet();
        QueryCompiler.Compiled selection = QueryCompiler.compileSelection(
            document,
            new Set<String>{ 'Message__c' },
            chosen
        );
        List<SObject> rows = QueryCompiler.run(selection);
        System.Assert.areEqual(200, rows.size(), 'Chosen records that do not match are left out');
        System.Assert.isTrue(
            selection.soql.startsWith('SELECT Id, Message__c FROM Error_Log__c WHERE'),
            'The document\'s columns and row count are ignored: ' + selection.soql
        );
        System.Assert.isTrue(
            selection.soql.endsWith('AND Id IN :onlyIds'),
            'The chosen records are bound: ' + selection.soql
        );
    }

    @IsTest
    static void refusesDocumentsOutsideTheRules() {
        Map<String, String> refused = new Map<String, String>{
            'not JSON' => 'SELECT Id FROM Account',
            'unknown object' => '{"version": 1, "object": "No_Such__c", "fields": ["Name"]}',
            'unknown field' => '{"version": 1, "object": "Error_Log__c", "fields": ["No_Such__c"]}',
            'injected field' => '{"version": 1, "object": "Error_Log__c", "fields": ["Id FROM User"]}',
            'no columns' => '{"version": 1, "object": "Error_Log__c", "fields": []}',
            'too many rows' => query(null, null, 2001),
            'bad direction' => query(null, '[{"field": "Context__c", "direction": "UP"}]', null),
            'unsortable' => query(null, '[{"field": "Message__c", "direction": "ASC"}]', null),
            'bad filter' => query(
                '{"version": 1, "conditions": [{"id": 1, "field": "Timestamp__c", "operator": "contains", "value": "x"}]}',
                null,
                null
            ),
            'future version' => '{"version": 2, "object": "Error_Log__c", "fields": ["Name"]}'
        };
        for (String reason : refused.keySet()) {
            try {
                QueryCompiler.compile(refused.get(reason));
                System.Assert.fail('Must be refused: ' + reason);
            } catch (QueryCompiler.QueryCompilerException expected) {
                System.Assert.isTrue(
                    String.isNotBlank(expected.getMessage()),
                    'The refusal says what to fix: ' + reason
                );
            }
        }
    }
}
