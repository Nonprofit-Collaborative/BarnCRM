/**
 * The Opportunity mirror page (X-01, R-OM8, R-OM11): what the reconciliation shows Maria, the
 * refusals given before anything starts, and the nightly schedule.
 */
@IsTest(testFor='ApexClass:OpportunityMirrorController')
private class OpportunityMirrorControllerTest {
    private static final Date FROM_DATE = Date.newInstance(2026, 9, 1);
    private static final Date TO_DATE = Date.newInstance(2026, 9, 30);

    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.ensureDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
        }
    }

    private static void choose(String direction) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        upsert settings;
    }

    /** Maria: BarnCRM Admin, so she can manage settings, and the Opportunity Mirror set. */
    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin', 'Opportunity_Mirror' }
        );
    }

    private static Gift__c gift(Decimal amount, Integer day) {
        Id luis = [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1].Id;
        Gift__c gift = GivingTestDataFactory.buildGift(luis, amount);
        gift.Gift_Date__c = Date.newInstance(2026, 9, day);
        return gift;
    }

    private static Id linkOf(Gift__c gift) {
        return [
            SELECT Opportunity_Id__c
            FROM Gift__c
            WHERE Id = :gift.Id
            WITH SYSTEM_MODE
        ]
        .Opportunity_Id__c;
    }

    private static OpportunityMirrorController.Status ready() {
        OpportunityMirrorController.Status status = new OpportunityMirrorController.Status();
        status.available = true;
        status.direction = OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES;
        status.canRun = true;
        status.canManage = true;
        status.running = false;
        return status;
    }

    private static String refusalOf(Callable action) {
        try {
            action.call(null, null);
        } catch (AuraHandledException refused) {
            return refused.getMessage();
        }
        return null;
    }

    /**
     * The absent branch of every test that stops where the org has no Opportunity: the page
     * refuses the action in words, before anything starts (R-OM1).
     * `OpportunityMirrorUnavailableTest` runs this branch.
     */
    private static void assertRefusedAsUnavailable(String action) {
        System.runAs(maria()) {
            Assert.areEqual(
                Label.Connect_OpportunityMirror_Unavailable,
                refusalOf(new Action(action)),
                'Without Opportunity ' + action + ' is refused in words (R-OM1).'
            );
        }
    }

    /** The page actions, so each refusal test reads as one line. */
    private class Action implements Callable {
        private final String name;
        Action(String name) {
            this.name = name;
        }
        public Object call(String unused, Map<String, Object> args) {
            switch on name {
                when 'runNow' {
                    return OpportunityMirrorController.runNow();
                }
                when 'copyAgain' {
                    return OpportunityMirrorController.copyRangeAgain(FROM_DATE, TO_DATE);
                }
                when 'copyReversed' {
                    return OpportunityMirrorController.copyRangeAgain(TO_DATE, FROM_DATE);
                }
                when 'compareEmpty' {
                    return OpportunityMirrorController.compare(null, TO_DATE);
                }
                when 'compareReversed' {
                    return OpportunityMirrorController.compare(TO_DATE, FROM_DATE);
                }
                when 'schedule' {
                    return OpportunityMirrorController.schedule();
                }
                when 'stop' {
                    return OpportunityMirrorController.stop();
                }
                when 'status' {
                    return OpportunityMirrorController.getStatus();
                }
                when else {
                    return OpportunityMirrorController.compare(FROM_DATE, TO_DATE);
                }
            }
        }
    }

    @IsTest
    static void theReconciliationListsEachKindOfDifference() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!OpportunityMirrorService.isAvailable()) {
                assertRefusedAsUnavailable('compare');
                return;
            }
            User admin = maria();
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
            Gift__c matched = gift(40, 5);
            Gift__c edited = gift(100, 6);
            Gift__c orphaned = gift(25, 7);
            System.runAs(admin) {
                insert new List<Gift__c>{ matched, edited, orphaned };
            }
            choose(OpportunityMirrorService.OFF);
            Gift__c unlinked = gift(10, 8);
            insert unlinked;

            Schema.SObjectType opportunityType = OpportunityMirrorService.opportunityType();
            SObject handEdit = opportunityType.newSObject(linkOf(edited));
            handEdit.put('Amount', 175);
            update handEdit;
            delete opportunityType.newSObject(linkOf(orphaned));
            SObject direct = opportunityType.newSObject();
            direct.put('Name', 'Entered by hand');
            direct.put('Amount', 60);
            direct.put('CloseDate', Date.newInstance(2026, 9, 9));
            direct.put('StageName', stageOf(linkOf(matched)));
            insert direct;

            OpportunityMirrorReconciliation.Comparison result;
            Test.startTest();
            System.runAs(admin) {
                result = OpportunityMirrorController.compare(FROM_DATE, TO_DATE);
            }
            Test.stopTest();

            Assert.areEqual(4, result.giftCount, 'Every gift in the totals dated in the range.');
            Assert.areEqual(175, result.giftTotal, 'Their total.');
            Assert.areEqual(
                3,
                result.opportunityCount,
                'Matched, hand edited, and entered by hand.'
            );
            Assert.areEqual(275, result.opportunityTotal, 'Their total.');
            Assert.areEqual(4, result.differenceCount, 'One row for each difference.');
            Map<String, String> reasonByName = new Map<String, String>();
            for (OpportunityMirrorReconciliation.Difference row : result.differences) {
                reasonByName.put(
                    row.giftId != null ? String.valueOf(row.giftId) : row.opportunityName,
                    row.reason
                );
            }
            Assert.areEqual(
                Label.Connect_OpportunityMirror_DiffAmount,
                reasonByName.get(edited.Id),
                'Hand edit.'
            );
            Assert.areEqual(
                Label.Connect_OpportunityMirror_DiffMissing,
                reasonByName.get(orphaned.Id),
                'Deleted.'
            );
            Assert.areEqual(
                Label.Connect_OpportunityMirror_DiffNoOpportunity,
                reasonByName.get(unlinked.Id),
                'Saved while the mirror was off.'
            );
            Assert.areEqual(
                Label.Connect_OpportunityMirror_DiffNoGift,
                reasonByName.get('Entered by hand'),
                'Nobody made a gift of it.'
            );
        }
    }

    private static String stageOf(Id opportunityId) {
        return (String) Database.queryWithBinds(
                'SELECT StageName FROM ' +
                    OpportunityMirrorService.opportunityType().getDescribe().getName() +
                    ' WHERE Id = :opportunityId',
                new Map<String, Object>{ 'opportunityId' => opportunityId },
                AccessLevel.SYSTEM_MODE
            )[0]
            .get('StageName');
    }

    @IsTest
    static void aRangeTooLargeOrMalformedIsRefusedInWords() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insert gift(40, 5);
            OpportunityMirrorReconciliation.maxRecords = 0;
            Test.startTest();
            System.runAs(maria()) {
                Assert.areEqual(
                    Label.Connect_OpportunityMirror_ErrorDatesRequired,
                    refusalOf(new Action('compareEmpty'))
                );
                Assert.areEqual(
                    Label.Connect_OpportunityMirror_ErrorDateOrder,
                    refusalOf(new Action('compareReversed'))
                );
                Assert.areEqual(
                    OpportunityMirrorService.isAvailable()
                        ? Label.Connect_OpportunityMirror_ErrorTooMany
                        : Label.Connect_OpportunityMirror_Unavailable,
                    refusalOf(new Action('compare')),
                    'Refused rather than shown in part (ADR-0051).'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void thePageNeedsTheOpportunityMirrorPermissionSet() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'Giving_Admin' });
            Test.startTest();
            System.runAs(david) {
                Assert.areEqual(
                    Label.Connect_OpportunityMirror_NoUsePermission,
                    refusalOf(new Action('status')),
                    'The page says what he needs (ADR-0038 point 3).'
                );
                Assert.areEqual(
                    Label.Connect_OpportunityMirror_NoUsePermission,
                    refusalOf(new Action('compare')),
                    'Refused in words, not with the platform error a user mode read gives.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void comparingNeedsReadAccessToOpportunities() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Profile> minimum = [
                SELECT Id
                FROM Profile
                WHERE Name = 'Minimum Access - Salesforce'
                LIMIT 1
            ];
            if (!OpportunityMirrorService.isAvailable()) {
                assertRefusedAsUnavailable('compare');
                return;
            }
            if (minimum.isEmpty()) {
                return; // An org without that profile has no such user to prove it with.
            }
            User rosa = TestDataFactory.createUser(
                'Rosa',
                new List<String>{ 'Giving_Admin', 'Opportunity_Mirror' }
            );
            System.runAs(new User(Id = UserInfo.getUserId())) {
                update new User(Id = rosa.Id, ProfileId = minimum[0].Id);
            }
            Test.startTest();
            System.runAs(rosa) {
                Assert.areEqual(
                    Label.Connect_OpportunityMirror_NoOpportunityRead,
                    refusalOf(new Action('compare')),
                    'Refused plainly (R-OM11).'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void someoneWhoCannotManageSettingsCannotRunScheduleOrStop() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!OpportunityMirrorService.isAvailable()) {
                assertRefusedAsUnavailable('runNow');
                return;
            }
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
            User fundraiser = TestDataFactory.createUserOnTheRunningUsersProfile(
                'Ana',
                new List<String>{ 'Giving_Admin', 'Opportunity_Mirror' }
            );
            Test.startTest();
            System.runAs(fundraiser) {
                Assert.isFalse(OpportunityMirrorController.getStatus().canManage, 'She may look.');
                for (String action : new List<String>{ 'runNow', 'schedule', 'stop' }) {
                    Assert.areEqual(
                        Label.Connect_OpportunityMirror_NoManagePermission,
                        refusalOf(new Action(action)),
                        action + ' is refused (ADR-0038).'
                    );
                }
            }
            Test.stopTest();
            Assert.isNull(OpportunityMirrorSchedulable.nextRunAt(), 'Nothing was scheduled.');
        }
    }

    @IsTest
    static void theStatusCarriesTheLastCompletedRun() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Datetime ranAt = Datetime.newInstanceGmt(2026, 9, 24, 8, 30, 0);
            ConnectSettingsWriter.recordOpportunityMirrorRun(ranAt, '3 Opportunities created.');
            OpportunityMirrorController.Status status;
            Test.startTest();
            System.runAs(maria()) {
                status = OpportunityMirrorController.getStatus();
            }
            Test.stopTest();
            Assert.areEqual(ranAt, status.lastRunAt, 'When it started.');
            Assert.areEqual('3 Opportunities created.', status.lastSummary, 'What it did.');
        }
    }

    @IsTest
    static void runNowStartsARunForMariaAndIsRefusedWhileOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            choose(OpportunityMirrorService.OFF);
            Test.startTest();
            System.runAs(admin) {
                Assert.areEqual(
                    OpportunityMirrorService.isAvailable()
                        ? Label.Connect_OpportunityMirror_SwitchedOff
                        : Label.Connect_OpportunityMirror_Unavailable,
                    refusalOf(new Action('runNow')),
                    'Nothing starts, and the page says why.'
                );
                if (OpportunityMirrorService.isAvailable()) {
                    choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
                    Assert.isTrue(OpportunityMirrorController.runNow().running, 'Started.');
                }
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void copyingAgainNeedsGiftsToOpportunitiesAndARange() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!OpportunityMirrorService.isAvailable()) {
                assertRefusedAsUnavailable('copyAgain');
                return;
            }
            User admin = maria();
            choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS);
            Test.startTest();
            System.runAs(admin) {
                Assert.areEqual(
                    Label.Connect_OpportunityMirror_CopyAgainGiftsOnly,
                    refusalOf(new Action('copyAgain')),
                    'A gift is never changed from its Opportunity.'
                );
                choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
                Assert.areEqual(
                    Label.Connect_OpportunityMirror_ErrorDateOrder,
                    refusalOf(new Action('copyReversed'))
                );
                Assert.isTrue(
                    OpportunityMirrorController.copyRangeAgain(FROM_DATE, TO_DATE).running,
                    'Started.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void mariaSchedulesAndStopsTheNightlyRun() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!OpportunityMirrorService.isAvailable()) {
                assertRefusedAsUnavailable('schedule');
                Assert.isNull(OpportunityMirrorSchedulable.nextRunAt(), 'Nothing was scheduled.');
                return;
            }
            User admin = maria();
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
            Test.startTest();
            System.runAs(admin) {
                Assert.isNotNull(OpportunityMirrorController.schedule().nextRunAt, 'Scheduled.');
                Assert.isNull(OpportunityMirrorController.stop().nextRunAt, 'Stopped.');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void eachRefusalNamesItsOwnReason() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            OpportunityMirrorController.Status status = ready();
            Assert.isNull(
                OpportunityMirrorController.refusal(status, false),
                'Everything allows it.'
            );
            status.running = true;
            Assert.isNull(OpportunityMirrorController.refusal(status, true), 'Scheduling may.');
            Assert.areEqual(
                Label.Connect_OpportunityMirror_Running,
                OpportunityMirrorController.refusal(status, false)
            );
            status.canRun = false;
            Assert.areEqual(
                Label.Connect_OpportunityMirror_NoOpportunityAccess,
                OpportunityMirrorController.refusal(status, false)
            );
            status.canManage = false;
            Assert.areEqual(
                Label.Connect_OpportunityMirror_NoManagePermission,
                OpportunityMirrorController.refusal(status, false)
            );
            status.direction = OpportunityMirrorService.OFF;
            Assert.areEqual(
                Label.Connect_OpportunityMirror_SwitchedOff,
                OpportunityMirrorController.refusal(status, false)
            );
            status.available = false;
            Assert.areEqual(
                Label.Connect_OpportunityMirror_Unavailable,
                OpportunityMirrorController.refusal(status, false)
            );
        }
    }
}
