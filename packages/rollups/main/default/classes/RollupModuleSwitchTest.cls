/**
 * Turning BarnCRM Rollup Builder off on the Module Manager stops the whole engine, not only the
 * module's own registry rows (ADR-NEXT `NEXT-rollup-builder-module.md`, decision 9): the trigger
 * handler wherever another package registers it, the Flow action, Core's merge seam, the queue
 * processor, the nightly and full runs and the scheduler. Turning it on again runs it again.
 *
 * People (Contact) are counted on their organization (`AccountId`), as in RollupBackgroundTest.
 */
@IsTest(testFor='ApexClass:RollupService, ApexClass:RollupQueue, ApexClass:RollupTriggerHandler')
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

    /** Giving registers the engine's handler on its own objects, under its own module name. */
    private static void handlerRegisteredByAnotherModule() {
        Automation_Registry__mdt row = TestDataFactory.registryEntry('Giving_Rollups_Test', true);
        row.Handler_Class__c = 'RollupTriggerHandler';
        row.Object_Name__c = 'Contact';
        row.Module__c = 'Giving';
        row.Execution_Order__c = 90;
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{ row };
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
            RollupService.runForSurvivors('Account', new Set<Id>{ employer.Id });
            Id nightly = RollupService.startNightlyRun();
            Id everything = RollupService.startFullRunOfEveryDefinition();
            new RollupScheduler().execute(null);
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
                [
                    SELECT COUNT()
                    FROM AsyncApexJob
                    WHERE ApexClass.Name IN ('RollupQueue', 'RollupFullRecalcBatch')
                ],
                'No processor or batch was started'
            );
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
