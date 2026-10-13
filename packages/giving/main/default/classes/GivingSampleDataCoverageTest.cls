/**
 * The Giving sample data module as Core's loader sees it (its name, label, count, load and remove
 * entry points and the payload it reads), and the queueable that loads it stage by stage. The
 * stages are called directly where a platform test would refuse a job that queues another.
 */
@IsTest(testFor='ApexClass:GivingSampleData, ApexClass:GivingSampleDataQueueable')
private class GivingSampleDataCoverageTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static final String PERSON_KEY = 'H001-1';

    private static void insertSamplePerson() {
        Account household = new Account(
            Name = 'The Sample Family',
            Sample_Data__c = true,
            Sample_Data_Key__c = 'H001'
        );
        insert household;
        insert new Contact(
            FirstName = 'Maria',
            LastName = 'Sample',
            AccountId = household.Id,
            Sample_Data__c = true,
            Sample_Data_Key__c = PERSON_KEY
        );
    }

    private static Map<String, Object> gift(String key, Decimal amount) {
        return new Map<String, Object>{
            'key' => key,
            'donor' => PERSON_KEY,
            'daysAgo' => 30,
            'amount' => amount,
            'type' => 'Check',
            'status' => 'Received',
            'appeal' => 'Spring Appeal',
            'acknowledgmentStatus' => 'Acknowledged',
            'paymentReference' => 'Check 1001',
            'commitment' => null,
            'allocations' => new List<Object>{
                new Map<String, Object>{ 'fund' => 'General Fund', 'amount' => amount }
            }
        };
    }

    private static String payload(Integer gifts) {
        List<Object> rows = new List<Object>();
        for (Integer i = 1; i <= gifts; i++) {
            rows.add(gift('G' + i, 10 + i));
        }
        return JSON.serialize(
            new Map<String, Object>{
                'funds' => new List<Object>{
                    new Map<String, Object>{
                        'key' => 'General Fund',
                        'name' => 'General Fund',
                        'accountingCode' => '4000',
                        'restricted' => false,
                        'active' => true,
                        'description' => 'General Fund'
                    }
                },
                'appeals' => new List<Object>{
                    new Map<String, Object>{
                        'key' => 'Spring Appeal',
                        'name' => 'Spring Appeal',
                        'parent' => null,
                        'goal' => 25000,
                        'cost' => 500,
                        'startDaysAgo' => 300,
                        'endDaysAgo' => null,
                        'active' => true,
                        'description' => 'Spring Appeal'
                    }
                },
                'commitments' => new List<Object>(),
                'gifts' => rows,
                'tributes' => new List<Object>(),
                'softCredits' => new List<Object>()
            }
        );
    }

    // ----------------------------------------------------------------------------- the module

    @IsTest
    static void theModuleIntroducesItselfToTheStatusCard() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingSampleData module = new GivingSampleData();

            Assert.areEqual(
                GivingSampleData.MODULE_NAME,
                module.moduleName(),
                'Core finds it by name'
            );
            Assert.areEqual(
                System.Label.Giving_SampleData_GiftsLabel,
                module.countLabel(),
                'It counts gifts'
            );
            Assert.areEqual(0, module.countLoaded(), 'Nothing is loaded yet');
            Assert.areEqual(0, module.removeAll(), 'And removing nothing removes nothing');
        }
    }

    @IsTest
    static void thePayloadComesFromTheOverrideOrTheStaticResource() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingSampleData.jsonOverride = payload(1);
            Assert.areEqual(payload(1), GivingSampleData.getSampleDataJson(), 'The override wins');

            GivingSampleData.jsonOverride = null;
            Boolean resolved = false;
            try {
                resolved = String.isNotBlank(GivingSampleData.getSampleDataJson());
            } catch (GivingSampleData.SampleDataException missing) {
                Assert.areEqual(
                    System.Label.Giving_SampleData_ResourceMissing,
                    missing.getMessage(),
                    'A missing resource says so in the label words'
                );
                resolved = true;
            }
            Assert.isTrue(
                resolved,
                'Either the shipped payload is read or the absence is explained'
            );
        }
    }

    @IsTest
    static void startingTheLoadRunsTheReferenceDataStageFirst() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePerson();
            // No gifts, so the first job has no second stage to queue: a platform test refuses a job
            // that queues another.
            GivingSampleData.jsonOverride = payload(0);

            Test.startTest();
            new GivingSampleData().enqueueLoad();
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Fund__c WHERE Sample_Data__c = TRUE],
                'The first job loads the funds'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Appeal__c WHERE Sample_Data__c = TRUE],
                'And the appeals'
            );
        }
    }

    // --------------------------------------------------------------------------- the queueable

    @IsTest
    static void theWholeChainLoadsTheReferenceDataThenTheGiftsThenFinishes() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePerson();
            GivingSampleData.jsonOverride = payload(5);

            Test.startTest();
            new GivingSampleDataQueueable(
                    GivingSampleDataQueueable.STAGE_REFERENCE_DATA,
                    new Map<String, Id>()
                )
                .execute(null);
            Test.stopTest();

            Assert.areEqual(
                5,
                [SELECT COUNT() FROM Gift__c WHERE Sample_Data__c = TRUE],
                'The second job, started by the first, loads all five gifts'
            );
            Assert.areEqual(5, new GivingSampleData().countLoaded(), 'And the card counts them');
            Assert.isTrue(
                new GivingSampleData().removeAll() >= 5,
                'Removal takes at least the five gifts'
            );
            Assert.areEqual(0, new GivingSampleData().countLoaded(), 'Nothing is left');
        }
    }

    @IsTest
    static void twoHundredGiftsLoadInTwoChunks() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insertSamplePerson();
            GivingSampleData.jsonOverride = payload(200);
            Map<String, Id> reference = GivingSampleDataLoader.loadReferenceData(
                GivingSampleDataSet.parse(GivingSampleData.getSampleDataJson())
            );

            new GivingSampleDataQueueable(0, reference).execute(null);
            Integer afterFirst = new GivingSampleData().countLoaded();
            new GivingSampleDataQueueable(1, reference).execute(null);

            Assert.areEqual(
                GivingSampleData.GIFT_CHUNK_SIZE,
                afterFirst,
                'The first job loads one chunk of gifts'
            );
            Assert.areEqual(200, new GivingSampleData().countLoaded(), 'The second loads the rest');
        }
    }

    @IsTest
    static void aPayloadThatCannotBeReadFailsTheJobSoThePlatformRecordsIt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingSampleData.jsonOverride = 'this is not json';
            Boolean failed = false;

            try {
                new GivingSampleDataQueueable(
                        GivingSampleDataQueueable.STAGE_REFERENCE_DATA,
                        new Map<String, Id>()
                    )
                    .execute(null);
            } catch (Exception expected) {
                failed = true;
            }

            Assert.isTrue(failed, 'The failure is passed on after it is logged');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Fund__c WHERE Sample_Data__c = TRUE],
                'Nothing loaded'
            );
        }
    }
}
