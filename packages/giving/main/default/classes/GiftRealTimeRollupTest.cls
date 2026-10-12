/**
 * Real-time rollups on the Giving objects (rollup proposal bug 1, slice S1).
 *
 * The real-time handler used to be registered only on Contact and Household Member, so a total in
 * Real-time or Both mode moved only at night. Giving now registers it on Gift, Soft Credit, Gift
 * Allocation and Commitment through its Automation Registry rows. These tests save records and
 * read the totals back without ever asking for a recalculation: if a total moved, the save moved
 * it.
 *
 * Today's engine finishes a real-time run in a queued job, so the totals are read after
 * `Test.stopTest`, which runs that job. The stricter promise, totals right before the save
 * returns, is `theTotalsAreRightInTheSameTransaction` below, which is switched on with the new
 * engine's instant path (slice S6).
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class GiftRealTimeRollupTest {
    private static final Set<String> GIVING_SOURCES = new Set<String>{
        'Gift__c',
        'Soft_Credit__c',
        'Gift_Allocation__c',
        'Commitment__c'
    };

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        GivingRollupTestData.installShippedRollups();
    }

    @IsTest
    static void everyGivingSourceIsRegisteredForRealTimeRollups() {
        Set<String> registered = new Set<String>();
        for (Automation_Registry__mdt entry : [
            SELECT Object_Name__c, Enabled_By_Default__c
            FROM Automation_Registry__mdt
            WHERE Handler_Class__c = 'RollupTriggerHandler' AND Object_Name__c IN :GIVING_SOURCES
        ]) {
            Assert.isTrue(
                entry.Enabled_By_Default__c,
                'A real-time total is on from install, like every shipped total.'
            );
            registered.add(entry.Object_Name__c);
        }
        Assert.areEqual(
            GIVING_SOURCES,
            registered,
            'Every Giving object a shipped rollup counts runs the real-time rollups when saved.'
        );
    }

    /**
     * Ana gives 250. Her own totals and her household's move with the save, and nobody pressed
     * Recalculate.
     */
    @IsTest
    static void aSavedGiftUpdatesThePersonAndTheHousehold() {
        Contact ana = [SELECT Id, AccountId FROM Contact LIMIT 1];

        Test.startTest();
        insert GivingTestDataFactory.buildGift(ana.Id, 250);
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
        Assert.areEqual(250, person.Total_Giving__c, 'Ana\'s total giving');
        Assert.areEqual(1, person.Gift_Count__c, 'Ana\'s gift count');
        Assert.areEqual(250, person.Largest_Gift__c, 'Ana\'s largest gift');
        Assert.areEqual(Date.today(), person.Last_Gift_Date__c, 'Ana\'s last gift date');

        Account household = GivingRollupTestData.account(ana.AccountId);
        Assert.areEqual(250, household.Total_Giving__c, 'The Nolan household\'s total giving');
        Assert.areEqual(1, household.Gift_Count__c, 'The Nolan household\'s gift count');
    }

    /** The allocation a gift is given to the default fund moves that fund's total. */
    @IsTest
    static void aSavedGiftUpdatesTheFundItIsAllocatedTo() {
        Contact ana = [SELECT Id FROM Contact LIMIT 1];
        Fund__c general = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];

        Test.startTest();
        insert GivingTestDataFactory.buildGift(ana.Id, 250);
        Test.stopTest();

        Fund__c fund = GivingRollupTestData.fund(general.Id);
        GivingTestDataFactory.assertRollupWrote(fund.Total_Raised__c);
        Assert.areEqual(250, fund.Total_Raised__c, 'General has raised the gift');
        Assert.areEqual(1, fund.Gift_Count__c, 'One gift designated to General');
    }

    /** Bea solicited Ana's gift. Her soft credit total moves when the credit is saved. */
    @IsTest
    static void aSavedSoftCreditUpdatesThePersonCredited() {
        Contact ana = [SELECT Id FROM Contact LIMIT 1];
        Contact bea = GivingTestDataFactory.insertHouseholdContact(
            'The Lindqvist Family',
            'Bea',
            'Lindqvist'
        );
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 500);
        insert gift;
        GivingRollupTestData.nextSave();

        Test.startTest();
        insert new Soft_Credit__c(
            Gift__c = gift.Id,
            Contact__c = bea.Id,
            Role__c = 'Solicitor',
            Amount__c = 500
        );
        Test.stopTest();

        Contact credited = GivingRollupTestData.person(bea.Id);
        GivingTestDataFactory.assertRollupWrote(credited.Total_Soft_Credits__c);
        Assert.areEqual(500, credited.Total_Soft_Credits__c, 'Bea is recognized for the gift');
        Assert.areEqual(
            0,
            GivingRollupTestData.valueOf(credited.Total_Giving__c),
            'Recognition is never giving'
        );
    }

    /** Ana pledges 300. Her pledge balance shows it as soon as the pledge is saved. */
    @IsTest
    static void aSavedCommitmentUpdatesThePledgeBalance() {
        Contact ana = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        insert new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = ana.Id,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today(),
            Expected_Total__c = 300,
            Installments_Planned__c = 3
        );
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Pledge_Balance__c);
        Assert.areEqual(300, person.Pledge_Balance__c, 'Promised and not yet paid');
    }

    /**
     * Two hundred gifts in one save, ten each from twenty donors in twenty households, as a gift
     * batch or an import posts them. Every donor, every household and the fund are right, and the
     * save stays inside the platform's limits (plan Section 7.2).
     */
    @IsTest
    static void twoHundredGiftsInOneSaveUpdateEveryDonor() {
        List<String> names = new List<String>();
        for (Integer i = 0; i < 20; i++) {
            names.add('Donor' + i);
        }
        List<Contact> donors = GivingRollupTestData.peopleInOwnHouseholds(names);
        List<Gift__c> gifts = new List<Gift__c>();
        for (Contact donor : donors) {
            gifts.addAll(GivingTestDataFactory.buildGifts(donor.Id, 10, 25));
        }
        Assert.areEqual(200, gifts.size(), 'The bulk case is two hundred records');

        Test.startTest();
        insert gifts;
        Test.stopTest();

        Map<Id, Contact> people = new Map<Id, Contact>(
            [
                SELECT Id, AccountId, Total_Giving__c, Gift_Count__c
                FROM Contact
                WHERE Id IN :donors
            ]
        );
        Set<Id> householdIds = new Set<Id>();
        for (Contact donor : people.values()) {
            GivingTestDataFactory.assertRollupWrote(donor.Total_Giving__c);
            Assert.areEqual(250, donor.Total_Giving__c, 'Ten gifts of 25 from each donor');
            Assert.areEqual(10, donor.Gift_Count__c, 'Ten gifts from each donor');
            householdIds.add(donor.AccountId);
        }
        for (Account household : [
            SELECT Total_Giving__c, Gift_Count__c
            FROM Account
            WHERE Id IN :householdIds
        ]) {
            Assert.areEqual(250, household.Total_Giving__c, 'Each household\'s total');
            Assert.areEqual(10, household.Gift_Count__c, 'Each household\'s gift count');
        }
        Fund__c general = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];
        Assert.areEqual(
            5000,
            GivingRollupTestData.fund(general.Id).Total_Raised__c,
            'Every gift went to General'
        );
    }

    /**
     * DISABLED until slice S6 (instant path in the new engine). Add `@IsTest` back in that slice.
     *
     * The promise rollup proposal D4 makes for an ordinary save: the totals are right before the
     * save returns, with no queued job in between. Today's engine finishes a real-time run in a
     * queued job, so the totals are still blank at the assertion below and this test fails by
     * design until the instant path lands.
     */
    @SuppressWarnings('PMD.ApexUnitTestMethodShouldHaveIsTestAnnotation, PMD.UnusedPrivateMethod')
    static void theTotalsAreRightInTheSameTransaction() {
        Contact ana = [SELECT Id, AccountId FROM Contact LIMIT 1];

        Test.startTest();
        insert GivingTestDataFactory.buildGift(ana.Id, 250);
        Contact person = GivingRollupTestData.person(ana.Id);
        Account household = GivingRollupTestData.account(ana.AccountId);
        Test.stopTest();

        Assert.areEqual(250, person.Total_Giving__c, 'Right before the save returned');
        Assert.areEqual(250, household.Total_Giving__c, 'And on the household too');
    }
}
