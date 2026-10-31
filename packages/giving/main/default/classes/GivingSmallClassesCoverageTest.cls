/**
 * The small Giving classes whose edges no other test reaches: the receipt renderer's refusal of
 * an empty document, the nightly overdue and top up jobs when they find nothing or cannot run,
 * the stewardship starter when it cannot read its templates, the donor delete guard's name, and
 * a failed email's reason.
 *
 * A nightly job that fails must say so on the Nightly Jobs page and never throw, because a
 * scheduled job's exception goes nowhere anyone looks.
 */
@IsTest(
    testFor='ApexClass:BlobToPdfReceiptRenderer, ApexClass:InstallmentSchedulable, ApexClass:InstallmentTopUpSchedulable, ApexClass:StewardshipTriggerHandler, ApexClass:GiftDonorDeleteGuardHandler'
)
private class GivingSmallClassesCoverageTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
        }
    }

    // ---------------------------------------------------------------------- receipt renderer

    @IsTest
    static void theShippedRendererRefusesAnEmptyDocumentAndDescribesItself() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            BlobToPdfReceiptRenderer renderer = new BlobToPdfReceiptRenderer();
            String blank;
            String empty;
            try {
                renderer.render('  ');
            } catch (BlobToPdfReceiptRenderer.ReceiptRendererException refused) {
                blank = refused.getMessage();
            }
            try {
                renderer.render(null);
            } catch (BlobToPdfReceiptRenderer.ReceiptRendererException refused) {
                empty = refused.getMessage();
            }

            Assert.areEqual(
                Label.Giving_Receipt_NothingToRender,
                blank,
                'White space is nothing to render'
            );
            Assert.areEqual(
                Label.Giving_Receipt_NothingToRender,
                empty,
                'So is no document at all'
            );
            Assert.isTrue(
                renderer.describe().contains('Blob.toPdf'),
                'It says which service it uses'
            );
        }
    }

    @IsTest
    static void theShippedRendererMakesAPdfFromHtml() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Blob pdf = new BlobToPdfReceiptRenderer().render('<p>Thank you for your gift.</p>');

            Assert.isNotNull(pdf, 'A document comes back');
            Assert.isTrue(pdf.size() > 0, 'And it has content');
        }
    }

    // ----------------------------------------------------------------------- nightly overdue

    @IsTest
    static void theOverdueJobSaysSoWhenNothingWasOverdue() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            new InstallmentSchedulable().execute(null);
            Test.stopTest();

            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            Assert.areEqual(
                System.Label.Giving_NightlyJobs_OverdueNoneFound,
                settings.Installment_Overdue_Last_Run_Summary__c,
                'The page says the pass ran and found nothing'
            );
            Assert.isNotNull(settings.Installment_Overdue_Last_Run__c, 'With the time it ran');
        }
    }

    @IsTest
    static void theOverdueJobSavesTheNightSummaryEvenWhenItsOwnWorkFails() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User outsider = TestDataFactory.createUser('NoAccess', new List<String>());

            System.runAs(outsider) {
                Test.startTest();
                new InstallmentSchedulable().execute(null);
                Test.stopTest();
            }

            Assert.areEqual(
                System.Label.Giving_NightlyJobs_RunFailed,
                Giving_Settings__c.getOrgDefaults().Installment_Overdue_Last_Run_Summary__c,
                'A pass that could not read the payments says it failed rather than claiming none were late'
            );
        }
    }

    // --------------------------------------------------------------------------- top up job

    @IsTest
    static void theTopUpJobStartsItsBatch() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            new InstallmentTopUpSchedulable().execute(null);
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM AsyncApexJob
                    WHERE ApexClass.Name = 'InstallmentTopUpBatch' AND JobType = 'BatchApex'
                ],
                'The nightly job hands the work to the top up batch'
            );
        }
    }

    // ---------------------------------------------------------------------------- stewardship

    @IsTest
    static void aStewardshipStarterThatCannotReadItsTemplatesLeavesTheGiftsAlone() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact donor = new Contact(LastName = 'Ramirez');
            insert donor;
            List<Gift__c> gifts = new List<Gift__c>();
            for (Integer i = 0; i < 200; i++) {
                gifts.add(GivingTestDataFactory.buildGift(donor.Id, 10 + i));
            }
            insert gifts;
            User outsider = TestDataFactory.createUser('NoAccess', new List<String>());

            System.runAs(outsider) {
                TriggerHandler.setTestRecords(gifts, null);
                try {
                    new StewardshipTriggerHandler().afterInsert();
                } finally {
                    TriggerHandler.setTestRecords(null, null);
                }
            }

            for (Gift__c gift : gifts) {
                Assert.isFalse(
                    gift.hasErrors(),
                    'A plan that could not start never stops a gift being saved'
                );
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Stewardship_Plan__c], 'And no plan was made');
        }
    }

    @IsTest
    static void aStewardshipStarterGivenNothingDoesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TriggerHandler.setTestRecords(null, null);
            new StewardshipTriggerHandler().afterInsert();
            TriggerHandler.setTestRecords(new List<SObject>(), null);
            new StewardshipTriggerHandler().afterInsert();
            TriggerHandler.setTestRecords(null, null);

            Assert.areEqual(0, [SELECT COUNT() FROM Stewardship_Plan__c], 'No gifts, no plans');
        }
    }

    // ------------------------------------------------------------------------- donor delete

    @IsTest
    static void theDonorDeleteGuardIsNamedForTheAutomationRegistry() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.areEqual(
                'GiftDonorDeleteGuardHandler',
                new GiftDonorDeleteGuardHandler().getName(),
                'The registry rows that switch the guard on and off find it by this name'
            );
        }
    }

    @IsTest
    static void aDonorWithNoGiftsIsDeletedWithTheGuardOn() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 200; i++) {
                people.add(new Contact(FirstName = 'Donor' + i, LastName = 'Nobody'));
            }
            insert people;

            Test.startTest();
            delete people;
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Contact WHERE LastName = 'Nobody'],
                'Two hundred people with no gifts are deleted in one save: the guard only refuses donors the books name'
            );
        }
    }

    // ------------------------------------------------------------------------- mail sender

    @IsTest
    static void aFailedSendExplainsItselfInNoMoreThan255Characters() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String unknown = Label.Giving_Acknowledgment_SendFailedUnknown;
            Assert.areEqual(
                unknown,
                AcknowledgmentService.failureReasonOf(null, unknown),
                'No answer from the platform reads as unknown'
            );
            Assert.areEqual(
                unknown,
                AcknowledgmentService.failureReasonOf(EmailSendOutcome.failed(' '), unknown),
                'A blank reason too'
            );
            Assert.areEqual(
                255,
                AcknowledgmentService.failureReasonOf(
                        EmailSendOutcome.failed('x'.repeat(300)),
                        unknown
                    )
                    .length(),
                'A long reason is trimmed to fit the record'
            );
        }
    }
}
