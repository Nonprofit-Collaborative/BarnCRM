/**
 * Tests the module extension point of the sample data loader (C-10).
 *
 * Core cannot compile against a module package, so the real implementation (Giving) cannot
 * be referenced here. The tests inject stub modules through the @TestVisible override and
 * assert what Core does with them: it starts the first one, it starts the one after a named
 * module, and it asks each of them for its own count and its own removal.
 */
@IsTest
private class SampleDataModulesTest {
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

        public void enqueueLoad() {
            loadStarted = true;
        }

        /** Removes in chunks of two, the way a module removes in chunks of its load size. */
        public Integer removeNext() {
            removeCalls++;
            Integer removed = Math.min(loaded, 2);
            loaded -= removed;
            return removed;
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
            }
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
                'the second waits: a queueable may only enqueue one job, so each module starts the next'
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
    static void testStartAfterAnUnknownModuleStartsNothing() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule only = new StubModule('Only', 3);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ only };

            SampleDataModules.startAfter('NotInstalled');

            System.assertEquals(false, only.loadStarted, 'an unknown name starts no module');
        }
    }

    @IsTest
    static void testRemoveNextEmptiesEachModuleInTurnOneChunkAtATime() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            StubModule first = new StubModule('First', 3);
            StubModule second = new StubModule('Second', 5);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ first, second };

            List<Integer> chunks = new List<Integer>();
            Integer removed = SampleDataModules.removeNext();
            while (removed > 0) {
                chunks.add(removed);
                removed = SampleDataModules.removeNext();
            }

            System.assertEquals(
                new List<Integer>{ 2, 1, 2, 2, 1 },
                chunks,
                'one chunk per call, the first module emptied before the second'
            );
            System.assertEquals(0, first.loaded, 'the first module is empty');
            System.assertEquals(0, second.loaded, 'so is the second');
            System.assertEquals(
                0,
                SampleDataModules.removeNext(),
                'and then there is nothing left'
            );
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
