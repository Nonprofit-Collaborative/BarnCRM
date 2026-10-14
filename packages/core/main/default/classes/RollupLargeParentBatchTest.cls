/**
 * The large parent route of the Rollup Queue (canonical model R-RQ6, ADR-NEXT). Core holds no
 * giving objects, so the totals here roll organizations up to their parent account
 * (`ParentId`), as `RollupQueueTest` does. A test seam stands in for the row threshold, so a
 * parent with a handful of children is "too large" without inserting 50,000 rows.
 */
@IsTest(testFor='ApexClass:RollupLargeParentBatch')
private class RollupLargeParentBatchTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Id organizationType() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    /** Counts each organization's children into Number of Employees, and sums their revenue. */
    private static void insertDefinitions() {
        insert new List<Rollup_Definition__c>{
            new Rollup_Definition__c(
                Name = 'Child organizations',
                Definition_Key__c = 'Test_Large_Child_Count',
                Source_Object__c = 'Account',
                Relationship_Path__c = 'ParentId',
                Aggregate__c = 'COUNT',
                Target_Object__c = 'Account',
                Target_Field__c = 'NumberOfEmployees',
                Mode__c = RollupService.MODE_BOTH,
                Fiscal_Year_Aware__c = false,
                Active__c = true
            ),
            new Rollup_Definition__c(
                Name = 'Child revenue',
                Definition_Key__c = 'Test_Large_Child_Revenue',
                Source_Object__c = 'Account',
                Relationship_Path__c = 'ParentId',
                Source_Field__c = 'AnnualRevenue',
                Aggregate__c = 'SUM',
                Target_Object__c = 'Account',
                Target_Field__c = 'AnnualRevenue',
                Mode__c = RollupService.MODE_BOTH,
                Fiscal_Year_Aware__c = false,
                Active__c = true
            )
        };
    }

    /** A parent with this many children, each with revenue 10; its stored count is `stored`. */
    private static Account parentWith(Integer children, Integer stored) {
        Account parent = new Account(
            Name = 'Large parent ' + children,
            RecordTypeId = organizationType(),
            NumberOfEmployees = stored
        );
        insert parent;
        List<Account> rows = new List<Account>();
        for (Integer i = 0; i < children; i++) {
            rows.add(
                new Account(
                    Name = 'Child ' + i,
                    RecordTypeId = organizationType(),
                    ParentId = parent.Id,
                    AnnualRevenue = 10
                )
            );
        }
        insert rows;
        update new Account(Id = parent.Id, NumberOfEmployees = stored, AnnualRevenue = null);
        // What the saves queued is not under test: each test queues its own entries.
        delete [SELECT Id FROM Rollup_Queue__c];
        return parent;
    }

    private static Rollup_Queue__c entryFor(Id parentId, Integer attempts) {
        Rollup_Queue__c entry = new Rollup_Queue__c(
            Target_Object__c = 'Account',
            Record_Ids__c = String.valueOf(parentId),
            Record_Count__c = 1,
            Attempts__c = attempts,
            Status__c = RollupQueue.STATUS_PENDING,
            // Not due, so only the batch under test calculates it, never a queue run.
            Next_Attempt__c = Datetime.now().addMinutes(5)
        );
        insert entry;
        return [
            SELECT Id, Target_Object__c, Record_Ids__c, Definition_Ids__c, Attempts__c
            FROM Rollup_Queue__c
            WHERE Id = :entry.Id
        ];
    }

    private static List<Rollup_Queue__c> entries() {
        return [
            SELECT Record_Ids__c, Status__c, Attempts__c, Next_Attempt__c, Last_Error__c
            FROM Rollup_Queue__c
            ORDER BY CreatedDate, Id
        ];
    }

    @IsTest
    static void aParentWhoseStoredCountsReachTheThresholdIsOversized() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account large = parentWith(1, 40);
            Account small = parentWith(1, 2);
            RollupLargeParentBatch.largeParentRowsForTest = 30;

            Set<Id> oversized = RollupLargeParentBatch.oversized(
                Account.SObjectType,
                RollupSelector.selectActiveForTarget('Account', RollupService.everyMode()),
                new Set<Id>{ large.Id, small.Id }
            );

            Assert.areEqual(new Set<Id>{ large.Id }, oversized, 'Only the one its counts say');
            RollupLargeParentBatch.largeParentRowsForTest = null;
            Assert.areEqual(
                Limits.getLimitQueryRows() / 5,
                RollupLargeParentBatch.largeParentRows(),
                'A fifth of what a transaction may read, by default'
            );
        }
    }

    @IsTest
    static void theBatchFoldsChunksIntoTheSameTotalsAsOneQuery() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account parent = parentWith(5, 0);
            Rollup_Queue__c entry = entryFor(parent.Id, 0);

            Test.startTest();
            // Two rows a chunk: three chunks for five children, folded together.
            RollupLargeParentBatch.forEntries(new List<Rollup_Queue__c>{ entry }).runInline(2);
            Test.stopTest();

            Account written = [
                SELECT NumberOfEmployees, AnnualRevenue
                FROM Account
                WHERE Id = :parent.Id
            ];
            Assert.areEqual(5, written.NumberOfEmployees, 'Every child counted once');
            Assert.areEqual(50, written.AnnualRevenue, 'Every child summed once');
            Assert.isTrue(entries().isEmpty(), 'The entry the batch held is finished');
        }
    }

    @IsTest
    static void theBatchRunsAsAPlatformJob() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account parent = parentWith(4, 0);
            Rollup_Queue__c entry = entryFor(parent.Id, 0);

            Test.startTest();
            Database.executeBatch(
                RollupLargeParentBatch.forEntries(new List<Rollup_Queue__c>{ entry }),
                2000
            );
            Test.stopTest();

            Account written = [
                SELECT NumberOfEmployees, AnnualRevenue
                FROM Account
                WHERE Id = :parent.Id
            ];
            Assert.areEqual(4, written.NumberOfEmployees, 'Counted by the job');
            Assert.areEqual(40, written.AnnualRevenue, 'Summed by the job');
            Assert.isTrue(entries().isEmpty(), 'The entry is finished');
        }
    }

    @IsTest
    static void aStoppedChunkWritesNothingAndChargesTheEntry() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account parent = parentWith(3, 0);
            Rollup_Queue__c entry = entryFor(parent.Id, 1);
            RollupLargeParentBatch.stoppedChunksForTest = 1;

            Test.startTest();
            RollupLargeParentBatch.forEntries(new List<Rollup_Queue__c>{ entry }).runInline(2);
            Test.stopTest();

            Account written = [SELECT NumberOfEmployees FROM Account WHERE Id = :parent.Id];
            Assert.areEqual(0, written.NumberOfEmployees, 'A partial answer is never written');
            List<Rollup_Queue__c> left = entries();
            Assert.areEqual(1, left.size(), 'The entry stays');
            Assert.areEqual(2, left[0].Attempts__c, 'Charged one attempt');
            Assert.areEqual(RollupQueue.STATUS_PENDING, left[0].Status__c, 'Tried again later');
            Assert.isTrue(left[0].Last_Error__c.contains('Too many query rows'), 'Saying why');
        }
    }

    @IsTest
    static void theQueueSendsAnOversizedParentToTheBatch() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account large = parentWith(2, 40);
            Account small = parentWith(1, 0);
            RollupLargeParentBatch.largeParentRowsForTest = 30;

            Test.startTest();
            RollupQueue.add(
                new Map<String, Set<Id>>{ 'Account' => new Set<Id>{ large.Id, small.Id } }
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT NumberOfEmployees FROM Account WHERE Id = :small.Id].NumberOfEmployees,
                'The small parent is recalculated in the run'
            );
            Assert.areEqual(
                40,
                [SELECT NumberOfEmployees FROM Account WHERE Id = :large.Id].NumberOfEmployees,
                'The large one is left to the batch'
            );
            Assert.isTrue(RollupLargeParentBatch.startedForTest, 'A batch run was started');
            List<Rollup_Queue__c> held = entries();
            Assert.areEqual(1, held.size(), 'One entry, for the large parent');
            Assert.areEqual(String.valueOf(large.Id), held[0].Record_Ids__c, 'Holding it alone');
            Assert.isTrue(
                held[0].Next_Attempt__c > Datetime.now().addMinutes(30),
                'Waiting while the batch holds it'
            );
        }
    }

    @IsTest
    static void aStoppedRunChargesItsEntriesAndNeverLeavesThemWithoutAProcessor() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account parent = parentWith(1, 0);
            Rollup_Queue__c fresh = entryFor(parent.Id, 0);
            Rollup_Queue__c last = entryFor(parent.Id, RollupQueue.MAX_ATTEMPTS - 1);

            Test.startTest();
            RollupQueue.stopped(
                new List<Rollup_Queue__c>{ fresh, last },
                'System.LimitException: Too many query rows: 50001'
            );
            Test.stopTest();

            Map<Id, Rollup_Queue__c> byId = new Map<Id, Rollup_Queue__c>(
                [SELECT Status__c, Attempts__c, Next_Attempt__c, Last_Error__c FROM Rollup_Queue__c]
            );
            Rollup_Queue__c charged = byId.get(fresh.Id);
            Assert.areEqual(1, charged.Attempts__c, 'Charged one attempt');
            Assert.areEqual(RollupQueue.STATUS_PENDING, charged.Status__c, 'Not Failed yet');
            Assert.isTrue(charged.Last_Error__c.contains('Too many query rows'), 'Saying why');
            Assert.isTrue(
                charged.Next_Attempt__c > Datetime.now().addMinutes(30),
                'Held by the batch the run handed it to'
            );
            Assert.areEqual(
                RollupQueue.STATUS_FAILED,
                byId.get(last.Id).Status__c,
                'The fifth attempt is Failed and waits for Retry'
            );
            Assert.isTrue(RollupLargeParentBatch.startedForTest, 'The batch took the rest');
            Assert.areEqual(
                1,
                RollupQueue.readyEventsPublished,
                'A fresh processor is announced for everything else'
            );
        }
    }

    @IsTest
    static void entriesGroupByEntityWithTheirDefinitions() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Rollup_Definition__c count = [
                SELECT Id
                FROM Rollup_Definition__c
                WHERE Definition_Key__c = 'Test_Large_Child_Count'
            ];
            Account parent = parentWith(1, 0);
            Rollup_Queue__c named = entryFor(parent.Id, 2);
            named.Definition_Ids__c = String.valueOf(count.Id);

            List<RollupLargeParentBatch.Target> targets = RollupLargeParentBatch.targetsFor(
                new List<Rollup_Queue__c>{ named }
            );

            Assert.areEqual(1, targets.size(), 'One entity');
            Assert.areEqual(1, targets[0].definitions.size(), 'Only the definition it names');
            Assert.areEqual(2, targets[0].attempts, 'Carrying its attempts');
            Assert.isFalse(RollupLargeParentBatch.begin(null), 'Nothing to start');
        }
    }
}
