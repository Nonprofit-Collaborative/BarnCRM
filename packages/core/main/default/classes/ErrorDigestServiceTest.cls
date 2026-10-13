/**
 * The error digest (C-23, R-E5): what it counts, whom it goes to, that it says nothing when
 * nothing is new, that no entry is counted twice, and that a weekly digest waits its week.
 *
 * The digest runs as the administrator who scheduled it, so every run here is Maria's, on a
 * minimal profile holding only the packaged BarnCRM Admin set. Messages are captured rather
 * than sent, except in the one test that proves the real send path handles either outcome.
 */
@IsTest(testFor='ApexClass:ErrorDigestService')
private class ErrorDigestServiceTest {
    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static Error_Log__c entry(String source, String severity, String status) {
        return new Error_Log__c(
            Timestamp__c = System.now(),
            Context__c = source,
            Message__c = 'The Garcia household could not be renamed.',
            Technical_Detail__c = 'DmlException: FIELD_CUSTOM_VALIDATION_EXCEPTION',
            Record_Reference__c = FakeIds.of(Account.SObjectType, 1),
            Severity__c = severity,
            Status__c = status
        );
    }

    private static BarnCRM_Settings__c settings() {
        return BarnCRM_Settings__c.getOrgDefaults();
    }

    private static void setDigest(String recipients, String frequency, Datetime coveredUntil) {
        BarnCRM_Settings__c record = settings();
        record.Error_Digest_Recipients__c = recipients;
        record.Error_Digest_Frequency__c = frequency;
        record.Error_Digest_Covered_Until__c = coveredUntil;
        TestDataFactory.saveSettings(record);
    }

    @IsTest
    static void theDigestCountsNewEntriesAndGoesToTheListedUser() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User jen = TestDataFactory.createUser('Jen', new List<String>{ 'BarnCRM_Staff' });
            User admin = maria();
            setDigest('JEN@barncrm.example.invalid', null, null);
            List<Error_Log__c> logs = new List<Error_Log__c>{
                entry('Household naming', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW),
                entry('Household naming', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW),
                entry('Household naming', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW),
                entry(
                    'Seasonal address swap',
                    ErrorLogger.SEVERITY_WARNING,
                    ErrorLogger.STATUS_NEW
                ),
                entry(
                    'Seasonal address swap',
                    ErrorLogger.SEVERITY_WARNING,
                    ErrorLogger.STATUS_NEW
                ),
                entry('Already looked at', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_RESOLVED),
                entry('Last week', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW)
            };
            insert logs;
            Test.setCreatedDate(logs[6].Id, System.now().addDays(-3));
            ErrorDigestService.capturedMessages = new List<Messaging.SingleEmailMessage>();

            ErrorDigestService.Outcome outcome;
            System.runAs(admin) {
                Test.startTest();
                outcome = ErrorDigestService.sendNow();
                Test.stopTest();
            }

            Assert.isTrue(outcome.sent, 'Something was new, so a digest went out.');
            Assert.areEqual(5, outcome.entries, 'Five new: not the resolved one, not last week.');
            List<Messaging.SingleEmailMessage> sent = ErrorDigestService.capturedMessages;
            Assert.areEqual(1, sent.size(), 'One message, to the one listed user.');
            Assert.areEqual(
                jen.Id,
                sent[0].getTargetObjectId(),
                'Addressed to Jen, found by email.'
            );
            Assert.isFalse(sent[0].getSaveAsActivity(), 'No activity is logged against Jen.');
            Assert.isTrue(sent[0].getSubject().contains('5'), 'The subject gives the count.');

            String body = sent[0].getPlainTextBody();
            Assert.isTrue(body.contains('Household naming: 3'), 'Counted by source.');
            Assert.isTrue(body.contains('Seasonal address swap: 2'), 'Every source.');
            Assert.isTrue(
                body.contains('Error: 3') && body.contains('Warning: 2'),
                'And by severity.'
            );
            Assert.isTrue(body.contains('/' + logs[0].Id), 'Each listed entry links to itself.');
            Assert.isFalse(body.contains(logs[5].Id), 'A resolved entry is not listed.');
            Assert.isFalse(body.contains('Garcia'), 'The message is never copied.');
            Assert.isFalse(body.contains('DmlException'), 'Nor the technical detail.');
            Assert.isFalse(
                body.contains(FakeIds.of(Account.SObjectType, 1)),
                'Nor the record it names.'
            );

