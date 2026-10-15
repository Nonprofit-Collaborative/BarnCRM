/**
 * What stops, limits and records a run of the Opportunity mirror (X-01, R-OM7, R-OM8): a pause or
 * the Automation page switch, a direction changed partway through, the record type list (Master
 * included), two runs making the same gift, a chunk of two hundred, and the last run kept for the
 * page and for Health Check.
 *
 * Opportunity is written and read through describe here too, so this class compiles where it
 * does not exist; there each test checks that nothing happened and stops.
 */
@IsTest(testFor='ApexClass:OpportunityMirrorService, ApexClass:OpportunityMirrorBatch')
private class OpportunityMirrorRunTest {
    private static final String RUN_CONTEXT = 'Opportunity mirror: run';

    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.ensureDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
        }
    }

    private static void choose(String direction) {
        Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        upsert settings;
    }

    /** Maria runs the mirror and manages the settings, pause included. */
    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin', 'Opportunity_Mirror' }
        );
    }

    private static Id luisId() {
        return [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1].Id;
    }

    /** Gifts saved before the mirror was on, so a run has them to copy. */
    private static List<Gift__c> giftsBeforeTheMirror(Integer howMany) {
        choose(OpportunityMirrorService.OFF);
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(luisId(), howMany, 20);
        insert gifts;
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
        return (List<Gift__c>) Database.query(
            'SELECT ' + OpportunityMirrorSelector.GIFT_FIELDS + ' FROM Gift__c',
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Integer countOpportunities() {
        return OpportunityMirrorService.isAvailable()
            ? Database.countQuery(
                  'SELECT COUNT() FROM ' +
                  OpportunityMirrorService.opportunityType().getDescribe().getName(),
                  AccessLevel.SYSTEM_MODE
              )
            : 0;
    }

    private static List<Error_Log__c> runLogs() {
        return [
            SELECT Message__c
            FROM Error_Log__c
            WHERE Context__c = :RUN_CONTEXT AND Severity__c = 'Info'
            WITH SYSTEM_MODE
        ];
    }

    /**
     * The absent branch of every test that stops where the org has no Opportunity: no run
     * started, no gift was linked, and nothing was logged (R-OM1).
     * `OpportunityMirrorUnavailableTest` runs this branch.
     */
    private static void assertNothingMirrored() {
        Set<String> contexts = new Set<String>{ RUN_CONTEXT, OpportunityMirrorService.CONTEXT };
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Gift__c WHERE Opportunity_Id__c != NULL WITH SYSTEM_MODE],
            'Without Opportunity no gift is linked (R-OM1).'
        );
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Error_Log__c
                WHERE Context__c IN :contexts
                WITH SYSTEM_MODE
            ],
            'No run started, so nothing is logged.'
        );
        Assert.isNull(OpportunityMirrorBatch.run(), 'And none can start.');
    }

    private static Mirror_Settings__c stored() {
        return [
            SELECT Opportunity_Mirror_Last_Run__c, Opportunity_Mirror_Last_Summary__c
            FROM Mirror_Settings__c
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }

    @IsTest
    static void aRunWhileAutomationIsPausedDoesNothingAndSaysSoOnce() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            giftsBeforeTheMirror(3);
            User admin = maria();
            Test.startTest();
            System.runAs(admin) {
                AutomationControl.pauseAll(1);
                OpportunityMirrorBatch.run();
            }
            Test.stopTest();
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            Assert.areEqual(0, countOpportunities(), 'Paused is paused (R-OM8).');
            List<Error_Log__c> logged = runLogs();
            Assert.areEqual(1, logged.size(), 'One Info entry.');
            Assert.isTrue(logged[0].Message__c.contains('paused'), logged[0].Message__c);
            Assert.isNull(
                stored().Opportunity_Mirror_Last_Run__c,
                'A skipped run is not recorded.'
            );
        }
    }

    @IsTest
    static void aRunSwitchedOffOnTheAutomationPageDoesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            giftsBeforeTheMirror(3);
            TestDataFactory.insertAutomationSettings(
                new Map<String, Boolean>{ OpportunityMirrorService.AUTOMATION_NAME => false }
            );
            Test.startTest();
            System.runAs(maria()) {
                OpportunityMirrorBatch.run();
            }
            Test.stopTest();
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            Assert.areEqual(0, countOpportunities(), 'Off is off.');
            List<Error_Log__c> logged = runLogs();
            Assert.areEqual(1, logged.size(), 'One Info entry.');
            Assert.isTrue(logged[0].Message__c.contains('switched off'), logged[0].Message__c);
        }
    }

    @IsTest
    static void chunksAfterAPauseOrADirectionChangeAreLeftForTheNextRun() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Gift__c> gifts = giftsBeforeTheMirror(4);
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            User admin = maria();
            Test.startTest();
            System.runAs(admin) {
                OpportunityMirrorBatch run = new OpportunityMirrorBatch(
                    OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES,
                    null,
                    null
                );
                run.start(null);
                run.execute(null, new List<Gift__c>{ gifts[0] });
                choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS);
                run.execute(null, new List<Gift__c>{ gifts[1] });
                choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
                AutomationControl.pauseAll(1);
                run.execute(null, new List<Gift__c>{ gifts[2], gifts[3] });
                run.finish(null);
            }
            Test.stopTest();
            Assert.areEqual(1, countOpportunities(), 'Only the chunk before the change.');
            List<Error_Log__c> logged = runLogs();
            Assert.areEqual(1, logged.size(), 'One Info entry: the summary.');
            Assert.isTrue(
                logged[0].Message__c.contains('3 left for the next run'),
                logged[0].Message__c
            );
            Assert.isTrue(
                logged[0].Message__c.contains('paused'),
                'It says why: ' + logged[0].Message__c
            );
            Assert.isNull(
                stored().Opportunity_Mirror_Last_Run__c,
                'An interrupted run is not recorded.'
            );
        }
    }

    @IsTest
    static void aRunIsRecordedAndRechecksLinkedGiftsChangedSinceTheLastOne() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
            User admin = maria();
            Gift__c given = GivingTestDataFactory.buildGift(luisId(), 100);
            System.runAs(admin) {
                insert given;
            }
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            MirrorSettingsWriter.recordOpportunityMirrorRun(System.now().addDays(-1), 'Yesterday');
            // A change whose copy was skipped, as when the saver could not create Opportunities.
            AutomationControl.bypass(OpportunityMirrorService.AUTOMATION_NAME);
            update new Gift__c(Id = given.Id, Amount__c = 130);
            AutomationControl.clearBypass(OpportunityMirrorService.AUTOMATION_NAME);
            Datetime before = System.now().addSeconds(-1);
            Test.startTest();
            System.runAs(admin) {
                OpportunityMirrorBatch.run();
            }
            Test.stopTest();
            String linked = [
                SELECT Opportunity_Id__c
                FROM Gift__c
                WHERE Id = :given.Id
                WITH SYSTEM_MODE
            ]
            .Opportunity_Id__c;
            SObject copy = Database.queryWithBinds(
                'SELECT Amount FROM ' +
                    OpportunityMirrorService.opportunityType().getDescribe().getName() +
                    ' WHERE Id = :linked',
                new Map<String, Object>{ 'linked' => linked },
                AccessLevel.SYSTEM_MODE
            )[0];
            Assert.areEqual(130, (Decimal) copy.get('Amount'), 'The skipped change is put right.');
            Mirror_Settings__c recorded = stored();
            Assert.isTrue(
                recorded.Opportunity_Mirror_Last_Run__c >= before,
                'The run is recorded.'
            );
            Assert.isTrue(
                recorded.Opportunity_Mirror_Last_Summary__c.contains('1 updated'),
                recorded.Opportunity_Mirror_Last_Summary__c
            );
        }
    }

    @IsTest
    static void aChunkOfTwoHundredIsCopiedAndLinked() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Gift__c> gifts = giftsBeforeTheMirror(200);
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            OpportunityMirrorService.Result result;
            Test.startTest();
            System.runAs(maria()) {
                result = OpportunityMirrorService.syncSaved(gifts);
            }
            Test.stopTest();
            Assert.areEqual(200, result.created, 'Every gift (plan Section 7.2).');
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Gift__c WHERE Opportunity_Id__c != NULL WITH SYSTEM_MODE],
                'And every link stored.'
            );
        }
    }

    @IsTest
    static void aRecordTypeTheOrgDoesNotHaveMakesNoGifts() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
            settings.Opportunity_Mirror_Direction__c = OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS;
            settings.Opportunity_Mirror_Start__c = Datetime.newInstance(2026, 1, 1);
            settings.Opportunity_Mirror_Record_Types__c = 'No_Such_Record_Type';
            upsert settings;
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            Assert.areEqual(0, OpportunityGiftService.recordTypeIds().size(), 'Matches nothing.');
            Test.startTest();
            System.runAs(maria()) {
                OpportunityMirrorBatch.run();
            }
            Test.stopTest();
            List<Error_Log__c> named = [
                SELECT Message__c
                FROM Error_Log__c
                WHERE Context__c = :RUN_CONTEXT AND Severity__c = 'Warning'
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(1, named.size(), 'The unknown name is named once a run.');
            Assert.isTrue(named[0].Message__c.contains('No_Such_Record_Type'), 'By its name.');
            Assert.isTrue(
                OpportunityMirrorSelector.wonOpportunitiesQuery(
                        'Opportunity',
                        new List<String>{ 'Id' },
                        true
                    )
                    .contains('RecordTypeId IN :recordTypeIds'),
                'The run filters on it (R-OM7).'
            );
            settings.Opportunity_Mirror_Record_Types__c = null;
            upsert settings;
            Assert.isNull(OpportunityGiftService.recordTypeIds(), 'Empty means every record type.');
        }
    }

    @IsTest
    static void masterInTheRecordTypeListIsLeftOutAndNamedOnce() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
            settings.Opportunity_Mirror_Direction__c = OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS;
            settings.Opportunity_Mirror_Start__c = Datetime.newInstance(2026, 1, 1);
            settings.Opportunity_Mirror_Record_Types__c = 'Master';
            upsert settings;
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            Assert.isTrue(OpportunityGiftService.listsMasterRecordType(), 'Master is listed.');
            Assert.areEqual(
                0,
                OpportunityGiftService.recordTypeIds().size(),
                'An Opportunity without a record type stores none, so Master is left out.'
            );
            Assert.isTrue(
                OpportunityGiftService.unknownRecordTypes().isEmpty(),
                'Master is a real name, not a mistyped one.'
            );
            Test.startTest();
            System.runAs(maria()) {
                OpportunityMirrorBatch.run();
            }
            Test.stopTest();
            List<Error_Log__c> warned = [
                SELECT Message__c
                FROM Error_Log__c
                WHERE Context__c = :RUN_CONTEXT AND Severity__c = 'Warning'
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(1, warned.size(), 'One Warning a run, not a silent run.');
            Assert.areEqual(
                Label.Mirror_OpportunityMirror_MasterRecordType,
                warned[0].Message__c,
                'It says why Master matches nothing and what to do.'
            );
            settings.Opportunity_Mirror_Record_Types__c = 'master, No_Such_Record_Type';
            upsert settings;
            Assert.isTrue(OpportunityGiftService.listsMasterRecordType(), 'In any case.');
            Assert.areEqual(
                new List<String>{ 'No_Such_Record_Type' },
                OpportunityGiftService.unknownRecordTypes(),
                'Only the mistyped name is unknown.'
            );
        }
    }

    @IsTest
    static void onlyADuplicateOnTheLinkItselfIsAnotherRunsGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String link = Gift__c.Opportunity_Id__c.getDescribe().getName();
            String lookalike = link.removeEndIgnoreCase('__c') + '_Legacy__c';
            String other = Gift__c.External_Id__c.getDescribe().getName();
            StatusCode duplicate = StatusCode.DUPLICATE_VALUE;

            // The refusal names its fields.
            Assert.isTrue(
                OpportunityGiftService.isLinkDuplicate(duplicate, new List<String>{ link }, ''),
                'A duplicate on the link is another run\'s gift.'
            );
            Assert.isFalse(
                OpportunityGiftService.isLinkDuplicate(
                    duplicate,
                    new List<String>{ other },
                    'duplicate value found: ' + link
                ),
                'The fields decide when there are any.'
            );
            Assert.isFalse(
                OpportunityGiftService.isLinkDuplicate(
                    StatusCode.REQUIRED_FIELD_MISSING,
                    new List<String>{ link },
                    link
                ),
                'Only a duplicate.'
            );

            // The refusal names the field only in its message.
            for (List<String> noFields : new List<List<String>>{ null, new List<String>() }) {
                Assert.isTrue(
                    OpportunityGiftService.isLinkDuplicate(
                        duplicate,
                        noFields,
                        'duplicate value found: ' +
                            link +
                            ' duplicates value on record with id: a0B000000000001AAA'
                    ),
                    'The link, as a whole word of the message.'
                );
                Assert.isFalse(
                    OpportunityGiftService.isLinkDuplicate(
                        duplicate,
                        noFields,
                        'duplicate value found: ' +
                            lookalike +
                            ' duplicates value on record with id: a0B000000000001AAA'
                    ),
                    'A field whose name only contains the link\'s is not the link.'
                );
                Assert.isFalse(
                    OpportunityGiftService.isLinkDuplicate(
                        duplicate,
                        noFields,
                        'duplicate value found: ' +
                            other +
                            ' duplicates value on record with id: a0B000000000001AAA'
                    ),
                    'Another unique field is not the link.'
                );
                Assert.isFalse(
                    OpportunityGiftService.isLinkDuplicate(duplicate, noFields, null),
                    'No message, no match.'
                );
            }
        }
    }

    @IsTest
    static void anOpportunityMadeIntoAGiftTwiceAtOnceIsCountedUnchanged() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS);
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingMirrored();
                return;
            }
            String won;
            for (SObject stage : OpportunityMirrorSelector.activeStages()) {
                if (stage.get('IsWon') == true) {
                    won = (String) stage.get('ApiName');
                }
            }
            SObject online = OpportunityMirrorService.opportunityType().newSObject();
            online.put('Name', 'Online gift');
            online.put('Amount', 45);
            online.put('CloseDate', Date.newInstance(2026, 9, 20));
            online.put('StageName', won);
            online.put('AccountId', [SELECT AccountId FROM Contact WHERE Id = :luisId()].AccountId);
            insert online;
            OpportunityMirrorService.Result result;
            Test.startTest();
            System.runAs(maria()) {
                result = OpportunityGiftService.makeGifts(new List<SObject>{ online, online });
            }
            Test.stopTest();
            Assert.areEqual(1, result.created, 'One gift.');
            Assert.areEqual(1, result.unchanged, 'The duplicate is not a failure.');
            Assert.areEqual(0, result.failed, 'Nothing refused.');
        }
    }

    @IsTest
    static void theStartDateIsReadInTheOrgTimeZone() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Datetime start = Datetime.newInstanceGmt(2026, 1, 1, 3, 0, 0);
            Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
            settings.Opportunity_Mirror_Start__c = start;
            upsert settings;
            String zone = [SELECT TimeZoneSidKey FROM Organization LIMIT 1].TimeZoneSidKey;
            Date expected = Date.valueOf(start.format('yyyy-MM-dd', zone));
            // Maria's own time zone is GMT; the org's decides.
            System.runAs(maria()) {
                Assert.areEqual(expected, OpportunityGiftService.startDate(), 'The org\'s day.');
            }

        }
    }
}
