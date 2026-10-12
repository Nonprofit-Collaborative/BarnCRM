/**
 * Rollup regression suite, part 1: what every way of changing a gift does to the totals
 * (rollup proposal, migration step 1, slice S2).
 *
 * Engine agnostic on purpose. Each test changes records the way staff do, through ordinary saves
 * and the public `RollupService` entry points, and asserts only the values on the target records.
 * Nothing here names the engine behind `RollupService`, so the same tests judge today's engine and
 * the one that replaces it (proposal D1).
 *
 * A test method is one transaction, so a test that saves the same record twice marks each later
 * save with `GivingRollupTestData.nextSave()`, as two separate edits would be in an org. Every
 * change happens between `Test.startTest` and `Test.stopTest`, so work an engine queues has
 * finished before anything is read back.
 *
 * Merges are covered by `GivingContactMergeTest`; this class adds the totals beyond the sum.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class RollupRegressionPathsTest {
    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        GivingTestDataFactory.insertHouseholdContact('The Lindqvist Family', 'Bea', 'Lindqvist');
        GivingRollupTestData.installShippedRollups();
    }

    private static Contact ana() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
    }

    private static Contact bea() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Lindqvist' LIMIT 1];
    }

    /** An organization's gift lands on the organization and on no household. */
    @IsTest
    static void anOrganizationsGiftLandsOnTheOrganization() {
        Account riverbend = GivingTestDataFactory.insertOrganization('Riverbend Manufacturing');

        Test.startTest();
        insert GivingTestDataFactory.buildAccountGift(riverbend.Id, 1000);
        Test.stopTest();

        Account organization = GivingRollupTestData.account(riverbend.Id);
        GivingTestDataFactory.assertRollupWrote(organization.Total_Giving__c);
        Assert.areEqual(1000, organization.Total_Giving__c, 'Riverbend\'s total giving');
        Assert.areEqual(1, organization.Gift_Count__c, 'Riverbend\'s gift count');
        Assert.areEqual(
            0,
            GivingRollupTestData.valueOf(
                GivingRollupTestData.account(ana().AccountId).Total_Giving__c
            ),
            'No household was credited'
        );
    }

    /** Ana's 100 was mistyped and corrected to 175. Every total follows the correction. */
    @IsTest
    static void changingTheAmountMovesEveryTotal() {
        Contact ana = ana();
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 100);

        Test.startTest();
        insert gift;
        GivingRollupTestData.nextSave();
        update new Gift__c(Id = gift.Id, Amount__c = 175);
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
        Assert.areEqual(175, person.Total_Giving__c, 'The corrected amount, not the sum of both');
        Assert.areEqual(1, person.Gift_Count__c, 'Still one gift');
        Assert.areEqual(175, person.Largest_Gift__c, 'The largest gift is the corrected one');
        Assert.areEqual(
            175,
            GivingRollupTestData.account(ana.AccountId).Total_Giving__c,
            'The household follows'
        );
        Fund__c general = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];
        Assert.areEqual(
            175,
            GivingRollupTestData.fund(general.Id).Total_Raised__c,
            'The single allocation moved with the gift, and so did the fund'
        );
    }

    /** A pending gift counts nowhere until it is received. */
    @IsTest
    static void aPendingGiftCountsOnceItIsReceived() {
        Contact ana = ana();
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 80);
        gift.Status__c = 'Pending';

        Test.startTest();
        insert gift;
        GivingRollupTestData.nextSave();
        update new Gift__c(Id = gift.Id, Status__c = 'Received');
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
        Assert.areEqual(80, person.Total_Giving__c, 'Received now, so counted');
        Assert.areEqual(1, person.Gift_Count__c, 'Counted once');
    }

    /** A gift received and then put back to Pending leaves every total it was in. */
    @IsTest
    static void aGiftThatStopsMatchingTheFilterLeavesTheTotals() {
        Contact ana = ana();
        Gift__c kept = GivingTestDataFactory.buildGift(ana.Id, 40);
        Gift__c reopened = GivingTestDataFactory.buildGift(ana.Id, 60);

        Test.startTest();
        insert new List<Gift__c>{ kept, reopened };
        GivingRollupTestData.nextSave();
        update new Gift__c(Id = reopened.Id, Status__c = 'Pending');
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
        Assert.areEqual(40, person.Total_Giving__c, 'Only the gift still received');
        Assert.areEqual(1, person.Gift_Count__c, 'Only the gift still received');
        Assert.areEqual(40, person.Largest_Gift__c, 'The pending gift is not the largest');
    }

    /** A gift entered by mistake and deleted leaves no trace in any total. */
    @IsTest
    static void deletingAGiftTakesItOutOfEveryTotal() {
        Contact ana = ana();
        Gift__c kept = GivingTestDataFactory.buildGift(ana.Id, 100);
        Gift__c mistake = GivingTestDataFactory.buildGift(ana.Id, 50);

        Test.startTest();
        insert new List<Gift__c>{ kept, mistake };
        GivingRollupTestData.nextSave();
        delete mistake;
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
        Assert.areEqual(100, person.Total_Giving__c, 'Only the gift that stands');
        Assert.areEqual(1, person.Gift_Count__c, 'One gift left');
        Assert.areEqual(100, person.Largest_Gift__c, 'The largest of what is left');
        Account household = GivingRollupTestData.account(ana.AccountId);
        Assert.areEqual(100, household.Total_Giving__c, 'The household follows');
        Assert.areEqual(1, household.Gift_Count__c, 'The household follows');
    }

    /** Deleting the only gift leaves zero, not the old total. */
    @IsTest
    static void deletingTheOnlyGiftLeavesNothing() {
        Contact ana = ana();
        Gift__c mistake = GivingTestDataFactory.buildGift(ana.Id, 50);

        Test.startTest();
        insert mistake;
        GivingRollupTestData.nextSave();
        delete mistake;
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        Assert.areEqual(0, GivingRollupTestData.valueOf(person.Total_Giving__c), 'Nothing given');
        Assert.areEqual(0, GivingRollupTestData.valueOf(person.Gift_Count__c), 'No gifts');
    }

    /** A deleted gift restored from the recycle bin counts again. */
    @IsTest
    static void restoringADeletedGiftPutsItBack() {
        Contact ana = ana();
        Gift__c kept = GivingTestDataFactory.buildGift(ana.Id, 100);
        Gift__c restored = GivingTestDataFactory.buildGift(ana.Id, 50);

        Test.startTest();
        insert new List<Gift__c>{ kept, restored };
        GivingRollupTestData.nextSave();
        delete restored;
        GivingRollupTestData.nextSave();
        undelete restored;
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
        Assert.areEqual(150, person.Total_Giving__c, 'Both gifts again');
        Assert.areEqual(2, person.Gift_Count__c, 'Both gifts again');
        Assert.areEqual(
            150,
            GivingRollupTestData.account(ana.AccountId).Total_Giving__c,
            'The household follows'
        );
    }

    /**
     * The gift was Bea's, not Ana's. Moving it takes it off Ana and her household and puts it on
     * Bea and hers: the old parent and the new one are both recalculated.
     */
    @IsTest
    static void movingAGiftToAnotherDonorMovesItsTotals() {
        Contact ana = ana();
        Contact bea = bea();
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 100);

        Test.startTest();
        insert gift;
        GivingRollupTestData.nextSave();
        update new Gift__c(Id = gift.Id, Donor_Contact__c = bea.Id);
        Test.stopTest();

        Contact oldDonor = GivingRollupTestData.person(ana.Id);
        Contact newDonor = GivingRollupTestData.person(bea.Id);
        GivingTestDataFactory.assertRollupWrote(newDonor.Total_Giving__c);
        Assert.areEqual(100, newDonor.Total_Giving__c, 'Bea\'s gift');
        Assert.areEqual(1, newDonor.Gift_Count__c, 'Bea\'s gift');
        Assert.areEqual(0, GivingRollupTestData.valueOf(oldDonor.Total_Giving__c), 'Not Ana\'s');
        Assert.areEqual(0, GivingRollupTestData.valueOf(oldDonor.Gift_Count__c), 'Not Ana\'s');
        Assert.areEqual(
            100,
            GivingRollupTestData.account(bea.AccountId).Total_Giving__c,
            'Bea\'s household is credited'
        );
        Assert.areEqual(
            0,
            GivingRollupTestData.valueOf(
                GivingRollupTestData.account(ana.AccountId).Total_Giving__c
            ),
            'Ana\'s household no longer is'
        );
    }

    /** An allocation moved to another fund moves the money between the two fund totals. */
    @IsTest
    static void movingAnAllocationMovesItBetweenFunds() {
        Contact ana = ana();
        Fund__c general = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];
        Fund__c building = GivingTestDataFactory.buildFund('Building', false);
        insert building;
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 100);

        Test.startTest();
        insert gift;
        GivingRollupTestData.nextSave();
        Gift_Allocation__c allocation = [
            SELECT Id
            FROM Gift_Allocation__c
            WHERE Gift__c = :gift.Id
            LIMIT 1
        ];
        update new Gift_Allocation__c(Id = allocation.Id, Fund__c = building.Id);
        Test.stopTest();

        Fund__c toFund = GivingRollupTestData.fund(building.Id);
        GivingTestDataFactory.assertRollupWrote(toFund.Total_Raised__c);
        Assert.areEqual(100, toFund.Total_Raised__c, 'Building has the money now');
        Assert.areEqual(1, toFund.Gift_Count__c, 'And the gift');
        Fund__c fromFund = GivingRollupTestData.fund(general.Id);
        Assert.areEqual(
            0,
            GivingRollupTestData.valueOf(fromFund.Total_Raised__c),
            'General does not'
        );
        Assert.areEqual(
            0,
            GivingRollupTestData.valueOf(fromFund.Gift_Count__c),
            'General does not'
        );
    }

    /**
     * Two people are merged. The survivor's count, largest gift and dates include what the merge
     * moved onto her, not only her total (C-20).
     */
    @IsTest
    static void aMergeMovesEveryTotalOntoTheSurvivor() {
        Contact ana = ana();
        Contact bea = bea();
        Gift__c hers = GivingTestDataFactory.buildGift(ana.Id, 100);
        Gift__c moved = GivingTestDataFactory.buildGift(bea.Id, 300);
        moved.Gift_Date__c = Date.today().addDays(-30);
        insert new List<Gift__c>{ hers, moved };

        Test.startTest();
        Database.merge(new Contact(Id = ana.Id), bea.Id);
        Test.stopTest();

        Contact survivor = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(survivor.Total_Giving__c);
        Assert.areEqual(400, survivor.Total_Giving__c, 'Both people\'s giving');
        Assert.areEqual(2, survivor.Gift_Count__c, 'Both people\'s gifts');
        Assert.areEqual(300, survivor.Largest_Gift__c, 'Bea\'s gift was the larger');
        Assert.areEqual(
            Date.today().addDays(-30),
            survivor.First_Gift_Date__c,
            'Bea\'s gift came first'
        );
    }

    /**
     * Two hundred gifts from twenty donors are corrected in one save, as a data fix through the
     * data loader would. Every donor's total is the corrected one (plan Section 7.2).
     */
    @IsTest
    static void twoHundredCorrectionsInOneSaveAreAllCounted() {
        List<String> names = new List<String>();
        for (Integer i = 0; i < 20; i++) {
            names.add('Donor' + i);
        }
        List<Contact> donors = GivingRollupTestData.peopleInOwnHouseholds(names);
        List<Gift__c> gifts = new List<Gift__c>();
        for (Contact donor : donors) {
            gifts.addAll(GivingTestDataFactory.buildGifts(donor.Id, 10, 25));
        }

        Test.startTest();
        insert gifts;
        GivingRollupTestData.nextSave();
        List<Gift__c> corrections = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            corrections.add(new Gift__c(Id = gift.Id, Amount__c = 30));
        }
        update corrections;
        Test.stopTest();

        Assert.areEqual(200, corrections.size(), 'The bulk case is two hundred records');
        Set<Id> householdIds = new Set<Id>();
        for (Contact donor : [
            SELECT AccountId, Total_Giving__c, Gift_Count__c, Largest_Gift__c
            FROM Contact
            WHERE Id IN :donors
        ]) {
            GivingTestDataFactory.assertRollupWrote(donor.Total_Giving__c);
            Assert.areEqual(300, donor.Total_Giving__c, 'Ten corrected gifts of 30');
            Assert.areEqual(10, donor.Gift_Count__c, 'Still ten gifts');
            Assert.areEqual(30, donor.Largest_Gift__c, 'The corrected amount');
            householdIds.add(donor.AccountId);
        }
        for (Account household : [SELECT Total_Giving__c FROM Account WHERE Id IN :householdIds]) {
            Assert.areEqual(300, household.Total_Giving__c, 'Each household follows');
        }
    }
}
