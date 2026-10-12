/**
 * Rollup regression suite, part 2: households in both membership modes, and the household soft
 * credit totals (rollup proposal, migration step 1, slice S3; bug 3).
 *
 * Engine agnostic on purpose: records are changed through ordinary saves, totals are calculated
 * through the public `RollupService` entry points, and only target record values are asserted.
 *
 * The household soft credit totals reach the household through a mode-resolved token
 * (`Contact__c > {Household} | Account__c > {Household}`). Reading today's adapter and engine
 * says they cannot work yet: the adapter hands a token path to the engine as a rollup started
 * from the parent with the source record's own Id as its lookup, so a recalculation matches no
 * household, and on oi-test a real-time run on Soft Credit threw NullPointerException in
 * Rollup.fillWrapper (via getParentQueryWrapper), which is why Soft Credit is not registered for
 * real time until slice S6. The tests that encode the right answer are therefore written now and
 * switched off, each naming the slice that switches it on. A disabled test found to pass on
 * today's engine is switched on at once.
 *
 * Slice S5 switched on the household token tests. They run on BarnCRM's own engine: each calls
 * `GivingRollupTestData.useOwnEngine()` first, which routes `RollupService` to `RollupEngine` for
 * that test only, until slice S8 swaps the engine for everyone and removes the call.
 *
 * The `Account__c > {Household}` alternative resolves a person stored as an account, which needs
 * a Person Account org; it is not covered here.
 */
