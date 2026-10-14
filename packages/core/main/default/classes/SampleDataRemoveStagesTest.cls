/**
 * Tests Core's sample data removal (ADMIN-3): SampleDataRemoveStages and the SampleDataRemoveBatch
 * that runs it. A 200-household set is removed stage by stage in dependency order, a failing
 * stage stops the removal and is logged, and a test context runs the first stage alone, as the
 * load tests do.
 *
 * An Apex test runs one execute of a batch and nothing a batch starts, so the batch methods and
 * the stages are called directly here, one stage per call, as the platform calls them in an org.
 */
@IsTest(testFor='ApexClass:SampleDataRemoveStages, ApexClass:SampleDataRemoveBatch')
private class SampleDataRemoveStagesTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWithInstalledModules();
    }

    /** A removal that fails at the stage it is told to, and records what ran. */
    private class FailingStages implements SampleDataStages {
        private final Integer failAt;
        private List<Integer> ran = new List<Integer>();
        private Boolean finished = false;

        private FailingStages(Integer failAt) {
            this.failAt = failAt;
        }

        public String name() {
            return 'FailingRemoval';
        }

        public Integer stageCount() {
            return 3;
        }

        public void runStage(Integer stage) {
            if (stage == failAt) {
                throw new SampleDataException('stage ' + stage + ' failed');
            }
            ran.add(stage);
        }

        public void finish() {
            finished = true;
        }
    }

    /** Two hundred households of one person each, one organization, a connection, an affiliation. */
    private static String buildJson() {
        List<Object> households = new List<Object>();
        for (Integer h = 0; h < 200; h++) {
            households.add(
                new Map<String, Object>{
                    'key' => 'H' + h,
                    'customName' => false,
                    'members' => new List<Object>{
                        new Map<String, Object>{
                            'key' => 'H' +
                            h +
                            '-1',
                            'firstName' => 'Person',
                            'lastName' => 'Removal' + h,
                            'householdRole' => 'Head'
                        }
                    }
                }
            );
        }
        Map<String, Object> root = new Map<String, Object>{
            'households' => households,
            'organizations' => new List<Object>{
                new Map<String, Object>{ 'key' => 'O1', 'name' => 'Removal Foundation' }
            },
            'relationships' => new List<Object>{
                new Map<String, Object>{
                    'person' => 'H0-1',
                    'relatedPerson' => 'H1-1',
                    'type' => 'Friend',
                    'status' => 'Current'
                }
            },
            'affiliations' => new List<Object>{
                new Map<String, Object>{
                    'person' => 'H0-1',
                    'organization' => 'O1',
                    'role' => 'Board Member',
                    'status' => 'Current'
                }
            }
        };
        return JSON.serialize(root);
    }

    private static void loadTwoHundredHouseholds() {
        SampleDataSet data = SampleDataSet.parse(buildJson());
        SampleDataLoadStages.loadHouseholdsAndOrganizations(data);
        for (Integer chunk = 0; chunk < data.chunkCount(); chunk++) {
            SampleDataLoadStages.loadContactChunk(data, chunk);
        }
        SampleDataConnections.loadConnections(data);
    }

    @IsTest
    static void testStagesRemoveTwoHundredHouseholdsInDependencyOrder() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadTwoHundredHouseholds();
            SampleDataRemoveStages stages = new SampleDataRemoveStages();
            SampleDataStageBatch batch = new SampleDataRemoveBatch(stages);
            SampleDataStageBatch.everyStageInTest = true;

            Test.startTest();
            List<Integer> order = (List<Integer>) batch.start(null);
            // Connections 1, affiliations 1, contacts 2 chunks of 100, accounts 3 chunks (201).
            System.assertEquals(
                new List<Integer>{ 0, 1, 2, 3, 4, 5, 6 },
                order,
                'one stage for each chunk of each kind of record'
            );
            System.assertEquals(200, [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE]);

            batch.execute(null, new List<Integer>{ 0 });
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Relationship__c WHERE Sample_Data__c = TRUE],
                'stage 0: connections go first'
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Affiliation__c WHERE Sample_Data__c = TRUE],
                'affiliations wait for their stage'
            );
            System.assertEquals(
                200,
                [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE],
                'and so do the people'
            );

            batch.execute(null, new List<Integer>{ 1 });
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Affiliation__c WHERE Sample_Data__c = TRUE],
                'stage 1: affiliations'
            );
            System.assertEquals(200, [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE]);

            batch.execute(null, new List<Integer>{ 2 });
            System.assertEquals(
                100,
                [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE],
                'stage 2: the first chunk of one hundred people'
            );

            batch.execute(null, new List<Integer>{ 3 });
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE],
                'stage 3: the rest of the people'
            );
            System.assert(
                [SELECT COUNT() FROM Account WHERE Sample_Data__c = TRUE] > 0,
                'the households and the organization outlast every person'
            );

            for (Integer stage = 4; stage <= 6; stage++) {
                batch.execute(null, new List<Integer>{ stage });
            }
            batch.finish(null);
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Account WHERE Sample_Data__c = TRUE],
                'every household and organization is gone'
            );
            System.assertEquals(false, batch.stopped, 'no stage failed');
            System.assertEquals(
                false,
                SampleDataRemoveStages.removeNextChunk(),
                'nothing is left, so a further stage does nothing'
            );
        }
    }

    @IsTest
    static void testStageCountFollowsWhatIsLeft() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            System.assertEquals(
                0,
                new SampleDataRemoveStages().stageCount(),
                'an org with no sample data has no stages'
            );

            loadTwoHundredHouseholds();

            System.assertEquals(
                7,
                new SampleDataRemoveStages().stageCount(),
                'one connection, one affiliation, 200 people and 201 accounts make 1+1+2+3'
            );
        }
    }

    @IsTest
    static void testRemovalLeavesRecordsTheLoaderDidNotCreate() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadTwoHundredHouseholds();
            Account ownHousehold = new Account(Name = 'A real household');
            insert ownHousehold;
            Contact ownPerson = new Contact(LastName = 'Real', AccountId = ownHousehold.Id);
            insert ownPerson;

            SampleDataRemoveStages stages = new SampleDataRemoveStages();
            Integer count = stages.stageCount();
            for (Integer stage = 0; stage < count; stage++) {
                stages.runStage(stage);
            }

            System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE]);
            System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Sample_Data__c = TRUE]);
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Contact WHERE Id = :ownPerson.Id],
                'a person the admin entered is not touched'
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :ownHousehold.Id],
                'a household the admin entered is not touched'
            );
        }
    }

    @IsTest
    static void testATestContextRunsTheFirstStageOnly() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadTwoHundredHouseholds();
            SampleDataStageBatch batch = new SampleDataRemoveBatch(new SampleDataRemoveStages());

            List<Integer> order = (List<Integer>) batch.start(null);

            System.assertEquals(
                new List<Integer>{ 0 },
                order,
                'the platform allows one execute of a batch in a test'
            );
        }
    }

    @IsTest
    static void testAFailedStageIsRolledBackLoggedAndStopsTheRemoval() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            FailingStages stages = new FailingStages(1);
            SampleDataStageBatch.everyStageInTest = true;
            SampleDataStageBatch batch = new SampleDataRemoveBatch(stages);

            Test.startTest();
            for (Integer stage : (List<Integer>) batch.start(null)) {
                batch.execute(null, new List<Integer>{ stage });
            }
            batch.finish(null);
            Test.stopTest();

            System.assertEquals(new List<Integer>{ 0 }, stages.ran, 'stage 2 never runs');
            System.assertEquals(true, batch.stopped, 'the removal is marked stopped');
            System.assertEquals(false, stages.finished, 'a stopped removal hands over to nothing');
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'FailingRemoval%'],
                'the failure is logged once, with the stage that failed'
            );
        }
    }

    @IsTest
    static void testRemovalRunsInItsOwnBatchClass() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadTwoHundredHouseholds();

            Test.startTest();
            SampleDataRemoveBatch.startRemoval(new SampleDataRemoveStages());
            System.assertEquals(
                true,
                new SampleDataSelector().hasRunningRemoveJob(),
                'the status card can see the removal'
            );
            System.assertEquals(
                false,
                new SampleDataSelector().hasRunningLoadJob(),
                'and tell it from a load'
            );
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Relationship__c WHERE Sample_Data__c = TRUE],
                'the test context ran the first stage, which deletes the connections'
            );
            System.assertEquals(
                200,
                [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE],
                'and only that stage'
            );
        }
    }
}