            BarnCRM_Settings__c after = settings();
            Assert.isNotNull(after.Error_Digest_Covered_Until__c, 'The window moved on.');
            Assert.isNotNull(after.Error_Digest_Last_Run__c, 'The run is recorded.');
            Assert.areEqual(
                String.format(Label.Core_ErrorDigest_SummarySent, new List<Object>{ '5', '1' }),
                after.Error_Digest_Last_Run_Summary__c,
                'And says what it did.'
            );
        }
    }

    @IsTest
    static void nothingNewSendsNothingAndMovesTheWindowOn() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User admin = maria();
            ErrorDigestService.capturedMessages = new List<Messaging.SingleEmailMessage>();

            ErrorDigestService.Outcome outcome;
            System.runAs(admin) {
                Test.startTest();
                outcome = ErrorDigestService.runScheduled();
                Test.stopTest();
            }

            Assert.isFalse(outcome.sent, 'Nothing new, nothing sent.');
            Assert.isTrue(ErrorDigestService.capturedMessages.isEmpty(), 'Not a single message.');
            BarnCRM_Settings__c after = settings();
            Assert.isNotNull(
                after.Error_Digest_Covered_Until__c,
                'An empty window is still covered.'
            );
            Assert.isTrue(
                after.Error_Digest_Last_Run_Summary__c.startsWith(
                    Label.Core_ErrorDigest_SummaryNothingNew.substringBefore('{0}')
                ),
                'The run says nothing was new.'
            );
        }
    }

    @IsTest
    static void noEntryIsCountedInTwoDigests() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User admin = maria();
            setDigest(null, null, null);
            insert entry('Household naming', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW);
            ErrorDigestService.capturedMessages = new List<Messaging.SingleEmailMessage>();

            ErrorDigestService.Outcome first;
            ErrorDigestService.Outcome second;
            System.runAs(admin) {
                Test.startTest();
                first = ErrorDigestService.sendNow();
                second = ErrorDigestService.sendNow();
                Test.stopTest();
            }

            Assert.isTrue(first.sent, 'The first digest carries the entry.');
            Assert.isTrue(first.recipients >= 1, 'To the administrators, Maria among them.');
            Assert.isFalse(second.sent, 'The second finds nothing new.');
            Assert.areEqual(0, second.entries, 'The entry is not counted again.');
        }
    }

    @IsTest
    static void aWeeklyDigestWaitsItsWeek() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User admin = maria();
            setDigest(null, ErrorDigestService.FREQUENCY_WEEKLY, System.now().addDays(-2));
            insert entry('Household naming', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW);
            ErrorDigestService.capturedMessages = new List<Messaging.SingleEmailMessage>();

            ErrorDigestService.Outcome early;
            ErrorDigestService.Outcome due;
            Test.startTest();
            System.runAs(admin) {
                early = ErrorDigestService.runScheduled();
            }
            // Moving the window back is test setup, not something Maria does: the setting is protected.
            setDigest(null, ErrorDigestService.FREQUENCY_WEEKLY, System.now().addDays(-7));
            System.runAs(admin) {
                due = ErrorDigestService.runScheduled();
            }
            Test.stopTest();

            Assert.isFalse(early.sent, 'Two days into the week, the scheduled run waits.');
            Assert.isTrue(
                early.summary.startsWith(
                    Label.Core_ErrorDigest_SummaryNotDue.substringBefore('{0}')
                ),
                'And says when it will be due.'
            );
            Assert.isTrue(due.sent, 'Seven days on, it sends.');
        }
    }

    @IsTest
    static void aDailyDigestIsDueAFewMinutesShortOfADay() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User admin = maria();
            setDigest(
                null,
                ErrorDigestService.FREQUENCY_DAILY,
                System.now().addMinutes(-(24 * 60 - 5))
            );
            insert entry('Household naming', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW);
            ErrorDigestService.capturedMessages = new List<Messaging.SingleEmailMessage>();

            ErrorDigestService.Outcome outcome;
            System.runAs(admin) {
                Test.startTest();
                outcome = ErrorDigestService.runScheduled();
                Test.stopTest();
            }

            Assert.isTrue(
                outcome.sent,
                'The 07:00 run is due even when yesterday ended at 07:00:05.'
            );
        }
    }

    @IsTest
    static void theRealSendPathEitherSendsOrKeepsTheWindow() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User admin = maria();
            insert entry('Household naming', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW);

            ErrorDigestService.Outcome outcome;
            System.runAs(admin) {
                Test.startTest();
                outcome = ErrorDigestService.sendNow();
                Test.stopTest();
            }

            // Whether this org may send email is its own setting; both outcomes are correct ones.
            BarnCRM_Settings__c after = settings();
            if (outcome.sent) {
                Assert.isNotNull(
                    after.Error_Digest_Covered_Until__c,
                    'Sent, so the window moved on.'
                );
            } else {
                Assert.isNull(
                    after.Error_Digest_Covered_Until__c,
                    'Not sent, so the next run tries the same window again.'
                );
                Assert.isTrue(
                    outcome.summary.startsWith(
                        Label.Core_ErrorDigest_SummaryNotSent.substringBefore('{0}')
                    ),
                    'And the run says why.'
                );
            }
        }
    }

    @IsTest
    static void aFloodedErrorLogStillGetsItsDigest() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User admin = maria();
            List<Error_Log__c> logs = new List<Error_Log__c>();
            for (Integer i = 0; i < 5; i++) {
                logs.add(
                    entry('Household naming', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW)
                );
            }
            insert logs;
            ErrorDigestService.entryCap = 3;
            ErrorDigestService.capturedMessages = new List<Messaging.SingleEmailMessage>();

            ErrorDigestService.Outcome outcome;
            System.runAs(admin) {
                Test.startTest();
                outcome = ErrorDigestService.sendNow();
                Test.stopTest();
            }

            Assert.isTrue(outcome.sent, 'More than it can count, and the digest still goes out.');
            Assert.areEqual(3, outcome.entries, 'It counted up to its cap.');
            Assert.isTrue(outcome.summary.contains('3+'), 'And says there were more.');
            String body = ErrorDigestService.capturedMessages[0].getPlainTextBody();
            Assert.isTrue(body.contains('Household naming: 3'), 'The counts cover what it read.');
            Assert.isTrue(
                body.contains(Label.Core_ErrorDigest_Capped.substringBefore('{0}')),
                'And the email says the numbers are the newest few.'
            );
            Assert.isNotNull(settings().Error_Digest_Covered_Until__c, 'The window moved on.');
        }
    }

    @IsTest
    static void aFailedSendKeepsTheWindowAndIsLoggedOnce() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User admin = maria();
            insert entry('Household naming', ErrorLogger.SEVERITY_ERROR, ErrorLogger.STATUS_NEW);
            ErrorDigestService.sendFailureForTest = 'email is switched off for this org';

            ErrorDigestService.Outcome first;
            ErrorDigestService.Outcome second;
            System.runAs(admin) {
                Test.startTest();
                first = ErrorDigestService.sendNow();
                second = ErrorDigestService.sendNow();
                Test.stopTest();
            }

            Assert.isFalse(first.sent || second.sent, 'Nothing could be sent.');
            Assert.isTrue(first.summary.contains('email is switched off'), 'The run says why.');
            Assert.isNull(
                settings().Error_Digest_Covered_Until__c,
                'The window stays, so the next run tries the same entries again.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Error digest'],
                'The same reason twice is one Error Log entry, not one a day.'
            );
        }
    }

    @IsTest
    static void theFirstDigestKeepsTheShippedDefaults() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            ErrorDigestWriter.recordRun(System.now(), 'Nothing new.', System.now());
            Test.stopTest();

            BarnCRM_Settings__c saved = [
                SELECT
                    Error_Digest_Last_Run__c,
                    Relationship_Auto_Reciprocal__c,
                    Auto_Create_Households__c,
                    Coexistence_Mode__c,
                    Household_Membership_Mode__c
                FROM BarnCRM_Settings__c
                WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            ];
            Assert.isNotNull(saved.Error_Digest_Last_Run__c, 'The run is recorded.');
            Assert.isTrue(
                saved.Relationship_Auto_Reciprocal__c,
                'A feature that ships on stays on.'
            );
            Assert.isTrue(
                saved.Auto_Create_Households__c,
                'Households are still created by default.'
            );
            Assert.isNull(saved.Coexistence_Mode__c, 'Nobody confirmed a coexistence mode.');
            Assert.isNull(saved.Household_Membership_Mode__c, 'Nobody chose a membership mode.');
        }
    }
}
