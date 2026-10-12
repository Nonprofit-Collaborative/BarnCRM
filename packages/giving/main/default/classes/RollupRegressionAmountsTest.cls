/**
 * Rollup regression suite, part 1: refunds and fiscal year windows (rollup proposal, migration
 * step 1, slice S2).
 *
 * Engine agnostic on purpose: records are changed through ordinary saves and `GiftService`, totals
 * are calculated through the public `RollupService` entry points, and only target record values
 * are asserted, so the same tests judge today's engine and the one that replaces it.
 *
 * `GiftRollupRefundTest` holds the person's total and count after a refund; this class adds the
 * real-time path, the household, the largest gift and the fund, and the fiscal windows with a
 * start month other than January (R-R3).
 *
 * The shipped rollups are installed inside each test rather than in the setup. A test that
 * recalculates installs them after its records are saved, so the only run over those records is
 * the recalculation it asserts on; a test of the real-time path installs them first and makes
 * every save between `Test.startTest` and `Test.stopTest`.
 */
@IsTest
private class RollupRegressionAmountsTest {
    private static final String HOUSEHOLD_THIS_YEAR = 'Household_Giving_This_Year';
    private static final String FUND_THIS_YEAR = 'Fund_Total_Raised_This_Year';

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
    }

    private static Contact ana() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
    }

    private static Fund__c general() {
        return [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];
    }

    // --------------------------------------------------------------------------------- refunds

    /**
     * Ana gives 250 and 100 of it goes back, saved as staff save it. The totals reflect what the
     * organization still holds while the count and the largest gift remember the gift as given
     * (ADR-0022).
     */
    @IsTest
    static void aPartialRefundSavedNowLeavesWhatIsHeld() {
        GivingRollupTestData.installShippedRollups();
        Contact ana = ana();
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 250);

        Test.startTest();
        insert gift;
        GivingRollupTestData.nextSave();
        GiftService.refund(gift.Id, 100, 'Donor asked for the misdirected portion back');
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Total_Giving__c);
        Assert.areEqual(150, person.Total_Giving__c, 'What the organization still holds');
        Assert.areEqual(1, person.Gift_Count__c, 'A refund is not a gift given');
        Assert.areEqual(250, person.Largest_Gift__c, 'The largest gift is the gift as given');
        Account household = GivingRollupTestData.account(ana.AccountId);
        Assert.areEqual(150, household.Total_Giving__c, 'The household holds the same');
        Assert.areEqual(1, household.Gift_Count__c, 'And gave once');
        // The fund after a refund is asserted by the recalculation below; in real time it waits
        // for Gift Allocation to be registered in slice S6.
    }

    /**
     * The same gift refunded in full, then recalculated as the nightly run would. The household
     * total and the fund total are zero, the counts are one, and the largest gift is still 250.
     */
    @IsTest
    static void aFullRefundRecalculatedLeavesZeroAndOneGift() {
        Contact ana = ana();
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 250);
        insert gift;
        GivingRollupTestData.nextSave();
        GiftService.refund(gift.Id, 250, 'Gift sent to the wrong organization');
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        GivingRollupTestData.recalculate(
            new Set<String>{
                GivingRollupTestData.HOUSEHOLD_TOTAL,
                GivingRollupTestData.HOUSEHOLD_COUNT,
                GivingRollupTestData.HOUSEHOLD_LARGEST,
                GivingRollupTestData.CONTACT_LARGEST,
                GivingRollupTestData.FUND_TOTAL,
                GivingRollupTestData.FUND_COUNT
            }
        );
        Test.stopTest();

        Account household = GivingRollupTestData.account(ana.AccountId);
        GivingTestDataFactory.assertRollupWrote(household.Total_Giving__c);
        Assert.areEqual(0, household.Total_Giving__c, 'Nothing held, and zero rather than blank');
        Assert.areEqual(1, household.Gift_Count__c, 'The household gave once');
        Assert.areEqual(250, household.Largest_Gift__c, 'The gift as given');
        Assert.areEqual(
            250,
            GivingRollupTestData.person(ana.Id).Largest_Gift__c,
            'A negative gift is never anybody\'s largest'
        );
        Fund__c fund = GivingRollupTestData.fund(general().Id);
        Assert.areEqual(0, fund.Total_Raised__c, 'The fund holds nothing of it');
        Assert.areEqual(1, fund.Gift_Count__c, 'One gift to the fund');
    }

    /**
     * Two hundred gifts, each refunded in part in one bulk save of the negative gifts, as an
     * import of a refund file would post them. Every donor's total is what is still held.
     */
    @IsTest
    static void twoHundredRefundsInOneSaveAreAllCounted() {
        GivingRollupTestData.installShippedRollups();
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
        List<Gift__c> refunds = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            Gift__c refund = GivingTestDataFactory.buildGift(gift.Donor_Contact__c, -5);
            refund.Original_Gift__c = gift.Id;
            refund.Refund_Reason__c = 'Processing fee returned';
            refunds.add(refund);
        }
        insert refunds;
        Test.stopTest();

        Assert.areEqual(200, refunds.size(), 'The bulk case is two hundred records');
        for (Contact donor : [
            SELECT Total_Giving__c, Gift_Count__c
            FROM Contact
            WHERE Id IN :donors
        ]) {
            GivingTestDataFactory.assertRollupWrote(donor.Total_Giving__c);
            Assert.areEqual(200, donor.Total_Giving__c, 'Ten gifts of 25, each with 5 returned');
            Assert.areEqual(10, donor.Gift_Count__c, 'Still ten gifts given');
        }
    }

    // ---------------------------------------------------------------------------- fiscal years

    /** The first day of the fiscal year the org is in today, for a fiscal year starting in this month. */
    private static Date currentFiscalYearStart(Integer startMonth) {
        Date today = Date.today();
        Integer year = today.month() >= startMonth ? today.year() : today.year() - 1;
        return Date.newInstance(year, startMonth, 1);
    }

    /**
     * Six gifts from Ana, each on or next to a fiscal year boundary, with amounts that are powers
     * of two so that every sum names exactly which gifts are in it. Returns the gifts.
     */
    private static List<Gift__c> giftsAroundTheBoundaries(Id donorId, Date thisYearStart) {
        List<Gift__c> gifts = new List<Gift__c>{
            datedGift(donorId, 1, Date.today()),
            datedGift(donorId, 2, thisYearStart),
            datedGift(donorId, 4, thisYearStart.addDays(-1)),
            datedGift(donorId, 8, thisYearStart.addYears(-1)),
            datedGift(donorId, 16, thisYearStart.addYears(-1).addDays(-1)),
            datedGift(donorId, 32, thisYearStart.addYears(-2).addDays(-1))
        };
        insert gifts;
        return gifts;
    }

    private static Gift__c datedGift(Id donorId, Decimal amount, Date giftDate) {
        Gift__c gift = GivingTestDataFactory.buildGift(donorId, amount);
        gift.Gift_Date__c = giftDate;
        return gift;
    }

    /**
     * Recalculates every fiscal total and asserts each against the boundary gifts: this year has
     * 1 and 2, last year 4 and 8, two years ago 16, and 32 is in none of them. A gift dated on the
     * first day of a fiscal year belongs to that year and not the one before (R-R3).
     */
    private static void assertFiscalTotals(Contact ana, Date thisYearStart) {
        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Giving_This_Year__c);
        Assert.areEqual(3, person.Giving_This_Year__c, 'Today and the first day of this year');
        Assert.areEqual(
            12,
            person.Giving_Last_Year__c,
            'The last day and the first day of last year'
        );
        Assert.areEqual(16, person.Giving_Two_Years_Ago__c, 'The last day of two years ago');
        Assert.areEqual(2, person.Gifts_Last_Year__c, 'Two gifts last year');
        Assert.areEqual(63, person.Total_Giving__c, 'All time has all six');
        Assert.areEqual(
            thisYearStart.addYears(-2).addDays(-1),
            person.First_Gift_Date__c,
            'The oldest gift'
        );
        Assert.areEqual(
            3,
            GivingRollupTestData.account(ana.AccountId).Giving_This_Year__c,
            'The household\'s year is the same year'
        );
        Fund__c fund = [SELECT Total_Raised_This_Year__c FROM Fund__c WHERE Id = :general().Id];
        Assert.areEqual(
            3,
            fund.Total_Raised_This_Year__c,
            'A fund\'s year is decided by the gift date too'
        );
    }

    private static Set<String> fiscalKeys() {
        return new Set<String>{
            GivingRollupTestData.CONTACT_THIS_YEAR,
            GivingRollupTestData.CONTACT_LAST_YEAR,
            GivingRollupTestData.CONTACT_TWO_YEARS_AGO,
            GivingRollupTestData.CONTACT_GIFTS_LAST_YEAR,
            GivingRollupTestData.CONTACT_TOTAL,
            GivingRollupTestData.CONTACT_FIRST_DATE,
            HOUSEHOLD_THIS_YEAR,
            FUND_THIS_YEAR
        };
    }

    /** A fiscal year that starts in July, as most of the sector's does. */
    @IsTest
    static void fiscalTotalsFollowAJulyStart() {
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
        SettingsService.clearCaches();
        Contact ana = ana();
        Date thisYearStart = currentFiscalYearStart(7);
        giftsAroundTheBoundaries(ana.Id, thisYearStart);
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        GivingRollupTestData.recalculate(fiscalKeys());
        Test.stopTest();

        assertFiscalTotals(ana, thisYearStart);
    }

    /** With the start month never set, the fiscal year is the calendar year. */
    @IsTest
    static void fiscalTotalsDefaultToTheCalendarYear() {
        Contact ana = ana();
        Date thisYearStart = currentFiscalYearStart(1);
        giftsAroundTheBoundaries(ana.Id, thisYearStart);
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        GivingRollupTestData.recalculate(fiscalKeys());
        Test.stopTest();

        assertFiscalTotals(ana, thisYearStart);
    }

    /**
     * A refund in last fiscal year of a gift given the year before that lowers the year the
     * refund is dated in, because a year's total is the money that moved that year (ADR-0022).
     */
    @IsTest
    static void aRefundCountsInTheYearItIsDated() {
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
        SettingsService.clearCaches();
        Contact ana = ana();
        Date thisYearStart = currentFiscalYearStart(7);
        Gift__c gift = datedGift(ana.Id, 300, thisYearStart.addYears(-2));
        insert gift;
        Gift__c refund = datedGift(ana.Id, -100, thisYearStart.addYears(-1));
        refund.Original_Gift__c = gift.Id;
        refund.Refund_Reason__c = 'Returned the following year';
        insert refund;
        GivingRollupTestData.installShippedRollups();

        Test.startTest();
        GivingRollupTestData.recalculate(fiscalKeys());
        Test.stopTest();

        Contact person = GivingRollupTestData.person(ana.Id);
        GivingTestDataFactory.assertRollupWrote(person.Giving_Two_Years_Ago__c);
        Assert.areEqual(300, person.Giving_Two_Years_Ago__c, 'The gift, in the year it was given');
        Assert.areEqual(-100, person.Giving_Last_Year__c, 'The refund, in the year it went back');
        Assert.areEqual(
            0,
            GivingRollupTestData.valueOf(person.Gifts_Last_Year__c),
            'No gift given last year'
        );
        Assert.areEqual(200, person.Total_Giving__c, 'All time nets the two');
    }
}
