/**
 * The Auto-Merge area's server side (C-51): permission checks, a background run through
 * AutoMergeJob, the Recent Runs list, and undo of a run.
 */
@IsTest(testFor='ApexClass:AutoMergeController')
private class AutoMergeControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static List<Contact> twins(String firstName, Integer pairs) {
        List<Contact> people = new List<Contact>();
        for (Integer i = 0; i < pairs; i++) {
            String email = firstName.toLowerCase() + i + '@example.org';
            people.add(
                new Contact(FirstName = firstName + i, LastName = 'Automerge', Email = email)
            );
            people.add(
                new Contact(FirstName = firstName + i, LastName = 'Automerge', Email = email)
            );
        }
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.insert(people, options, AccessLevel.SYSTEM_MODE);
        AutoMergeService.pairsForTest = new List<List<Id>>();
        for (Integer i = 0; i < people.size(); i += 2) {
            AutoMergeService.pairsForTest.add(new List<Id>{ people[i].Id, people[i + 1].Id });
        }
        return people;
    }

    private static Boolean canReviewSuggestions() {
        return Schema.SObjectType.DuplicateRecordSet.isAccessible() &&
            Schema.SObjectType.DuplicateRecordSet.isDeletable() &&
            Schema.SObjectType.DuplicateRecordItem.isAccessible();
    }

    @IsTest
    static void withoutManageSettingsEverythingIsRefused() {
        System.runAs(TestUsers.standardUser('Automergeless')) {
            for (Integer action = 0; action < 4; action++) {
                try {
                    if (action == 0) {
                        AutoMergeController.getView();
                    } else if (action == 1) {
                        AutoMergeController.preview();
                    } else if (action == 2) {
                        AutoMergeController.startRun();
                    } else {
                        AutoMergeController.undoRun('run');
                    }
                    Assert.fail('Action ' + action + ' is refused.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        Label.Core_Duplicates_ErrorPermissionRequired,
                        expected.getMessage()
                    );
                }
            }
        }
    }

    @IsTest
    static void aRunMergesInTheBackgroundAndIsListed() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twins('Run', 3);
            if (!canReviewSuggestions()) {
                // Skipped: duplicate record sets are licensed to Sales and Service Cloud only.
                try {
                    AutoMergeController.preview();
                    Assert.fail('Without Duplicate Review access a preview is refused.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        Label.Core_Duplicates_ErrorNoSuggestionAccess,
                        expected.getMessage()
                    );
                }
                return;
            }

            AutoMergeController.PreviewView preview = AutoMergeController.preview();
            Assert.areEqual(3, preview.total);
            Assert.areEqual(AutoMergeService.NAME_AND_EMAIL, preview.exactRule);

            Test.startTest();
            AutoMergeController.startRun();
            Test.stopTest();

            Assert.areEqual(3, [SELECT COUNT() FROM Contact WHERE Id IN :people WITH SYSTEM_MODE]);
            AutoMergeController.PanelView view = AutoMergeController.getView();
            Assert.areEqual(1, view.runs.size());
            Assert.areEqual(3, view.runs[0].merged);
            Assert.isTrue(view.runs[0].canUndo);
            Assert.isFalse(view.running);
        }
    }

    @IsTest
    static void undoRunRestoresTheRunInTheBackground() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twins('Undo', 2);
            AutoMergeService.mergeAll(AutoMergeService.candidates(), 'run-undo');
            Assert.areEqual(2, [SELECT COUNT() FROM Contact WHERE Id IN :people WITH SYSTEM_MODE]);

            Test.startTest();
            AutoMergeController.undoRun('run-undo');
            Test.stopTest();

            Assert.areEqual(4, [SELECT COUNT() FROM Contact WHERE Id IN :people WITH SYSTEM_MODE]);
            AutoMergeController.PanelView view = AutoMergeController.getView();
            Assert.areEqual(2, view.runs[0].undone);
            Assert.isFalse(view.runs[0].canUndo, 'Nothing is left to undo.');
            try {
                AutoMergeController.undoRun('run-undo');
                Assert.fail('A run undone already is refused.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(Label.Core_AutoMerge_ErrorNoUndo, expected.getMessage());
            }
        }
    }

    @IsTest
    static void aRunWithNothingToMergeIsRefused() {
        System.runAs(TestUsers.admin()) {
            AutoMergeService.pairsForTest = new List<List<Id>>();
            if (!canReviewSuggestions()) {
                // Skipped: duplicate record sets are licensed to Sales and Service Cloud only.
                return;
            }
            try {
                AutoMergeController.startRun();
                Assert.fail('Nothing to merge is refused.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(Label.Core_AutoMerge_ErrorNothing, expected.getMessage());
            }
        }
    }

    @IsTest
    static void theJobCountsWhatItMergedAndSkipped() {
        System.runAs(TestUsers.admin()) {
            twins('Job', 2);
            List<String> refs = new List<String>();
            for (AutoMergeService.Candidate pair : AutoMergeService.candidates()) {
                refs.add(pair.ref);
            }
            refs.add(refs[0]);

            Test.startTest();
            AutoMergeJob.startMerge(refs);
            Test.stopTest();

            Error_Log__c summary = [
                SELECT Message__c
                FROM Error_Log__c
                WHERE Context__c = :AutoMergeJob.LOG_CONTEXT
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            Assert.isTrue(
                summary.Message__c.contains('2 pairs merged, 1 skipped'),
                summary.Message__c
            );
        }
    }
}
