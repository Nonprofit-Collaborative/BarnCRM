/**
 * Core finds the Rollup Builder module's engine by name, or works without it (ADR-NEXT): the
 * resolver's own answers, and each Core caller with an engine present and absent.
 */
@IsTest(testFor='ApexClass:RollupEngineExtensions')
private class RollupEngineExtensionsTest {
    @TestSetup
    static void createTheAdmin() {
        TestUsers.admin();
    }

    /** Records what Core asked of the engine. */
    private class RecordingEngine implements RollupEngineExtension {
        public List<String> calls = new List<String>();
        public void afterMerge(String targetObject, List<SObject> mergedRecords) {
            calls.add('afterMerge ' + targetObject);
        }
        public void forSurvivors(String targetObject, Set<Id> survivorIds) {
            calls.add('forSurvivors ' + targetObject);
        }
        public void startQueuedRecalculation() {
            calls.add('startQueuedRecalculation');
        }
        public void processPending() {
            calls.add('processPending');
        }
        public Datetime lastCalculated() {
            return null;
        }
        public Boolean isStale() {
            return false;
        }
        public Map<String, Set<String>> targetFieldsByObject() {
            calls.add('targetFieldsByObject');
            return new Map<String, Set<String>>{ 'Contact' => new Set<String>{ 'Description' } };
        }
    }

    @IsTest
    static void anOverrideIsWhatCoreFinds() {
        System.runAs(TestUsers.admin()) {
            RecordingEngine engine = new RecordingEngine();
            RollupEngineExtensions.extensionOverride = engine;

            Assert.areEqual(engine, RollupEngineExtensions.find(), 'The injected engine');
            Assert.isTrue(RollupEngineExtensions.isInstalled(), 'counts as installed');
        }
    }

    @IsTest
    static void anOrgWithoutTheModuleHasNoEngine() {
        System.runAs(TestUsers.admin()) {
            RollupEngineExtensions.noneForTest = true;

            Assert.isNull(RollupEngineExtensions.find(), 'No module, no engine');
            Assert.isFalse(RollupEngineExtensions.isInstalled(), 'and Core says so');
        }
    }

    @IsTest
    static void aClassThatIsMissingOrTheWrongShapeIsAbsent() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            RollupEngineExtension missing = RollupEngineExtensions.resolve('NoSuchEngineClass');
            RollupEngineExtension wrongShape = RollupEngineExtensions.resolve(
                'RollupEngineExtensions'
            );
            Test.stopTest();

            Assert.isNull(missing, 'A class that is not there is absent');
            Assert.isNull(wrongShape, 'A class that is not an engine is absent');
        }
    }

    @IsTest
    static void resumingAutomationStartsTheWaitingTotalsOnlyWhenThereIsAnEngine() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.pausedSettings(-1);
            RecordingEngine engine = new RecordingEngine();
            RollupEngineExtensions.extensionOverride = engine;

            Test.startTest();
            Boolean resumed = AutomationControl.resumeExpiredPause();
            Test.stopTest();

            Assert.isTrue(resumed, 'The expired pause is cleared');

            Assert.areEqual(
                new List<String>{ 'processPending' },
                engine.calls,
                'The resume asks the engine to start what waited'
            );
        }
    }

    @IsTest
    static void resumingWithoutTheModuleStillResumes() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.pausedSettings(-1);
            RollupEngineExtensions.noneForTest = true;

            Test.startTest();
            Boolean resumed = AutomationControl.resumeExpiredPause();
            Test.stopTest();

            Assert.isTrue(resumed, 'Nothing waits, and the resume holds');
            Assert.isFalse(AutomationControl.isPaused(), 'Automation runs again');
        }
    }

    @IsTest
    static void rollupTargetsComeFromTheEngine() {
        System.runAs(TestUsers.admin()) {
            RecordingEngine engine = new RecordingEngine();
            RollupEngineExtensions.extensionOverride = engine;

            Test.startTest();
            Boolean description = DataProtectedFields.isProtected(
                Contact.SObjectType,
                'Description'
            );
            Test.stopTest();

            Assert.isTrue(description, 'A field the engine reports as a rollup target is kept');
            Assert.areEqual(new List<String>{ 'targetFieldsByObject' }, engine.calls, 'Asked once');
        }
    }

    @IsTest
    static void withoutTheModuleNoFieldIsARollupTarget() {
        System.runAs(TestUsers.admin()) {
            RollupEngineExtensions.noneForTest = true;

            Test.startTest();
            Boolean description = DataProtectedFields.isProtected(
                Contact.SObjectType,
                'Description'
            );
            Test.stopTest();

            Assert.isFalse(description, 'No module, no rollup targets');
        }
    }

    /** A module whose engine fails whatever Core asks of it. */
    private class FailingEngine implements RollupEngineExtension {
        public void afterMerge(String targetObject, List<SObject> mergedRecords) {
            throw new IllegalArgumentException('afterMerge failed');
        }
        public void forSurvivors(String targetObject, Set<Id> survivorIds) {
            throw new IllegalArgumentException('forSurvivors failed');
        }
        public void startQueuedRecalculation() {
            throw new IllegalArgumentException('startQueuedRecalculation failed');
        }
        public void processPending() {
            throw new IllegalArgumentException('processPending failed');
        }
        public Datetime lastCalculated() {
            throw new IllegalArgumentException('lastCalculated failed');
        }
        public Boolean isStale() {
            throw new IllegalArgumentException('isStale failed');
        }
        public Map<String, Set<String>> targetFieldsByObject() {
            throw new IllegalArgumentException('targetFieldsByObject failed');
        }
    }

    @IsTest
    static void aFailingEngineCostsOnlyItsRollupTargetsAndIsLogged() {
        System.runAs(TestUsers.admin()) {
            RollupEngineExtensions.extensionOverride = new FailingEngine();

            Test.startTest();
            Boolean description = DataProtectedFields.isProtected(
                Contact.SObjectType,
                'Description'
            );
            Test.stopTest();

            Assert.isFalse(description, 'No targets were reported, so none are kept');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'DataProtectedFields.rollupTargetsOf'
                ],
                'The failure is in the Error Log rather than thrown at the caller'
            );
        }
    }

    @IsTest
    static void mergingAccountsWithoutTheModuleStillMerges() {
        System.runAs(TestUsers.admin()) {
            RollupEngineExtensions.noneForTest = true;
            Account kept = new Account(Name = 'Riverside Food Bank');
            Account merged = new Account(Name = 'Riverside Food Bank (old)');
            insert new List<Account>{ kept, merged };

            Test.startTest();
            Database.merge(kept, merged.Id);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id IN (:kept.Id, :merged.Id)],
                'The merge went through: only the survivor is left'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'AccountTriggerHandler'],
                'With no engine there is nothing to recalculate and nothing fails'
            );
        }
    }
}
