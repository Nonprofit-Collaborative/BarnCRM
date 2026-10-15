/**
 * Turning BarnCRM Rollup Builder off on the Module Manager stops the whole engine, not only the
 * module's own registry rows (ADR-0125 `0125-rollup-builder-module.md`, decision 9): the trigger
 * handler wherever another package registers it, the Flow action, Core's merge seam, the queue
 * processor, the nightly and full runs and the scheduler. Recalculate is refused and says why.
 * Turning it on again drains what waited and recalculates every rollup.
 *
 * People (Contact) are counted on their organization (`AccountId`), as in RollupBackgroundTest.
 */
@IsTest(
    testFor='ApexClass:RollupService, ApexClass:RollupQueue, ApexClass:RollupTriggerHandler, ApexClass:RollupController'
)
private class RollupModuleSwitchTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static Rollup_Definition__c staffCount() {
        return new Rollup_Definition__c(
            Name = 'Staff count',
            Definition_Key__c = 'Test_Switch_Staff_Count',
            Source_Object__c = 'Contact',
            Relationship_Path__c = 'AccountId',
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static Account organization() {
        Account created = new Account(
            Name = 'Organization',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
        insert created;
        return created;
    }

    private static Integer countOn(Id organizationId) {
        Integer count = [SELECT NumberOfEmployees FROM Account WHERE Id = :organizationId]
        .NumberOfEmployees;
        return count == null ? 0 : count;
    }

    private static Integer pending() {
        return [SELECT COUNT() FROM Rollup_Queue__c WHERE Status__c = :RollupQueue.STATUS_PENDING];
    }

    /**
     * Jobs started of this class: a batch's own BatchApex row or a Queueable. A batch also gets a
     * BatchApexWorker row per chunk it runs, with the same class, so those are left out.
     */
    private static Integer jobsOf(String className) {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = :className AND JobType IN ('BatchApex', 'Queueable')
        ];
    }

    private static Integer infoLogsSaying(String message) {
        Integer count = 0;
        for (Error_Log__c entry : [
            SELECT Message__c
            FROM Error_Log__c
            WHERE Severity__c = :ErrorLogger.SEVERITY_INFO
        ]) {
            if (entry.Message__c == message) {
                count++;
            }
        }
        return count;
    }

    /** Giving registers the engine's handler on its own objects, under its own module name. */
    private static void handlerRegisteredByAnotherModule() {
        Automation_Registry__mdt row = TestDataFactory.registryEntry('Giving_Rollups_Test', true);
        row.Handler_Class__c = 'RollupTriggerHandler';
        row.Object_Name__c = 'Contact';
        row.Module__c = 'Giving';
        row.Execution_Order__c = 90;
        TestDataFactory.useRegistry(new List<Automation_Registry__mdt>{ row });
    }

    private static ModuleManagerService.ModuleStatus moduleRow() {
        for (ModuleManagerService.ModuleStatus row : ModuleManagerService.getModules()) {
            if (row.name == RollupService.MODULE_NAME) {
                return row;
            }
        }
        return null;
    }

    @IsTest
    static void turnedOffEveryEntryPointDoesNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert staffCount();
            Account employer = organization();
            handlerRegisteredByAnotherModule();
            ModuleManagerService.turnOff(RollupService.MODULE_NAME);

            Test.startTest();
            Contact person = new Contact(LastName = 'Ames', AccountId = employer.Id);
            insert person;
            RollupRecalcAction.Request request = new RollupRecalcAction.Request();
            request.record = person;
            RollupRecalcAction.recalculate(new List<RollupRecalcAction.Request>{ request });
            RollupService.runAfterDelete('Contact', new List<SObject>{ person });
            RollupService.runForSurvivors('Account', new Set<Id>{ employer.Id });
            Id nightly = RollupService.startNightlyRun();
            Id everything = RollupService.startFullRunOfEveryDefinition();
            new RollupScheduler().execute(null);
            new RollupScheduler(true).execute(null);
            RollupService.startQueuedRecalculation();
            Test.stopTest();

            Assert.isTrue(RollupService.isTurnedOff(), 'The module is off');
            Assert.areEqual(
                ModuleManagerService.STATUS_OFF,
                moduleRow().status,
                'The Module Manager says so'
            );
            Assert.isTrue(moduleRow().canSwitch, 'And offers the switch');
            Assert.areEqual(0, countOn(employer.Id), 'No entry point counted Ames');
            Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Queue__c], 'Nothing was queued');
            Assert.isNull(nightly, 'The nightly run did not start');
            Assert.isNull(everything, 'Nor did Recalculate all');
            Assert.areEqual(
                0,
                jobsOf('RollupQueue') + jobsOf('RollupFullRecalcBatch'),
                'No processor or batch was started'
            );
            Assert.areEqual(
                2,
                infoLogsSaying(System.Label.Core_Rollups_FullRunTurnedOff),
                'Each full run says why it did not start'
            );
            Assert.areEqual(
                2,
                infoLogsSaying(System.Label.Core_Rollups_ScheduledRunTurnedOff),
                'The nightly run and Run tonight each say they were skipped'
            );
        }
    }

    @IsTest
    static void recalculateIsRefusedWhileItIsOff() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c definition = staffCount();
            insert definition;
            ModuleManagerService.turnOff(RollupService.MODULE_NAME);
            List<String> refusals = new List<String>();

            Test.startTest();
            try {
                RollupController.recalculate(definition.Id);
            } catch (AuraHandledException refused) {
                refusals.add(refused.getMessage());
            }
            try {
                RollupController.recalculateAll();
            } catch (AuraHandledException refused) {
                refusals.add(refused.getMessage());
            }
            try {
                RollupController.runTonight();
            } catch (AuraHandledException refused) {
                refusals.add(refused.getMessage());
            }
            Test.stopTest();

            Assert.areEqual(
                new List<String>{
                    System.Label.Core_Rollups_ErrorTurnedOff,
                    System.Label.Core_Rollups_ErrorTurnedOff,
                    System.Label.Core_Rollups_ErrorTurnedOff
                },
                refusals,
                'Recalculate, Recalculate all and Run tonight each say the module is off'
            );
            Assert.areEqual(0, jobsOf('RollupFullRecalcBatch'), 'No run started');
        }
    }

    @IsTest
    static void theBuilderSavesAndSaysItCalculatesOnceItIsOn() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            ModuleManagerService.turnOff(RollupService.MODULE_NAME);
            RollupBuilderController.Draft draft = new RollupBuilderController.Draft();
            draft.name = 'Staff count';
            draft.targetObject = 'Account';
            draft.targetField = 'NumberOfEmployees';
            draft.sourceObject = 'Contact';
            draft.relationshipPath = 'AccountId';
            draft.aggregate = 'COUNT';
            draft.mode = RollupService.MODE_BOTH;
            draft.active = true;

            Test.startTest();
            RollupBuilderController.SaveResult result = RollupBuilderController.save(draft, true);
            Test.stopTest();

            Assert.isNotNull(result.recordId, 'The rollup is saved');
            Assert.areEqual(
                System.Label.Core_RollupBuilder_SavedTurnedOff,
                result.notice,
                'And the notice says it is calculated once the module is on'
            );
            Assert.areEqual(0, jobsOf('RollupFullRecalcBatch'), 'Nothing started');
        }
    }

    @IsTest
    static void queuedTotalsWaitWhileItIsOff() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert staffCount();
            Account employer = organization();
            insert new Contact(LastName = 'Ames', AccountId = employer.Id);
            Integer queued = pending();
            ModuleManagerService.turnOff(RollupService.MODULE_NAME);

            Test.startTest();
            System.enqueueJob(new RollupQueue());
            Test.stopTest();

            Assert.isTrue(queued > 0, 'The save queued its total while the module was on');
            Assert.areEqual(queued, pending(), 'The processor left the entries waiting');
            Assert.areEqual(0, countOn(employer.Id), 'And counted nothing');
        }
    }

    @IsTest
    static void retryWhileOffPutsEntriesBackToWait() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert staffCount();
            Account employer = organization();
            ModuleManagerService.turnOff(RollupService.MODULE_NAME);
            // A fifth failed attempt, so the entry is Failed and on the Needs attention list.
            RollupQueue.retryLater(
                'Account',
                new Map<Id, String>{ employer.Id => 'Locked' },
                RollupQueue.MAX_ATTEMPTS - 1
            );
            insert new Contact(LastName = 'Ames', AccountId = employer.Id);

            Test.startTest();
            RollupAttentionController.retry(null);
            Test.stopTest();

            Assert.areEqual(1, pending(), 'Retry put the entry back in the queue');
            Assert.areEqual(0, jobsOf('RollupQueue'), 'But no processor ran while it is off');
            Assert.areEqual(0, countOn(employer.Id), 'And nothing was counted');
        }
    }

    @IsTest
    static void turnedOnAgainItDrainsTheQueueAndRecalculatesEverything() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert staffCount();
            Account employer = organization();
            Account other = organization();
            ModuleManagerService.turnOff(RollupService.MODULE_NAME);
            // Saved while off: nothing records them, so only a full recalculation counts them.
            insert new List<Contact>{
                new Contact(LastName = 'Ames', AccountId = employer.Id),
                new Contact(LastName = 'Baker', AccountId = other.Id)
            };
            // An entry that waited while off (a merge's survivors, for one).
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => new Set<Id>{ employer.Id } });
            Assert.areEqual(1, pending(), 'The entry waits while the module is off');

            Test.startTest();
            ModuleManagerService.turnOn(RollupService.MODULE_NAME);
            Test.stopTest();

            Assert.isFalse(RollupService.isTurnedOff(), 'The module is on');
            Assert.areEqual(1, jobsOf('RollupQueue'), 'Turn on started the queue processor');
            Assert.areEqual(1, jobsOf('RollupFullRecalcBatch'), 'And a full recalculation');
            Assert.areEqual(0, pending(), 'The waiting entry was drained');
            Assert.areEqual(1, countOn(employer.Id), 'Ames is counted');
            Assert.areEqual(1, countOn(other.Id), 'And Baker, saved while it was off');
        }
    }

    @IsTest
    static void turnedOnAgainTheEngineRuns() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert staffCount();
            Account employer = organization();
            handlerRegisteredByAnotherModule();
            ModuleManagerService.turnOff(RollupService.MODULE_NAME);
            ModuleManagerService.turnOn(RollupService.MODULE_NAME);

            Test.startTest();
            insert new Contact(LastName = 'Ames', AccountId = employer.Id);
            Test.stopTest();

            Assert.isFalse(RollupService.isTurnedOff(), 'The module is on');
            Assert.areEqual(ModuleManagerService.STATUS_ON, moduleRow().status);
            Assert.areEqual(1, countOn(employer.Id), 'Just after the save the queue counted Ames');
        }
    }
}
