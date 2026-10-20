/**
 * Tests the module extension point of the sample data loader (C-10).
 *
 * Core cannot compile against a module package, so the real implementation (Giving) cannot
 * be referenced here. The tests inject stub modules through the @TestVisible override and
 * assert what Core does with them: it starts the first one, it starts the one after a named
 * module, and it asks each of them for its own count and its own removal.
 */
@IsTest(testFor='ApexClass:SampleDataModules')
private class SampleDataModulesTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWithInstalledModules();
    }

    private class StubModule implements SampleDataModule {
        private final String name;
        private Integer loaded;
        private Boolean loadStarted = false;
        private Integer removeCalls = 0;

        private StubModule(String name, Integer loaded) {
            this.name = name;
            this.loaded = loaded;
        }

        public String moduleName() {
            return name;
        }

        public String countLabel() {
            return name + ' records';
        }

        public Integer countLoaded() {
            return loaded;
        }

        public Boolean hasSampleRecords() {
            return loaded > 0;
        }

        public void enqueueLoad() {
            loadStarted = true;
        }

        public void enqueueRemove() {
            removeCalls++;
            loaded = 0;
        }
    }

    @IsTest
    static void testInstalledResolvesOnlyUsableModules() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            // No override, so this asks the org itself. In an org with Core alone the list is
            // empty; where a module package is installed every entry has to be usable, because
            // Core calls these methods from the load chain and from the status card.
            List<SampleDataModule> modules = SampleDataModules.installed();

            for (SampleDataModule module : modules) {
                System.assertNotEquals(
                    '',
                    module.moduleName(),
                    'a resolved module has to name itself, or startAfter can never find it'
                );
                System.assertNotEquals(
                    null,
                    module.countLabel(),
                    'a resolved module has to give the card its own wording for its number'
                );
                System.assertNotEquals(
                    null,
                    module.countLoaded(),
                    'a resolved module has to answer with a number the card can show'
                );
                System.assertNotEquals(
                    null,
                    module.hasSampleRecords(),
                    'a resolved module has to say whether it still has sample records'
                );
            }
        }
    }

    @IsTest
    static void testAnyHasSampleRecordsAsksEveryModule() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule first = new StubModule('First', 0);
            StubModule second = new StubModule('Second', 0);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ first, second };
            Assert.isFalse(SampleDataModules.anyHasSampleRecords(), 'No module has any');

            second.loaded = 2;
            Assert.isTrue(
                SampleDataModules.anyHasSampleRecords(),
                'One module with sample records is enough'
            );
        }
    }

    @IsTest
    static void testStartFirstStartsOnlyTheFirstModule() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule first = new StubModule('First', 3);
            StubModule second = new StubModule('Second', 5);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ first, second };

            SampleDataModules.startFirst();

            System.assertEquals(true, first.loadStarted, 'the first module is started');
            System.assertEquals(
                false,
                second.loadStarted,
                'the second waits: modules load one at a time, so each module starts the next'
            );
        }
    }

    @IsTest
    static void testStartAfterStartsTheNextModule() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule first = new StubModule('First', 3);
            StubModule second = new StubModule('Second', 5);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ first, second };

            SampleDataModules.startAfter('First');

            System.assertEquals(
                true,
                second.loadStarted,
                'the module after the named one is started'
            );
            System.assertEquals(
                false,
                first.loadStarted,
                'the module that finished is not restarted'
            );
        }
    }

    @IsTest
    static void testStartAfterTheLastModuleStartsNothing() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule only = new StubModule('Only', 3);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ only };

            SampleDataModules.startAfter('Only');

            System.assertEquals(
                false,
                only.loadStarted,
                'the end of the chain is quiet rather than an error'
            );
        }
    }

    @IsTest
    static void theEndOfALoadWithoutTheRollupModuleStillFinishes() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            RollupEngineExtensions.noneForTest = true;
            StubModule only = new StubModule('Only', 3);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ only };

            Test.startTest();
            SampleDataModules.startAfter('Only');
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Error_Log__c],
                'with no engine to start, the load ends and says so without an error'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'],
                'and no rollup processor is queued'
            );
        }
    }

    @IsTest
    static void testStartAfterAnUnknownModuleStartsNothing() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule only = new StubModule('Only', 3);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ only };

            SampleDataModules.startAfter('NotInstalled');

            System.assertEquals(false, only.loadStarted, 'an unknown name starts no module');
        }
    }

    @IsTest
    static void testStartRemovalStartsTheLastModuleFirst() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule first = new StubModule('First', 3);
            StubModule second = new StubModule('Second', 5);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ first, second };

            SampleDataModules.startRemoval();

            System.assertEquals(1, second.removeCalls, 'the last module is removed first');
            System.assertEquals(0, first.removeCalls, 'the earlier module waits for the hand-off');
            System.assertEquals(
                0,
                SampleDataStageBatch.started.size(),
                'Core\'s own records wait for every module'
            );
        }
    }

    @IsTest
    static void testRemoveAfterStartsTheModuleBeforeThenCore() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule first = new StubModule('First', 3);
            StubModule second = new StubModule('Second', 5);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ first, second };

            SampleDataModules.removeAfter('Second');
            System.assertEquals(1, first.removeCalls, 'the module before the named one goes next');
            System.assertEquals(0, SampleDataStageBatch.started.size(), 'Core is not started yet');

            Test.startTest();
            SampleDataModules.removeAfter('First');
            Test.stopTest();

            System.assertEquals(1, SampleDataStageBatch.started.size(), 'Core\'s removal starts');
            System.assert(
                SampleDataStageBatch.started[0] instanceof SampleDataRemoveStages,
                'after the first module, the batch is Core\'s own removal stages'
            );
        }
    }

    @IsTest
    static void testRemoveAfterAnUnknownModuleStartsNothing() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule only = new StubModule('Only', 3);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ only };

            SampleDataModules.removeAfter('NotInstalled');

            System.assertEquals(0, only.removeCalls, 'an unknown name starts no module');
            System.assertEquals(0, SampleDataStageBatch.started.size(), 'and not Core either');
        }
    }

    @IsTest
    static void testCountsCarryEachModuleNameLabelAndNumber() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataModules.moduleOverride = new List<SampleDataModule>{
                new StubModule('Giving', 709)
            };

            List<SampleDataLoader.ModuleCount> counts = SampleDataModules.counts();

            System.assertEquals(1, counts.size(), 'one installed module is one count');
            System.assertEquals('Giving', counts[0].name);
            System.assertEquals(
                'Giving records',
                counts[0].label,
                'the module supplies the wording, so Core never names a gift'
            );
            System.assertEquals(709, counts[0].recordCount);
        }
    }

    @IsTest
    static void aClassOfTheWrongShapeIsLeftOutAndLogged() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            // A real class with a no-argument constructor that is not a SampleDataModule.
            SampleDataModule module = SampleDataModules.resolve('SampleDataModules');
            Test.getEventBus().deliver();

            System.assertEquals(null, module, 'only a class that implements the interface is used');
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'SampleDataModules.resolve'],
                'a module shipped in the wrong shape is written to the Error Log'
            );
        }
    }

    @IsTest
    static void aModuleThatIsNotInstalledIsNotAnError() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataModule module = SampleDataModules.resolve('NoSuchSampleDataModuleFu3');
            Test.getEventBus().deliver();

            System.assertEquals(null, module, 'a module that is not installed contributes nothing');
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'SampleDataModules.resolve'],
                'an org without the module is the ordinary case, not an error'
            );
        }
    }

    @IsTest
    static void installedModulesAreLookedUpOncePerTransaction() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            List<SampleDataModule> first = SampleDataModules.installed();
            List<SampleDataModule> second = SampleDataModules.installed();

            System.assertEquals(first.size(), second.size(), 'the same modules both times');
            for (Integer index = 0; index < first.size(); index++) {
                System.assert(first[index] === second[index], 'the cached instance is reused');
            }
        }
    }
}
