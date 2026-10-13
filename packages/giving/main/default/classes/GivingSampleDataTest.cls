/**
 * Tests the Giving sample data set (C-10) against a small inline payload injected through
 * the @TestVisible jsonOverride hook, so no test depends on the generated static resource
 * or on its size.
 *
 * The stages are called directly rather than through the queueable chain, because an Apex
 * test context runs only the first job it is given. The sample people the stages look for
 * are created here the way Core's loader creates them: flagged as sample data and carrying
 * the generator key the payload names them by.
 */
@IsTest(testFor='ApexClass:GivingSampleData')
private class GivingSampleDataTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static final String PERSON_KEY = 'H001-1';
    private static final String SECOND_PERSON_KEY = 'H002-1';
    private static final String ORGANIZATION_KEY = 'O001';

    /** A household, two people and an organization, flagged and keyed as Core's loader leaves them. */
    private static void insertSamplePeople() {
        Account household = new Account(
            Name = 'The Sample Family',
            Sample_Data__c = true,
            Sample_Data_Key__c = 'H001'
        );
        Account organization = new Account(
            Name = 'Cedar Valley Foundation',
            Sample_Data__c = true,
            Sample_Data_Key__c = ORGANIZATION_KEY
        );
        insert new List<Account>{ household, organization };
        insert new List<Contact>{
            new Contact(
                FirstName = 'Maria',
                LastName = 'Sample',
                AccountId = household.Id,
                Sample_Data__c = true,
                Sample_Data_Key__c = PERSON_KEY
            ),
            new Contact(
                FirstName = 'David',
                LastName = 'Sample',
                AccountId = household.Id,
                Sample_Data__c = true,
                Sample_Data_Key__c = SECOND_PERSON_KEY
            )
        };
    }

    private static Map<String, Object> fund(String name, String code) {
        return new Map<String, Object>{
            'key' => name,
            'name' => name,
            'accountingCode' => code,
            'restricted' => name != 'General Fund',
            'active' => true,
            'description' => name
        };
    }

    private static Map<String, Object> appeal(String name, String parent) {
        return new Map<String, Object>{
            'key' => name,
            'name' => name,
            'parent' => parent,
            'goal' => 25000,
            'cost' => 500,
            'startDaysAgo' => 300,
            'endDaysAgo' => null,
            'active' => true,
            'description' => name
        };
    }

    private static Map<String, Object> gift(
        String key,
        String donor,
        Integer daysAgo,
        Decimal amount,
        String status
    ) {
        return new Map<String, Object>{
            'key' => key,
            'donor' => donor,
            'daysAgo' => daysAgo,
            'amount' => amount,
            'type' => 'Check',
            'status' => status,
            'appeal' => 'Spring Appeal',
            'acknowledgmentStatus' => 'Acknowledged',
            'paymentReference' => 'Check 1001',
            'commitment' => null,
            'allocations' => new List<Object>{
                new Map<String, Object>{ 'fund' => 'General Fund', 'amount' => amount }
            }
        };
    }

    /**
     * A payload holding two funds, a parent and child appeal, a pledge, three ordinary
     * gifts, a refunded gift with the negative gift that reverses it, one tribute and one
     * hand-entered soft credit.
     */
    private static String buildJson() {
        Map<String, Object> pledge = new Map<String, Object>{
            'key' => 'C001',
            'donor' => PERSON_KEY,
            'type' => 'Pledge',
            'frequency' => 'Quarterly',
            'amount' => 250,
            'expectedTotal' => 1000,
            'installmentsPlanned' => 4,
            'startDaysAgo' => 200,
            'endDaysAgo' => null,
            'dayOfMonth' => 1,
            'status' => 'Active',
            'fund' => 'General Fund',
            'appeal' => 'Annual Fund'
        };

        Map<String, Object> refunded = gift('G0004', PERSON_KEY, 90, 500, 'Refunded');
        Map<String, Object> reversal = gift('G0005', PERSON_KEY, 60, -500, 'Received');
        reversal.put('originalGift', 'G0004');
        reversal.put('refundReason', 'Card charged twice at the gala.');
        reversal.put(
            'allocations',
            new List<Object>{
                new Map<String, Object>{ 'fund' => 'General Fund', 'amount' => -500 }
            }
        );

        Map<String, Object> tribute = new Map<String, Object>{
            'gift' => 'G0001',
            'type' => 'In honor of',
            'honoreePerson' => SECOND_PERSON_KEY,
            'recipientPerson' => null,
            'message' => 'In honour of David Sample, with thanks.'
        };
        Map<String, Object> credit = new Map<String, Object>{
            'gift' => 'G0001',
            'person' => SECOND_PERSON_KEY,
            'role' => 'Solicitor',
            'amount' => 1000
        };

        Map<String, Object> root = new Map<String, Object>{
            'funds' => new List<Object>{
                fund('General Fund', '4000'),
                fund('Building Fund', '4100')
            },
            'appeals' => new List<Object>{
                appeal('Annual Fund', null),
                appeal('Spring Appeal', 'Annual Fund')
            },
            'commitments' => new List<Object>{ pledge },
            'gifts' => new List<Object>{
                gift('G0001', PERSON_KEY, 30, 1000, 'Received'),
                gift('G0002', ORGANIZATION_KEY, 400, 5000, 'Received'),
                gift('G0003', PERSON_KEY, 800, 75, 'Received'),
                refunded,
                reversal
            },
            'tributes' => new List<Object>{ tribute },
            'softCredits' => new List<Object>{ credit }
        };
        return JSON.serialize(root);
    }

    @IsTest
    static void testStagesRunInOrderThroughTheStageBatch() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();
            GivingSampleData.jsonOverride = buildJson();
            GivingSampleDataStages stages = new GivingSampleDataStages();

            Test.startTest();
            Integer stageCount = stages.stageCount();
            for (Integer stage = 0; stage < stageCount; stage++) {
                stages.runStage(stage);
            }
            stages.finish();
            Test.stopTest();

            System.assertEquals(2, stageCount, 'one reference data stage and one gift chunk');
            System.assertEquals(
                5,
                [SELECT COUNT() FROM Gift__c WHERE Sample_Data__c = TRUE],
                'the gift stage reads the funds and appeals the reference stage kept for it'
            );
        }
    }

    @IsTest
    static void testEnqueueLoadStartsTheStageBatch() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();
            GivingSampleData.jsonOverride = buildJson();

            Test.startTest();
            new GivingSampleData().enqueueLoad();
            Test.stopTest();

            // A test context runs one execute of a batch, which is the reference data stage.
            System.assertEquals(
                2,
                [SELECT COUNT() FROM Fund__c WHERE Sample_Data__c = TRUE],
                'the stage batch runs the reference data stage first'
            );
        }
    }

    /** Runs both load stages in order, the way the stage batch does in an org. */
    private static GivingSampleDataSet loadEverything() {
        GivingSampleDataSet data = GivingSampleDataSet.parse(buildJson());
        Map<String, Id> idsByKey = GivingSampleDataLoader.loadReferenceData(data);
        for (Integer chunk = 0; chunk < data.chunkCount(); chunk++) {
            GivingSampleDataLoader.loadGiftChunk(data, chunk, idsByKey);
        }
        return data;
    }

    @IsTest
    static void testReferenceStageInsertsFundsAppealsAndCommitments() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();

            Test.startTest();
            GivingSampleDataSet data = GivingSampleDataSet.parse(buildJson());
            GivingSampleDataLoader.loadReferenceData(data);
            Test.stopTest();

            System.assertEquals(
                2,
                [SELECT COUNT() FROM Fund__c WHERE Sample_Data__c = TRUE],
                'both funds in the payload are created'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Fund__c WHERE Sample_Data__c = TRUE AND Is_Default__c = TRUE],
                'no sample fund claims the default: the org keeps the default fund it had'
            );
            Appeal__c child = [
                SELECT Parent_Appeal__r.Name, Goal__c
                FROM Appeal__c
                WHERE Name = 'Spring Appeal'
                LIMIT 1
            ];
            System.assertEquals(
                'Annual Fund',
                child.Parent_Appeal__r.Name,
                'a child appeal is loaded under the parent it names'
            );
            Commitment__c pledge = [
                SELECT Amount__c, Expected_Total__c, Sample_Data__c
                FROM Commitment__c
                LIMIT 1
            ];
            System.assertEquals(250, pledge.Amount__c, 'the pledge keeps its installment amount');
            System.assertEquals(true, pledge.Sample_Data__c, 'the pledge is flagged for removal');
            System.assertEquals(
                4,
                [SELECT COUNT() FROM Installment__c],
                'the commitment trigger generated the four installments the pledge planned'
            );
        }
    }

    @IsTest
    static void testGiftStageInsertsGiftsAllocationsTributesAndSoftCredits() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();

            Test.startTest();
            loadEverything();
            Test.stopTest();

            System.assertEquals(
                5,
                [SELECT COUNT() FROM Gift__c WHERE Sample_Data__c = TRUE],
                'every gift in the payload is loaded, the reversal included'
            );
            Gift__c organizationGift = [
                SELECT Donor_Account__c, Donor_Contact__c, Amount__c, External_Id__c
                FROM Gift__c
                WHERE External_Id__c = 'SAMPLE-G0002'
            ];
            System.assertNotEquals(
                null,
                organizationGift.Donor_Account__c,
                'a gift whose donor key is an organization is credited to the account'
            );
            System.assertEquals(
                null,
                organizationGift.Donor_Contact__c,
                'an organization gift names no person as the donor'
            );
            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM Gift_Allocation__c
                    WHERE Gift__c = :organizationGift.Id AND Amount__c = 5000
                ],
                'the allocation in the file is the one the gift gets, not a default fund one'
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Tribute__c],
                'the tribute named against its gift is loaded'
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Soft_Credit__c WHERE Is_Automatic__c = FALSE],
                'the hand-entered soft credit is loaded as a credit staff entered'
            );
        }
    }

    @IsTest
    static void testRefundIsANegativeGiftLinkedToTheGiftItReverses() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();

            Test.startTest();
            loadEverything();
            Test.stopTest();

            Gift__c original = [
                SELECT Id, Status__c
                FROM Gift__c
                WHERE External_Id__c = 'SAMPLE-G0004'
            ];
            Gift__c reversal = [
                SELECT Amount__c, Original_Gift__c, Refund_Reason__c, Status__c
                FROM Gift__c
                WHERE External_Id__c = 'SAMPLE-G0005'
            ];
            System.assertEquals(
                'Refunded',
                original.Status__c,
                'the gift that went back keeps its own amount and takes the reversed status (R-G3)'
            );
            System.assertEquals(
                original.Id,
                reversal.Original_Gift__c,
                'the negative gift names the gift it reverses, in a later insert than the original'
            );
            System.assertEquals(
                -500,
                reversal.Amount__c,
                'the reversal carries the money back out'
            );
            System.assertEquals(
                'Card charged twice at the gala.',
                reversal.Refund_Reason__c,
                'the reason is held on the negative gift rather than by editing the original'
            );
        }
    }

    @IsTest
    static void testNoSampleGiftCarriesAReceiptNumber() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();

            Test.startTest();
            loadEverything();
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Gift__c WHERE Receipt_Number__c != NULL],
                'a receipted gift cannot be deleted (ADR-0024), so the sample set never receipts one'
            );
        }
    }

    @IsTest
    static void testGiftDatesAreCountedBackFromTheDayTheSetIsLoaded() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();

            Test.startTest();
            loadEverything();
            Test.stopTest();

            Gift__c recent = [
                SELECT Gift_Date__c
                FROM Gift__c
                WHERE External_Id__c = 'SAMPLE-G0001'
            ];
            Gift__c oldest = [
                SELECT Gift_Date__c
                FROM Gift__c
                WHERE External_Id__c = 'SAMPLE-G0003'
            ];
            System.assertEquals(
                Date.today().addDays(-30),
                recent.Gift_Date__c,
                'a thirty day offset is thirty days before the load, so this year is never empty'
            );
            System.assertEquals(
                Date.today().addDays(-800),
                oldest.Gift_Date__c,
                'the oldest gift stays two years back whenever the set is loaded'
            );
        }
    }

    @IsTest
    static void testRemoveDeletesEverySampleRecordAndItsDetails() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();
            loadEverything();

            Test.startTest();
            Integer removed = GivingSampleDataLoader.removeAll();
            Test.stopTest();

            System.assertEquals(
                10,
                removed,
                'five gifts, one commitment, two appeals and two funds are the ten rows deleted by name'
            );
            System.assertEquals(0, [SELECT COUNT() FROM Gift__c], 'no sample gift is left');
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Gift_Allocation__c],
                'allocations go with the gift they belong to'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Tribute__c],
                'tributes go with the gift they belong to'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Soft_Credit__c],
                'soft credits go with the gift they belong to'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Installment__c],
                'installments go with the commitment they belong to'
            );
            System.assertEquals(0, [SELECT COUNT() FROM Commitment__c]);
            System.assertEquals(0, [SELECT COUNT() FROM Appeal__c]);
            System.assertEquals(0, [SELECT COUNT() FROM Fund__c]);
        }
    }

    @IsTest
    static void testRemoveLeavesRecordsTheLoaderDidNotCreate() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();
            loadEverything();
            // The organization's own default fund: sample funds never take the flag, and a gift
            // the fundraiser enters saves only when there is a default fund to allocate it to.
            Fund__c ownFund = GivingTestDataFactory.buildFund('Our own fund', true);
            insert ownFund;
            Contact ownDonor = GivingTestDataFactory.insertHouseholdContact(
                'The Real Family',
                'Ada',
                'Real'
            );
            Gift__c ownGift = GivingTestDataFactory.buildGift(ownDonor.Id, 40);
            insert ownGift;

            Test.startTest();
            GivingSampleDataLoader.removeAll();
            Test.stopTest();

            System.assertEquals(
                1,
                [SELECT COUNT() FROM Gift__c WHERE Id = :ownGift.Id],
                'a gift the fundraiser entered is not touched by removing sample data'
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Fund__c WHERE Id = :ownFund.Id],
                'a fund the administrator created is not touched'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Gift__c WHERE Sample_Data__c = TRUE],
                'every sample gift is gone'
            );
        }
    }

    @IsTest
    static void testCountLoadedAndLabelAnswerTheStatusCard() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePeople();
            loadEverything();

            GivingSampleData module = new GivingSampleData();

            System.assertEquals(
                'Giving',
                module.moduleName(),
                'the module names itself the way Core knows it'
            );
            System.assertEquals(
                System.Label.Giving_SampleData_GiftsLabel,
                module.countLabel(),
                'the card is given the packaged label rather than a hard-coded word'
            );
            System.assertEquals(
                5,
                module.countLoaded(),
                'the number the card shows is the sample gifts in the org'
            );
        }
    }

    @IsTest
    static void testChunksAtOneHundredGifts() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingSampleDataSet data = GivingSampleDataSet.parse(buildJson());
            System.assertEquals(
                5,
                data.gifts.size(),
                'the payload holds five gifts, which is one chunk'
            );
            System.assertEquals(1, data.chunkCount(), 'five gifts need one chunk of a hundred');
            System.assertEquals(
                5,
                data.giftsInChunk(0).size(),
                'the only chunk holds every gift in the payload'
            );
            System.assertEquals(
                0,
                data.giftsInChunk(1).size(),
                'a chunk past the end of the payload holds nothing'
            );
        }
    }

    @IsTest
    static void testAPayloadMissingItsGiftAmountIsRejected() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Object> root = new Map<String, Object>{
                'funds' => new List<Object>{ fund('General Fund', '4000') },
                'appeals' => new List<Object>(),
                'commitments' => new List<Object>(),
                'gifts' => new List<Object>{
                    new Map<String, Object>{
                        'key' => 'G0001',
                        'donor' => PERSON_KEY,
                        'daysAgo' => 10
                    }
                },
                'tributes' => new List<Object>(),
                'softCredits' => new List<Object>()
            };

            Boolean threw = false;
            try {
                GivingSampleDataSet.parse(JSON.serialize(root));
            } catch (GivingSampleData.SampleDataException failed) {
                threw = true;
                System.assertEquals(
                    System.Label.Giving_SampleData_ErrorInvalidData,
                    failed.getMessage(),
                    'a payload that cannot be loaded says so with the packaged label'
                );
            }
            System.assertEquals(true, threw, 'a gift with no amount is invalid data');
        }
    }

    @IsTest
    static void testGiftsForPeopleWhoAreNotInTheOrgAreSkippedRatherThanFailing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            // No sample people at all: the Giving set is loaded into an org whose Core sample
            // data has already been removed, which must not throw.
            Test.startTest();
            GivingSampleDataSet data = GivingSampleDataSet.parse(buildJson());
            Map<String, Id> idsByKey = GivingSampleDataLoader.loadReferenceData(data);
            Integer loaded = GivingSampleDataLoader.loadGiftChunk(data, 0, idsByKey);
            Test.stopTest();

            System.assertEquals(0, loaded, 'a gift with no donor in the org is skipped');
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Gift__c],
                'nothing is inserted for a donor that is not there'
            );
        }
    }
}
