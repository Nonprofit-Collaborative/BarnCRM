/**
 * The allocations of a gift always total the gift, whichever way a person tries to change
 * them, and a percent and an amount always agree (R-GA1, R-GA2).
 */
@IsTest
private class GiftAllocationTriggerHandlerTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        }
    }

    private static Gift__c giftOf(Decimal amount, Boolean withDefaultAllocation) {
        Contact person = [SELECT Id FROM Contact LIMIT 1];
        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, amount);
        try {
            GiftService.suppressDefaultAllocations = !withDefaultAllocation;
            insert gift;
        } finally {
            GiftService.suppressDefaultAllocations = false;
        }
        return gift;
    }

    @IsTest
    static void aGiftWithNoAllocationGetsTheDefaultFund() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Gift__c gift = giftOf(250, true);
            Test.stopTest();

            List<Gift_Allocation__c> allocations = [
                SELECT Id, Fund__c, Amount__c, Percent__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :gift.Id
            ];
            System.assertEquals(1, allocations.size(), 'One allocation, for the whole gift.');
            System.assertEquals(250, allocations[0].Amount__c, 'It carries the whole amount.');
            System.assertEquals(100, allocations[0].Percent__c, 'Which is all of it.');
        }
    }

    @IsTest
    static void aPercentBecomesAnAmount() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftOf(200, false);
            Fund__c fund = [SELECT Id FROM Fund__c LIMIT 1];

            Test.startTest();
            insert new Gift_Allocation__c(Gift__c = gift.Id, Fund__c = fund.Id, Percent__c = 100);
            Test.stopTest();

            Gift_Allocation__c saved = [
                SELECT Id, Amount__c, Percent__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :gift.Id
            ];
            System.assertEquals(
                200,
                saved.Amount__c,
                'A person who thinks in percentages gets the amount worked out for them.'
            );
        }
    }

    @IsTest
    static void percentagesThatRoundStillTotalTheGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            // 100.01 in thirds is the case that actually rounds: each share works out to a
            // fraction of a cent, and the leftover cent has to land somewhere.
            Gift__c gift = giftOf(100.01, false);
            Fund__c general = [SELECT Id FROM Fund__c LIMIT 1];
            Fund__c scholarship = GivingTestDataFactory.buildFund('Scholarship', false);
            Fund__c building = GivingTestDataFactory.buildFund('Building', false);
            insert new List<Fund__c>{ scholarship, building };

            Test.startTest();
            insert new List<Gift_Allocation__c>{
                new Gift_Allocation__c(Gift__c = gift.Id, Fund__c = general.Id, Percent__c = 33.33),
                new Gift_Allocation__c(
                    Gift__c = gift.Id,
                    Fund__c = scholarship.Id,
                    Percent__c = 33.33
                ),
                new Gift_Allocation__c(Gift__c = gift.Id, Fund__c = building.Id, Percent__c = 33.34)
            };
            Test.stopTest();

            Decimal total = 0;
            for (Gift_Allocation__c allocation : [
                SELECT Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :gift.Id
            ]) {
                total += allocation.Amount__c;
            }
            System.assertEquals(
                100.01,
                total,
                'The rounding difference goes to the largest allocation, so the total is exact.'
            );
            System.assertEquals(
                33.35,
                [
                    SELECT Amount__c
                    FROM Gift_Allocation__c
                    WHERE Gift__c = :gift.Id
                    ORDER BY Amount__c DESC
                    LIMIT 1
                ]
                .Amount__c,
                'And it lands on the largest allocation, not on whichever row saved last.'
            );
        }
    }

    @IsTest
    static void anUnderAllocatedSaveIsRefusedAndNamesTheDifference() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftOf(250, true);
            Gift_Allocation__c allocation = [
                SELECT Id, Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :gift.Id
            ];

            String message = '';
            Test.startTest();
            try {
                allocation.Amount__c = 100;
                update allocation;
            } catch (DmlException totalsError) {
                message = totalsError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assert(
                message.contains('The difference is'),
                'The message names the difference so David can see what is missing: ' + message
            );
        }
    }

    @IsTest
    static void deletingTheOnlyAllocationIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftOf(250, true);
            Gift_Allocation__c allocation = [
                SELECT Id
                FROM Gift_Allocation__c
                WHERE Gift__c = :gift.Id
            ];

            String message = '';
            Test.startTest();
            try {
                delete allocation;
            } catch (DmlException deleteError) {
                message = deleteError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assert(
                message.contains('The difference is'),
                'A gift cannot be left with nothing designated: ' + message
            );
        }
    }

    @IsTest
    static void deletingAGiftTakesItsAllocationsWithIt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftOf(250, true);

            Test.startTest();
            delete gift;
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Gift_Allocation__c],
                'Allocations are deleted with their gift, and the total check does not fight it.'
            );
        }
    }

    @IsTest
    static void aGiftWithNoDefaultFundSaysWhatToDo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            delete [SELECT Id FROM Fund__c];
            Contact person = [SELECT Id FROM Contact LIMIT 1];

            String message = '';
            Test.startTest();
            try {
                insert GivingTestDataFactory.buildGift(person.Id, 40);
            } catch (DmlException fundError) {
                message = fundError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assert(
                message.contains('No default fund is set'),
                'The error tells Maria exactly where to go: ' + message
            );
        }
    }

    @IsTest
    static void twoHundredAllocationsSaveInOneGo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = [SELECT Id FROM Contact LIMIT 1];
            Fund__c fund = [SELECT Id FROM Fund__c LIMIT 1];
            List<Gift__c> gifts = GivingTestDataFactory.buildGifts(person.Id, 200, 10);
            try {
                GiftService.suppressDefaultAllocations = true;
                insert gifts;
            } finally {
                GiftService.suppressDefaultAllocations = false;
            }

            List<Gift_Allocation__c> allocations = new List<Gift_Allocation__c>();
            for (Gift__c gift : gifts) {
                allocations.add(GivingTestDataFactory.buildAllocation(gift.Id, fund.Id, 10));
            }

            Test.startTest();
            insert allocations;
            Test.stopTest();

            System.assertEquals(
                200,
                [SELECT COUNT() FROM Gift_Allocation__c],
                'Two hundred allocations in one save stay inside the platform limits.'
            );
        }
    }

    @IsTest
    static void undeletingAGiftBringsItsAllocationsBackAndTheyStillAddUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftOf(250, true);
            delete gift;

            Test.startTest();
            undelete gift;
            Test.stopTest();

            Decimal total = 0;
            for (Gift_Allocation__c allocation : [
                SELECT Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :gift.Id
            ]) {
                total += allocation.Amount__c;
            }
            System.assertEquals(
                250,
                total,
                'Allocations come back with their gift and the totals are rechecked, not assumed.'
            );
        }
    }
}
