/**
 * The dispatcher's error contract inside a real trigger (ADR-0165 dispatcher error contract): a
 * handler failure refuses only the records it belongs to, and the rest of the save goes ahead.
 *
 * Each test makes `TestFailingHandler` the whole Contact registry and saves five people, one or
 * two of them named so the handler fails for them, with a partial save (allOrNone false) as the
 * Data Loader and the Bulk API save.
 */
@IsTest(testFor='ApexClass:TriggerDispatcher')
private class TriggerDispatcherPartialSaveTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static void registerFailingHandler(Boolean alwaysRuns) {
        Automation_Registry__mdt entry = TestDataFactory.registryEntry('Failing_Test', true);
        entry.Handler_Class__c = 'TestFailingHandler';
        entry.Object_Name__c = 'Contact';
        entry.Always_Runs__c = alwaysRuns;
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{ entry };
        TestFailingHandler.attempts = 0;
    }

    private static List<Contact> people(List<String> lastNames) {
        List<Contact> result = new List<Contact>();
        for (String lastName : lastNames) {
            result.add(new Contact(FirstName = 'Test', LastName = lastName));
        }
        return result;
    }

    private static Integer failures(List<Database.SaveResult> results) {
        Integer failed = 0;
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                failed++;
                Assert.areEqual(
                    Label.Core_Automation_UnexpectedError,
                    result.getErrors()[0].getMessage(),
                    'A refused record carries the friendly message.'
                );
            }
        }
        return failed;
    }

    @IsTest
    static void aBeforeFailureRefusesOnlyItsRecord() {
        System.runAs(TestUsers.admin()) {
            registerFailingHandler(false);
            TestFailingHandler.failIn = 'before';
            List<Contact> batch = people(
                new List<String>{ 'Avery', 'Blake', 'Refuse Casey', 'Drew', 'Emery' }
            );

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(batch, false);
            Test.stopTest();

            Assert.areEqual(1, failures(results), 'Only the failing record is refused.');
            Assert.isFalse(results[2].isSuccess(), 'The refused record is the one that failed.');
            List<Contact> saved = [
                SELECT LastName, Description
                FROM Contact
                WHERE FirstName = 'Test'
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(4, saved.size(), 'The other four people are saved.');
            for (Contact person : saved) {
                Assert.areEqual(
                    TestFailingHandler.SEEN,
                    person.Description,
                    'Every saved person had the handler work done.'
                );
            }
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'Failing_Test' AND Severity__c = :ErrorLogger.SEVERITY_ERROR
                    WITH SYSTEM_MODE
                ],
                'The failure itself is logged once, with its technical detail.'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE
                        Context__c = 'Trigger dispatch: Contact'
                        AND Severity__c = :ErrorLogger.SEVERITY_WARNING
                    WITH SYSTEM_MODE
                ],
                'The refused record is logged by its row.'
            );
        }
    }

    @IsTest
    static void anAfterFailureRefusesOnlyItsRecordAndUndoesTheFailedWork() {
        System.runAs(TestUsers.admin()) {
            registerFailingHandler(false);
            TestFailingHandler.failIn = 'after';
            List<Contact> batch = people(
                new List<String>{ 'Avery', 'Refuse Blake', 'Casey', 'Drew', 'Refuse Emery' }
            );

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(batch, false);
            Test.stopTest();

            Assert.areEqual(2, failures(results), 'Only the two failing records are refused.');
            Assert.areEqual(
                3,
                [SELECT COUNT() FROM Contact WHERE FirstName = 'Test' WITH SYSTEM_MODE],
                'The other three people are saved.'
            );
            List<Saved_Query__c> notes = [
                SELECT Name
                FROM Saved_Query__c
                WHERE Object_Name__c = 'Contact'
                WITH SYSTEM_MODE
            ];
            Set<String> names = new Set<String>();
            for (Saved_Query__c note : notes) {
                names.add(note.Name);
            }
            Assert.areEqual(
                new Set<String>{ 'Avery', 'Casey', 'Drew' },
                names,
                'The work of every failed attempt is undone, and each saved person has it once.'
            );
            Assert.areEqual(3, notes.size(), 'No saved person has the after work twice.');
        }
    }

    @IsTest
    static void anAllOrNothingSaveNamesOnlyTheFailingRecord() {
        System.runAs(TestUsers.admin()) {
            registerFailingHandler(false);
            TestFailingHandler.failIn = 'before';
            List<Contact> batch = people(
                new List<String>{ 'Avery', 'Blake', 'Casey', 'Refuse Drew' }
            );
            DmlException refused;

            Test.startTest();
            try {
                Database.insert(batch, true);
            } catch (DmlException expected) {
                refused = expected;
            }
            Test.stopTest();

            Assert.isNotNull(refused, 'An all or nothing save with a failing record is refused.');
            Assert.areEqual(1, refused.getNumDml(), 'Only the failing record carries the error.');
            Assert.areEqual(3, refused.getDmlIndex(0), 'The error is on the failing row.');
        }
    }

    @IsTest
    static void anAlwaysRunsFailureStillRefusesEveryRecord() {
        System.runAs(TestUsers.admin()) {
            registerFailingHandler(true);
            TestFailingHandler.failIn = 'before';
            List<Contact> batch = people(new List<String>{ 'Avery', 'Refuse Blake', 'Casey' });

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(batch, false);
            Test.stopTest();

            Assert.areEqual(
                3,
                failures(results),
                'An integrity rule that could not be checked lets no record through.'
            );
            Assert.areEqual(
                1,
                TestFailingHandler.attempts,
                'A failing always-run rule is not run again to narrow it.'
            );
        }
    }

    @IsTest
    static void withNoRoomLeftEveryOpenRecordIsRefused() {
        System.runAs(TestUsers.admin()) {
            registerFailingHandler(false);
            TestFailingHandler.failIn = 'before';
            TriggerDispatcher.noRoomForTest = true;
            List<Contact> batch = people(new List<String>{ 'Avery', 'Refuse Blake', 'Casey' });

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(batch, false);
            Test.stopTest();

            Assert.areEqual(
                3,
                failures(results),
                'Without room to run the handlers again, the records not cleared are refused.'
            );
        }
    }

    @IsTest
    static void aSingleRecordIsRefusedWithoutRunningAgain() {
        System.runAs(TestUsers.admin()) {
            registerFailingHandler(false);
            TestFailingHandler.failIn = 'after';

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                people(new List<String>{ 'Refuse Avery' }),
                false
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                failures(results),
                'The one record is refused, in an after context.'
            );
            Assert.areEqual(
                2,
                TestFailingHandler.attempts,
                'One before and one after run: a single record is never run again.'
            );
        }
    }

    @IsTest
    static void aCleanSaveRunsEachHandlerOnce() {
        System.runAs(TestUsers.admin()) {
            registerFailingHandler(false);
            TestFailingHandler.failIn = 'after';

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                people(new List<String>{ 'Avery', 'Blake', 'Casey' }),
                false
            );
            Test.stopTest();

            Assert.areEqual(0, failures(results), 'Nothing fails.');
            Assert.areEqual(2, TestFailingHandler.attempts, 'One before and one after run.');
        }
    }
}
