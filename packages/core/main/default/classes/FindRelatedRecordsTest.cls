/**
 * Related records in Find (C-36, canonical model R-SQ8): semi-joins and anti-joins with their
 * own bound filters, related record columns as subqueries, and the refusals. Data jobs and
 * their journal pages stand in for any parent and child, since Core owns both.
 *
 * No org has run these yet; they are written against the behaviour the classes document.
 */
@IsTest
private class FindRelatedRecordsTest {
    private static final String UNDO_ONLY = '{"version": 1, "conditions": [{"id": 1, "field": "Phase__c", "operator": "equals", "value": "Undo"}]}';

    private static String query(List<Object> related, List<Object> children) {
        Map<String, Object> document = new Map<String, Object>{
            'version' => 1,
            'object' => 'Import_Batch__c',
            'fields' => new List<Object>{ 'Name' },
            'limit' => 2000
        };
        if (related != null) {
            document.put('related', related);
        }
        if (children != null) {
            document.put('children', children);
        }
        return JSON.serialize(document);
    }

    private static Map<String, Object> journals(Boolean has, String filter) {
        Map<String, Object> entry = new Map<String, Object>{
            'object' => 'Import_Journal__c',
            'field' => 'Import_Batch__c',
            'has' => has
        };
        if (filter != null) {
            entry.put('filter', JSON.deserializeUntyped(filter));
        }
        return entry;
    }

    /** 200 jobs: the first 100 have a commit page, and the first 50 of those an undo page too. */
    private static List<Import_Batch__c> makeJobs() {
        List<Import_Batch__c> jobs = new List<Import_Batch__c>();
        for (Integer index = 0; index < 200; index++) {
            jobs.add(new Import_Batch__c());
        }
        insert jobs;
        List<Import_Journal__c> pages = new List<Import_Journal__c>();
        for (Integer index = 0; index < 100; index++) {
            pages.add(new Import_Journal__c(Import_Batch__c = jobs[index].Id, Phase__c = 'Commit'));
            if (index < 50) {
                pages.add(
                    new Import_Journal__c(Import_Batch__c = jobs[index].Id, Phase__c = 'Undo')
                );
            }
        }
        insert pages;
        return jobs;
    }

    private static void expectRefusal(String document, String expected) {
        try {
            QueryCompiler.compile(document);
            System.Assert.fail('Refused: ' + document);
        } catch (QueryCompiler.QueryCompilerException refused) {
            System.Assert.areEqual(expected, refused.getMessage(), 'The refusal says why');
        }
    }

    @IsTest
    static void aSemiJoinKeepsTheRecordsWithMatchingRelatedRecords() {
        makeJobs();

        Test.startTest();
        QueryCompiler.Compiled compiled = QueryCompiler.compile(
            query(new List<Object>{ journals(true, UNDO_ONLY) }, null)
        );
        List<SObject> rows = QueryCompiler.run(compiled);
        Test.stopTest();

        System.Assert.isTrue(
            compiled.soql.contains(
                'Id IN (SELECT Import_Batch__c FROM Import_Journal__c WHERE (Phase__c = :rj0_0))'
            ),
            'The related filter is a semi-join with its own bind names: ' + compiled.soql
        );
        System.Assert.areEqual('Undo', compiled.binds.get('rj0_0'), 'The value is bound');
        System.Assert.isTrue(
            compiled.display.contains('WHERE (Phase__c = \'Undo\'))'),
            'The display writes the value in: ' + compiled.display
        );
        System.Assert.areEqual(50, rows.size(), 'Only the jobs with an undo page');
    }

    @IsTest
    static void anAntiJoinKeepsTheRecordsWithNoRelatedRecords() {
        makeJobs();

        Test.startTest();
        List<SObject> rows = QueryCompiler.run(
            QueryCompiler.compile(query(new List<Object>{ journals(false, null) }, null))
        );
        Integer counted = QueryCompiler.count(
            query(new List<Object>{ journals(false, null) }, null),
            1000
        );
        Test.stopTest();

        System.Assert.areEqual(100, rows.size(), 'The jobs with no journal page at all');
        System.Assert.areEqual(100, counted, 'A count reads the same records');
    }

