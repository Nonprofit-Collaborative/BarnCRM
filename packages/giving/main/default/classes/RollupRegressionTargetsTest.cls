/**
 * Rollup regression suite, part 2: two rollups writing one field, and the freshness stamps
 * (rollup proposal, migration step 1, slice S3; bugs 2, 4 and 5).
 *
 * Engine agnostic on purpose: records are changed through ordinary saves, totals are calculated
 * through the public `RollupService` entry points, and only stored values are asserted.
 *
 * Several shipped rollups write the same field for different kinds of account: Household total
 * giving and Account total giving both write `Total_Giving__c` on Account, kept apart by their
 * target filters (R-R8). The vendored engine read no target filter, so which one won was decided
 * by run order (bug 2). Its freshness stamps were wrong too: a recalculation never stamped the
 * records it wrote (bug 4), and a definition was marked calculated when its run was queued rather
 * than when it finished (bug 5). The tests that encode the right answers were written then and
 * switched off, each naming the slice that switched it on (proposal migration step 3: these were
 * fixed in the new engine, not patched into the old one).
 *
 * Slice S5 switched on the target filter and record freshness tests, and slice S7 the definition
 * freshness test, on BarnCRM's own engine, which slice S8 made the only one.
 */
@IsTest(testFor='ApexClass:RollupEngine, ApexClass:RollupService')
private class RollupRegressionTargetsTest {
    private static final Set<String> TOTAL_GIVING_KEYS = new Set<String>{
        GivingRollupTestData.HOUSEHOLD_TOTAL,
        GivingRollupTestData.ACCOUNT_TOTAL
    };

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        }
    }

    private static Contact ana() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
    }

    // --------------------------------------------------------------------------- target overlap

    /**
     * The Nolan household gives 500 in its own name and Ana, a member, gives 100. The household's
     * total giving is 600. Account total giving also reaches the household through Donor Account,
     * where it would count only the 500, and its target filter (not a household) is what keeps it
     * off this record.
     */
    @IsTest
    static void aHouseholdsTotalIsTheHouseholdRollupsAnswer() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = ana();
            insert new List<Gift__c>{
                GivingTestDataFactory.buildAccountGift(ana.AccountId, 500),
                GivingTestDataFactory.buildGift(ana.Id, 100)
            };
            GivingRollupTestData.installShippedRollups();

            Test.startTest();
            GivingRollupTestData.recalculate(TOTAL_GIVING_KEYS);
            Test.stopTest();

            Account household = GivingRollupTestData.account(ana.AccountId);
            Assert.areEqual(600, household.Total_Giving__c, 'Everything the household gave');
        }
    }

    /**
     * The same household saving its own gift now: the real-time run of both rollups leaves the
     * household's own answer, 600, whichever runs last.
     */
    @IsTest
    static void aHouseholdsOwnGiftSavedNowKeepsTheHouseholdAnswer() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = ana();
            GivingRollupTestData.installShippedRollups();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(ana.Id, 100);
            GivingRollupTestData.nextSave();
            insert GivingTestDataFactory.buildAccountGift(ana.AccountId, 500);
            Test.stopTest();

            Account household = GivingRollupTestData.account(ana.AccountId);
            Assert.areEqual(600, household.Total_Giving__c, 'Everything the household gave');
            Assert.areEqual(2, household.Gift_Count__c, 'Both gifts');
        }
    }

    /**
     * Riverbend, an organization, gives 1000. Recalculating both total giving rollups leaves
     * Riverbend at 1000: the household rollup's target filter keeps it from writing an
     * organization at all, so it cannot reset the organization's total to zero.
     */
    @IsTest
    static void anOrganizationsTotalIsTheAccountRollupsAnswer() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account riverbend = GivingTestDataFactory.insertOrganization('Riverbend Manufacturing');
            insert GivingTestDataFactory.buildAccountGift(riverbend.Id, 1000);
            GivingRollupTestData.installShippedRollups();

            Test.startTest();
            GivingRollupTestData.recalculate(TOTAL_GIVING_KEYS);
            Test.stopTest();

            Assert.areEqual(
                1000,
                GivingRollupTestData.account(riverbend.Id).Total_Giving__c,
                'Riverbend\'s own giving'
            );
        }
    }

    // -------------------------------------------------------------------------------- freshness

    /**
     * A gift saved now stamps "Rollups last calculated" on the records whose totals it changed, so
     * the record page can say how current its numbers are (canonical model Section 26).
     */
    @IsTest
    static void aSavedGiftStampsTheRecordsItChanged() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = ana();
            GivingRollupTestData.installShippedRollups();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(ana.Id, 100);
            Test.stopTest();

            Assert.isNotNull(
                GivingRollupTestData.person(ana.Id).Rollups_Last_Calculated__c,
                'Ana\'s totals were calculated'
            );
            Assert.isNotNull(
                GivingRollupTestData.account(ana.AccountId).Rollups_Last_Calculated__c,
                'Her household\'s were too'
            );
        }
    }

    /** Once a recalculation has finished, the Rollups page says when it ran. */
    @IsTest
    static void aFinishedRecalculationMarksTheRollupCalculated() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = ana();
            insert GivingTestDataFactory.buildGift(ana.Id, 100);
            GivingRollupTestData.installShippedRollups();

            Test.startTest();
            GivingRollupTestData.recalculate(new Set<String>{ GivingRollupTestData.CONTACT_TOTAL });
            Test.stopTest();

            Rollup_Definition__c definition = GivingRollupTestData.definitions(
                new Set<String>{ GivingRollupTestData.CONTACT_TOTAL }
            )[0];
            Assert.isNotNull(definition.Last_Calculated__c, 'The run finished');
            Assert.areEqual(
                100,
                GivingRollupTestData.person(ana.Id).Total_Giving__c,
                'And wrote the total'
            );
        }
    }

    /**
     * A recalculation stamps "Rollups last calculated" on every record it wrote, in the same save
     * as the totals, so the nightly run leaves every record saying when its numbers were last
     * made (bug 4).
     */
    @IsTest
    static void aRecalculationStampsTheRecordsItWrote() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = ana();
            insert GivingTestDataFactory.buildGift(ana.Id, 100);
            GivingRollupTestData.installShippedRollups();
            Assert.isNull(
                GivingRollupTestData.person(ana.Id).Rollups_Last_Calculated__c,
                'Nothing has calculated Ana\'s totals yet'
            );

            Test.startTest();
            GivingRollupTestData.recalculate(
                new Set<String>{
                    GivingRollupTestData.CONTACT_TOTAL,
                    GivingRollupTestData.HOUSEHOLD_TOTAL
                }
            );
            Test.stopTest();

            Assert.isNotNull(
                GivingRollupTestData.person(ana.Id).Rollups_Last_Calculated__c,
                'Ana\'s totals were recalculated'
            );
            Assert.isNotNull(
                GivingRollupTestData.account(ana.AccountId).Rollups_Last_Calculated__c,
                'Her household\'s were too'
            );
        }
    }

    /**
     * A rollup is never marked calculated before its totals are written: whenever the Rollups
     * page shows a time, the numbers on the records are already the ones that run produced. The
     * vendored engine stamped the time when the run was queued, so for a moment the page said
     * calculated while Ana's total was still blank (bug 5). Switched on in slice S7: the full
     * run stamps the time when its last pass finishes.
     */
    @IsTest
    static void aRollupIsNeverMarkedCalculatedBeforeItsTotalsAre() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = ana();
            insert GivingTestDataFactory.buildGift(ana.Id, 100);
            GivingRollupTestData.installShippedRollups();
            Set<String> keys = new Set<String>{ GivingRollupTestData.CONTACT_TOTAL };

            Test.startTest();
            GivingRollupTestData.recalculate(keys);
            Datetime markedWhileRunning = GivingRollupTestData.definitions(keys)[0]
                .Last_Calculated__c;
            Decimal totalWhileRunning = GivingRollupTestData.person(ana.Id).Total_Giving__c;
            Test.stopTest();

            if (markedWhileRunning != null) {
                Assert.areEqual(
                    100,
                    totalWhileRunning,
                    'Marked calculated, so the total had to be written already'
                );
            }
            Assert.isNotNull(
                GivingRollupTestData.definitions(keys)[0].Last_Calculated__c,
                'Marked calculated once the run finished'
            );
            Assert.areEqual(
                100,
                GivingRollupTestData.person(ana.Id).Total_Giving__c,
                'With the total written'
            );
        }
    }
}
