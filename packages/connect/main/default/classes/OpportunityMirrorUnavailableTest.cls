/**
 * The Opportunity mirror on an org without Opportunity, the Platform-only shape no test org has
 * (ADR-0013, dynamic-apex.md section 9). `OpportunityMirrorService.unavailableForTest` makes the
 * org look that way, so the absent path is run and asserted here rather than skipped by the
 * tests that need Opportunity: gifts save, nothing is linked, nothing is logged, no run starts,
 * and the page says the mirror is unavailable (R-OM1).
 */
@IsTest
private class OpportunityMirrorUnavailableTest {
    private static final Set<String> MIRROR_CONTEXTS = new Set<String>{
        OpportunityMirrorService.CONTEXT,
        'Opportunity mirror: run',
        'OpportunityMirrorController'
    };

    @TestSetup
    static void setup() {
        GivingTestDataFactory.ensureDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
    }

    private static void choose(String direction) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        settings.Opportunity_Mirror_Start__c = Datetime.newInstance(2026, 1, 1);
        upsert settings;
    }

    /** Maria runs the mirror and manages the settings. */
    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin', 'Opportunity_Mirror' }
        );
    }

    private static Id luisId() {
        return [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1].Id;
    }

    private static Integer countLinked() {
        return [SELECT COUNT() FROM Gift__c WHERE Opportunity_Id__c != NULL WITH SYSTEM_MODE];
    }

    private static Integer countLogged() {
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Context__c IN :MIRROR_CONTEXTS
            WITH SYSTEM_MODE
        ];
    }

    private static String refusalOf(String action) {
        try {
            if (action == 'runNow') {
                OpportunityMirrorController.runNow();
            } else if (action == 'copyAgain') {
                OpportunityMirrorController.copyRangeAgain(
                    Date.newInstance(2026, 9, 1),
                    Date.newInstance(2026, 9, 30)
                );
            } else if (action == 'schedule') {
                OpportunityMirrorController.schedule();
            } else {
                OpportunityMirrorController.compare(
                    Date.newInstance(2026, 9, 1),
                    Date.newInstance(2026, 9, 30)
                );
            }
        } catch (AuraHandledException refused) {
            return refused.getMessage();
        }
        return null;
    }

    @IsTest
    static void theSeamHidesOpportunity() {
        OpportunityMirrorService.unavailableForTest = true;

        Assert.isNull(OpportunityMirrorService.opportunityType(), 'No Opportunity object.');
        Assert.isNull(OpportunityMirrorService.roleType(), 'No contact role object.');
        Assert.isNull(OpportunityMirrorService.roleObjectName(), 'So no role object name.');
        Assert.isFalse(OpportunityMirrorService.isAvailable(), 'So the mirror is unavailable.');
        Assert.isFalse(OpportunityMirrorService.copiesGifts(), 'It copies nothing.');
        Assert.isFalse(OpportunityMirrorService.canCopy(), 'And nobody can copy.');
        Assert.areEqual(
            new List<String>{ 'Id', 'Name', 'Amount', 'CloseDate', 'AccountId' },
            OpportunityGiftService.opportunityFields(),
            'No Campaign field is looked for on an object that is not there.'
        );
    }

    @IsTest
    static void savingTwoHundredGiftsLinksNothingAndLogsNothing() {
        OpportunityMirrorService.unavailableForTest = true;
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(luisId(), 200, 25);

        Test.startTest();
        System.runAs(maria()) {
            insert gifts;
            update new Gift__c(Id = gifts[0].Id, Amount__c = 30);
            delete gifts[1];
        }
        Test.stopTest();

        Assert.areEqual(199, [SELECT COUNT() FROM Gift__c], 'Every gift saves (R-OM6).');
        Assert.areEqual(0, countLinked(), 'None is given an Opportunity.');
        Assert.areEqual(0, countLogged(), 'An org without Opportunity is not an error.');
    }

    @IsTest
    static void deletingAGiftThatNamesAnOpportunityWarnsNothing() {
        OpportunityMirrorService.unavailableForTest = true;
        Gift__c given = GivingTestDataFactory.buildGift(luisId(), 40);
        // Brought in from another system: the value is kept as it was typed.
        given.Opportunity_Id__c = '006000000000001AAA';

        Test.startTest();
        System.runAs(maria()) {
            insert given;
            delete given;
        }
        Test.stopTest();

        Assert.areEqual(0, countLogged(), 'No Opportunity to leave behind, so nothing to say.');
    }

    @IsTest
    static void aRunOfSavedGiftsDoesNothing() {
        choose(OpportunityMirrorService.OFF);
        insert GivingTestDataFactory.buildGifts(luisId(), 3, 20);
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
        OpportunityMirrorService.unavailableForTest = true;
        List<Gift__c> saved = (List<Gift__c>) Database.query(
            'SELECT ' + OpportunityMirrorSelector.GIFT_FIELDS + ' FROM Gift__c',
            AccessLevel.SYSTEM_MODE
        );

        OpportunityMirrorService.Result result;
        Id job;
        Test.startTest();
        System.runAs(maria()) {
            result = OpportunityMirrorService.syncSaved(saved);
            job = OpportunityMirrorBatch.run();
        }
        Test.stopTest();

        Assert.areEqual(0, result.created + result.updated + result.failed, 'Nothing is copied.');
        Assert.isNull(job, 'No run starts.');
        Assert.areEqual(0, countLinked(), 'No gift is linked.');
        Assert.areEqual(0, countLogged(), 'Nothing is logged.');
    }

    @IsTest
    static void noRunStartsInEitherDirection() {
        OpportunityMirrorService.unavailableForTest = true;
        Id copying;
        Id making;

        Test.startTest();
        System.runAs(maria()) {
            copying = OpportunityMirrorBatch.run();
            choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS);
            making = OpportunityMirrorBatch.run();
        }
        Test.stopTest();

        Assert.isNull(copying, 'Gifts to Opportunities does not start.');
        Assert.isNull(making, 'Nor does Opportunities to Gifts.');
        Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift is made.');
    }

    @IsTest
    static void thePageSaysUnavailableAndRefusesEveryAction() {
        OpportunityMirrorService.unavailableForTest = true;
        OpportunityMirrorController.Status status;
        Map<String, String> refusals = new Map<String, String>();

        Test.startTest();
        System.runAs(maria()) {
            status = OpportunityMirrorController.getStatus();
            for (String action : new List<String>{ 'runNow', 'copyAgain', 'schedule', 'compare' }) {
                refusals.put(action, refusalOf(action));
            }
        }
        Test.stopTest();

        Assert.isFalse(status.available, 'The page says the mirror cannot work here.');
        Assert.isFalse(status.canRun, 'And that no run can.');
        for (String action : refusals.keySet()) {
            Assert.areEqual(
                Label.Connect_OpportunityMirror_Unavailable,
                refusals.get(action),
                action + ' is refused in words, before anything starts.'
            );
        }
        Assert.isNull(OpportunityMirrorSchedulable.nextRunAt(), 'Nothing was scheduled.');
        Assert.areEqual(0, countLogged(), 'A refusal is not an error.');
    }

    @IsTest
    static void healthCheckReportsNoStaleRun() {
        User admin = maria();
        System.runAs(admin) {
            OpportunityMirrorSchedulable.schedule();
        }
        OpportunityMirrorService.unavailableForTest = true;
        ConnectHealthCheckExtension.nowForTest = System.now().addDays(3);
        List<HealthCheckService.Finding> findings;

        Test.startTest();
        System.runAs(admin) {
            findings = new ConnectHealthCheckExtension().findings();
        }
        Test.stopTest();

        Assert.isTrue(findings.isEmpty(), 'No Opportunity, no run to be late.');
    }
}
