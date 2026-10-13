/**
 * The Rollup Queue and its processor (canonical model Section 14A, rollup proposal slice S6).
 * Core holds no giving objects, so the totals here roll organizations up to their parent account
 * (`ParentId`), which runs the same engine the giving totals do.
 */
@IsTest(testFor='ApexClass:RollupQueue')
private class RollupQueueTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Id organizationType() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    /** Counts each organization's child organizations into its Number of Employees. */
    private static void insertChildCount() {
        insert new Rollup_Definition__c(
            Name = 'Child organizations',
            Definition_Key__c = 'Test_Child_Count',
            Source_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    /** Parents, each with one child organization. Returns the parents' ids. */
    private static Set<Id> parentsWithOneChild(Integer count) {
        List<Account> parents = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            parents.add(new Account(Name = 'Parent ' + i, RecordTypeId = organizationType()));
        }
        insert parents;
        List<Account> children = new List<Account>();
        for (Account parent : parents) {
            children.add(
                new Account(
                    Name = parent.Name + ' child',
                    RecordTypeId = organizationType(),
                    ParentId = parent.Id
                )
            );
        }
        insert children;
        return new Map<Id, Account>(parents).keySet();
    }

    /** Ids of the Account key prefix that name no record, for entries that are only text. */
    private static Set<Id> fakeAccountIds(Integer count) {
        Set<Id> ids = new Set<Id>();
        for (Integer i = 1; i <= count; i++) {
            ids.add(Id.valueOf('001' + String.valueOf(i).leftPad(12, '0')));
        }
        return ids;
    }

    private static List<Rollup_Queue__c> entries() {
        return [
            SELECT
                Target_Object__c,
                Record_Ids__c,
                Record_Count__c,
                Status__c,
                Attempts__c,
                Next_Attempt__c,
                Last_Error__c
            FROM Rollup_Queue__c
            ORDER BY Record_Count__c DESC
        ];
    }

    @IsTest
    static void aBulkChangeIsQueuedInEntriesOfTwoHundredWithOneProcessor() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => fakeAccountIds(450) });
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => fakeAccountIds(10) });
            Integer processors = [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'RollupQueue'
            ];
            List<Rollup_Queue__c> queued = entries();

            Assert.areEqual(4, queued.size(), '450 records make three entries, and 10 a fourth');
            Assert.areEqual(200, queued[0].Record_Count__c, 'At most 200 records per entry');
            Assert.areEqual(200, queued[0].Record_Ids__c.split(',').size(), 'Counted as held');
            Decimal waiting = 0;
            for (Rollup_Queue__c entry : queued) {
                waiting += entry.Record_Count__c;
                Assert.areEqual(RollupQueue.STATUS_PENDING, entry.Status__c, 'Waiting');
                Assert.areEqual(0, entry.Attempts__c, 'Not tried yet');
                Assert.isNull(entry.Next_Attempt__c, 'Due now');
                Assert.areEqual('Account', entry.Target_Object__c, 'Named, not referenced');
            }
            Assert.areEqual(460, waiting, 'Records waiting is a sum');
            Assert.areEqual(1, processors, 'One processor per transaction, however many entries');
            Test.stopTest();

            // One run recalculates one slice of 200 (R-RQ3). The 10 are among the first 200, so
            // their entry merges into the first slice; the two entries that do not fit wait for
            // the next run, which a test cannot run.
            List<Rollup_Queue__c> left = entries();
            Assert.areEqual(
                2,
                left.size(),
                'Records with no totals to write are finished and their entries deleted'
            );
            Decimal stillWaiting = 0;
            for (Rollup_Queue__c entry : left) {
                stillWaiting += entry.Record_Count__c;
                Assert.areEqual(RollupQueue.STATUS_PENDING, entry.Status__c, 'Still pending');
            }
            Assert.areEqual(250, stillWaiting, 'The records past the first slice wait');
            Assert.areEqual(0, RollupQueue.lastChainDelay, 'The next run is asked for now');
        }
    }

    @IsTest
    static void theProcessorRecalculatesASliceAndLeavesTheRestPending() {
        System.runAs(TestUsers.admin()) {
            insertChildCount();
            Set<Id> parents = parentsWithOneChild(250);

            Test.startTest();
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => parents });
            Test.stopTest();

            Integer counted = [
                SELECT COUNT()
                FROM Account
                WHERE Id IN :parents AND NumberOfEmployees = 1
            ];
            Assert.areEqual(200, counted, 'One run recalculates one slice of 200');
            List<Rollup_Queue__c> left = entries();
            Assert.areEqual(1, left.size(), 'The entry that did not fit waits for the next run');
            Assert.areEqual(50, left[0].Record_Count__c, 'Holding the other 50');
            Assert.areEqual(RollupQueue.STATUS_PENDING, left[0].Status__c, 'Still pending');
        }
    }

    @IsTest
    static void entriesForTheSameRecordsAreMergedWithinTheSlice() {
        System.runAs(TestUsers.admin()) {
            List<Id> ids = new List<Id>(fakeAccountIds(6));
            List<Rollup_Queue__c> due = new List<Rollup_Queue__c>{
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = ids[0] + ',' + ids[1] + ',' + ids[2],
                    Attempts__c = 0
                ),
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = ids[1] + ',' + ids[2] + ',' + ids[3],
                    Attempts__c = 2
                ),
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = ids[4] + ',' + ids[5],
                    Attempts__c = 0
                )
            };

            RollupQueue.Slice slice = RollupQueue.take(due, 4);

            Assert.areEqual(
                4,
                slice.idsByTarget.get('Account').size(),
                'Two entries, four records'
            );
            Assert.areEqual(2, slice.finished.size(), 'Both merged entries are finished');
            Assert.areEqual(2, slice.attemptsByTarget.get('Account'), 'Carrying the most attempts');
            Assert.isTrue(slice.remainders.isEmpty(), 'Nothing split');

            RollupQueue.Slice halved = RollupQueue.take(due, 2);
            Assert.areEqual(2, halved.idsByTarget.get('Account').size(), 'Only the slice is taken');
            Assert.areEqual(1, halved.remainders.size(), 'The first entry is split');
            Assert.areEqual(1, halved.remainders[0].Record_Count__c, 'One record left over');
            Assert.areEqual(String.valueOf(ids[2]), halved.remainders[0].Record_Ids__c, 'The last');
        }
    }

    @IsTest
    static void aRecordThatCannotBeSavedIsTriedLaterThenFails() {
        System.runAs(TestUsers.admin()) {
            Id locked = new List<Id>(fakeAccountIds(1))[0];

            Test.startTest();
            RollupQueue.retryLater('Account', new Map<Id, String>{ locked => 'Record locked.' }, 0);
            RollupQueue.retryLater('Account', new Map<Id, String>{ locked => 'Record locked.' }, 4);
            Test.stopTest();

            Rollup_Queue__c again;
            Rollup_Queue__c failed;
            for (Rollup_Queue__c entry : entries()) {
                if (entry.Attempts__c == 1) {
                    again = entry;
                } else {
                    failed = entry;
                }
            }
            Assert.isNotNull(again, 'The first failure is queued again');
            Assert.areEqual(RollupQueue.STATUS_PENDING, again.Status__c, 'To be tried again');
            Assert.isTrue(again.Next_Attempt__c > Datetime.now(), 'Later, not straight away');
            Assert.isTrue(again.Last_Error__c.contains('Record locked.'), 'Saying why');
            Assert.areEqual(5, failed.Attempts__c, 'The fifth attempt');
            Assert.areEqual(RollupQueue.STATUS_FAILED, failed.Status__c, 'Waits for Retry');
        }
    }

    @IsTest
    static void aRunThatStopsChargesItsEntriesAnAttempt() {
        System.runAs(TestUsers.admin()) {
            List<Rollup_Queue__c> held = new List<Rollup_Queue__c>{
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = String.join(new List<Id>(fakeAccountIds(2)), ','),
                    Record_Count__c = 2,
                    Attempts__c = 0
                ),
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = String.join(new List<Id>(fakeAccountIds(1)), ','),
                    Record_Count__c = 1,
                    Attempts__c = 4
                )
            };
            insert held;

            Test.startTest();
            RollupQueue.charge(held, 'Apex CPU time limit exceeded');
            Test.stopTest();

            List<Rollup_Queue__c> charged = entries();
            Assert.areEqual(1, charged[0].Attempts__c, 'One attempt charged');
            Assert.areEqual(RollupQueue.STATUS_PENDING, charged[0].Status__c, 'Tried again later');
            Assert.isTrue(charged[0].Next_Attempt__c > Datetime.now(), 'After a pause');
            Assert.isTrue(
                charged[0].Last_Error__c.contains('Apex CPU time limit exceeded'),
                'With the reason'
            );
            Assert.areEqual(
                RollupQueue.STATUS_FAILED,
                charged[1].Status__c,
                'Fifth attempt: Failed'
            );
        }
    }

    @IsTest
    static void theDelayDoublesWithEachAttempt() {
        System.runAs(TestUsers.admin()) {
            Datetime now = Datetime.now();
            Assert.isTrue(RollupQueue.nextAttempt(1) >= now.addMinutes(2), 'Two minutes first');
            Assert.isTrue(RollupQueue.nextAttempt(2) >= now.addMinutes(4), 'Then four');
            Assert.isTrue(RollupQueue.nextAttempt(4) >= now.addMinutes(16), 'Then sixteen');
            Assert.isTrue(
                RollupQueue.nextAttempt(9) < now.addMinutes(17),
                'Never longer than the last'
            );
        }
    }

    @IsTest
    static void anEntryIdThatIsNotAnIdIsDropped() {
        System.runAs(TestUsers.admin()) {
            List<Id> ids = RollupQueue.idsOf(
                new Rollup_Queue__c(Record_Ids__c = '001000000000001, nonsense')
            );
            Assert.areEqual(1, ids.size(), 'Only the identifier is kept');
        }
    }

    private static Integer processorsQueued() {
        return [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'RollupQueue'];
    }

    @IsTest
    static void insideAQueueableTheEngineLeavesTheChainedJobFree() {
        System.runAs(TestUsers.admin()) {
            insertChildCount();
            Set<Id> parents = parentsWithOneChild(200);
            Test.startTest();
            RollupQueue.queueableForTest = true;
            // A bulk change saved inside a Queueable queues its 200 parents (R-R4).
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => parents });

            Assert.areEqual(
                0,
                Limits.getQueueableJobs(),
                'The one job a Queueable may queue is left for its own next step'
            );
            Assert.areEqual(0, processorsQueued(), 'No processor is started from a Queueable');
            Decimal waiting = 0;
            for (Rollup_Queue__c entry : entries()) {
                waiting += entry.Record_Count__c;
                Assert.areEqual(RollupQueue.STATUS_PENDING, entry.Status__c, 'Waiting');
            }
            Assert.areEqual(200, waiting, 'Every parent waits in the queue');

            // The chain ends and starts the processor itself.
            RollupService.startQueuedRecalculation();
            Assert.areEqual(1, processorsQueued(), 'The end of the chain starts one processor');
            RollupService.startQueuedRecalculation();
            Assert.areEqual(1, processorsQueued(), 'Asking again starts no second one');
            Test.stopTest();

            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Account WHERE Id IN :parents AND NumberOfEmployees = 1],
                'The processor the chain started calculated every total'
            );
            Assert.areEqual(0, entries().size(), 'Every entry is finished');
        }
    }

    @IsTest
    static void startingTheProcessorWithNothingPendingStartsNothing() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            RollupService.startQueuedRecalculation();
            Assert.areEqual(0, processorsQueued(), 'No entries, no processor');
            Test.stopTest();
        }
    }

    @IsTest
    static void outsideAQueueableABulkChangeStillStartsTheProcessor() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            RollupQueue.queueableForTest = false;
            RollupQueue.add(new Map<String, Set<Id>>{ 'Account' => fakeAccountIds(10) });
            Assert.areEqual(1, processorsQueued(), 'A save outside a Queueable starts one');
            Test.stopTest();
        }
    }
}