    @IsTest
    static void twoRelatedConditionsKeepTheirBindsApart() {
        makeJobs();
        String commitOnly = UNDO_ONLY.replace('Undo', 'Commit');

        QueryCompiler.Compiled compiled = QueryCompiler.compile(
            query(new List<Object>{ journals(true, commitOnly), journals(false, UNDO_ONLY) }, null)
        );

        System.Assert.areEqual('Commit', compiled.binds.get('rj0_0'), 'The first entry');
        System.Assert.areEqual('Undo', compiled.binds.get('rj1_0'), 'The second entry');
        System.Assert.areEqual(
            50,
            QueryCompiler.run(compiled).size(),
            'A commit page and no undo page'
        );
    }

    @IsTest
    static void aRelatedRecordColumnListsTheNewestRelatedRecords() {
        makeJobs();
        Map<String, Object> column = new Map<String, Object>{
            'relationship' => 'Import_Journals__r',
            'fields' => new List<Object>{ 'Phase__c', 'Entry_Count__c' },
            'limit' => 1
        };

        Test.startTest();
        QueryCompiler.Compiled compiled = QueryCompiler.compile(
            query(null, new List<Object>{ column })
        );
        List<SObject> rows = QueryCompiler.run(compiled);
        Test.stopTest();

        System.Assert.isTrue(
            compiled.soql.contains(
                '(SELECT Id, Phase__c, Entry_Count__c FROM Import_Journals__r ORDER BY CreatedDate DESC LIMIT 1)'
            ),
            'The column is a subquery: ' + compiled.soql
        );
        Integer withPages = 0;
        for (SObject row : rows) {
            List<SObject> pages = row.getSObjects('Import_Journals__r');
            if (pages != null && !pages.isEmpty()) {
                System.Assert.areEqual(1, pages.size(), 'At most the limit per record');
                withPages++;
            }
        }
        System.Assert.areEqual(100, withPages, 'Every job with a journal page shows one');
        System.Assert.isFalse(
            QueryCompiler.compileSelection(
                    query(null, new List<Object>{ column }),
                    new Set<String>{ 'Id' },
                    null
                )
                .soql.contains('(SELECT'),
            'A bulk update selection ignores related record columns'
        );
    }

    @IsTest
    static void namesThatAreNotRelatedRecordsAreRefused() {
        expectRefusal(
            query(
                new List<Object>{
                    new Map<String, Object>{
                        'object' => 'Error_Log__c',
                        'field' => 'User__c',
                        'has' => true
                    }
                },
                null
            ),
            String.format(
                System.Label.Core_Find_ErrorRelated,
                new List<Object>{ 'Error_Log__c.User__c' }
            )
        );
        expectRefusal(
            query(
                new List<Object>{
                    new Map<String, Object>{ 'object' => 'No_Such_Object__c', 'field' => 'X__c' }
                },
                null
            ),
            String.format(
                System.Label.Core_Find_ErrorRelated,
                new List<Object>{ 'No_Such_Object__c' }
            )
        );
        expectRefusal(
            query(
                null,
                new List<Object>{ new Map<String, Object>{ 'relationship' => 'Nothing_Here' } }
            ),
            String.format(System.Label.Core_Find_ErrorRelated, new List<Object>{ 'Nothing_Here' })
        );
        expectRefusal(
            query(
                null,
                new List<Object>{
                    new Map<String, Object>{
                        'relationship' => 'Import_Journals__r',
                        'fields' => new List<Object>{ 'Phase__c' },
                        'limit' => 11
                    }
                }
            ),
            System.Label.Core_Find_ErrorChildColumn
        );
        expectRefusal(
            query(
                new List<Object>{
                    journals(true, null),
                    journals(true, null),
                    journals(false, null)
                },
                null
            ),
            System.Label.Core_Find_ErrorRelatedCount
        );
    }

    @IsTest
    static void theRelatedRecordListNamesEachLookup() {
        User maria = TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });

        System.runAs(maria) {
            List<FindRelatedRecords.ChildOption> options = FindController.listChildRelationships(
                'Import_Batch__c'
            );
            FindRelatedRecords.ChildOption journalsOption = null;
            for (FindRelatedRecords.ChildOption option : options) {
                if (option.relationshipName == 'Import_Journals__r') {
                    journalsOption = option;
                }
            }
            System.Assert.isNotNull(journalsOption, 'The journal is offered: ' + options);
            System.Assert.areEqual('Import_Journal__c', journalsOption.objectName, 'Its object');
            System.Assert.areEqual('Import_Batch__c', journalsOption.field, 'Its lookup');
            System.Assert.isTrue(journalsOption.filterable, 'It can be a condition');
        }
    }
}