@IsTest
private class RollupRegressionHouseholdsTest {
    private static final Set<String> HOUSEHOLD_SOFT_KEYS = new Set<String>{
        GivingRollupTestData.HOUSEHOLD_SOFT_TOTAL,
        GivingRollupTestData.HOUSEHOLD_SOFT_COUNT
    };

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        // Credits are made by hand in these tests, so that which household is credited is
        // decided by the test and not by the automatic household credit.
        RecognitionTestData.setAutomaticHouseholdCredits(false);
    }

    /** A gift from Wei, solicited by the person given. Returns the gift. */
    private static Gift__c giftFromWei(Decimal amount) {
        Contact wei = GivingTestDataFactory.insertHouseholdContact('The Lee Family', 'Wei', 'Lee');
        Gift__c gift = GivingTestDataFactory.buildGift(wei.Id, amount);
        insert gift;
        return gift;
    }

    private static Soft_Credit__c solicitorCredit(Id giftId, Id contactId, Decimal amount) {
        return new Soft_Credit__c(
            Gift__c = giftId,
            Contact__c = contactId,
            Role__c = 'Solicitor',
            Amount__c = amount
        );
    }

    // ------------------------------------------------------------------------- membership modes

    /**
     * In junction mode a person's household is a membership row, not their contact's account.
     * Ana's gift still lands on the household she is a member of, and on her (R-G2, plan
     * Section 4.6).
     */
    @IsTest
    static void aGiftLandsOnTheHouseholdInJunctionMode() {
        RecognitionTestData.useJunctionMembership();
        Account garcia = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', null);
        RecognitionTestData.membership(garcia.Id, ana.Id, 'Head');
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        insert GivingTestDataFactory.buildGift(ana.Id, 120);
        Test.stopTest();

        Account household = GivingRollupTestData.account(garcia.Id);
        GivingTestDataFactory.assertRollupWrote(household.Total_Giving__c);
        Assert.areEqual(120, household.Total_Giving__c, 'The household Ana is a member of');
        Assert.areEqual(1, household.Gift_Count__c, 'One gift');
        Assert.areEqual(
            120,
            GivingRollupTestData.person(ana.Id).Total_Giving__c,
            'And Ana herself'
        );
    }

    /** The same gift recalculated, as the nightly run would, in junction mode. */
    @IsTest
    static void aRecalculatedGiftLandsOnTheHouseholdInJunctionMode() {
        RecognitionTestData.useJunctionMembership();
        Account garcia = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', null);
        RecognitionTestData.membership(garcia.Id, ana.Id, 'Head');
        insert GivingTestDataFactory.buildGift(ana.Id, 120);
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        GivingRollupTestData.recalculate(
            new Set<String>{
                GivingRollupTestData.HOUSEHOLD_TOTAL,
                GivingRollupTestData.HOUSEHOLD_COUNT
            }
        );
        Test.stopTest();

        Account household = GivingRollupTestData.account(garcia.Id);
        GivingTestDataFactory.assertRollupWrote(household.Total_Giving__c);
        Assert.areEqual(120, household.Total_Giving__c, 'The household Ana is a member of');
        Assert.areEqual(1, household.Gift_Count__c, 'One gift');
    }

    // ------------------------------------------------------------------- household soft credits

    /**
     * Ana solicited Wei's gift. In contact mode her household's soft credit total and count
     * include her credit, reached through `Contact__c > {Household}`.
     */
    @IsTest
    static void aSoftCreditLandsOnTheHouseholdInContactMode() {
        GivingRollupTestData.useOwnEngine();
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        Gift__c gift = giftFromWei(500);
        insert solicitorCredit(gift.Id, ana.Id, 500);
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        GivingRollupTestData.recalculate(HOUSEHOLD_SOFT_KEYS);
        Test.stopTest();

        Account household = GivingRollupTestData.account(ana.AccountId);
        Assert.areEqual(500, household.Total_Soft_Credits__c, 'Ana\'s credit, on her household');
        Assert.areEqual(1, household.Soft_Credit_Count__c, 'One gift recognized');
        Assert.areEqual(
            0,
            GivingRollupTestData.valueOf(household.Total_Giving__c),
            'Recognition is never giving'
        );
    }

    /**
     * The same credit in junction mode, where `{Household}` is the membership row rather than the
     * contact's account: the same definition, the same answer.
     */
    @IsTest
    static void aSoftCreditLandsOnTheHouseholdInJunctionMode() {
        GivingRollupTestData.useOwnEngine();
        RecognitionTestData.useJunctionMembership();
        Account garcia = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', null);
        RecognitionTestData.membership(garcia.Id, ana.Id, 'Head');
        Contact wei = RecognitionTestData.person('Wei', 'Lee', null);
        Gift__c gift = RecognitionTestData.gift(wei.Id, null, 500);
        insert solicitorCredit(gift.Id, ana.Id, 500);
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        GivingRollupTestData.recalculate(HOUSEHOLD_SOFT_KEYS);
        Test.stopTest();

        Account household = GivingRollupTestData.account(garcia.Id);
        Assert.areEqual(500, household.Total_Soft_Credits__c, 'Ana\'s credit, on her household');
        Assert.areEqual(1, household.Soft_Credit_Count__c, 'One gift recognized');
    }

    /**
     * Ana gives 500 and Luis, in her household, is credited for it automatically. 200 of the gift
     * goes back, and the negative gift carries a negative credit for Luis (R-SC5). The household
     * soft credit total nets to 300 and the count stays at one, as the giving totals do
     * (ADR-0022, ADR-0023).
     */
    @IsTest
    static void aRefundedCreditNetsOutOfTheHouseholdTotal() {
        GivingRollupTestData.useOwnEngine();
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        insert new Contact(FirstName = 'Luis', LastName = 'Nolan', AccountId = ana.AccountId);
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 500);
        insert gift;
        GiftService.refund(gift.Id, 200, 'Part returned');
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        GivingRollupTestData.recalculate(HOUSEHOLD_SOFT_KEYS);
        Test.stopTest();

        Account household = GivingRollupTestData.account(ana.AccountId);
        Assert.areEqual(
            300,
            household.Total_Soft_Credits__c,
            'Luis is recognized for what is held'
        );
        Assert.areEqual(1, household.Soft_Credit_Count__c, 'Still one gift recognized');
    }

    /**
     * DISABLED until slice S6 (trigger collection, instant path). Add `@IsTest` back in that
     * slice.
     *
     * A soft credit saved now moves the household soft credit total without a recalculation, as
     * the person's own soft credit total already does.
     */
    @SuppressWarnings('PMD.ApexUnitTestMethodShouldHaveIsTestAnnotation, PMD.UnusedPrivateMethod')
    static void aSavedSoftCreditUpdatesTheHousehold() {
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        Gift__c gift = giftFromWei(500);
        GivingRollupTestData.nextSave();
        insert solicitorCredit(gift.Id, ana.Id, 500);
        Test.stopTest();

        Account household = GivingRollupTestData.account(ana.AccountId);
        Assert.areEqual(500, household.Total_Soft_Credits__c, 'Moved with the save');
        Assert.areEqual(1, household.Soft_Credit_Count__c, 'Moved with the save');
    }

    /**
     * DISABLED until slice S6 (Contact and Household Member changes mark both households).
     * Add `@IsTest` back in that slice.
     *
     * Ana moves from the Nolan household to the Lindqvist household. A total reached through
     * `{Household}` is the household she is in now, so her soft credit leaves the old household's
     * total and joins the new one's, with no recalculation.
     */
    @SuppressWarnings('PMD.ApexUnitTestMethodShouldHaveIsTestAnnotation, PMD.UnusedPrivateMethod')
    static void aPersonWhoMovesTakesTheirSoftCreditsWithThem() {
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        Contact bea = GivingTestDataFactory.insertHouseholdContact(
            'The Lindqvist Family',
            'Bea',
            'Lindqvist'
        );
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        Gift__c gift = giftFromWei(500);
        GivingRollupTestData.nextSave();
        insert solicitorCredit(gift.Id, ana.Id, 500);
        GivingRollupTestData.nextSave();
        update new Contact(Id = ana.Id, AccountId = bea.AccountId);
        Test.stopTest();

        Assert.areEqual(
            0,
            GivingRollupTestData.valueOf(
                GivingRollupTestData.account(ana.AccountId).Total_Soft_Credits__c
            ),
            'The household Ana left'
        );
        Assert.areEqual(
            500,
            GivingRollupTestData.account(bea.AccountId).Total_Soft_Credits__c,
            'The household Ana joined'
        );
    }

    /**
     * Two hundred soft credits, ten each for twenty solicitors in twenty households, recalculated
     * in one run. Every household is right (plan Section 7.2).
     */
    @IsTest
    static void twoHundredSoftCreditsReachTwentyHouseholds() {
        GivingRollupTestData.useOwnEngine();
        List<String> names = new List<String>();
        for (Integer i = 0; i < 20; i++) {
            names.add('Solicitor' + i);
        }
        List<Contact> solicitors = GivingRollupTestData.peopleInOwnHouseholds(names);
        Account riverbend = GivingTestDataFactory.insertOrganization('Riverbend Manufacturing');
        List<Gift__c> gifts = new List<Gift__c>();
        for (Integer i = 0; i < 200; i++) {
            gifts.add(GivingTestDataFactory.buildAccountGift(riverbend.Id, 10));
        }
        insert gifts;
        List<Soft_Credit__c> credits = new List<Soft_Credit__c>();
        for (Integer i = 0; i < 200; i++) {
            credits.add(solicitorCredit(gifts[i].Id, solicitors[Math.mod(i, 20)].Id, 10));
        }
        insert credits;
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        GivingRollupTestData.recalculate(HOUSEHOLD_SOFT_KEYS);
        Test.stopTest();

        Set<Id> householdIds = new Set<Id>();
        for (Contact solicitor : solicitors) {
            householdIds.add(solicitor.AccountId);
        }
        for (Account household : [
            SELECT Total_Soft_Credits__c, Soft_Credit_Count__c
            FROM Account
            WHERE Id IN :householdIds
        ]) {
            Assert.areEqual(100, household.Total_Soft_Credits__c, 'Ten credits of 10');
            Assert.areEqual(10, household.Soft_Credit_Count__c, 'Ten gifts recognized');
        }
    }
}
