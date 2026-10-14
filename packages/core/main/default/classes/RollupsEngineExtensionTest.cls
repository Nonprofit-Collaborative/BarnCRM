/**
 * The engine answers Core's seam with what the engine itself says (ADR-NEXT): the targets of
 * its definitions, its freshness, and its queue, unchanged by the trip through the interface.
 */
@IsTest(testFor='ApexClass:RollupsEngineExtension')
private class RollupsEngineExtensionTest {
    @TestSetup
    static void createTheAdmin() {
        TestUsers.admin();
    }

    @IsTest
    static void coreFindsThisEngineByName() {
        System.runAs(TestUsers.admin()) {
            // Through Core's public lookup, since a module cannot see Core's test seams.
            Assert.isTrue(
                RollupEngineExtensions.find() instanceof RollupsEngineExtension,
                'The class Core looks up is this one'
            );
        }
    }

    @IsTest
    static void everyDefinitionsTargetIsReportedActiveOrNot() {
        System.runAs(TestUsers.admin()) {
            insert new Rollup_Definition__c(
                Name = 'Member count',
                Definition_Key__c = 'Core_Seam_Targets',
                Source_Object__c = 'Household_Member__c',
                Target_Object__c = 'Account',
                Relationship_Path__c = 'Household__c',
                Aggregate__c = 'COUNT',
                Target_Field__c = 'Member_Count__c',
                Mode__c = RollupService.MODE_SCHEDULED,
                Fiscal_Year_Aware__c = false,
                Active__c = false
            );

            Test.startTest();
            Map<String, Set<String>> targets = new RollupsEngineExtension().targetFieldsByObject();
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ 'Member_Count__c' },
                targets.get('Account'),
                'An inactive definition still owns its field'
            );
        }
    }

    @IsTest
    static void freshnessIsTheEnginesOwn() {
        System.runAs(TestUsers.admin()) {
            RollupsEngineExtension engine = new RollupsEngineExtension();

            Test.startTest();
            Datetime last = engine.lastCalculated();
            Boolean stale = engine.isStale();
            Test.stopTest();

            Assert.areEqual(RollupService.lastCalculated(), last, 'When the totals last completed');
            Assert.areEqual(RollupService.isStale(), stale, 'and whether that is too long ago');
        }
    }

    @IsTest
    static void anEmptyQueueStartsNothing() {
        System.runAs(TestUsers.admin()) {
            RollupsEngineExtension engine = new RollupsEngineExtension();

            Test.startTest();
            engine.processPending();
            engine.startQueuedRecalculation();
            engine.forSurvivors('Contact', new Set<Id>());
            engine.afterMerge('Account', new List<SObject>());
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Rollup_Queue__c],
                'Nothing was waiting, so nothing was queued'
            );
        }
    }
}
