/**
 * Runs of the Opportunity mirror (X-01, R-OM7, R-OM8): the gifts that existed before the mirror
 * was turned on get their Opportunities in one run, won Opportunities become gifts once and only
 * once, and the nightly schedule is started and stopped from the page.
 *
 * Opportunity is written and read through describe here too, so this class compiles where it
 * does not exist; there each test checks that nothing happened and stops.
 */
@IsTest
private class OpportunityMirrorBatchTest {
    private static final String LOG_CONTEXT = 'Opportunity mirror: run';
    // detection-only: read by name so this class compiles where Opportunity does not exist
    private static final String ROLE_OBJECT = 'OpportunityContactRole';

    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.ensureDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
        }
    }

    private static void choose(String direction, Date startDate) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        settings.Opportunity_Mirror_Start__c = startDate == null
            ? null
            : Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
        upsert settings;
    }

    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Giving_Admin', 'Opportunity_Mirror' }
        );
    }

    private static Id luisId() {
        return [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1].Id;
    }

    private static String opportunityObject() {
        return OpportunityMirrorService.opportunityType().getDescribe().getName();
    }

    private static String wonStage() {
        for (SObject stage : OpportunityMirrorSelector.activeStages()) {
            if (stage.get('IsWon') == true) {
                return (String) stage.get('ApiName');
            }
        }
        return null;
    }

    /** A won Opportunity, as an online giving tool writes one, with Luis as primary contact. */
    private static SObject onlineGift(
        String name,
        Decimal amount,
        Date closeDate,
        Boolean withLuis
    ) {
        SObject opportunity = OpportunityMirrorService.opportunityType().newSObject();
        opportunity.put('Name', name);
        opportunity.put('Amount', amount);
        opportunity.put('CloseDate', closeDate);
        opportunity.put('StageName', wonStage());
        insert opportunity;
        if (withLuis) {
            SObject role = Schema.getGlobalDescribe().get(ROLE_OBJECT).newSObject();
            role.put('OpportunityId', opportunity.Id);
            role.put('ContactId', luisId());
            role.put('IsPrimary', true);
            insert role;
        }
        return opportunity;
    }

    private static List<Gift__c> giftsFromOpportunities() {
        return [
            SELECT Id, Amount__c, Gift_Date__c, Donor_Contact__c, Type__c, Opportunity_Id__c
            FROM Gift__c
            WHERE Opportunity_Id__c != NULL
            WITH SYSTEM_MODE
        ];
    }

    private static Integer countLogs(String severity, String context) {
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Context__c = :context AND Severity__c = :severity
            WITH SYSTEM_MODE
        ];
    }

    /**
     * The absent branch of every test that stops where the org has no Opportunity: no gift was
     * linked, nothing was logged, and no run can start (R-OM1).
     * `OpportunityMirrorUnavailableTest` runs this branch.
     */
    private static void assertNothingMirrored() {
        Set<String> contexts = new Set<String>{ LOG_CONTEXT, OpportunityMirrorService.CONTEXT };
        Assert.areEqual(0, giftsFromOpportunities().size(), 'Without Opportunity nothing links.');
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Error_Log__c
                WHERE Context__c IN :contexts
                WITH SYSTEM_MODE
            ],
            'Nothing is logged.'
        );
        Assert.isNull(OpportunityMirrorBatch.run(), 'And no run can start.');
    }

    @IsTest
    static void aRunGivesTheGiftsThatWereThereBeforeTheirOpportunities() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Gift__c> gifts = GivingTestDataFactory.buildGifts(luisId(), 3, 40);
            gifts.add(GivingTestDataFactory.buildGift(luisId(), 15));
            gifts[3].Status__c = 'Pending';
            insert gifts;
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES, null);
            Test.startTest();
            System.runAs(maria()) {
                OpportunityMirrorBatch.run();
            }
            Test.stopTest();
            if (!OpportunityMirrorService.isAvailable()) {
                Assert.areEqual(0, giftsFromOpportunities().size(), 'Nothing without Opportunity.');
                return;
            }
            Assert.areEqual(
                3,
                giftsFromOpportunities().size(),
                'The three received gifts, not Pending.'
            );
            Assert.areEqual(
                3,
                Database.countQuery(
                    'SELECT COUNT() FROM ' + opportunityObject(),
                    AccessLevel.SYSTEM_MODE
                ),
                'One Opportunity each.'
            );
            Assert.areEqual(1, countLogs('Info', LOG_CONTEXT), 'The run says what it did.');
        }
    }

    @IsTest
    static void copyingARangeAgainPutsAHandEditRight() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES, null);
            User admin = maria();
            Gift__c given = GivingTestDataFactory.buildGift(luisId(), 100);
            given.Gift_Date__c = Date.newInstance(2026, 9, 20);
            System.runAs(admin) {
                insert given;
            }
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            Id linked = [
                SELECT Opportunity_Id__c
                FROM Gift__c
                WHERE Id = :given.Id
                WITH SYSTEM_MODE
            ]
            .Opportunity_Id__c;
            SObject edited = OpportunityMirrorService.opportunityType().newSObject(linked);
            edited.put('Amount', 175);
            update edited;
            Test.startTest();
            System.runAs(admin) {
                OpportunityMirrorBatch.runRange(
                    Date.newInstance(2026, 9, 1),
                    Date.newInstance(2026, 9, 30)
                );
            }
            Test.stopTest();
            SObject copy = Database.queryWithBinds(
                'SELECT Amount FROM ' + opportunityObject() + ' WHERE Id = :linked',
                new Map<String, Object>{ 'linked' => linked },
                AccessLevel.SYSTEM_MODE
            )[0];
            Assert.areEqual(100, (Decimal) copy.get('Amount'), 'The gift is the source (R-OM11).');
        }
    }

    @IsTest
    static void wonOpportunitiesBecomeGiftsOnceAndRefusalsAreGroupedByReason() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!OpportunityMirrorService.isAvailable()) {
                choose(
                    OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS,
                    Date.newInstance(2026, 1, 1)
                );
                Assert.isNull(OpportunityMirrorBatch.run(), 'No Opportunity, no run.');
                return;
            }
            Date closed = Date.newInstance(2026, 9, 20);
            SObject good = onlineGift('Online gift from Luis', 60, closed, true);
            onlineGift('Old online gift', 70, Date.newInstance(2025, 12, 31), true);
            onlineGift('Free ticket', 0, closed, true);
            onlineGift('Free ticket too', 0, closed, true);
            onlineGift('Nobody gave this', 30, closed, false);
            choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS, Date.newInstance(2026, 1, 1));
            User admin = maria();
            Test.startTest();
            System.runAs(admin) {
                OpportunityMirrorBatch.run();
            }
            Test.stopTest();

            List<Gift__c> made = giftsFromOpportunities();
            Assert.areEqual(
                1,
                made.size(),
                'Only the won Opportunity after the start date with a donor.'
            );
            Assert.areEqual(
                String.valueOf(good.Id),
                made[0].Opportunity_Id__c,
                'Linked in the insert.'
            );
            Assert.areEqual(60, made[0].Amount__c, 'The amount is the Opportunity\'s.');
            Assert.areEqual(closed, made[0].Gift_Date__c, 'So is the date.');
            Assert.areEqual(
                luisId(),
                made[0].Donor_Contact__c,
                'The primary contact is the donor.'
            );
            Assert.areEqual(
                'Other',
                made[0].Type__c,
                'An Opportunity says nothing of how it was paid.'
            );
            Assert.areEqual(
                2,
                countLogs('Warning', 'Opportunity mirror'),
                'One Warning per reason: two free tickets share one, the donorless one has its own.'
            );

            // A second run makes nothing new: the Opportunity ID on the gift remembers it.
            OpportunityMirrorService.Result again;
            System.runAs(admin) {
                again = OpportunityGiftService.makeGifts(new List<SObject>{ good });
            }
            Assert.areEqual(0, again.created, 'Never twice.');
            Assert.areEqual(1, again.unchanged, 'It is recognized.');
        }
    }

    @IsTest
    static void withoutAStartDateNoOpportunityBecomesAGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS, null);
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            onlineGift('Online gift from Luis', 60, Date.today(), true);
            Test.startTest();
            System.runAs(maria()) {
                OpportunityMirrorBatch.run();
            }
            Test.stopTest();
            Assert.areEqual(0, giftsFromOpportunities().size(), 'No start date, no gifts (R-OM7).');
        }
    }

    @IsTest
    static void theNightlyRunIsScheduledOnceAndStopped() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES, null);
            User admin = maria();
            Test.startTest();
            // The nightly run executes as the person who scheduled it.
            System.runAs(admin) {
                Id first = OpportunityMirrorSchedulable.schedule();
                Id second = OpportunityMirrorSchedulable.schedule();
                Assert.areEqual(first, second, 'Pressing Schedule twice keeps one job.');
                Assert.isNotNull(
                    OpportunityMirrorSchedulable.nextRunAt(),
                    'It knows when it runs next.'
                );
                OpportunityMirrorSchedulable.stop();
                Assert.isNull(
                    OpportunityMirrorSchedulable.nextRunAt(),
                    'Stopped, it has no next run.'
                );
                new OpportunityMirrorSchedulable().execute(null);
            }
            Test.stopTest();
            Assert.isFalse(
                OpportunityMirrorSchedulable.isRunning(),
                'The run it started has finished.'
            );
        }
    }
}
