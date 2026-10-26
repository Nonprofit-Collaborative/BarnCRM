/**
 * What a refund does to recognition (R-SC5, R-SC6, ADR-0023).
 *
 * Two rules used to fire on the same full refund and undo each other: R-SC5 gave the negative
 * gift a negative automatic credit, and R-SC6 deleted the original gift's automatic credit once
 * its status became Refunded. Both reversals applied, so a gift of 250 refunded in full left the
 * household member recognized for minus 250 instead of nothing. ADR-0023 keeps R-SC5's negative
 * credit and stops the deletion.
 *
 * Like `GiftRollupRefundTest`, this runs the real refund path and the real shipped rollup rows
 * rather than definitions the test builds, because the number a fundraiser reads is the rollup.
 */
@IsTest(testFor='ApexClass:SoftCreditService, ApexClass:GiftService')
private class SoftCreditRefundTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static final String KEY_TOTAL = 'Contact_Total_Soft_Credits';
    private static final String KEY_COUNT = 'Contact_Soft_Credit_Count';

    /**
     * Ana gives 250 and asks for all of it back. Luis, her household member, was recognized for
     * the gift and is now recognized for nothing: the credit and the credit that reverses it are
     * both on his record, and they cancel.
     */
    @IsTest
    static void aFullyRefundedGiftLeavesTheHouseholdMemberRecognizedForNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RecognitionTestData.setAutomaticHouseholdCredits(true);
            GivingTestDataFactory.insertDefaultFund();
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 250);
            Assert.areEqual(
                250,
                RecognitionTestData.creditsFor(gift.Id)[0].Amount__c,
                'Luis starts recognized for the whole gift.'
            );

            Id refundId = GiftService.refund(gift.Id, 250, 'Donor asked for all of it back');

            Assert.areEqual(
                'Refunded',
                [SELECT Status__c FROM Gift__c WHERE Id = :gift.Id].Status__c,
                'The whole gift has gone back, so R-G3 moves the original off Received.'
            );
            Assert.areEqual(
                1,
                RecognitionTestData.creditsFor(gift.Id).size(),
                'The refunded gift keeps the credit it earned: the reversal is the negative gift, ' +
                'not the deletion of this one (ADR-0023).'
            );
            Assert.areEqual(
                -250,
                RecognitionTestData.creditsFor(refundId)[0].Amount__c,
                'The negative gift carries the negative credit that cancels it (R-SC5).'
            );

            Test.startTest();
            RollupService.ensureDefaults();
            RollupService.runFullRecalculation(
                definitionsFor(new Set<String>{ KEY_TOTAL, KEY_COUNT })
            );
            Test.stopTest();

            Contact recalculated = [
                SELECT Total_Soft_Credits__c, Soft_Credit_Count__c
                FROM Contact
                WHERE Id = :luis.Id
            ];
            GivingTestDataFactory.assertRollupWrote(recalculated.Total_Soft_Credits__c);
            Assert.areEqual(
                0,
                recalculated.Total_Soft_Credits__c,
                'Recognition reverses the way money does: nothing left, not minus the gift.'
            );
            Assert.areEqual(
                1,
                recalculated.Soft_Credit_Count__c,
                'Luis was recognized on one gift. The reversal is not a second gift recognized, ' +
                'and it is not minus one either.'
            );
        }
    }

    /**
     * The partial refund, kept here because it is the case the rejected alternative in ADR-0023
     * got wrong: suppressing the negative credit would leave recognition at 250 against giving
     * of 150.
     */
    @IsTest
    static void aPartiallyRefundedGiftLeavesRecognitionForWhatIsStillHeld() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RecognitionTestData.setAutomaticHouseholdCredits(true);
            GivingTestDataFactory.insertDefaultFund();
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 250);
            GiftService.refund(gift.Id, 100, 'Donor asked for the misdirected portion back');

            Assert.areEqual(
                'Received',
                [SELECT Status__c FROM Gift__c WHERE Id = :gift.Id].Status__c,
                'Part of the gift is still held, so the original keeps its status.'
            );

            Test.startTest();
            RollupService.ensureDefaults();
            RollupService.runFullRecalculation(definitionsFor(new Set<String>{ KEY_TOTAL }));
            Test.stopTest();

            Decimal total = [SELECT Total_Soft_Credits__c FROM Contact WHERE Id = :luis.Id]
            .Total_Soft_Credits__c;
            GivingTestDataFactory.assertRollupWrote(total);
            Assert.areEqual(
                150,
                total,
                'Recognition tracks the money the organization still holds.'
            );
        }
    }

    private static List<Rollup_Definition__c> definitionsFor(Set<String> keys) {
        List<Rollup_Definition__c> definitions = [
            SELECT
                Id,
                Name,
                Definition_Key__c,
                Source_Object__c,
                Target_Object__c,
                Relationship_Path__c,
                Aggregate__c,
                Source_Field__c,
                Order_By_Field__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Active__c
            FROM Rollup_Definition__c
            WHERE Definition_Key__c IN :keys
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(
            keys.size(),
            definitions.size(),
            'The shipped defaults under test have to be materialized before they can run.'
        );
        return definitions;
    }
}
