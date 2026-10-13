/**
 * Tests SampleDataStageBatch and Core's SampleDataLoadStages: the stage order, every stage of a
 * 200-person load run to the end, the hand-off to the module loads, and a stage that fails.
 *
 * An Apex test runs one execute of a batch and nothing a batch starts, so the batch methods are
 * called directly here, one stage per execute, as the platform calls them in an org.
 */
@IsTest
private class SampleDataStageBatchTest {
    /** A module that records that Core started it, standing in for Giving. */
    private class StubModule implements SampleDataModule {
        private Boolean loadStarted = false;

        public String moduleName() {
            return 'Stub';
        }

        public String countLabel() {
            return 'Stub records';
        }

        public Integer countLoaded() {
            return 0;
        }

        public void enqueueLoad() {
            loadStarted = true;
        }

        public Integer removeAll() {
            return 0;
        }
    }

    /** A load that records each stage it runs, and fails at the stage it is told to. */
    private class RecordingStages implements SampleDataStages {
        private final Integer failAt;
        private List<Integer> ran = new List<Integer>();
        private Boolean finished = false;

        private RecordingStages(Integer failAt) {
            this.failAt = failAt;
        }

        public String name() {
            return 'RecordingStages';
        }

        public Integer stageCount() {
            return 3;
        }

        public void runStage(Integer stage) {
            Database.insert(new Account(Name = 'Stage ' + stage), AccessLevel.USER_MODE);
            if (stage == failAt) {
                throw new SampleDataException('stage ' + stage + ' failed');
            }
            ran.add(stage);
        }

        public void finish() {
            finished = true;
        }
    }

    /** One hundred households of two people each, one organization and one connection. */
    private static String buildJson() {
        List<Object> households = new List<Object>();
        for (Integer h = 0; h < 100; h++) {
            List<Object> members = new List<Object>();
            for (Integer m = 1; m <= 2; m++) {
                members.add(
                    new Map<String, Object>{
                        'key' => 'H' +
                        h +
                        '-' +
                        m,
                        'firstName' => 'Person' + m,
                        'lastName' => 'Stage' + h,
                        'householdRole' => m == 1 ? 'Head' : 'Other'
                    }
                );
            }
            households.add(
                new Map<String, Object>{
                    'key' => 'H' + h,
                    'customName' => false,
                    'members' => members
                }
            );
        }
        Map<String, Object> root = new Map<String, Object>{
            'households' => households,
            'organizations' => new List<Object>{
                new Map<String, Object>{ 'key' => 'O1', 'name' => 'Stage Foundation' }
            },
            'relationships' => new List<Object>{
                new Map<String, Object>{
                    'person' => 'H0-1',
                    'relatedPerson' => 'H1-1',
                    'type' => 'Friend',
                    'status' => 'Current'
                }
            }
        };
        return JSON.serialize(root);
    }

    @IsTest
    static void testCoreStagesRunInOrderToTheModuleHandOff() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.jsonOverride = buildJson();
            StubModule module = new StubModule();
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ module };
            SampleDataStageBatch.everyStageInTest = true;
            SampleDataStageBatch batch = new SampleDataStageBatch(new SampleDataLoadStages());

            Test.startTest();
            List<Integer> order = (List<Integer>) batch.start(null);
            System.assertEquals(
                new List<Integer>{ 0, 1, 2, 3 },
                order,
                'accounts, two contact chunks of one hundred, then connections'
            );

            batch.execute(null, new List<Integer>{ 0 });
            System.assertEquals(
                100,
                SampleDataLoader.status().householdCount,
                'stage 0: households'
            );
            System.assertEquals(0, SampleDataLoader.status().contactCount, 'no people yet');

            batch.execute(null, new List<Integer>{ 1 });
            System.assertEquals(
                100,
                SampleDataLoader.status().contactCount,
                'stage 1: first chunk'
            );

            batch.execute(null, new List<Integer>{ 2 });
            System.assertEquals(
                200,
                SampleDataLoader.status().contactCount,
                'stage 2: second chunk'
            );
            System.assertEquals(false, module.loadStarted, 'modules wait for the last stage');

            batch.execute(null, new List<Integer>{ 3 });
            batch.finish(null);
            Test.stopTest();

            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(
                2,
                status.relationshipCount,
                'the connection and its mirror, using the household map kept between stages'
            );
            System.assertEquals(false, batch.stopped, 'no stage failed');
            System.assertEquals(true, module.loadStarted, 'finish starts the first module');
        }
    }

    @IsTest
    static void testATestContextRunsTheFirstStageOnly() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.jsonOverride = buildJson();
            SampleDataStageBatch batch = new SampleDataStageBatch(new SampleDataLoadStages());

            List<Integer> order = (List<Integer>) batch.start(null);

            System.assertEquals(
                new List<Integer>{ 0 },
                order,
                'the platform allows one execute of a batch in a test'
            );
        }
    }

    @IsTest
    static void testAFailedStageIsRolledBackAndStopsTheLoad() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            RecordingStages stages = new RecordingStages(1);
            SampleDataStageBatch.everyStageInTest = true;
            SampleDataStageBatch batch = new SampleDataStageBatch(stages);

            Test.startTest();
            for (Integer stage : (List<Integer>) batch.start(null)) {
                batch.execute(null, new List<Integer>{ stage });
            }
            batch.finish(null);
            Test.stopTest();

            System.assertEquals(new List<Integer>{ 0 }, stages.ran, 'stage 2 never runs');
            System.assertEquals(true, batch.stopped, 'the load is marked stopped');
            System.assertEquals(false, stages.finished, 'a stopped load hands over to nothing');
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE Name LIKE 'Stage %'],
                'the failed stage is rolled back and the stage before it is kept'
            );
        }
    }

    @IsTest
    static void testFinishWaitsForEveryStage() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            RecordingStages stages = new RecordingStages(null);
            SampleDataStageBatch batch = new SampleDataStageBatch(stages);

            Test.startTest();
            batch.start(null);
            batch.execute(null, new List<Integer>{ 0 });
            batch.finish(null);
            Test.stopTest();

            System.assertEquals(
                false,
                stages.finished,
                'a batch that ran one of three stages does not hand over'
            );
        }
    }

    @IsTest
    static void testLoadStartsTheStageBatch() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.jsonOverride = buildJson();

            Test.startTest();
            SampleDataLoader.load();
            Test.stopTest();

            System.assertEquals(1, SampleDataStageBatch.started.size(), 'one batch is started');
            System.assert(
                SampleDataStageBatch.started[0] instanceof SampleDataLoadStages,
                'the batch runs Core\'s own stages first'
            );
            System.assertEquals(
                100,
                SampleDataLoader.status().householdCount,
                'the batch ran the accounts stage'
            );
        }
    }
}
