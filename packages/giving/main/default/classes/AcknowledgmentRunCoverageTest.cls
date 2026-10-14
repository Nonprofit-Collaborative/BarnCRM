/**
 * The runs behind the Acknowledgments page: the nightly batch and its chunks, the email and letter
 * runs, marking a letter run sent, and the page's own buttons and refusals. A chunk that fails
 * costs the run that chunk and nothing more, and a person is told in words rather than by a
 * platform error.
 *
 * Nothing here sends mail. The sender is the recording stand-in from the other acknowledgment
 * tests, and the batch is driven one chunk at a time so the stand-in is the one in use.
 */
@IsTest(
    testFor='ApexClass:AcknowledgmentBatch, ApexClass:AcknowledgmentRunService, ApexClass:AcknowledgmentController, ApexClass:AcknowledgmentScheduler'
)
private class AcknowledgmentRunCoverageTest {
    private static final Integer TWO_HUNDRED = 200;

    /** A sender whose platform call fails outright, as an exhausted mail limit would. */
    private class BrokenSender implements AcknowledgmentSender {
        public List<AcknowledgmentSendOutcome> send(List<Messaging.SingleEmailMessage> messages) {
            throw new AcknowledgmentService.AcknowledgmentException('The mail service is down.');
        }
    }

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
        }
    }

    private static void emailRule() {
        insert AcknowledgmentTestData.buildRule(
            'Everything else',
            100,
            AcknowledgmentRuleService.CHANNEL_EMAIL,
            'BarnCRM_Thank_You'
        );
    }

    private static void letterRule() {
        insert AcknowledgmentTestData.buildRule(
            'Letters',
            100,
            AcknowledgmentRuleService.CHANNEL_LETTER,
            null
        );
    }

    private static List<Gift__c> giftsFor(Contact donor, Integer howMany) {
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(donor.Id, howMany, 50);
        insert gifts;
        return gifts;
    }

    private static Acknowledgment_Run__c newRun() {
        Acknowledgment_Run__c run = new Acknowledgment_Run__c(
            Channel__c = AcknowledgmentRuleService.CHANNEL_EMAIL,
            Status__c = AcknowledgmentRunService.STATUS_RUNNING,
            Started__c = System.now(),
            Gifts_Processed__c = 0,
            Acknowledgments_Sent__c = 0,
            Errors__c = 0
        );
        insert run;
        return run;
    }

    private static Acknowledgment_Run__c reload(Id runId) {
        return [
            SELECT
                Status__c,
                Gifts_Processed__c,
                Acknowledgments_Sent__c,
                Errors__c,
                Finished__c,
                Merge_File_Document_Id__c
            FROM Acknowledgment_Run__c
            WHERE Id = :runId
        ];
    }

    // ------------------------------------------------------------------------- the batch

    @IsTest
    static void theBatchReadsTheQueueAndSendsEachChunkAndFinishesTheRun() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            giftsFor(donor, TWO_HUNDRED);
            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            AcknowledgmentService.senderOverride = sender;
            Acknowledgment_Run__c run = newRun();
            AcknowledgmentBatch batch = new AcknowledgmentBatch(run.Id);
            List<Gift__c> queued = AcknowledgmentSelector.queuedGifts(500);

            Test.startTest();
            Assert.isNotNull(batch.start(null), 'The batch reads the queue through a locator');
            Assert.areEqual(TWO_HUNDRED, queued.size(), 'All 200 gifts are waiting');
            for (Integer start = 0; start < queued.size(); start += 100) {
                List<Gift__c> chunk = new List<Gift__c>();
                for (Integer i = start; i < start + 100; i++) {
                    chunk.add(queued[i]);
                }
                batch.execute(null, chunk);
            }
            Acknowledgment_Run__c midway = reload(run.Id);
            batch.finish(null);
            Test.stopTest();

            Assert.areEqual(
                TWO_HUNDRED,
                midway.Gifts_Processed__c,
                'Progress is saved after each chunk'
            );
            Assert.areEqual(TWO_HUNDRED, sender.received.size(), 'Every gift got its message');
            Acknowledgment_Run__c done = reload(run.Id);
            Assert.areEqual(
                AcknowledgmentRunService.STATUS_COMPLETED,
                done.Status__c,
                'The run completed'
            );
            Assert.areEqual(TWO_HUNDRED, done.Acknowledgments_Sent__c, 'All 200 were sent');
            Assert.areEqual(0, done.Errors__c, 'With no errors');
            Assert.isNotNull(done.Finished__c, 'And a finish time');
            Assert.areEqual(
                TWO_HUNDRED,
                [
                    SELECT COUNT()
                    FROM Gift__c
                    WHERE Acknowledgment_Status__c = :AcknowledgmentRuleService.STATUS_ACKNOWLEDGED
                ],
                'Every gift is marked acknowledged'
            );
        }
    }

    @IsTest
    static void aChunkThatFailsCostsTheRunThatChunkAndEndsItWithErrors() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            giftsFor(donor, 3);
            AcknowledgmentService.senderOverride = new BrokenSender();
            Acknowledgment_Run__c run = newRun();
            AcknowledgmentBatch batch = new AcknowledgmentBatch(run.Id);

            Test.startTest();
            batch.execute(null, AcknowledgmentSelector.queuedGifts(500));
            batch.finish(null);
            Test.stopTest();

            Acknowledgment_Run__c done = reload(run.Id);
            Assert.areEqual(3, done.Gifts_Processed__c, 'The lost chunk is counted as processed');
            Assert.areEqual(3, done.Errors__c, 'And as errors');
            Assert.areEqual(0, done.Acknowledgments_Sent__c, 'Nothing was sent');
            Assert.areEqual(
                AcknowledgmentRunService.STATUS_COMPLETED_WITH_ERRORS,
                done.Status__c,
                'So the run says it finished with errors'
            );
        }
    }

    // ----------------------------------------------------------------------- the run service

    @IsTest
    static void aPersonWithoutThePermissionCannotStartAnyRun() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            AcknowledgmentService.sendPermission = false;
            Integer refused = 0;
            for (Integer attempt = 0; attempt < 3; attempt++) {
                try {
                    if (attempt == 0) {
                        AcknowledgmentRunService.startEmailRun();
                    } else if (attempt == 1) {
                        AcknowledgmentRunService.runLetterMerge();
                    } else {
                        AcknowledgmentRunService.markLetterRunSent(
                            FakeIds.of(Acknowledgment_Run__c.SObjectType, 1)
                        );
                    }
                } catch (AcknowledgmentService.AcknowledgmentException expected) {
                    Assert.areEqual(
                        Label.Giving_Acknowledgment_NoPermission,
                        expected.getMessage()
                    );
                    refused++;
                }
            }
            Assert.areEqual(3, refused, 'Each of the three entry points names the permission');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Acknowledgment_Run__c],
                'And no run was recorded'
            );
        }
    }

    @IsTest
    static void anEmailRunWithNothingWaitingStartsAndCompletes() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            Acknowledgment_Run__c started;

            Test.startTest();
            started = AcknowledgmentRunService.startEmailRun();
            Test.stopTest();

            Assert.areEqual(
                AcknowledgmentRunService.STATUS_RUNNING,
                started.Status__c,
                'It starts running'
            );
            Assert.isNotNull(started.Async_Job_Id__c, 'With the job that does the sending');
            Acknowledgment_Run__c done = reload(started.Id);
            Assert.areEqual(
                AcknowledgmentRunService.STATUS_COMPLETED,
                done.Status__c,
                'The batch ran with an empty queue and finished the run'
            );
        }
    }

    @IsTest
    static void aLetterRunWithNoLettersWaitingCompletesAtOnce() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();

            Test.startTest();
            Acknowledgment_Run__c run = AcknowledgmentRunService.runLetterMerge();
            Test.stopTest();

            Assert.areEqual(
                AcknowledgmentRunService.STATUS_COMPLETED,
                run.Status__c,
                'Nothing to merge'
            );
            Assert.isNull(run.Merge_File_Document_Id__c, 'So there is no file');
        }
    }

    @IsTest
    static void aLetterRunMakesOneFileAndMarkingItSentThanksEveryGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            letterRule();
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            giftsFor(donor, TWO_HUNDRED);

            Test.startTest();
            Acknowledgment_Run__c run = AcknowledgmentRunService.runLetterMerge();
            Test.stopTest();

            Assert.areEqual(
                AcknowledgmentRunService.STATUS_READY_TO_MERGE,
                run.Status__c,
                'The run waits for somebody to print and mail the letters'
            );
            Assert.areEqual(TWO_HUNDRED, run.Acknowledgments_Sent__c, 'All 200 are in the file');
            Assert.isNotNull(run.Merge_File_Document_Id__c, 'The file is stored');

            Acknowledgment_Run__c settled = AcknowledgmentRunService.markLetterRunSent(run.Id);

            Assert.areEqual(
                AcknowledgmentRunService.STATUS_COMPLETED,
                settled.Status__c,
                'Marked sent'
            );
            Assert.areEqual(
                TWO_HUNDRED,
                [
                    SELECT COUNT()
                    FROM Gift__c
                    WHERE Acknowledgment_Status__c = :AcknowledgmentRuleService.STATUS_ACKNOWLEDGED
                ],
                'Every gift in the file is now acknowledged'
            );
            Assert.areEqual(
                TWO_HUNDRED,
                [
                    SELECT COUNT()
                    FROM Acknowledgment__c
                    WHERE Status__c = :AcknowledgmentService.STATUS_SENT
                ],
                'And every letter row is sent'
            );
        }
    }

    @IsTest
    static void aLetterRunCanOnlyBeMarkedSentOnceAndOnlyIfItExists() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            Acknowledgment_Run__c completed = newRun();
            completed.Status__c = AcknowledgmentRunService.STATUS_COMPLETED;
            update completed;
            String missing;
            String notWaiting;

            try {
                AcknowledgmentRunService.markLetterRunSent(
                    FakeIds.of(Acknowledgment_Run__c.SObjectType, 7)
                );
            } catch (AcknowledgmentRunService.AcknowledgmentRunException refused) {
                missing = refused.getMessage();
            }
            try {
                AcknowledgmentRunService.markLetterRunSent(completed.Id);
            } catch (AcknowledgmentRunService.AcknowledgmentRunException refused) {
                notWaiting = refused.getMessage();
            }

            Assert.areEqual(Label.Giving_Acknowledgment_RunNotFound, missing, 'No such run');
            Assert.areEqual(
                Label.Giving_Acknowledgment_RunNotWaiting,
                notWaiting,
                'Not waiting to be marked'
            );
        }
    }

    @IsTest
    static void progressAndFinishWriteTheCountsTheyAreGiven() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Acknowledgment_Run__c run = newRun();

            AcknowledgmentRunService.recordProgress(run.Id, 10, 8, 2);
            Acknowledgment_Run__c progress = reload(run.Id);
            Assert.areEqual(10, progress.Gifts_Processed__c, 'Processed so far');
            Assert.areEqual(8, progress.Acknowledgments_Sent__c, 'Sent so far');
            Assert.areEqual(2, progress.Errors__c, 'Errors so far');
            Assert.areEqual(
                AcknowledgmentRunService.STATUS_RUNNING,
                progress.Status__c,
                'Still running'
            );

            AcknowledgmentRunService.finish(run.Id, 10, 10, 0);
            Assert.areEqual(
                AcknowledgmentRunService.STATUS_COMPLETED,
                reload(run.Id).Status__c,
                'No errors: completed'
            );
            AcknowledgmentRunService.finish(run.Id, 10, 9, 1);
            Assert.areEqual(
                AcknowledgmentRunService.STATUS_COMPLETED_WITH_ERRORS,
                reload(run.Id).Status__c,
                'Any error: completed with errors'
            );
        }
    }

    // --------------------------------------------------------------------- the page buttons

    @IsTest
    static void theButtonsRunTheirJobsAndReturnThePageAsItNowStands() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            letterRule();
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            giftsFor(donor, 2);

            Test.startTest();
            AcknowledgmentController.PageView afterLetters = AcknowledgmentController.produceLetters();
            Assert.areEqual(1, afterLetters.runs.size(), 'The letter run is listed');
            Assert.isTrue(afterLetters.runs[0].waitingToBeMarkedSent, 'Waiting to be marked sent');
            Assert.areEqual(2, afterLetters.runs[0].sent, 'With both letters in it');
            Assert.isNotNull(afterLetters.runs[0].mergeFileId, 'And the file to download');

            AcknowledgmentController.PageView afterMark = AcknowledgmentController.markLettersSent(
                afterLetters.runs[0].id
            );
            Assert.isFalse(afterMark.runs[0].waitingToBeMarkedSent, 'No longer waiting');
            Assert.areEqual(0, afterMark.letterQueue, 'And the letter queue is empty');

            AcknowledgmentController.PageView afterEmails = AcknowledgmentController.sendEmailsNow();
            Test.stopTest();

            Assert.areEqual(2, afterEmails.runs.size(), 'The email run joins the list');
        }
    }

    @IsTest
    static void theScheduleIsSwitchedOnAndOffFromThePage() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();

            Test.startTest();
            AcknowledgmentController.PageView switchedOn = AcknowledgmentController.setSchedule(
                true
            );
            AcknowledgmentController.PageView again = AcknowledgmentController.setSchedule(true);
            Assert.isTrue(switchedOn.scheduled, 'The nightly job is scheduled');
            Assert.isNotNull(switchedOn.nextRunAt, 'With a next run to show');
            Assert.isTrue(again.scheduled, 'Switching it on twice leaves it on');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM CronTrigger
                    WHERE CronJobDetail.Name = :AcknowledgmentScheduler.JOB_NAME
                ],
                'And only one job'
            );
            AcknowledgmentController.PageView off = AcknowledgmentController.setSchedule(false);
            AcknowledgmentController.PageView offAgain = AcknowledgmentController.setSchedule(
                false
            );
            Test.stopTest();

            Assert.isFalse(off.scheduled, 'Switched off');
            Assert.isNull(off.nextRunAt, 'With no next run');
            Assert.isFalse(offAgain.scheduled, 'Switching off twice is harmless');
        }
    }

    @IsTest
    static void theNightlyJobStartsAnEmailRunOnlyWhileTheFeatureIsOn() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();

            Test.startTest();
            new AcknowledgmentScheduler().execute(null);
            Test.stopTest();
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Acknowledgment_Run__c],
                'Switched on: a run starts'
            );

            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            settings.Acknowledgments_Enabled__c = false;
            upsert settings;
            new AcknowledgmentScheduler().execute(null);
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Acknowledgment_Run__c],
                'Switched off: nothing new'
            );
        }
    }

    @IsTest
    static void aNightlyJobThatCannotStartIsLoggedNotThrown() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            AcknowledgmentService.sendPermission = false;

            Test.startTest();
            new AcknowledgmentScheduler().execute(null);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Acknowledgment_Run__c],
                'Nothing started and nothing thrown'
            );
        }
    }

    @IsTest
    static void aPersonWithoutThePermissionIsTold() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            AcknowledgmentService.sendPermission = false;
            List<String> messages = new List<String>();
            try {
                AcknowledgmentController.produceLetters();
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
            try {
                AcknowledgmentController.markLettersSent(
                    FakeIds.of(Acknowledgment_Run__c.SObjectType, 1)
                );
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }

            Assert.areEqual(
                new List<String>{
                    Label.Giving_Acknowledgment_NoPermission,
                    Label.Giving_Acknowledgment_NoPermission
                },
                messages,
                'Both buttons say what is missing in the words the label gives'
            );
        }
    }

    @IsTest
    static void anUnexpectedFailureShowsTheGeneralMessageNotThePlatformsOwn() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User outsider = TestDataFactory.createUser('NoAccess', new List<String>());
            String message;

            System.runAs(outsider) {
                try {
                    AcknowledgmentController.getPage();
                } catch (AuraHandledException failure) {
                    message = failure.getMessage();
                }
            }

            Assert.areEqual(
                Label.Giving_Acknowledgment_UnexpectedError,
                message,
                'A person who cannot read the rules gets the general message, never a query error'
            );
        }
    }
}
