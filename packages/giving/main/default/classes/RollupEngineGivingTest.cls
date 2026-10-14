/**
 * BarnCRM's own rollup engine on the shipped giving totals, called through its entry point
 * (`RollupEngine.recalculate`), which is what slices S6, S7 and S8 call (rollup proposal S5).
 *
 * The fund totals are sourced from Gift Allocation and filtered and windowed on the parent gift
 * (`Gift__r.Status__c`, `Gift__r.Gift_Date__c`), which the vendored engine could not aggregate.
 */
@IsTest(testFor='ApexClass:RollupEngine')
private class RollupEngineGivingTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        }
    }

    private static Gift__c gift(Id donorId, Decimal amount, String status, Date giftDate) {
        Gift__c gift = GivingTestDataFactory.buildGift(donorId, amount);
        gift.Status__c = status;
        gift.Gift_Date__c = giftDate;
        return gift;
    }

    @IsTest
    static void fundTotalsReadThroughTheParentGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = [SELECT Id FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
            Fund__c general = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];
            insert new List<Gift__c>{
                gift(ana.Id, 100, 'Received', Date.today()),
                gift(ana.Id, 40, 'Received', Date.today().addYears(-2)),
                gift(ana.Id, 25, 'Pending', Date.today())
            };
            GivingRollupTestData.installShippedRollups();

            Test.startTest();
            RollupEngine.Result first = RollupEngine.recalculate(
                new Set<Id>{ general.Id },
                Fund__c.SObjectType
            );
            RollupEngine.Result second = RollupEngine.recalculate(
                new Set<Id>{ general.Id },
                Fund__c.SObjectType
            );
            Test.stopTest();

            Fund__c fund = [
                SELECT
                    Total_Raised__c,
                    Total_Raised_This_Year__c,
                    Gift_Count__c,
                    Last_Gift_Date__c,
                    Rollups_Last_Calculated__c
                FROM Fund__c
                WHERE Id = :general.Id
            ];
            Assert.areEqual(140, fund.Total_Raised__c, 'Received gifts only, filtered on the gift');
            Assert.areEqual(100, fund.Total_Raised_This_Year__c, 'Windowed on the gift date');
            Assert.areEqual(2, fund.Gift_Count__c, 'The pending gift is not counted');
            Assert.areEqual(Date.today(), fund.Last_Gift_Date__c, 'The latest gift date');
            Assert.isNotNull(fund.Rollups_Last_Calculated__c, 'Stamped with the totals');
            Assert.isTrue(first.refused.isEmpty(), 'Every shipped fund total planned and ran');
            Assert.areEqual(1, first.written.size(), 'The fund was written');
            Assert.isTrue(second.written.isEmpty(), 'Nothing changed the second time');
        }
    }
}
