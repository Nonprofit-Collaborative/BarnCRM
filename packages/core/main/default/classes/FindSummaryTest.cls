/**
 * Find summaries (C-36, canonical model R-SQ9): one aggregate query in user mode over the
 * document's records, grouped by a checked field, and the refusals.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest(testFor='ApexClass:FindSummary')
private class FindSummaryTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static String query(Map<String, Object> aggregate) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'object' => 'Import_Batch__c',
                'fields' => new List<Object>{ 'Name' },
                'aggregate' => aggregate
            }
        );
    }

    /** 200 jobs: 150 Complete with 1 to 150 rows updated, 50 Failed with 10 rows updated. */
    private static void makeJobs() {
        List<Import_Batch__c> jobs = new List<Import_Batch__c>();
        for (Integer index = 0; index < 200; index++) {
            jobs.add(
                new Import_Batch__c(
                    Status__c = index < 150
                        ? ImportBatchService.STATUS_COMPLETE
                        : ImportBatchService.STATUS_FAILED,
                    Rows_Updated__c = index < 150 ? index + 1 : 10
                )
            );
        }
        insert jobs;
    }

    private static Map<String, Object> lineValues(FindSummary.SummaryResult result) {
        Map<String, Object> byGroup = new Map<String, Object>();
        for (FindSummary.SummaryLine line : result.lines) {
            byGroup.put(line.groupValue, line.value);
        }
        return byGroup;
    }

    private static void expectRefusal(Map<String, Object> aggregate, String expected) {
        try {
            FindSummary.summarize(query(aggregate));
            System.Assert.fail('Refused: ' + aggregate);
        } catch (QueryCompiler.QueryCompilerException refused) {
            System.Assert.areEqual(expected, refused.getMessage(), 'The refusal says why');
        }
    }

    @IsTest
    static void countsTwoHundredRecordsByGroup() {
        System.runAs(TestUsers.admin()) {
            makeJobs();

            Test.startTest();
            FindSummary.SummaryResult result = FindSummary.summarize(
                query(new Map<String, Object>{ 'function' => 'count', 'groupBy' => 'Status__c' })
            );
            Test.stopTest();

            Map<String, Object> byGroup = lineValues(result);
            System.Assert.areEqual(
                150,
                byGroup.get(ImportBatchService.STATUS_COMPLETE),
                'Complete'
            );
            System.Assert.areEqual(50, byGroup.get(ImportBatchService.STATUS_FAILED), 'Failed');
            System.Assert.isTrue(
                result.soql.startsWith('SELECT Status__c grp, COUNT(Id) val FROM Import_Batch__c'),
                'The SOQL shown: ' + result.soql
            );
            System.Assert.isTrue(
                result.soql.endsWith(
                    'GROUP BY Status__c ORDER BY Status__c NULLS FIRST LIMIT 2000'
                ),
                'Grouped and ordered: ' + result.soql
            );
            System.Assert.isFalse(result.capped, 'Two groups are not capped');
        }
    }

    @IsTest
    static void totalsLowestAndHighestOverTheDocumentsRecords() {
        System.runAs(TestUsers.admin()) {
            makeJobs();

            Test.startTest();
            FindSummary.SummaryResult total = FindSummary.summarize(
                query(new Map<String, Object>{ 'function' => 'sum', 'field' => 'Rows_Updated__c' })
            );
            FindSummary.SummaryResult highest = FindSummary.summarize(
                query(
                    new Map<String, Object>{
                        'function' => 'MAX',
                        'field' => 'Rows_Updated__c',
                        'groupBy' => 'Status__c'
                    }
                )
            );
            Test.stopTest();

            System.Assert.areEqual(1, total.lines.size(), 'No group is one line');
            System.Assert.areEqual(
                Decimal.valueOf(150 * 151 / 2 + 50 * 10),
                (Decimal) total.lines[0].value,
                'The total of every record'
            );
            System.Assert.isNull(total.lines[0].groupValue, 'The one line has no group');
            Map<String, Object> byGroup = lineValues(highest);
            System.Assert.areEqual(
                150,
                ((Decimal) byGroup.get(ImportBatchService.STATUS_COMPLETE)).intValue(),
                'Highest of the completed jobs'
            );
        }
    }

    @IsTest
    static void fieldsThatCannotBeMeasuredOrGroupedAreRefused() {
        System.runAs(TestUsers.admin()) {
            expectRefusal(
                new Map<String, Object>{ 'function' => 'average' },
                System.Label.Core_Find_ErrorSummary
            );
            String runLogLabel = Schema.SObjectType.Import_Batch__c.fields.Run_Log__c.getLabel();
            expectRefusal(
                new Map<String, Object>{ 'function' => 'sum', 'field' => 'Run_Log__c' },
                String.format(
                    System.Label.Core_Find_ErrorSummaryField,
                    new List<Object>{ runLogLabel }
                )
            );
            expectRefusal(
                new Map<String, Object>{ 'function' => 'count', 'groupBy' => 'Run_Log__c' },
                String.format(
                    System.Label.Core_Find_ErrorSummaryGroup,
                    new List<Object>{ runLogLabel }
                )
            );
            expectRefusal(
                new Map<String, Object>{
                    'function' => 'sum',
                    'field' => 'Rows_Updated__c; DELETE'
                },
                String.format(
                    System.Label.Core_Filter_ErrorUnknownField,
                    new List<Object>{ 'Rows_Updated__c; DELETE' }
                )
            );
        }
    }

    @IsTest
    static void theControllerSummarizesForAPersonWithFind() {
        System.runAs(TestUsers.admin()) {
            makeJobs();
            User maria = TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
            FindSummary.SummaryResult result;

            System.runAs(maria) {
                result = FindController.summarize(
                    query(new Map<String, Object>{ 'function' => 'count' })
                );
            }

            System.Assert.areEqual(1, result.lines.size(), 'One line');
            System.Assert.isTrue(
                Integer.valueOf(result.lines[0].value) <= 200,
                'Counted with her own access'
            );
        }
    }
}
