/**
 * The Find tab's controller (C-34, canonical model Section 29D): the permission, running and
 * exporting as the user, and saved queries that are private until shared.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest(critical=true)
private class FindControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String ERRORS_ONLY =
        '{"version": 1, "object": "Error_Log__c", "fields": ["Context__c", "Severity__c"], ' +
        '"filter": {"version": 1, "conditions": [{"id": 1, "field": "Severity__c", "operator": "equals", "value": "Error"}]}, ' +
        '"orderBy": [{"field": "Context__c", "direction": "ASC"}], "limit": 2000}';

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static User david() {
        return TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Find_And_Export' });
    }

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
    static void withoutThePermissionFindSaysWhichOneIsMissing() {
        System.runAs(TestUsers.admin()) {
            User sam = TestDataFactory.createUser('Sam', new List<String>{ 'BarnCRM_Staff' });

            System.runAs(sam) {
                try {
                    FindController.getPage();
                    System.Assert.fail('Find needs its permission');
                } catch (AuraHandledException refused) {
                    System.Assert.areEqual(
                        System.Label.Core_Find_ErrorNoPermission,
                        refused.getMessage(),
                        'The message names the permission'
                    );
                }
            }

        }
    }

    @IsTest
    static void runsAQueryOverTwoHundredRecordsAndShowsItsSoql() {
        System.runAs(TestUsers.admin()) {
            makeLogs(200, 30);
            User maria = maria();

            Test.startTest();
            FindController.QueryResult result;
            System.runAs(maria) {
                result = FindController.runQuery(ERRORS_ONLY);
            }
            Test.stopTest();

            System.Assert.areEqual(200, result.rows.size(), 'Only matching records come back');
            System.Assert.isTrue(
                result.soql.contains('WHERE (Severity__c = \'Error\')'),
                'The SOQL shown has the value written in: ' + result.soql
            );
        }
    }

    @IsTest
    static void exportReadsPagesInIdOrderUntilDone() {
        System.runAs(TestUsers.admin()) {
            makeLogs(200, 0);
            User maria = maria();

            FindController.QueryResult page;
            System.runAs(maria) {
                page = FindController.exportPage(ERRORS_ONLY, null);
            }

            System.Assert.areEqual(200, page.rows.size(), 'One page holds every row here');
            System.Assert.isTrue(page.done, 'A short page is the last one');
            System.Assert.areEqual(
                String.valueOf(page.rows[199].Id),
                page.lastId,
                'The next page starts here'
            );
        }
    }

    @IsTest
    static void aSavedQueryIsPrivateUntilShared() {
        System.runAs(TestUsers.admin()) {
            User maria = maria();
            User david = david();

            FindController.FindPage saved;
            System.runAs(maria) {
                saved = FindController.saveQuery(null, 'Errors to review', ERRORS_ONLY, false);
            }
            System.Assert.areEqual(1, saved.savedQueries.size(), 'Maria sees her query');
            System.Assert.isTrue(saved.savedQueries[0].mine, 'As her own');
            System.Assert.isTrue(
                saved.savedQueries[0].objectName.endsWith('Error_Log__c'),
                'The object is copied from the document'
            );
            String recordId = saved.savedQueries[0].recordId;

            System.runAs(david) {
                System.Assert.isTrue(
                    FindController.getPage().savedQueries.isEmpty(),
                    'An unshared query is not David\'s to see'
                );
            }

            System.runAs(maria) {
                FindController.saveQuery(recordId, 'Errors to review', ERRORS_ONLY, true);
            }
            System.runAs(david) {
                List<FindController.SavedQueryView> shared = FindController.getPage().savedQueries;
                System.Assert.areEqual(1, shared.size(), 'A shared query is listed for David');
                System.Assert.isFalse(shared[0].mine, 'As someone else\'s');
                try {
                    FindController.deleteQuery(recordId);
                    System.Assert.fail('Only the owner may delete it');
                } catch (AuraHandledException refused) {
                    System.Assert.areEqual(
                        System.Label.Core_Find_ErrorNotYours,
                        refused.getMessage(),
                        'And he is told to save a copy'
                    );
                }
            }

            System.runAs(maria) {
                FindController.saveQuery(recordId, 'Errors to review', ERRORS_ONLY, false);
            }
            System.runAs(david) {
                System.Assert.isTrue(
                    FindController.getPage().savedQueries.isEmpty(),
                    'Unsharing takes it away again'
                );
            }

        }
    }

    @IsTest
    static void aQueryThatWouldNotRunOrHasNoNameIsNotSaved() {
        System.runAs(TestUsers.admin()) {
            User maria = maria();
            System.runAs(maria) {
                for (
                    List<String> attempt : new List<List<String>>{
                        new List<String>{ '', ERRORS_ONLY },
                        new List<String>{
                            'Broken',
                            '{"version": 1, "object": "Error_Log__c", "fields": ["Nope__c"]}'
                        }
                    }
                ) {
                    try {
                        FindController.saveQuery(null, attempt[0], attempt[1], false);
                        System.Assert.fail('Must not be saved: ' + attempt[0]);
                    } catch (AuraHandledException refused) {
                        System.Assert.isTrue(
                            String.isNotBlank(refused.getMessage()),
                            'The refusal says what to fix'
                        );
                    }
                }
                System.Assert.isTrue(
                    FindController.getPage().savedQueries.isEmpty(),
                    'Nothing saved'
                );
            }

        }
    }

    @IsTest
    static void sharingTwoHundredQueriesAtOnceWritesOneShareEach() {
        System.runAs(TestUsers.admin()) {
            List<Saved_Query__c> queries = new List<Saved_Query__c>();
            for (Integer index = 0; index < 200; index++) {
                queries.add(
                    new Saved_Query__c(
                        Name = 'Query ' + index,
                        Object_Name__c = 'Error_Log__c',
                        Query_JSON__c = ERRORS_ONLY
                    )
                );
            }
            insert queries;
            Map<Id, Boolean> sharedById = new Map<Id, Boolean>();
            for (Saved_Query__c query : queries) {
                sharedById.put(query.Id, true);
            }

            Test.startTest();
            SavedQuerySharingWriter.setShared(sharedById);
            SavedQuerySharingWriter.setShared(sharedById);
            Test.stopTest();

            String reason = Schema.Saved_Query__Share.RowCause.Shared_With_Find_Users__c;
            System.Assert.areEqual(
                200,
                [SELECT COUNT() FROM Saved_Query__Share WHERE RowCause = :reason],
                'One share per query, and sharing again adds none'
            );

            for (Id queryId : sharedById.keySet()) {
                sharedById.put(queryId, false);
            }
            SavedQuerySharingWriter.setShared(sharedById);
            System.Assert.areEqual(
                0,
                [SELECT COUNT() FROM Saved_Query__Share WHERE RowCause = :reason],
                'Unsharing removes them all'
            );
        }
    }

    @IsTest
    static void theObjectListLeavesOutCustomSettingsAndTheExportLimitHasADefault() {
        System.runAs(TestUsers.admin()) {
            User maria = maria();
            System.runAs(maria) {
                Set<String> names = new Set<String>();
                for (FindController.Option option : FindController.listObjects()) {
                    names.add(option.value.toLowerCase());
                }
                System.Assert.isFalse(names.isEmpty(), 'Maria can query something');
                for (String name : names) {
                    System.Assert.isFalse(
                        name.endsWith('barncrm_settings__c'),
                        'Settings are not offered'
                    );
                    System.Assert.isFalse(name.endsWith('__share'), 'Share tables are not offered');
                }
                System.Assert.areEqual(
                    FindController.DEFAULT_EXPORT_LIMIT,
                    FindController.getPage().exportLimit,
                    'The export limit reads as 50,000 until set'
                );
            }

        }
    }
}
