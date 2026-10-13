/**
 * The arithmetic a refund has to survive (R-R9, ADR-0022).
 *
 * This is the test the G-02 defect deserves. The shipped rollups used to filter on
 * `Status equals Received`, which R-G3 quietly breaks: a fully refunded gift is moved to
 * Refunded while the negative gifts that reverse it stay at Received, so the filter kept the
 * negatives, dropped the positive, and a gift of 250 refunded in two parts took the donor's
 * total to minus 250 instead of zero.
 *
 * It runs the real engine over the real shipped definitions rather than definitions the test
 * builds, because the thing under test is the filter document those rows carry.
 */
@IsTest
private class GiftRollupRefundTest {
    private static final String KEY_TOTAL = 'Contact_Total_Giving';
    private static final String KEY_COUNT = 'Contact_Gift_Count';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        }
    }

    /**
     * Ana gives 250 and asks for all of it back, in two parts. Her total giving is zero and she
     * still gave one gift: a sum and a count answer different questions here on purpose.
     */
    @IsTest
    static void aFullyRefundedGiftLeavesZeroGivenAndOneGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = [SELECT Id FROM Contact LIMIT 1];
            Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 250);
            insert gift;
            GiftService.refund(gift.Id, 100, 'Donor asked for the misdirected portion back');
            GiftService.refund(gift.Id, 150, 'The rest back');

            Assert.areEqual(
                'Refunded',
                [SELECT Status__c FROM Gift__c WHERE Id = :gift.Id].Status__c,
                'The whole gift has gone back, so R-G3 moves the original off Received.'
            );

            Test.startTest();
            RollupService.ensureDefaults();
            RollupService.runFullRecalculation(
                definitionsFor(new Set<String>{ KEY_TOTAL, KEY_COUNT })
            );
            Test.stopTest();

            Contact recalculated = [
                SELECT Total_Giving__c, Gift_Count__c
                FROM Contact
                WHERE Id = :ana.Id
            ];

            GivingTestDataFactory.assertRollupWrote(recalculated.Total_Giving__c);
            Assert.areEqual(
                0,
                recalculated.Total_Giving__c,
                'The negative gifts cancel the gift they reverse, so nothing is left in the total.'
            );
            Assert.areEqual(
                1,
                recalculated.Gift_Count__c,
                'Ana gave once. A refund is not a second gift given, and it is not minus one either.'
            );
        }
    }

    /**
     * The half of the same rule that a filter on Received alone got right, kept here so a later
     * change cannot fix the full refund by breaking the partial one.
     */
    @IsTest
    static void aPartiallyRefundedGiftLeavesWhatIsStillHeld() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = [SELECT Id FROM Contact LIMIT 1];
            Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 250);
            insert gift;
            GiftService.refund(gift.Id, 100, 'Donor asked for the misdirected portion back');

            Test.startTest();
            RollupService.ensureDefaults();
            RollupService.runFullRecalculation(
                definitionsFor(new Set<String>{ KEY_TOTAL, KEY_COUNT })
            );
            Test.stopTest();

            Contact recalculated = [
                SELECT Total_Giving__c, Gift_Count__c
                FROM Contact
                WHERE Id = :ana.Id
            ];

            GivingTestDataFactory.assertRollupWrote(recalculated.Total_Giving__c);
            Assert.areEqual(
                150,
                recalculated.Total_Giving__c,
                'Part of the gift is still money the organization holds.'
            );
            Assert.areEqual(1, recalculated.Gift_Count__c, 'Still one gift given.');
        }
    }

    /**
     * A Pending gift that will never be paid is cancelled, not written off (R-G16): no negative
     * gift, and the cancelled gift counts in neither the total nor the gift count.
     */
    @IsTest
    static void aCancelledGiftCountsNowhere() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = [SELECT Id FROM Contact LIMIT 1];
            Gift__c received = GivingTestDataFactory.buildGift(ana.Id, 250);
            Gift__c pledged = GivingTestDataFactory.buildGift(ana.Id, 40);
            pledged.Status__c = 'Pending';
            insert new List<Gift__c>{ received, pledged };
            update new Gift__c(Id = pledged.Id, Status__c = 'Cancelled');

            Test.startTest();
            RollupService.ensureDefaults();
            RollupService.runFullRecalculation(
                definitionsFor(new Set<String>{ KEY_TOTAL, KEY_COUNT })
            );
            Test.stopTest();

            Contact recalculated = [
                SELECT Total_Giving__c, Gift_Count__c
                FROM Contact
                WHERE Id = :ana.Id
            ];
            GivingTestDataFactory.assertRollupWrote(recalculated.Total_Giving__c);
            Assert.areEqual(250, recalculated.Total_Giving__c, 'Only the received gift');
            Assert.areEqual(1, recalculated.Gift_Count__c, 'Only the received gift');
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
        ];
        Assert.areEqual(
            keys.size(),
            definitions.size(),
            'The shipped defaults under test have to be materialized before they can run.'
        );
        return definitions;
    }
}
