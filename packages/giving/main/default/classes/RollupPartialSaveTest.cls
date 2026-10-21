/**
 * Totals after a partial save: a save with allOrNone false, as the Bulk API, Data Loader and
 * `Database.delete(records, false)` make it, where some records are refused.
 *
 * The platform then rolls the first attempt back, the Rollup Queue entries and the processor it
 * queued with it, and runs the triggers again for the records that passed, keeping static
 * variables. A retry that believed its processor was already queued, or its records already
 * handled, left entries Pending with no processor coming and totals that never caught up.
 *
 * The refusals come from the posting lock: Ana's two gifts dated in the closed month cannot be
 * changed or deleted (G-20), the other five can.
 */
@IsTest(testFor='ApexClass:RollupQueue, ApexClass:TriggerHandler')
private class RollupPartialSaveTest {
    private static final Decimal CLOSED_AMOUNT = 100;
    private static final Decimal OPEN_AMOUNT = 50;

    private static Date lastClosedDay() {
        return Date.today().toStartOfMonth().addDays(-1);
    }

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            Contact ana = GivingTestDataFactory.insertHouseholdContact(
                'The Nolan Family',
                'Ana',
                'Nolan'
            );
            GivingRollupTestData.installShippedRollups();
            List<Gift__c> gifts = GivingTestDataFactory.buildGifts(ana.Id, 2, CLOSED_AMOUNT);
            for (Gift__c gift : gifts) {
                gift.Gift_Date__c = lastClosedDay().addDays(-3);
            }
            gifts.addAll(GivingTestDataFactory.buildGifts(ana.Id, 5, OPEN_AMOUNT));
            insert gifts;
        }
        // Each test starts with nothing queued, so only what its own save queued is processed.
        delete [SELECT Id FROM Rollup_Queue__c];
    }

    private static Contact ana() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
    }

    private static List<Gift__c> gifts() {
        return [SELECT Id, Amount__c FROM Gift__c ORDER BY Amount__c DESC];
    }

    private static Id defaultFundId() {
        return [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1].Id;
    }

    private static Integer refusedCount(List<Database.SaveResult> results) {
        Integer refused = 0;
        for (Database.SaveResult result : results) {
            refused += result.isSuccess() ? 0 : 1;
        }
        return refused;
    }

    private static Integer refusedCount(List<Database.DeleteResult> results) {
        Integer refused = 0;
        for (Database.DeleteResult result : results) {
            refused += result.isSuccess() ? 0 : 1;
        }
        return refused;
    }

    private static Integer pendingEntries() {
        return [SELECT COUNT() FROM Rollup_Queue__c WHERE Status__c = :RollupQueue.STATUS_PENDING];
    }

    /** Whether a queued entry for this target entity names this record. */
    private static Boolean queued(Schema.SObjectType target, Id recordId) {
        for (Rollup_Queue__c entry : [
            SELECT Record_Ids__c
            FROM Rollup_Queue__c
            WHERE Target_Object__c = :String.valueOf(target)
        ]) {
            if (entry.Record_Ids__c != null && entry.Record_Ids__c.contains(recordId)) {
                return true;
            }
        }
        return false;
    }

    private static void assertTotals(Decimal total, Integer count) {
        Contact person = GivingRollupTestData.person(ana().Id);
        GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
        Assert.areEqual(total, person.Total_Giving__c, 'Ana\'s total giving');
        Assert.areEqual(count, person.Gift_Count__c, 'Ana\'s gift count');
        Assert.areEqual(
            total,
            GivingRollupTestData.account(ana().AccountId).Total_Giving__c,
            'The household follows'
        );
        Assert.areEqual(
            count,
            GivingRollupTestData.fund(defaultFundId()).Gift_Count__c,
            'The fund counts every gift left'
        );
    }

    /** The case seen in the org: 7 gifts deleted, 2 refused, and the totals never caught up. */
    @IsTest
    static void aDeleteWithRefusedGiftsStillProcessesTheTotals() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.closeBooksThrough(lastClosedDay());
            List<Gift__c> all = gifts();

            Test.startTest();
            List<Database.DeleteResult> results = Database.delete(all, false);
            Test.stopTest();

            Assert.areEqual(2, refusedCount(results), 'The two gifts in the books stay');
            Assert.areEqual(0, pendingEntries(), 'A processor ran for what the retry queued');
            assertTotals(2 * CLOSED_AMOUNT, 2);
        }
    }

    /**
     * The allocations are deleted with their gifts and fire no trigger, so the fund is read
     * before the delete. The retry must read it again: what the first attempt read went with it.
     */
    @IsTest
    static void aDeleteWithRefusedGiftsStillQueuesTheFund() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.closeBooksThrough(lastClosedDay());
            List<Gift__c> all = gifts();

            Test.startTest();
            Database.delete(all, false);
            Boolean fundQueued = queued(Fund__c.SObjectType, defaultFundId());
            Test.stopTest();

            Assert.isTrue(fundQueued, 'The fund of the deleted allocations is queued');
        }
    }

    @IsTest
    static void anInsertWithARefusedGiftStillProcessesTheTotals() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.closeBooksThrough(lastClosedDay());
            Gift__c intoClosedMonth = GivingTestDataFactory.buildGift(ana().Id, 30);
            intoClosedMonth.Gift_Date__c = lastClosedDay();
            List<Gift__c> added = new List<Gift__c>{
                intoClosedMonth,
                GivingTestDataFactory.buildGift(ana().Id, 20),
                GivingTestDataFactory.buildGift(ana().Id, 10)
            };

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(added, false);
            Boolean anaQueued = queued(Contact.SObjectType, ana().Id);
            Test.stopTest();

            Assert.areEqual(1, refusedCount(results), 'Nothing new goes into a closed month');
            Assert.isTrue(anaQueued, 'The retry queued Ana');
            Assert.areEqual(0, pendingEntries(), 'A processor ran for what the retry queued');
            assertTotals(2 * CLOSED_AMOUNT + 5 * OPEN_AMOUNT + 20 + 10, 9);
        }
    }

    @IsTest
    static void anUpdateWithARefusedGiftStillProcessesTheTotals() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.closeBooksThrough(lastClosedDay());
            List<Gift__c> all = gifts();

            Test.startTest();
            List<Database.SaveResult> results = Database.update(
                new List<Gift__c>{
                    new Gift__c(Id = all[0].Id, Amount__c = 150),
                    new Gift__c(Id = all[2].Id, Amount__c = 80)
                },
                false
            );
            Test.stopTest();

            Assert.areEqual(1, refusedCount(results), 'The amount in the books stays');
            Assert.areEqual(0, pendingEntries(), 'A processor ran for what the retry queued');
            assertTotals(2 * CLOSED_AMOUNT + 4 * OPEN_AMOUNT + 80, 7);
        }
    }
}
