/**
 * The Recalculate rollups Flow action (R-R12, slice S10). Account has no packaged real-time
 * trigger for organizations counting their child organizations (`ParentId`), so it stands in for
 * an administrator's own entity: the action is called with the records a record-triggered Flow
 * would hand it.
 */
@IsTest(testFor='ApexClass:RollupRecalcAction')
private class RollupRecalcActionTest {
    /** Totals read right after each save: recalculated in the save (RollupTestSupport). */
    @TestSetup
    static void recalculateInTheSave() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupTestSupport.recalculateInTheSave();
        }
    }

    private static Rollup_Definition__c childCount() {
        return new Rollup_Definition__c(
            Name = 'Child organization count',
            Definition_Key__c = 'Core_Flow_Child_Count',
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
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

    private static RollupRecalcAction.Request request(SObject record, SObject prior) {
        RollupRecalcAction.Request request = new RollupRecalcAction.Request();
        request.record = record;
        request.priorRecord = prior;
        return request;
    }

    private static Integer countOn(Id parentId) {
        return [SELECT NumberOfEmployees FROM Account WHERE Id = :parentId].NumberOfEmployees;
    }

    @IsTest
    static void aNewRecordIsCountedInTheSameSave() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount();
            Account parent = organization('Parent', null);
            insert parent;
            Account child = organization('Child', parent.Id);
            insert child;

            Test.startTest();
            RollupRecalcAction.recalculate(
                new List<RollupRecalcAction.Request>{ request(child, null) }
            );
            Test.stopTest();

            System.Assert.areEqual(1, countOn(parent.Id), 'The flow action counted the new record');
        }
    }

    @IsTest
    static void aRecordMovedToAnotherParentLeavesTheOldTotal() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount();
            Account oldParent = organization('Old parent', null);
            Account newParent = organization('New parent', null);
            insert new List<Account>{ oldParent, newParent };
            Account child = organization('Child', oldParent.Id);
            insert child;
            RollupRecalcAction.recalculate(
                new List<RollupRecalcAction.Request>{ request(child, null) }
            );
            System.Assert.areEqual(1, countOn(oldParent.Id), 'Counted under its first parent');

            Account prior = child.clone(true, true, true, true);
            child.ParentId = newParent.Id;
            update child;

            Test.startTest();
            RollupRecalcAction.recalculate(
                new List<RollupRecalcAction.Request>{ request(child, prior) }
            );
            Test.stopTest();

            System.Assert.areEqual(
                0,
                countOn(oldParent.Id),
                'The prior values marked the old parent'
            );
            System.Assert.areEqual(1, countOn(newParent.Id), 'The new parent counts it');
        }
    }

    @IsTest
    static void aRecordBeingDeletedQueuesItsTotalsForAfterTheDelete() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount();
            Account parent = organization('Parent', null);
            insert parent;
            Account child = organization('Child', parent.Id);
            insert child;
            RollupRecalcAction.recalculate(
                new List<RollupRecalcAction.Request>{ request(child, null) }
            );

            RollupRecalcAction.Request deleting = request(child, null);
            deleting.deleting = true;
            Test.startTest();
            RollupRecalcAction.recalculate(new List<RollupRecalcAction.Request>{ deleting });
            List<Rollup_Queue__c> queued = [
                SELECT Target_Object__c, Record_Ids__c
                FROM Rollup_Queue__c
            ];
            delete child;
            Test.stopTest();

            System.Assert.areEqual(1, queued.size(), 'The parent waits in the queue');
            System.Assert.isTrue(
                queued[0].Record_Ids__c.contains(String.valueOf(parent.Id)),
                'The queue holds the parent of the record being deleted'
            );
            System.Assert.areEqual(
                0,
                countOn(parent.Id),
                'Once the delete is done, the queue recalculated the parent without it'
            );
        }
    }

    @IsTest
    static void aBulkSaveOfTwoHundredRecordsIsQueuedAndEveryTotalLands() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount();
            List<Account> parents = new List<Account>();
            for (Integer i = 0; i < 100; i++) {
                parents.add(organization('Parent ' + i, null));
            }
            insert parents;
            List<Account> children = new List<Account>();
            for (Integer i = 0; i < 200; i++) {
                children.add(organization('Child ' + i, parents[Math.mod(i, 100)].Id));
            }
            insert children;
            List<RollupRecalcAction.Request> requests = new List<RollupRecalcAction.Request>();
            for (Account child : children) {
                requests.add(request(child, null));
            }

            Test.startTest();
            RollupRecalcAction.recalculate(requests);
            AggregateResult queued = [SELECT SUM(Record_Count__c) total FROM Rollup_Queue__c];
            Test.stopTest();

            System.Assert.areEqual(
                100,
                ((Decimal) queued.get('total')).intValue(),
                'One hundred parents are more than one save recalculates, so they were queued'
            );
            for (Account parent : [SELECT NumberOfEmployees FROM Account WHERE Id IN :parents]) {
                System.Assert.areEqual(2, parent.NumberOfEmployees, 'Every parent counts both');
            }
        }
    }

    @IsTest
    static void nothingRunsWhileAllAutomationIsPaused() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount();
            Account parent = organization('Parent', null);
            insert parent;
            Account child = organization('Child', parent.Id);
            insert child;
            TestDataFactory.defaultSettings();
            User maria = TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
            System.runAs(maria) {
                AutomationControl.pauseAll(2);
            }

            Test.startTest();
            RollupRecalcAction.recalculate(
                new List<RollupRecalcAction.Request>{ request(child, null) }
            );
            Test.stopTest();

            System.Assert.isNull(countOn(parent.Id), 'Paused automation leaves the total alone');
            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Queue__c], 'Nothing was queued');
        }
    }

    @IsTest
    static void anEmptyCallDoesNothingAndFailsNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Test.startTest();
            RollupRecalcAction.recalculate(null);
            RollupRecalcAction.recalculate(
                new List<RollupRecalcAction.Request>{ new RollupRecalcAction.Request() }
            );
            Test.stopTest();

            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Queue__c], 'Nothing was queued');
        }
    }
}
