/**
 * What the rollups cost a gift save and a soft credit save, in queries, with the shipped
 * rollups installed (ADR-NEXT async rollups, rollup review ROLLUPS-10).
 *
 * The cost is measured as the difference between two saves in one transaction: one with every
 * rollup automation bypassed, one with them running. Everything else the save runs is the same
 * in both, so the difference is what the rollups add. A warm-up save first fills the caches that
 * every save shares (settings, automation switches), so neither measured save pays for them.
 *
 * By default a save only marks the records its totals live on and queues them; the Rollup Queue
 * recalculates them just after the save. That is the budget pinned here. Recalculating in the
 * save costs several times as much, which `inTheSaveCostsMoreThanTheBudget` shows.
 */
@IsTest
private class GiftSaveRollupCostTest {
    /**
     * The most queries the rollups may add to a save when they are recalculated just after it:
     * the definitions read once, the households of the people the gift reaches, a path walked
     * through the gift, and the check for a waiting queue processor.
     */
    private static final Integer QUEUED_QUERY_BUDGET = 8;

    /** The most DML statements the rollups may add: the queue entries of each trigger. */
    private static final Integer QUEUED_DML_BUDGET = 4;

    /** Every automation that runs the real-time rollups, Core's and Giving's. */
    private static final List<String> ROLLUP_AUTOMATIONS = new List<String>{
        'Core_Rollups_Contact',
        'Core_Rollups_Household_Member',
        'Giving_Rollups_Gift',
        'Giving_Rollups_Commitment',
        'Giving_Rollups_Gift_Allocation',
        'Giving_Rollups_Soft_Credit'
    };

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
            GivingTestDataFactory.insertHouseholdContact(
                'The Lindqvist Family',
                'Bea',
                'Lindqvist'
            );
            RollupService.ensureDefaults();
        }
    }

    private static void bypassRollups(Boolean bypassed) {
        for (String automation : ROLLUP_AUTOMATIONS) {
            if (bypassed) {
                AutomationControl.bypass(automation);
            } else {
                AutomationControl.clearBypass(automation);
            }
        }
    }

    /** Queries and DML statements one insert spends. */
    private class Cost {
        Integer queries;
        Integer dml;

        Cost(SObject record) {
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            insert record;
            this.queries = Limits.getQueries() - queriesBefore;
            this.dml = Limits.getDmlStatements() - dmlBefore;
        }
    }

    private static Contact ana() {
        return [SELECT Id, AccountId FROM Contact WHERE FirstName = 'Ana' LIMIT 1];
    }

    private static Contact bea() {
        return [SELECT Id FROM Contact WHERE FirstName = 'Bea' LIMIT 1];
    }

    @IsTest
    static void aGiftSaveQueuesItsTotalsWithinTheBudget() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = ana();
            Test.startTest();
            bypassRollups(true);
            insert GivingTestDataFactory.buildGift(ana.Id, 10);
            Cost without = new Cost(GivingTestDataFactory.buildGift(ana.Id, 20));
            bypassRollups(false);
            Cost withRollups = new Cost(GivingTestDataFactory.buildGift(ana.Id, 250));
            Integer queued = [
                SELECT COUNT()
                FROM Rollup_Queue__c
                WHERE Status__c = :RollupQueue.STATUS_PENDING
            ];
            Test.stopTest();

            Integer rollupQueries = withRollups.queries - without.queries;
            Assert.isTrue(
                rollupQueries <= QUEUED_QUERY_BUDGET,
                'A gift save spends ' +
                    withRollups.queries +
                    ' queries, ' +
                    without.queries +
                    ' without the rollups: the rollups add ' +
                    rollupQueries +
                    ', over the budget of ' +
                    QUEUED_QUERY_BUDGET
            );
            Assert.isTrue(
                withRollups.dml - without.dml <= QUEUED_DML_BUDGET,
                'The rollups add ' + (withRollups.dml - without.dml) + ' DML statements'
            );
            Assert.isTrue(queued > 0, 'The save queued the records its totals live on');

            // Recalculation recomputes from every gift, so the two saved while the rollups were
            // bypassed count too: 10 + 20 + 250.
            Assert.areEqual(
                280,
                GivingRollupTestData.person(ana.Id).Total_Giving__c,
                'Just after the save, the queue put the gift in Ana\'s total'
            );
            Assert.areEqual(
                280,
                GivingRollupTestData.account(ana.AccountId).Total_Giving__c,
                'And in her household\'s'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Rollup_Queue__c WHERE Status__c = :RollupQueue.STATUS_FAILED],
                'Nothing failed in the queue'
            );
        }
    }

    @IsTest
    static void aSoftCreditSaveQueuesItsTotalsWithinTheBudget() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = ana();
            Contact bea = bea();
            bypassRollups(true);
            Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 500);
            insert gift;

            Test.startTest();
            insert new Soft_Credit__c(
                Gift__c = gift.Id,
                Contact__c = bea.Id,
                Role__c = 'Solicitor',
                Amount__c = 100
            );
            Cost without = new Cost(
                new Soft_Credit__c(
                    Gift__c = gift.Id,
                    Contact__c = bea.Id,
                    Role__c = 'Solicitor',
                    Amount__c = 100
                )
            );
            bypassRollups(false);
            Cost withRollups = new Cost(
                new Soft_Credit__c(
                    Gift__c = gift.Id,
                    Contact__c = bea.Id,
                    Role__c = 'Solicitor',
                    Amount__c = 300
                )
            );
            Test.stopTest();

            Integer rollupQueries = withRollups.queries - without.queries;
            Assert.isTrue(
                rollupQueries <= QUEUED_QUERY_BUDGET,
                'A soft credit save spends ' +
                    withRollups.queries +
                    ' queries, ' +
                    without.queries +
                    ' without the rollups: the rollups add ' +
                    rollupQueries +
                    ', over the budget of ' +
                    QUEUED_QUERY_BUDGET
            );
            Assert.areEqual(
                500,
                GivingRollupTestData.person(bea.Id).Total_Soft_Credits__c,
                'Just after the save, the queue recalculated all three credits from scratch'
            );
        }
    }

    /**
     * The same gift save with the totals recalculated in the save, as before ADR-NEXT: the
     * "before" number. There is no warm-up save here, because the recalculation in the save
     * needs the room a fresh transaction has (`RollupService.canRecalculateNow`), so the
     * bypassed save also pays for the shared caches and the difference is, if anything, low.
     */
    @IsTest
    static void inTheSaveCostsMoreThanTheBudget() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = ana();
            RollupTestSupport.recalculateInTheSave();
            Test.startTest();
            bypassRollups(true);
            Cost without = new Cost(GivingTestDataFactory.buildGift(ana.Id, 20));
            bypassRollups(false);
            Cost inTheSave = new Cost(GivingTestDataFactory.buildGift(ana.Id, 40));
            Contact person = GivingRollupTestData.person(ana.Id);
            Test.stopTest();

            Integer rollupQueries = inTheSave.queries - without.queries;
            Assert.areEqual(
                60,
                person.Total_Giving__c,
                'In the save, the total counts every gift before the save returns'
            );
            Assert.isTrue(
                rollupQueries > QUEUED_QUERY_BUDGET,
                'Recalculating in the save adds ' +
                    rollupQueries +
                    ' queries to a gift save, against ' +
                    QUEUED_QUERY_BUDGET +
                    ' just after it'
            );
        }
    }
}
