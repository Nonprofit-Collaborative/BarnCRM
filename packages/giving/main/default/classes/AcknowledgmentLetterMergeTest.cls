/**
 * ADR-0032's third test: the merge file is a file, and a letter run is finished by a person
 * (R-AK11).
 */
@IsTest(testFor='ApexClass:AcknowledgmentLetterMerge')
private class AcknowledgmentLetterMergeTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
        }
    }

    private static Acknowledgment_Rule__c letterRule() {
        Acknowledgment_Rule__c rule = AcknowledgmentTestData.buildRule(
            'Everything by post',
            10,
            AcknowledgmentRuleService.CHANNEL_LETTER,
            null
        );
        insert rule;
        return rule;
    }

    @IsTest
    static void theFileCarriesOneHeaderAndOneRowPerLetter() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                AcknowledgmentTestData.enable();
                letterRule();
                Contact donor = AcknowledgmentTestData.insertDonor(
                    'Ada',
                    'Byron',
                    'ada@example.org'
                );
                insert new List<Gift__c>{
                    GivingTestDataFactory.buildGift(donor.Id, 1500),
                    GivingTestDataFactory.buildGift(donor.Id, 2500)
                };

                Test.startTest();
                Acknowledgment_Run__c run = AcknowledgmentRunService.runLetterMerge();
                Test.stopTest();

                Assert.areEqual(
                    AcknowledgmentRunService.STATUS_READY_TO_MERGE,
                    run.Status__c,
                    'A letter run stops at Ready to merge, because nothing has been printed yet.'
                );
                Assert.areEqual(2, run.Acknowledgments_Sent__c, 'Both gifts are in the file.');
                Assert.isNotNull(run.Merge_File_Document_Id__c, 'And the file itself was stored.');

                ContentVersion stored = [
                    SELECT VersionData, Title
                    FROM ContentVersion
                    WHERE ContentDocumentId = :run.Merge_File_Document_Id__c
                    LIMIT 1
                ];
                List<String> lines = stored.VersionData.toString().split('\n');
                Assert.areEqual(
                    3,
                    lines.size(),
                    'One header and two rows: a merge document with a second header in the middle is the ' +
                    'defect this asserts against.'
                );
                Assert.isTrue(
                    lines[0].startsWith('Gift,Gift Date,Amount,Donor Name,Greeting'),
                    'The header names the columns a mail merge binds to, in a fixed order.'
                );
                Assert.isTrue(
                    lines[1].contains('Ada Byron'),
                    'And each row names the donor the letter is addressed to.'
                );
            }

        }
    }

    @IsTest
    static void aDonorNameWithACommaStillParses() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String quoted = AcknowledgmentLetterMerge.escape('Smith, Jr.');
            String withQuote = AcknowledgmentLetterMerge.escape('The "Big" Trust');
            String plain = AcknowledgmentLetterMerge.escape('Riverside Trust');

            Assert.areEqual(
                '"Smith, Jr."',
                quoted,
                'A comma inside a value is quoted, or every column after it shifts left by one.'
            );
            Assert.areEqual(
                '"The ""Big"" Trust"',
                withQuote,
                'A quote inside a value is doubled, which is what a spreadsheet expects.'
            );
            Assert.areEqual(
                'Riverside Trust',
                plain,
                'And a value with neither is left alone, so the file stays readable.'
            );
        }
    }

    @IsTest
    static void lettersStayQueuedUntilAPersonSaysTheyWentOut() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                AcknowledgmentTestData.enable();
                letterRule();
                Contact donor = AcknowledgmentTestData.insertDonor(
                    'Alan',
                    'Turing',
                    'alan@example.org'
                );
                Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 1500);
                insert gift;

                Test.startTest();
                Acknowledgment_Run__c run = AcknowledgmentRunService.runLetterMerge();
                Acknowledgment__c beforeMarking = [
                    SELECT Status__c, Sent_On__c
                    FROM Acknowledgment__c
                    WHERE Gift__c = :gift.Id
                ];
                AcknowledgmentRunService.markLetterRunSent(run.Id);
                Test.stopTest();

                Assert.areEqual(
                    AcknowledgmentService.STATUS_QUEUED,
                    beforeMarking.Status__c,
                    'Producing the file is not sending a letter: Salesforce cannot tell whether anything ' +
                    'was printed (R-AK11).'
                );
                Assert.areEqual(
                    AcknowledgmentService.STATUS_SENT,
                    [SELECT Status__c FROM Acknowledgment__c WHERE Gift__c = :gift.Id].Status__c,
                    'Marking the run sent is the persons word that the letters went.'
                );
                Assert.areEqual(
                    AcknowledgmentRuleService.STATUS_ACKNOWLEDGED,
                    [SELECT Acknowledgment_Status__c FROM Gift__c WHERE Id = :gift.Id]
                    .Acknowledgment_Status__c,
                    'And the gift is stamped from the ledger, the same way an emailed one is (R-AK6).'
                );
                Assert.areEqual(
                    AcknowledgmentRunService.STATUS_COMPLETED,
                    [SELECT Status__c FROM Acknowledgment_Run__c WHERE Id = :run.Id].Status__c,
                    'The run is closed.'
                );
            }

        }
    }

    @IsTest
    static void aLetterRunClaimsItsGiftsSoAnEmailRunCannotTakeThem() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                AcknowledgmentTestData.enable();
                letterRule();
                Contact donor = AcknowledgmentTestData.insertDonor(
                    'Ada',
                    'Byron',
                    'ada@example.org'
                );
                Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 1500);
                insert gift;

                Test.startTest();
                AcknowledgmentRunService.runLetterMerge();
                List<Gift__c> stillWaiting = AcknowledgmentSelector.queuedGifts(100);
                Test.stopTest();

                Assert.areEqual(
                    0,
                    stillWaiting.size(),
                    'A gift claimed for a letter has left the queue, so the nightly email send cannot ' +
                    'thank the same donor a second time (R-AK7).'
                );
            }

        }
    }

    @IsTest
    static void aRunThatIsNotWaitingCannotBeMarkedSent() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            Acknowledgment_Run__c run = new Acknowledgment_Run__c(
                Channel__c = AcknowledgmentRuleService.CHANNEL_EMAIL,
                Status__c = AcknowledgmentRunService.STATUS_COMPLETED
            );
            insert run;

            String message;
            try {
                AcknowledgmentRunService.markLetterRunSent(run.Id);
            } catch (AcknowledgmentRunService.AcknowledgmentRunException refused) {
                message = refused.getMessage();
            }

            Assert.isNotNull(
                message,
                'Marking a completed email run as sent is refused rather than quietly stamping ' +
                'records that already went out.'
            );
        }
    }
}
