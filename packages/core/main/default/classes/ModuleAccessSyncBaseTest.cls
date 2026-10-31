/**
 * The shared run of a module's access sync (ADR-0131): each set given a slice at a time, the
 * module's own step after each pass, nothing while the module is turned off, and the queued run.
 * Each module's test covers its own sets and step.
 */
@IsTest(testFor='ApexClass:ModuleAccessSyncBase')
private class ModuleAccessSyncBaseTest {
    @TestSetup
    static void createAdmin() {
        TestUsers.admin();
    }

    private class StepFailedException extends Exception {
    }

    /** A module whose sets are not installed, so the run gives nothing and counts its steps. */
    private class ExampleSync extends ModuleAccessSyncBase {
        public Integer steps = 0;
        public Boolean stepFails = false;

        public override String moduleName() {
            return 'Example';
        }

        public override String logContext() {
            return 'ExampleAccessSync';
        }

        public override Map<String, List<String>> setsByPermissionSet() {
            return new Map<String, List<String>>{
                'Example_Admin' => new List<String>{ 'BarnCRM_Admin' }
            };
        }

        public override Map<String, List<String>> setsByRole() {
            return new Map<String, List<String>>{
                'Example_Staff' => new List<String>{ 'Program_Staff' }
            };
        }

        public override Integer sliceSize() {
            return 10;
        }

        public override void afterSync() {
            steps++;
            if (stepFails) {
                throw new StepFailedException('Step failed');
            }
        }
    }

    private static Integer loggedFor(String context) {
        return [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :context WITH SYSTEM_MODE];
    }

    @IsTest
    static void eachPassGivesEverySetAndRunsTheModuleStep() {
        System.runAs(TestUsers.admin()) {
            ExampleSync sync = new ExampleSync();

            Test.startTest();
            Boolean more = sync.sync();
            Test.stopTest();

            Assert.isFalse(more, 'Sets that are not installed leave nothing to give');
            Assert.areEqual(1, sync.steps, 'The module step ran once after the pass');
        }
    }

    @IsTest
    static void aFailingModuleStepIsLoggedAndNeverStopsTheSync() {
        System.runAs(TestUsers.admin()) {
            ExampleSync sync = new ExampleSync();
            sync.stepFails = true;

            Test.startTest();
            Boolean more = sync.sync();
            Test.stopTest();

            Assert.isFalse(more, 'The pass still answers');
            Assert.areEqual(1, loggedFor('ExampleAccessSync'), 'The failure is logged');
        }
    }

    @IsTest
    static void givesNothingWhileTheModuleIsOff() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Modules_Turned_Off__c = 'Example';
            Database.upsert(settings, AccessLevel.SYSTEM_MODE);
            ExampleSync sync = new ExampleSync();

            Test.startTest();
            Boolean more = sync.sync();
            Test.stopTest();

            Assert.isFalse(more, 'Nothing to do');
            Assert.areEqual(0, sync.steps, 'Not even the module step');
        }
    }

    @IsTest
    static void aRequestQueuesTheRun() {
        System.runAs(TestUsers.admin()) {
            ExampleSync sync = new ExampleSync();
            sync.stepFails = true;

            Test.startTest();
            sync.requestSync();
            Test.stopTest();

            Assert.areEqual(
                1,
                loggedFor('ExampleAccessSync'),
                'The queued run ran the pass, its step included'
            );
        }
    }
}
