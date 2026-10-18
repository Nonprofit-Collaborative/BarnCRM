/**
 * Core asks each installed module's access sync to give its sets to BarnCRM's roles: every one
 * with the nightly access check, and a single one when the Module Manager turns it on (ADR-0131
 * `0131-module-access-sync-by-role.md`). No module is needed: the syncs are injected by key.
 */
@IsTest(testFor='ApexClass:ModuleAccessSyncs')
private class ModuleAccessSyncsTest {
    @TestSetup
    static void createAdmin() {
        TestUsers.admin();
    }

    private class SyncRefusedException extends Exception {
    }

    /** A sync that counts how often it is asked, and can fail. */
    private class RecordingSync implements ModuleAccessSync {
        public Integer asked = 0;
        private final Boolean fails;

        RecordingSync(Boolean fails) {
            this.fails = fails;
        }

        public void requestSync() {
            asked++;
            if (fails) {
                throw new SyncRefusedException('Refused');
            }
        }
    }

    @IsTest
    static void theNightlyCheckAsksEveryModuleEvenWhenOneFails() {
        System.runAs(TestUsers.admin()) {
            RecordingSync failing = new RecordingSync(true);
            RecordingSync working = new RecordingSync(false);
            ModuleAccessSyncs.overrides.put('Example_Failing', failing);
            ModuleAccessSyncs.overrides.put('Example_Working', working);

            Test.startTest();
            new TabAccessScheduler().execute(null);
            Test.stopTest();

            Assert.areEqual(1, failing.asked, 'The failing sync was asked, and its failure logged');
            Assert.areEqual(1, working.asked, 'And it did not stop the next one');
        }
    }

    @IsTest
    static void turningOnAsksOnlyThatModule() {
        System.runAs(TestUsers.admin()) {
            RecordingSync volunteers = new RecordingSync(false);
            RecordingSync other = new RecordingSync(false);
            ModuleAccessSyncs.overrides.put('Example_Volunteers', volunteers);
            ModuleAccessSyncs.overrides.put('Example_Other', other);

            Test.startTest();
            ModuleAccessSyncs.requestFor('Example_Volunteers');
            ModuleAccessSyncs.requestFor('Example_Absent');
            Test.stopTest();

            Assert.areEqual(1, volunteers.asked, 'The module turned on is asked');
            Assert.areEqual(0, other.asked, 'No other module is asked');
        }
    }

    @IsTest
    static void aMissingOrWrongClassIsSkipped() {
        System.runAs(TestUsers.admin()) {
            Exception thrown;

            Test.startTest();
            try {
                // No class Example_MissingAccessSync exists.
                ModuleAccessSyncs.requestFor('Example_Missing');
                // ModuleAccessSync is the interface itself, which cannot be built.
                ModuleAccessSyncs.requestFor('Module');
            } catch (Exception e) {
                thrown = e;
            }
            Test.stopTest();

            Assert.isNull(thrown, 'A missing or wrong class never gets in the way: ' + thrown);
        }
    }
}
