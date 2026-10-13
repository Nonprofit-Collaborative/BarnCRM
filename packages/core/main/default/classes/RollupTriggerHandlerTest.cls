/**
 * The generic real-time handler: one handler, whichever entity a package registers it against.
 *
 * Core holds no giving objects, so organizations count their child organizations (`ParentId`),
 * as `RollupEngineTest` does. Account is not registered for real time, so the handler is called
 * directly with the records in front of it, as a registered trigger would.
 */
@IsTest(testFor='ApexClass:RollupTriggerHandler')
private class RollupTriggerHandlerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Rollup_Definition__c childCount() {
        return new Rollup_Definition__c(
            Name = 'Child organization count',
            Definition_Key__c = 'Core_Child_Count',
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_REAL_TIME,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static Account organization(String name, Id parentId) {
        return new Account(
            Name = name,
            ParentId = parentId,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
    }

    private static Integer countOn(Id parentId) {
        return [SELECT NumberOfEmployees FROM Account WHERE Id = :parentId].NumberOfEmployees;
    }

    @IsTest
    static void theHandlerRunsTheDefinitionsForWhateverEntityItWasGiven() {
        System.runAs(TestUsers.admin()) {
            insert childCount();
            Account parent = organization('Parent', null);
            insert parent;
            Account child = organization('Child', parent.Id);
            insert child;

            TriggerHandler.clearRunClaims();
            TriggerHandler.testNew = new List<SObject>{ child };

            Test.startTest();
            new RollupTriggerHandler().afterInsert();
            Test.stopTest();

            System.Assert.areEqual(
                1,
                countOn(parent.Id),
                'The entity was worked out from the records in front of the handler, not hard coded'
            );
        }
    }

    @IsTest
    static void thesameRecordsAreNotRunTwiceInOneTransaction() {
        System.runAs(TestUsers.admin()) {
            insert childCount();
            Account parent = organization('Parent', null);
            insert parent;
            Account child = organization('Child', parent.Id);
            insert child;

            TriggerHandler.clearRunClaims();
            TriggerHandler.testNew = new List<SObject>{ child };
            RollupTriggerHandler handler = new RollupTriggerHandler();
            handler.afterInsert();
            update new Account(Id = parent.Id, NumberOfEmployees = 99);

            Test.startTest();
            handler.afterInsert();
            Test.stopTest();

            System.Assert.areEqual(
                99,
                countOn(parent.Id),
                'A rollup that causes its own object to be saved again does its work once per record'
            );
        }
    }

    /**
     * ROLLUPS-1: a handler earlier in the save updates the record being inserted (a gift linked
     * to its installment), so the rollup handler sees that nested update first. The update must
     * not use up the insert: the insert is the event that moves the totals.
     */
    @IsTest
    static void aNestedUpdateDoesNotSkipTheInsertItIsPartOf() {
        System.runAs(TestUsers.admin()) {
            insert childCount();
            Account parent = organization('Parent', null);
            insert parent;
            Account child = organization('Child', parent.Id);
            insert child;

            TriggerHandler.clearRunClaims();
            Account renamed = child.clone(true);
            renamed.Name = 'Child, renamed';
            TriggerHandler.testNew = new List<SObject>{ renamed };
            TriggerHandler.testOldMap = new Map<Id, SObject>{ child.Id => child };
            RollupTriggerHandler handler = new RollupTriggerHandler();

            Test.startTest();
            handler.afterUpdate();
            System.Assert.isNull(
                countOn(parent.Id),
                'The nested update changed nothing a rollup reads, so it marked nothing'
            );
            TriggerHandler.testNew = new List<SObject>{ child };
            TriggerHandler.testOldMap = null;
            handler.afterInsert();
            Test.stopTest();

            System.Assert.areEqual(
                1,
                countOn(parent.Id),
                'The insert still ran after the nested update of the same record'
            );
        }
    }

    /** Every update is its own change: a second update of a record in one transaction runs. */
    @IsTest
    static void aSecondUpdateOfTheSameRecordStillRuns() {
        System.runAs(TestUsers.admin()) {
            insert childCount();
            Account first = organization('First parent', null);
            Account second = organization('Second parent', null);
            insert new List<Account>{ first, second };
            Account child = organization('Child', null);
            insert child;

            TriggerHandler.clearRunClaims();
            RollupTriggerHandler handler = new RollupTriggerHandler();
            Account underFirst = child.clone(true);
            underFirst.ParentId = first.Id;
            Account underSecond = child.clone(true);
            underSecond.ParentId = second.Id;

            Test.startTest();
            update underFirst;
            TriggerHandler.testNew = new List<SObject>{ underFirst };
            TriggerHandler.testOldMap = new Map<Id, SObject>{ child.Id => child };
            handler.afterUpdate();
            update underSecond;
            TriggerHandler.testNew = new List<SObject>{ underSecond };
            TriggerHandler.testOldMap = new Map<Id, SObject>{ child.Id => underFirst };
            handler.afterUpdate();
            Test.stopTest();

            Integer leftBehind = countOn(first.Id);
            System.Assert.isTrue(
                leftBehind == null || leftBehind == 0,
                'The child moved away again, so the first parent counts nothing'
            );
            System.Assert.areEqual(1, countOn(second.Id), 'And the second move was counted');
        }
    }

    /**
     * A definition asking for a SUM with nothing to sum cannot be planned, so the engine refuses
     * it. Two things have to be true afterwards: the save went through, and Maria can find out
     * why the number did not move.
     *
     * The child is saved before the broken definition exists, so the only run of the rollup over
     * it is the one this test makes, and the single log entry below is that run's.
     */
    @IsTest
    static void aFailureIsLoggedRatherThanFailingTheSave() {
        System.runAs(TestUsers.admin()) {
            Account parent = organization('Parent', null);
            insert parent;
            Account child = organization('Child', parent.Id);
            insert child;

            Rollup_Definition__c broken = childCount();
            broken.Aggregate__c = 'SUM';
            broken.Source_Field__c = null;
            insert broken;

            TriggerHandler.clearRunClaims();
            TriggerHandler.testNew = new List<SObject>{ child };

            Test.startTest();
            new RollupTriggerHandler().afterInsert();
            Test.getEventBus().deliver();
            Test.stopTest();

            // Nothing thrown: the administrator's save went through.
            System.Assert.isNull(countOn(parent.Id), 'The broken definition wrote nothing');
            System.Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :child.Id],
                'The save the rollup was running for stands (R-R4, plan Principle 2)'
            );
            List<Error_Log__c> logged = [
                SELECT Message__c, Technical_Detail__c, Record_Reference__c, Object_Name__c
                FROM Error_Log__c
                WHERE Context__c = 'RollupPlanner.plan'
            ];
            System.Assert.areEqual(1, logged.size(), 'And the failure is in the log, once');
            System.Assert.areEqual(
                String.valueOf(broken.Id),
                logged[0].Record_Reference__c,
                'Pointing at the definition Maria has to fix'
            );
            System.Assert.areEqual(
                'Rollup_Definition__c',
                logged[0].Object_Name__c,
                'So the entry can be grouped by what it is about'
            );
            System.Assert.areEqual(
                Label.Core_ErrorLog_UnexpectedFailure,
                logged[0].Message__c,
                'What Maria reads is plain language'
            );
            System.Assert.isTrue(
                logged[0].Technical_Detail__c.contains('RollupPlanException'),
                'And the detail she forwards names what refused the definition'
            );
        }
    }

    @IsTest
    static void theHandlerNamesItselfTheWayTheRegistryDoes() {
        System.runAs(TestUsers.admin()) {
            System.Assert.areEqual(
                'RollupTriggerHandler',
                new RollupTriggerHandler().getName(),
                'The name matches the Automation Registry rows that register it'
            );
        }
    }
}
