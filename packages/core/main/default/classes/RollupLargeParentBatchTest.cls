/**
 * The large parent route of the Rollup Queue (canonical model R-RQ6, ADR-0116) and how a stopped
 * queue run narrows down to the record that stops it (R-RQ3). Core holds no giving objects, so
 * the totals here roll organizations up to their parent account (`ParentId`) or people up to
 * their organization, as `RollupQueueTest` and `RollupTextListsTest` do. Test seams stand in for
 * the row thresholds, so a parent with a handful of children is "too large" without inserting
 * 50,000 rows.
 */
@IsTest(testFor='ApexClass:RollupLargeParentBatch')
private class RollupLargeParentBatchTest {
    private static final String ROW_LIMIT = 'System.LimitException: Too many query rows: 50001';

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Id organizationType() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    private static Rollup_Definition__c definition(
        String key,
        String source,
        String path,
        String aggregate,
        String sourceField,
        String targetField
    ) {
        return new Rollup_Definition__c(
            Name = key,
            Definition_Key__c = 'Test_Large_' + key,
            Source_Object__c = source,
            Relationship_Path__c = path,
            Aggregate__c = aggregate,
            Source_Field__c = sourceField,
            Target_Object__c = 'Account',
            Target_Field__c = targetField,
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    /** Counts each organization's children into Number of Employees, and sums their revenue. */
    private static void insertDefinitions() {
        insert new List<Rollup_Definition__c>{
            definition('Count', 'Account', 'ParentId', 'COUNT', null, 'NumberOfEmployees'),
            definition('Revenue', 'Account', 'ParentId', 'SUM', 'AnnualRevenue', 'AnnualRevenue')
        };
    }

    /** A parent with this many children, each with revenue 10; its stored count is `stored`. */
    private static Account parentWith(Integer children, Integer stored) {
        Account parent = new Account(
            Name = 'Large parent ' + children,
            RecordTypeId = organizationType()
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
        return reread(entry.Id);
    }

    private static Rollup_Queue__c reread(Id entryId) {
        return [
            SELECT
                Id,
                Target_Object__c,
                Record_Ids__c,
                Definition_Ids__c,
                Attempts__c,
                Status__c,
                Next_Attempt__c,
                Last_Error__c
            FROM Rollup_Queue__c
            WHERE Id = :entryId
        ];
    }

    private static List<Rollup_Queue__c> entries() {
        return [
            SELECT
                Record_Ids__c,
                Record_Count__c,
                Status__c,
                Attempts__c,
                Next_Attempt__c,
                Last_Error__c
            FROM Rollup_Queue__c
            ORDER BY CreatedDate, Id
        ];
    }

    private static Account totalsOf(Id parentId) {
        return [
            SELECT NumberOfEmployees, AnnualRevenue, Description, Preferred_Name__c
            FROM Account
            WHERE Id = :parentId
        ];
    }

    /** Fake Account Ids, for entries that are only text. */
    private static List<Id> fakeAccountIds(Integer count) {
        List<Id> ids = new List<Id>();
        for (Integer i = 1; i <= count; i++) {
            ids.add(Id.valueOf('001' + String.valueOf(i).leftPad(12, '0')));
        }
        return ids;
    }

    /**
     * Calculates these definitions for the parent in one transaction, then again through the
     * batch three source rows a chunk, and asserts the two give the same totals.
     */
    private static void assertBatchMatchesEngine(
        List<Rollup_Definition__c> definitions,
        Id parentId
    ) {
        insert definitions;
        delete [SELECT Id FROM Rollup_Queue__c];
        RollupEngine.recalculate(new Set<Id>{ parentId }, definitions);
        Account expected = totalsOf(parentId);
        update new Account(
            Id = parentId,
            NumberOfEmployees = null,
            AnnualRevenue = null,
            Description = null,
            Preferred_Name__c = null
        );
        delete [SELECT Id FROM Rollup_Queue__c];

        RollupLargeParentBatch.forEntries(new List<Rollup_Queue__c>{ entryFor(parentId, 0) })
            .runInline(3);

        Account actual = totalsOf(parentId);
        Assert.areEqual(expected.NumberOfEmployees, actual.NumberOfEmployees, 'Number');
        Assert.areEqual(expected.AnnualRevenue, actual.AnnualRevenue, 'Currency');
        Assert.areEqual(expected.Description, actual.Description, 'Long text');
        Assert.areEqual(expected.Preferred_Name__c, actual.Preferred_Name__c, 'Text');
        Assert.isTrue(entries().isEmpty(), 'The entry the batch held is finished');
    }

    // --------------------------------------------------------------------------- estimates

    @IsTest
    static void storedCountsEstimateRowsAndAMissingCountIsUnknownNotSmall() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account large = parentWith(1, 40);
            Account never = parentWith(1, 0);
            update new Account(Id = never.Id, NumberOfEmployees = null);

            Map<Id, Integer> rows = RollupLargeParentBatch.estimate(
                Account.SObjectType,
                RollupSelector.selectActiveForTarget('Account', RollupService.everyMode()),
                new Set<Id>{ large.Id, never.Id }
            );

            Assert.areEqual(40, rows.get(large.Id), 'Its count, times one planned query');
            Assert.areEqual(
                RollupLargeParentBatch.UNKNOWN_ROWS_PER_QUERY,
                rows.get(never.Id),
                'Never calculated: unknown, not one row'
            );
            Assert.areEqual(
                Limits.getLimitQueryRows() * 2 / 5,
                RollupLargeParentBatch.largeParentRows(),
                'Two fifths of what a transaction may read, by default'
            );
            Assert.isTrue(
                RollupLargeParentBatch.largeParentRows() < RollupLargeParentBatch.sliceRowBudget(),
                'Below the run budget, leaving headroom'
            );
        }
    }

    @IsTest
    static void startingARunTakesTheRunLockCreatingItTheFirstTime() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account parent = parentWith(1, 0);

            Test.startTest();
            Boolean started = RollupLargeParentBatch.begin(
                new List<Rollup_Queue__c>{ entryFor(parent.Id, 0) },
                true
            );
            Boolean again = RollupLargeParentBatch.lockRuns();
            Test.stopTest();

            Assert.isTrue(started, 'Started under the lock');
            Assert.isTrue(again, 'The same transaction holds it already');
            Assert.areEqual(1, [SELECT COUNT() FROM Rollup_Run_Lock__c], 'One lock record');
        }
    }

    @IsTest
    static void aLockRecordAnotherRunCreatedFirstIsWaitedFor() {
        System.runAs(TestUsers.admin()) {
            RollupLargeParentBatch.competingLockForTest = true;

            Test.startTest();
            Boolean locked = RollupLargeParentBatch.lockRuns();
            Test.stopTest();

            Assert.isTrue(locked, 'Locked the record the other run created');
            Assert.areEqual(1, [SELECT COUNT() FROM Rollup_Run_Lock__c], 'Still one record');
        }
    }

    /** A record under the large record threshold stays in the queue; one at it goes here. */
    @IsTest
    static void onlyARecordAtTheLargeRecordThresholdGoesToTheBatch() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account fits = parentWith(1, 20);
            Account over = parentWith(2, 25);
            RollupLargeParentBatch.largeParentRowsForTest = 25;
            RollupLargeParentBatch.sliceRowBudgetForTest = 40;

            Test.startTest();
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => new Set<Id>{ fits.Id } });
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => new Set<Id>{ over.Id } });
            Test.stopTest();

            Assert.areEqual(1, totalsOf(fits.Id).NumberOfEmployees, 'Twenty rows: in the run');
            Assert.areEqual(25, totalsOf(over.Id).NumberOfEmployees, 'The threshold: the batch');
            Assert.isTrue(RollupLargeParentBatch.startedForTest, 'A batch run was started');
            List<Rollup_Queue__c> held = entries();
            Assert.areEqual(1, held.size(), 'Only the record at the threshold waits');
            Assert.areEqual(String.valueOf(over.Id), held[0].Record_Ids__c, 'Held by the batch');
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

            Assert.areEqual(1, totalsOf(small.Id).NumberOfEmployees, 'Small: in the run');
            Assert.areEqual(40, totalsOf(large.Id).NumberOfEmployees, 'Large: left to the batch');
            Assert.isTrue(RollupLargeParentBatch.startedForTest, 'A batch run was started');
            List<Rollup_Queue__c> held = entries();
            Assert.areEqual(1, held.size(), 'One entry, for the large parent');
            Assert.areEqual(String.valueOf(large.Id), held[0].Record_Ids__c, 'Holding it alone');
            Assert.areEqual(1, held[0].Attempts__c, 'Charged as the batch takes it');
            Assert.isTrue(
                held[0].Next_Attempt__c > Datetime.now().addMinutes(30),
                'Held while the batch runs'
            );
        }
    }

    @IsTest
    static void aRunTakesRecordsUpToItsRowBudgetAndLeavesTheRestForTheNext() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Set<Id> parents = new Set<Id>();
            for (Integer i = 0; i < 3; i++) {
                parents.add(parentWith(1, 10).Id);
            }
            RollupLargeParentBatch.sliceRowBudgetForTest = 25;

            Test.startTest();
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => parents });
            Test.stopTest();

            Integer recalculated = [
                SELECT COUNT()
                FROM Account
                WHERE Id IN :parents AND NumberOfEmployees = 1
            ];
            Assert.areEqual(2, recalculated, 'Ten rows each: two fit a budget of 25');
            List<Rollup_Queue__c> left = entries();
            Assert.areEqual(1, left.size(), 'The third waits for the next run');
            Assert.areEqual(1, left[0].Record_Count__c, 'Holding one record');
            Assert.areEqual(0, left[0].Attempts__c, 'Deferred, not charged');
            Assert.isNull(left[0].Next_Attempt__c, 'Due straight away');
        }
    }

    /**
     * The shape of the 25,000 row scale test: a large parent whose entries name only
     * definitions with no COUNT. Going by the named definitions' counts alone took it as
     * unknown (ten rows a query), so its queries read every source row and stopped the run on
     * the query row limit. The entity's stored counts decide, whichever definitions an entry
     * names: the large parent goes to the batch, the run reads only the small one, and the
     * batch then writes the large parent's totals.
     */
    @IsTest
    static void aLargeParentWhoseEntriesNameNoCountStillGoesToTheBatch() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Rollup_Definition__c revenue = [
                SELECT Id
                FROM Rollup_Definition__c
                WHERE Definition_Key__c = 'Test_Large_Revenue'
            ];
            Account large = parentWith(3, 40);
            Account small = parentWith(1, 0);
            RollupLargeParentBatch.largeParentRowsForTest = 30;

            Map<Id, Integer> rows = RollupLargeParentBatch.estimate(
                Account.SObjectType,
                RollupSelector.selectActiveByIds(new Set<Id>{ revenue.Id }),
                new Set<Id>{ large.Id }
            );
            Assert.areEqual(40, rows.get(large.Id), 'Its stored count, though no COUNT is named');

            Test.startTest();
            RollupQueue.add(
                new Map<String, Set<Id>>{ 'Account' => new Set<Id>{ large.Id, small.Id } },
                new Map<String, Set<Id>>{ 'Account' => new Set<Id>{ revenue.Id } }
            );
            Test.stopTest();

            Assert.areEqual(10, totalsOf(small.Id).AnnualRevenue, 'Small: summed in the run');
            Assert.isNull(totalsOf(large.Id).AnnualRevenue, 'Large: not read by the run');
            Assert.isTrue(RollupLargeParentBatch.startedForTest, 'A batch run was started');
            List<Rollup_Queue__c> held = [SELECT Id FROM Rollup_Queue__c];
            Assert.areEqual(1, held.size(), 'One entry, for the large parent');
            Rollup_Queue__c entry = reread(held[0].Id);
            Assert.areEqual(String.valueOf(large.Id), entry.Record_Ids__c, 'Holding it alone');
            Assert.areEqual(String.valueOf(revenue.Id), entry.Definition_Ids__c, 'Still named');

            RollupLargeParentBatch.forEntries(new List<Rollup_Queue__c>{ entry }).runInline(2);

            Account written = totalsOf(large.Id);
            Assert.areEqual(30, written.AnnualRevenue, 'Summed by the batch, in chunks');
            Assert.areEqual(40, written.NumberOfEmployees, 'The count was not named: untouched');
            Assert.isTrue(entries().isEmpty(), 'The entry is finished');
        }
    }

    /**
     * A run whose first entity reads more than its stored count said leaves less for the next:
     * the parent's count says one row but it has thirty children, so after it the second
     * entity's record (ten rows, unknown) no longer fits a budget of twenty and waits for the
     * next run, uncharged. Taken on estimates alone it would have run.
     */
    @IsTest
    static void rowsAnEntityReadDeferTheNextEntityWhenTheyExceedItsEstimate() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account understated = parentWith(30, 1);
            Id contactId = Id.valueOf('003000000000001');
            RollupLargeParentBatch.sliceRowBudgetForTest = 20;

            Test.startTest();
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => new Set<Id>{ understated.Id } });
            RollupQueue.add(new Map<String, Set<Id>>{ 'Contact' => new Set<Id>{ contactId } });
            Test.stopTest();

            Assert.areEqual(
                30,
                totalsOf(understated.Id).NumberOfEmployees,
                'The first entity ran, reading all thirty rows'
            );
            List<Rollup_Queue__c> waiting = [
                SELECT Record_Ids__c, Status__c, Attempts__c, Next_Attempt__c
                FROM Rollup_Queue__c
                WHERE Target_Object__c = 'Contact'
            ];
            Assert.areEqual(1, waiting.size(), 'The second entity waits in an entry');
            Assert.areEqual(String.valueOf(contactId), waiting[0].Record_Ids__c, 'Its record');
            Assert.areEqual(RollupQueue.STATUS_PENDING, waiting[0].Status__c, 'Pending');
            Assert.areEqual(0, waiting[0].Attempts__c, 'Deferred, not charged');
            Assert.isNull(waiting[0].Next_Attempt__c, 'Due straight away');
        }
    }

    /** What a run's recalculations read counts against its budget, not what was estimated. */
    @IsTest
    static void rowsARunReadLeaveLessOfItsBudgetThanTheEstimatesSaid() {
        System.runAs(TestUsers.admin()) {
            RollupLargeParentBatch.sliceRowBudgetForTest = 100;

            Assert.areEqual(60, RollupQueue.rowsLeft(60, 30), 'Read as estimated: the estimates');
            Assert.areEqual(20, RollupQueue.rowsLeft(60, 80), 'Read more: what was read');
            Assert.areEqual(-5, RollupQueue.rowsLeft(60, 105), 'Over: no later record fits');
        }
    }

    // ------------------------------------------------------------------------------ merging

    @IsTest
    static void chunksMergeSumsAveragesFiltersAndFirstValues() {
        System.runAs(TestUsers.admin()) {
            Account parent = new Account(Name = 'Parent', RecordTypeId = organizationType());
            insert parent;
            List<Account> children = new List<Account>();
            for (Integer i = 0; i < 7; i++) {
                children.add(
                    new Account(
                        Name = 'Child ' + i,
                        RecordTypeId = organizationType(),
                        ParentId = parent.Id,
                        AnnualRevenue = i * 10,
                        // Ties on the order attribute, broken by record Id across chunks.
                        NumberOfEmployees = Math.mod(i, 3) + 1
                    )
                );
            }
            insert children;
            Rollup_Definition__c filtered = definition(
                'Filtered',
                'Account',
                'ParentId',
                'COUNT',
                null,
                'NumberOfEmployees'
            );
            filtered.Filter_JSON__c = '{"version": 1, "conditions": [{"id": 1, "field": "AnnualRevenue", "operator": "greater than", "value": 15}]}';
            Rollup_Definition__c first = definition(
                'First',
                'Account',
                'ParentId',
                'FIRST',
                'Name',
                'Preferred_Name__c'
            );
            first.Order_By_Field__c = 'NumberOfEmployees';

            assertBatchMatchesEngine(
                new List<Rollup_Definition__c>{
                    definition(
                        'Average',
                        'Account',
                        'ParentId',
                        'AVG',
                        'AnnualRevenue',
                        'AnnualRevenue'
                    ),
                    filtered,
                    first
                },
                parent.Id
            );
            Account written = totalsOf(parent.Id);
            Assert.areEqual(30, written.AnnualRevenue, 'The average of 0 to 60');
            Assert.areEqual(5, written.NumberOfEmployees, 'Only revenue over 15');
            Assert.areEqual('Child 0', written.Preferred_Name__c, 'The tie goes to the lower Id');
        }
    }

    @IsTest
    static void chunksMergeLastValues() {
        System.runAs(TestUsers.admin()) {
            Account parent = new Account(Name = 'Parent', RecordTypeId = organizationType());
            insert parent;
            List<Account> children = new List<Account>();
            for (Integer i = 0; i < 5; i++) {
                children.add(
                    new Account(
                        Name = 'Child ' + i,
                        RecordTypeId = organizationType(),
                        ParentId = parent.Id,
                        NumberOfEmployees = 7
                    )
                );
            }
            insert children;
            Rollup_Definition__c last = definition(
                'Last',
                'Account',
                'ParentId',
                'LAST',
                'Name',
                'Preferred_Name__c'
            );
            last.Order_By_Field__c = 'NumberOfEmployees';

            assertBatchMatchesEngine(new List<Rollup_Definition__c>{ last }, parent.Id);
            Assert.areEqual(
                'Child 0',
                totalsOf(parent.Id).Preferred_Name__c,
                'Every row ties: the lower Id, whichever chunk read it'
            );
        }
    }

    @IsTest
    static void chunksMergeDistinctCountsAndTextLists() {
        System.runAs(TestUsers.admin()) {
            Account parent = new Account(Name = 'Parent', RecordTypeId = organizationType());
            insert parent;
            List<Contact> people = new List<Contact>();
            for (Integer i = 8; i >= 0; i--) {
                people.add(
                    new Contact(
                        LastName = 'P' + i,
                        Title = i == 4 ? null : 'Role ' + Math.mod(i, 3),
                        AccountId = parent.Id
                    )
                );
            }
            insert people;
            Rollup_Definition__c names = definition(
                'Names',
                'Contact',
                'AccountId',
                'TEXT_LIST',
                'LastName',
                'Description'
            );
            names.Delimiter__c = 'Semicolon';

            assertBatchMatchesEngine(
                new List<Rollup_Definition__c>{
                    definition(
                        'Distinct',
                        'Contact',
                        'AccountId',
                        'COUNT_DISTINCT',
                        'Title',
                        'NumberOfEmployees'
                    ),
                    names,
                    definition(
                        'Titles',
                        'Contact',
                        'AccountId',
                        'TEXT_LIST_DISTINCT',
                        'Title',
                        'Preferred_Name__c'
                    )
                },
                parent.Id
            );
            Account written = totalsOf(parent.Id);
            Assert.areEqual(3, written.NumberOfEmployees, 'Three titles, blanks left out');
            Assert.areEqual(
                'P0; P1; P2; P3; P4; P5; P6; P7; P8',
                written.Description,
                'Every name'
            );
            Assert.areEqual('Role 0, Role 1, Role 2', written.Preferred_Name__c, 'Each once');
        }
    }

    @IsTest
    static void aDistinctTallyKeepsOneEntryPerValue() {
        // runs-as: deploying user (pure function over in-memory values, no data access)
        RollupAggregator.Tally tally = new RollupAggregator.Tally();
        for (Integer i = 9; i >= 0; i--) {
            tally.add(
                new RollupAggregator.Listed(
                    'role',
                    '001' + String.valueOf(i).leftPad(15, '0'),
                    'Role'
                ),
                true
            );
        }
        Assert.areEqual(1, tally.listed.size(), 'Ten rows, one value, one entry');
        Assert.isTrue(tally.listed[0].recordId.endsWith('0'), 'The earliest row is the one kept');
        Assert.areEqual(1, tally.result('COUNT_DISTINCT', null), 'Counted once');
    }

    // ------------------------------------------------------------------------- the batch

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

            Account written = totalsOf(parent.Id);
            Assert.areEqual(4, written.NumberOfEmployees, 'Counted by the job');
            Assert.areEqual(40, written.AnnualRevenue, 'Summed by the job');
            Assert.isTrue(entries().isEmpty(), 'The entry is finished');
        }
    }

    @IsTest
    static void aStoppedChunkWritesNothingAndReleasesTheEntryWithTheReason() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account parent = parentWith(3, 0);
            Rollup_Queue__c entry = entryFor(parent.Id, 1);
            RollupLargeParentBatch.stoppedChunksForTest = 1;

            Test.startTest();
            RollupLargeParentBatch.forEntries(new List<Rollup_Queue__c>{ entry }).runInline(2);
            Test.stopTest();

            Assert.areEqual(0, totalsOf(parent.Id).NumberOfEmployees, 'Nothing partial written');
            List<Rollup_Queue__c> left = entries();
            Assert.areEqual(1, left.size(), 'The entry stays');
            Assert.areEqual(1, left[0].Attempts__c, 'Charged once, when the batch took it');
            Assert.areEqual(RollupQueue.STATUS_PENDING, left[0].Status__c, 'Tried again later');
            Assert.isTrue(
                left[0].Next_Attempt__c < Datetime.now().addMinutes(10),
                'No longer held'
            );
            Assert.isTrue(left[0].Last_Error__c.contains('Too many query rows'), 'Saying why');
        }
    }

    @IsTest
    static void theFifthAttemptThroughTheBatchIsFailed() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account parent = parentWith(2, 0);
            Rollup_Queue__c entry = entryFor(parent.Id, RollupQueue.MAX_ATTEMPTS - 1);

            Test.startTest();
            Boolean started = RollupLargeParentBatch.begin(
                new List<Rollup_Queue__c>{ entry },
                true
            );
            RollupLargeParentBatch.stoppedChunksForTest = 1;
            RollupLargeParentBatch.forEntries(new List<Rollup_Queue__c>{ reread(entry.Id) })
                .runInline(2);
            Test.stopTest();

            Assert.isTrue(started, 'The batch took it');
            Rollup_Queue__c failed = reread(entry.Id);
            Assert.areEqual(RollupQueue.MAX_ATTEMPTS, failed.Attempts__c, 'The fifth attempt');
            Assert.areEqual(RollupQueue.STATUS_FAILED, failed.Status__c, 'Waits for Retry');
            Assert.isTrue(failed.Last_Error__c.contains('Too many query rows'), 'Saying why');
        }
    }

    @IsTest
    static void whileARunIsGoingEntriesWaitTwoMinutesUncharged() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account parent = parentWith(1, 0);
            Rollup_Queue__c entry = entryFor(parent.Id, 0);
            RollupLargeParentBatch.runningForTest = true;

            Boolean started = RollupLargeParentBatch.begin(
                new List<Rollup_Queue__c>{ entry },
                true
            );

            Assert.isFalse(started, 'One run at a time');
            Rollup_Queue__c waiting = reread(entry.Id);
            Assert.areEqual(0, waiting.Attempts__c, 'Not charged');
            Assert.isTrue(
                waiting.Next_Attempt__c <= Datetime.now().addMinutes(3),
                'Routed again in two minutes'
            );
        }
    }

    @IsTest
    static void anExpiredHoldIsRoutedAgainAndCharged() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account large = parentWith(2, 40);
            Rollup_Queue__c entry = entryFor(large.Id, 1);
            update new Rollup_Queue__c(
                Id = entry.Id,
                Next_Attempt__c = Datetime.now().addMinutes(-1),
                Last_Error__c = System.Label.Core_Rollups_QueueHeldByBatch
            );
            RollupLargeParentBatch.largeParentRowsForTest = 30;

            Test.startTest();
            System.enqueueJob(new RollupQueue());
            Test.stopTest();

            List<Rollup_Queue__c> held = entries();
            Assert.areEqual(1, held.size(), 'Still one entry for the parent');
            Assert.areEqual(2, held[0].Attempts__c, 'A batch that never ended costs an attempt');
            Assert.isTrue(held[0].Next_Attempt__c > Datetime.now().addMinutes(30), 'Held again');
            Assert.areEqual(
                40,
                totalsOf(large.Id).NumberOfEmployees,
                'Not recalculated in the run'
            );
        }
    }

    // --------------------------------------------------------------- a run that stopped

    private class StandInException extends Exception {
    }

    /** What the platform hands a finalizer when its job died. */
    private class StoppedContext implements System.FinalizerContext {
        private final Exception thrown;

        StoppedContext(Exception thrown) {
            this.thrown = thrown;
        }

        public Id getAsyncApexJobId() {
            return null;
        }

        public Exception getException() {
            return this.thrown;
        }

        public String getRequestId() {
            return null;
        }

        public System.ParentJobResult getResult() {
            return System.ParentJobResult.UNHANDLED_EXCEPTION;
        }
    }

    @IsTest
    static void aLoneRecordOverTheRowLimitGoesToTheBatch() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Account parent = parentWith(1, 0);
            Rollup_Queue__c entry = entryFor(parent.Id, 0);
            RollupQueue.Drain drain = new RollupQueue.Drain();
            drain.held.add(entry);
            drain.takenIds.add(parent.Id);

            Test.startTest();
            drain.execute(new StoppedContext(new StandInException(ROW_LIMIT)));
            Test.stopTest();

            List<Rollup_Queue__c> held = entries();
            Assert.areEqual(1, held.size(), 'The record moved to one new entry');
            Assert.areNotEqual(entry.Id, held[0].Id, 'The old one is gone');
            Assert.areEqual(1, held[0].Attempts__c, 'Charged one attempt');
            Assert.isTrue(held[0].Next_Attempt__c > Datetime.now().addMinutes(30), 'Held');
            Assert.isTrue(RollupLargeParentBatch.startedForTest, 'By the batch');
            Assert.areEqual(1, RollupQueue.readyEventsPublished, 'The queue carries on');
            Assert.isTrue(
                [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Error'] > 0,
                'The stop is logged'
            );
        }
    }

    @IsTest
    static void aStoppedRunChargesOnlyTheRecordsItWasRecalculating() {
        System.runAs(TestUsers.admin()) {
            List<Id> ids = fakeAccountIds(4);
            Rollup_Queue__c entry = new Rollup_Queue__c(
                Target_Object__c = 'Account',
                Record_Ids__c = String.join(ids, ','),
                Record_Count__c = 4,
                Attempts__c = 0,
                Status__c = RollupQueue.STATUS_PENDING
            );
            insert entry;

            Test.startTest();
            RollupQueue.stopped(
                new List<Rollup_Queue__c>{ reread(entry.Id) },
                new Set<Id>{ ids[0], ids[1] },
                'Apex CPU time limit exceeded'
            );
            Test.stopTest();

            Rollup_Queue__c rest = reread(entry.Id);
            Assert.areEqual(ids[2] + ',' + ids[3], rest.Record_Ids__c, 'The rest as it was');
            Assert.areEqual(0, rest.Attempts__c, 'Not charged');
            Rollup_Queue__c charged = [
                SELECT Record_Ids__c, Attempts__c, Last_Error__c
                FROM Rollup_Queue__c
                WHERE Id != :entry.Id
            ];
            Assert.areEqual(ids[0] + ',' + ids[1], charged.Record_Ids__c, 'Only those two');
            Assert.areEqual(1, charged.Attempts__c, 'One attempt');
            Assert.isTrue(charged.Last_Error__c.contains('Apex CPU time'), 'Saying why');
            Assert.isFalse(RollupLargeParentBatch.startedForTest, 'Not a row limit: no batch');
        }
    }

    /**
     * One record in two hundred, each queued in its own entry, stops every run that holds it, for
     * a reason no batch fixes: retried entries merge again, so the runs narrow down 200, 50, 12,
     * 3, 1 to it in a few dozen runs rather than one run per record, and it alone ends Failed.
     */
    @IsTest
    static void onlyTheRecordThatStopsEveryRunEndsFailed() {
        System.runAs(TestUsers.admin()) {
            List<Id> ids = fakeAccountIds(200);
            Id bad = ids[137];
            List<Rollup_Queue__c> queued = new List<Rollup_Queue__c>();
            for (Id recordId : ids) {
                queued.add(
                    new Rollup_Queue__c(
                        Target_Object__c = 'Account',
                        Record_Ids__c = String.valueOf(recordId),
                        Record_Count__c = 1,
                        Attempts__c = 0,
                        Status__c = RollupQueue.STATUS_PENDING
                    )
                );
            }
            insert queued;

            Test.startTest();
            Integer runs = 0;
            while (runs < 40) {
                // Every retry made due now, then a run takes what the processor would.
                List<Rollup_Queue__c> waiting = [
                    SELECT Id
                    FROM Rollup_Queue__c
                    WHERE Status__c = :RollupQueue.STATUS_PENDING AND Next_Attempt__c != NULL
                ];
                for (Rollup_Queue__c entry : waiting) {
                    entry.Next_Attempt__c = Datetime.now().addMinutes(-1);
                }
                update waiting;
                List<Rollup_Queue__c> due = RollupQueue.selectDue(500);
                if (due.isEmpty()) {
                    break;
                }
                runs++;
                RollupQueue.Slice slice = RollupQueue.take(due, 200);
                Set<Id> taken = slice.idsByTarget.get('Account');
                if (taken.contains(bad)) {
                    RollupQueue.stopped(slice.entries, taken, 'Apex CPU time limit exceeded');
                } else {
                    update slice.remainders;
                    delete slice.finished;
                }
            }
            Test.stopTest();

            List<Rollup_Queue__c> left = entries();
            Assert.areEqual(1, left.size(), 'Everything else was recalculated');
            Assert.areEqual(String.valueOf(bad), left[0].Record_Ids__c, 'The bad record alone');
            Assert.areEqual(RollupQueue.STATUS_FAILED, left[0].Status__c, 'Failed after five');
            Assert.isTrue(runs < 40, 'Narrowed in a few dozen runs, not one per record');
        }
    }

    @IsTest
    static void aRetriedEntryRunsWithoutFreshOnesAndAQuarterAsLargeEachAttempt() {
        // runs-as: deploying user (pure function over in-memory entries, no data access)
        Assert.areEqual(50, RollupQueue.retrySlice(1, 200), 'First retry');
        Assert.areEqual(12, RollupQueue.retrySlice(2, 200), 'Second');
        Assert.areEqual(3, RollupQueue.retrySlice(3, 200), 'Third');
        Assert.areEqual(1, RollupQueue.retrySlice(4, 200), 'Fourth: one record');
        List<Id> ids = fakeAccountIds(3);
        RollupQueue.Slice slice = RollupQueue.take(
            new List<Rollup_Queue__c>{
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = ids[0] + ',' + ids[1],
                    Attempts__c = 4
                ),
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = String.valueOf(ids[2]),
                    Attempts__c = 0
                )
            },
            200
        );
        Assert.areEqual(1, slice.idsByTarget.get('Account').size(), 'One record, alone');
        Assert.areEqual(1, slice.remainders.size(), 'The other waits in its entry');
    }

    @IsTest
    static void retriedEntriesMergeOnlyWithTheSameAttemptsAndEntity() {
        // runs-as: deploying user (pure function over in-memory entries, no data access)
        List<Id> ids = fakeAccountIds(60);
        List<Rollup_Queue__c> due = new List<Rollup_Queue__c>();
        for (Integer i = 0; i < 60; i++) {
            due.add(
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = String.valueOf(ids[i]),
                    Attempts__c = i == 1 ? 2 : i == 2 ? 0 : 1
                )
            );
        }
        due.add(
            new Rollup_Queue__c(
                Target_Object__c = 'Contact',
                Record_Ids__c = '003000000000001',
                Attempts__c = 1
            )
        );
        RollupQueue.Slice slice = RollupQueue.take(due, 200);
        Assert.areEqual(50, slice.idsByTarget.get('Account').size(), 'Fifty, merged');
        Assert.isFalse(slice.idsByTarget.get('Account').contains(ids[1]), 'Not another attempt');
        Assert.isFalse(slice.idsByTarget.get('Account').contains(ids[2]), 'Not a fresh one');
        Assert.isFalse(slice.idsByTarget.containsKey('Contact'), 'One entity per retry run');
        Assert.areEqual(1, slice.attemptsByTarget.get('Account'), 'Charged from one');
        Assert.areEqual(50, slice.finished.size(), 'Each entry taken whole');
    }

    /** A refused save is already one record each, so its retries run at the full slice. */
    @IsTest
    static void refusedSaveRetriesRunAtTheFullSlice() {
        System.runAs(TestUsers.admin()) {
            List<Id> ids = fakeAccountIds(300);
            Map<Id, String> refused = new Map<Id, String>();
            for (Id recordId : ids) {
                refused.put(recordId, 'A validation rule refused it.');
            }
            RollupQueue.retryLater('Account', refused, 2);
            insert new Rollup_Queue__c(
                Target_Object__c = 'Account',
                Record_Ids__c = '001000000009999',
                Record_Count__c = 1,
                Attempts__c = 3,
                Last_Error__c = 'The rollup run stopped: Apex CPU time limit exceeded',
                Status__c = RollupQueue.STATUS_PENDING
            );
            List<Rollup_Queue__c> waiting = [SELECT Id FROM Rollup_Queue__c];
            for (Rollup_Queue__c entry : waiting) {
                entry.Next_Attempt__c = Datetime.now().addMinutes(-1);
            }
            update waiting;

            Test.startTest();
            List<Rollup_Queue__c> due = RollupQueue.selectDue(500);
            RollupQueue.Slice slice = RollupQueue.take(due, 200);
            Test.stopTest();

            Assert.isFalse(RollupQueue.narrows(due[0]), 'A refused save is not narrowed');
            Assert.isTrue(RollupQueue.narrows(due[due.size() - 1]), 'A stopped run is');
            Assert.areEqual(200, slice.idsByTarget.get('Account').size(), 'The full slice');
            Assert.isFalse(
                slice.idsByTarget.get('Account').contains(Id.valueOf('001000000009999')),
                'Not merged with a narrowed entry'
            );
            Assert.areEqual(3, slice.attemptsByTarget.get('Account'), 'Charged from three');
        }
    }

    @IsTest
    static void entriesGroupByEntityWithTheirDefinitions() {
        System.runAs(TestUsers.admin()) {
            insertDefinitions();
            Rollup_Definition__c count = [
                SELECT Id
                FROM Rollup_Definition__c
                WHERE Definition_Key__c = 'Test_Large_Count'
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
            Assert.isFalse(RollupLargeParentBatch.begin(null, true), 'Nothing to start');
        }
    }
}
