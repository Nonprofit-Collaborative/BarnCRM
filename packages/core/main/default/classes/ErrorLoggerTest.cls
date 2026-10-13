/**
 * What Maria reads when something fails, and the promise that logging never makes things worse.
 *
 * The two bulkification tests read `Limits.getPublishImmediateDML()`, not `Limits.getDmlStatements()`.
 * `ErrorLogWriter` records a failure by publishing an `Error_Log_Event__e` whose publish behavior is
 * Publish Immediately, and the platform meters those publishes on their own counter rather than on
 * the DML statement counter, which stays at zero on this path. The invariant being asserted is
 * unchanged: however many failures go in, one call goes out.
 */
@IsTest
private class ErrorLoggerTest {
    private class SampleException extends Exception {
    }

    private static Exception thrownException() {
        try {
            throw new SampleException('The pattern refers to a field this record does not have.');
        } catch (Exception caught) {
            return caught;
        }
    }

    @IsTest
    static void anExceptionBecomesSomethingMariaCanRead() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            ErrorLogger.log(thrownException(), 'Household naming');
            Test.stopTest();

            List<Error_Log__c> logged = [
                SELECT
                    Context__c,
                    Message__c,
                    Technical_Detail__c,
                    Severity__c,
                    Status__c,
                    Timestamp__c,
                    User__c,
                    Record_Reference__c,
                    Object_Name__c
                FROM Error_Log__c
            ];
            Assert.areEqual(1, logged.size(), 'One failure, one entry.');
            Error_Log__c entry = logged[0];
            Assert.areEqual('Household naming', entry.Context__c, 'Named in words, not in code.');
            Assert.areEqual(
                ErrorLogger.friendlyMessage('Household naming'),
                entry.Message__c,
                'What Maria reads is the plain language explanation, with no developer text in it.'
            );
            Assert.isTrue(
                entry.Message__c.contains('Household naming'),
                'And it names where it happened, so entries from different places differ.'
            );
            Assert.areEqual(
                Label.Core_ErrorLog_UnexpectedFailure,
                ErrorLogger.friendlyMessage(' '),
                'With nowhere to name, the plain explanation stands alone.'
            );
            Assert.isTrue(
                entry.Technical_Detail__c.contains('SampleException'),
                'The technical detail names the exception type.'
            );
            Assert.isTrue(
                entry.Technical_Detail__c.contains('The pattern refers to a field'),
                'And carries the words the exception itself used.'
            );
            Assert.areEqual(
                ErrorLogger.SEVERITY_ERROR,
                entry.Severity__c,
                'Severity defaults to Error.'
            );
            Assert.areEqual(ErrorLogger.STATUS_NEW, entry.Status__c, 'And status to New.');
            Assert.areEqual(UserInfo.getUserId(), entry.User__c, 'The person working is recorded.');
            Assert.isNotNull(entry.Timestamp__c, 'So is the time.');
            Assert.isNull(entry.Record_Reference__c, 'No record was named for this one.');
            Assert.isNull(entry.Object_Name__c, 'So there is nothing to group it by.');
        }
    }

    @IsTest
    static void anExceptionAboutARecordPointsAtThatRecord() {
        System.runAs(TestUsers.admin()) {
            Error_Log__c existing = TestDataFactory.insertErrorLogs(
                1,
                ErrorLogger.STATUS_RESOLVED
            )[0];

            Test.startTest();
            ErrorLogger.log(thrownException(), 'Household naming', existing.Id);
            Test.stopTest();

            List<Error_Log__c> logged = [
                SELECT Record_Reference__c, Object_Name__c
                FROM Error_Log__c
                WHERE Context__c = 'Household naming'
            ];
            Assert.areEqual(1, logged.size(), 'One entry for the failure.');
            Assert.areEqual(
                String.valueOf(existing.Id),
                logged[0].Record_Reference__c,
                'Maria can open the record from the entry.'
            );
            Assert.areEqual(
                'Error_Log__c',
                logged[0].Object_Name__c,
                'And can group entries by what they affect.'
            );
        }
    }

    @IsTest
    static void twoHundredFailuresCostOneStatement() {
        System.runAs(TestUsers.admin()) {
            List<String> messages = new List<String>();
            for (Integer i = 0; i < 200; i++) {
                messages.add('Row ' + i + ' could not be saved because its household is missing.');
            }

            Test.startTest();
            Integer statementsBefore = Limits.getPublishImmediateDML();
            ErrorLogger.logMessages(messages, 'Spreadsheet import', ErrorLogger.SEVERITY_WARNING);
            Integer statementsAfter = Limits.getPublishImmediateDML();
            Test.stopTest();

            Assert.areEqual(
                1,
                statementsAfter - statementsBefore,
                'Logging is done in one statement.'
            );
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Warning'],
                'Every row that failed is recorded.'
            );
        }
    }

    @IsTest
    static void twoHundredMessagesAboutTheirOwnRecordsCostOneStatement() {
        System.runAs(TestUsers.admin()) {
            Id aboutMe = UserInfo.getUserId();
            List<String> messages = new List<String>();
            List<Id> recordIds = new List<Id>();
            for (Integer i = 0; i < 200; i++) {
                messages.add('Appeal ' + i + ' could not be copied.');
                recordIds.add(Math.mod(i, 2) == 0 ? aboutMe : null);
            }
            messages.add('A message with no record beside it.');
            messages.add('  ');

            Test.startTest();
            Integer statementsBefore = Limits.getPublishImmediateDML();
            ErrorLogger.logMessages(
                messages,
                recordIds,
                'Appeal copy',
                ErrorLogger.SEVERITY_WARNING
            );
            Integer statementsAfter = Limits.getPublishImmediateDML();
            Test.stopTest();

            Assert.areEqual(
                1,
                statementsAfter - statementsBefore,
                'Logging is done in one statement.'
            );
            Assert.areEqual(
                201,
                [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Warning'],
                'Every message is recorded, and a blank one is not.'
            );
            Assert.areEqual(
                100,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Record_Reference__c = :String.valueOf(aboutMe)
                ],
                'Each entry names its own record, and one given none names none.'
            );
        }
    }

    @IsTest
    static void aListOfExceptionsIsLoggedTogether() {
        System.runAs(TestUsers.admin()) {
            List<Exception> failures = new List<Exception>{
                thrownException(),
                null,
                thrownException()
            };

            Test.startTest();
            Integer statementsBefore = Limits.getPublishImmediateDML();
            ErrorLogger.log(failures, 'Spreadsheet import');
            Integer statementsAfter = Limits.getPublishImmediateDML();
            Test.stopTest();

            Assert.areEqual(1, statementsAfter - statementsBefore, 'Still one statement.');
            Assert.areEqual(2, [SELECT COUNT() FROM Error_Log__c], 'The empty entry is skipped.');
        }
    }

    @IsTest
    static void aSeverityThatIsNotOfferedBecomesError() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            ErrorLogger.logMessage('The fund on this gift no longer exists.', null, 'Catastrophic');
            ErrorLogger.logMessage(
                'Nothing to worry about.',
                'Health check',
                ErrorLogger.SEVERITY_INFO
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Severity__c = 'Error' AND Context__c = 'BarnCRM'
                ],
                'An unrecognized severity is recorded as an error, under a default context.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Info'],
                'An offered severity is kept.'
            );
        }
    }

    @IsTest
    static void loggingNothingRecordsNothingAndThrowsNothing() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            ErrorLogger.log((Exception) null, 'Household naming');
            ErrorLogger.log((List<Exception>) null, 'Household naming');
            ErrorLogger.log(new List<Exception>(), 'Household naming');
            ErrorLogger.logMessage('   ', 'Household naming', ErrorLogger.SEVERITY_ERROR);
            ErrorLogger.logMessages(null, 'Household naming', ErrorLogger.SEVERITY_ERROR);
            ErrorLogger.logMessages(new List<String>{ '  ' }, 'Import', ErrorLogger.SEVERITY_ERROR);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'There was nothing to record.');
        }
    }

    @IsTest
    static void aVeryLongMessageIsTrimmedRatherThanLost() {
        System.runAs(TestUsers.admin()) {
            String enormous = 'x'.repeat(40000);

            Test.startTest();
            ErrorLogger.logMessage(enormous, enormous, ErrorLogger.SEVERITY_CRITICAL);
            Test.stopTest();

            List<Error_Log__c> logged = [SELECT Message__c, Context__c FROM Error_Log__c];
            Assert.areEqual(1, logged.size(), 'The entry was still written.');
            Assert.areEqual(32000, logged[0].Message__c.length(), 'The message is trimmed to fit.');
            Assert.areEqual(255, logged[0].Context__c.length(), 'So is the context.');
        }
    }

    @IsTest
    static void anEntrySurvivesTheRollbackItDocuments() {
        System.runAs(TestUsers.admin()) {
            // The failure this feature exists for ends in a rollback. An ordinary insert would be
            // undone with everything else, so the entry is published as a platform event instead
            // (canonical model rule R-E4). The person who hits the failure is David doing the day job,
            // whose access comes from the packaged permission set and not from a system administrator
            // profile, so the log runs inside System.runAs him: publishing is governed by Create on
            // the event, and if BarnCRM Staff did not carry it the writer would silently fall back
            // to the direct insert and the entry would go down with the rollback.
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });

            Test.startTest();
            Savepoint beforeTheFailure = Database.setSavepoint();
            TestDataFactory.insertErrorLogs(1, ErrorLogger.STATUS_NEW);
            System.runAs(david) {
                ErrorLogger.logMessage(
                    'The household could not be renamed, so nothing was saved.',
                    'Rollback',
                    ErrorLogger.SEVERITY_ERROR
                );
            }
            Database.rollback(beforeTheFailure);
            Test.getEventBus().deliver();
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'Test context%'],
                'The rollback undid the ordinary record, as a rollback does.'
            );
            List<Error_Log__c> survived = [
                SELECT Message__c, Severity__c, Status__c, User__c, Timestamp__c
                FROM Error_Log__c
                WHERE Context__c = 'Rollback'
            ];
            Assert.areEqual(1, survived.size(), 'And the Error Log entry outlived it.');
            Assert.areEqual(
                'The household could not be renamed, so nothing was saved.',
                survived[0].Message__c,
                'With the message intact.'
            );
            Assert.areEqual(
                ErrorLogger.SEVERITY_ERROR,
                survived[0].Severity__c,
                'And its severity.'
            );
            Assert.areEqual(ErrorLogger.STATUS_NEW, survived[0].Status__c, 'Waiting to be read.');
            Assert.areEqual(david.Id, survived[0].User__c, 'Naming David, who was working.');
            Assert.isNotNull(survived[0].Timestamp__c, 'And when.');
        }
    }

    @IsTest
    static void anEventWithASeverityNobodyRecognizesIsStillWritten() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            ErrorLogEventHandler.handle(
                new List<Error_Log_Event__e>{
                    new Error_Log_Event__e(
                        Message__c = 'Something happened.',
                        Context__c = 'Subscriber',
                        Severity__c = 'Catastrophic'
                    )
                }
            );
            ErrorLogEventHandler.handle(new List<Error_Log_Event__e>());
            ErrorLogEventHandler.handle(null);
            Test.stopTest();

            List<Error_Log__c> written = [SELECT Severity__c, Timestamp__c FROM Error_Log__c];
            Assert.areEqual(1, written.size(), 'The entry is written whatever the severity says.');
            Assert.areEqual(ErrorLogger.SEVERITY_ERROR, written[0].Severity__c, 'As an error.');
            Assert.isNotNull(written[0].Timestamp__c, 'With a time on it.');
        }
    }

    @IsTest
    static void theFallbackWritesEvenForSomeoneWithNoAccessToTheErrorLog() {
        System.runAs(TestUsers.admin()) {
            // The documented reason ErrorLogWriter is without sharing and writes in system mode: a
            // person who hits a failure because of their own access must still leave a trace.
            User david = TestDataFactory.createUser('David', new List<String>());

            Test.startTest();
            System.runAs(david) {
                ErrorLogWriter.writeDirectly(
                    new List<Error_Log__c>{
                        new Error_Log__c(
                            Timestamp__c = System.now(),
                            Context__c = 'No access',
                            Message__c = 'Recorded for a user who cannot create Error Log records.',
                            Severity__c = ErrorLogger.SEVERITY_ERROR,
                            Status__c = ErrorLogger.STATUS_NEW
                        )
                    }
                );
                ErrorLogWriter.writeDirectly(new List<Error_Log__c>());
                ErrorLogWriter.writeDirectly(null);
            }
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'No access'],
                'The entry is there even though the running user has no create access.'
            );
        }
    }

    @IsTest
    static void theTileCountsNewErrorsAndShowsTheMostRecent() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.insertErrorLogs(7, ErrorLogger.STATUS_NEW);
            TestDataFactory.insertErrorLogs(2, ErrorLogger.STATUS_RESOLVED);

            Test.startTest();
            Integer newCount = ErrorLogCountSelector.countNewUpTo(1000);
            List<Error_Log__c> recent = ErrorLogSelector.selectRecent(5);
            List<Error_Log__c> defaulted = ErrorLogSelector.selectRecent(null);
            List<Error_Log__c> capped = ErrorLogSelector.selectRecent(-3);
            Test.stopTest();

            Assert.areEqual(7, newCount, 'Only the new ones are counted.');
            Assert.areEqual(5, recent.size(), 'The tile shows five.');
            Assert.areEqual(5, defaulted.size(), 'Asking for none also shows five.');
            Assert.areEqual(5, capped.size(), 'So does asking for a nonsense number.');
            Assert.isTrue(
                recent[0].Timestamp__c >= recent[4].Timestamp__c,
                'The most recent is first.'
            );
        }
    }

    @IsTest
    static void anEntryCanBeReadBackById() {
        System.runAs(TestUsers.admin()) {
            List<Error_Log__c> existing = TestDataFactory.insertErrorLogs(
                2,
                ErrorLogger.STATUS_NEW
            );

            List<Error_Log__c> found = ErrorLogSelector.selectByIds(
                new Set<Id>{ existing[0].Id, existing[1].Id }
            );

            Assert.areEqual(2, found.size(), 'Both entries come back.');
            Assert.areEqual(
                0,
                ErrorLogSelector.selectByIds(new Set<Id>()).size(),
                'Asking for nothing queries nothing.'
            );
            Assert.areEqual(
                0,
                ErrorLogSelector.selectByIds(null).size(),
                'Asking for null queries nothing.'
            );
        }
    }
}
