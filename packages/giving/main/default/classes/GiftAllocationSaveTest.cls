/**
 * The allocations the package saves itself (R-GA1, R-GA2): a new gift's default allocation for
 * the whole amount, and a single allocation moved with its gift's amount. Pinned in bulk, with
 * the split gift that is refused and the allocation that already holds the new amount, so the
 * allocation handlers can share what the gift save already read (D-143).
 */
@IsTest(
    testFor='ApexClass:GiftService, ApexClass:GiftAllocationTriggerHandler, ApexClass:GiftPostingLock'
)
private class GiftAllocationSaveTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        }
    }

    private static List<Gift__c> gifts(Integer count, Decimal amount) {
        Contact person = [SELECT Id FROM Contact LIMIT 1];
        return GivingTestDataFactory.buildGifts(person.Id, count, amount);
    }

    private static Map<Id, List<Gift_Allocation__c>> allocationsOf(List<Gift__c> gifts) {
        Map<Id, List<Gift_Allocation__c>> byGift = new Map<Id, List<Gift_Allocation__c>>();
        for (Gift_Allocation__c allocation : [
            SELECT Gift__c, Fund__c, Amount__c, Percent__c, LastModifiedDate
            FROM Gift_Allocation__c
            WHERE Gift__c IN :new Map<Id, Gift__c>(gifts).keySet()
        ]) {
            if (!byGift.containsKey(allocation.Gift__c)) {
                byGift.put(allocation.Gift__c, new List<Gift_Allocation__c>());
            }
            byGift.get(allocation.Gift__c).add(allocation);
        }
        return byGift;
    }

    @IsTest
    static void twoHundredNewGiftsEachGetOneAllocationForTheWholeAmount() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Gift__c> saved = gifts(200, 40);
            Id fundId = [SELECT Id FROM Fund__c LIMIT 1].Id;

            Test.startTest();
            insert saved;
            Test.stopTest();

            Map<Id, List<Gift_Allocation__c>> byGift = allocationsOf(saved);
            Assert.areEqual(200, byGift.size(), 'Every gift is allocated.');
            for (List<Gift_Allocation__c> allocations : byGift.values()) {
                Assert.areEqual(1, allocations.size(), 'One allocation each.');
                Assert.areEqual(fundId, allocations[0].Fund__c, 'To the default fund.');
                Assert.areEqual(40, allocations[0].Amount__c, 'For the whole amount.');
                Assert.areEqual(100, allocations[0].Percent__c, 'Which is all of it.');
            }
        }
    }

    @IsTest
    static void twoHundredAmountChangesEachMoveTheirSingleAllocation() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Gift__c> saved = gifts(200, 40);
            insert saved;
            for (Gift__c gift : saved) {
                gift.Amount__c = 55.5;
            }

            Test.startTest();
            update saved;
            Test.stopTest();

            Map<Id, List<Gift_Allocation__c>> byGift = allocationsOf(saved);
            for (List<Gift_Allocation__c> allocations : byGift.values()) {
                Assert.areEqual(1, allocations.size(), 'Still one allocation each.');
                Assert.areEqual(55.5, allocations[0].Amount__c, 'It moved with the gift.');
                Assert.areEqual(100, allocations[0].Percent__c, 'Still all of it.');
            }
        }
    }

    @IsTest
    static void anAmountChangeOnASplitGiftIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = gifts(1, 100)[0];
            try {
                GiftService.suppressDefaultAllocations = true;
                insert gift;
            } finally {
                GiftService.suppressDefaultAllocations = false;
            }
            Fund__c building = GivingTestDataFactory.buildFund('Building Fund', false);
            insert building;
            Id generalId = [SELECT Id FROM Fund__c WHERE Id != :building.Id LIMIT 1].Id;
            insert new List<Gift_Allocation__c>{
                GivingTestDataFactory.buildAllocation(gift.Id, generalId, 60),
                GivingTestDataFactory.buildAllocation(gift.Id, building.Id, 40)
            };

            Test.startTest();
            Database.SaveResult result = Database.update(
                new Gift__c(Id = gift.Id, Amount__c = 120),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'The package cannot know which fund changed.');
            Assert.areEqual(
                Label.Giving_Gift_AmountChangeSplit,
                result.getErrors()[0].getMessage(),
                'The person is told to adjust the split first.'
            );
        }
    }

    @IsTest
    static void aGiftAndAllocationChangedTogetherStillAddUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = gifts(1, 100)[0];
            insert gift;
            Gift_Allocation__c allocation = allocationsOf(new List<Gift__c>{ gift })
                .get(gift.Id)[0];

            Test.startTest();
            update new Gift__c(Id = gift.Id, Amount__c = 80);
            update new Gift_Allocation__c(Id = allocation.Id, Percent__c = 100);
            Test.stopTest();

            Gift_Allocation__c after = allocationsOf(new List<Gift__c>{ gift }).get(gift.Id)[0];
            Assert.areEqual(80, after.Amount__c, 'The percent is turned into the new amount.');
            Assert.areEqual(100, after.Percent__c, 'All of it.');
        }
    }
}
