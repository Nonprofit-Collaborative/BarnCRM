/**
 * The Rollup Builder's Needs attention list and its Retry (R-RQ4, slice S13). Entries are made
 * directly, as the engine would leave them, and read as Maria (BarnCRM Admin). No test calls
 * Test.stopTest after a retry, so the processor a retry requests never runs and the entries stay
 * where the retry put them.
 */
@IsTest(testFor='ApexClass:RollupAttentionController')
private class RollupAttentionControllerTest {
    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static Rollup_Queue__c entry(String status, List<Id> ids, Integer attempts) {
        List<String> parts = new List<String>();
        for (Id recordId : ids) {
            parts.add(String.valueOf(recordId));
        }
        return new Rollup_Queue__c(
            Target_Object__c = 'Account',
            Record_Ids__c = String.join(parts, ','),
            Record_Count__c = ids.size(),
            Status__c = status,
            Attempts__c = attempts,
            Last_Error__c = status == RollupQueue.STATUS_FAILED
                ? 'A validation rule refused it.'
                : null
        );
    }

    @IsTest
    static void mariaSeesWhatIsWaitingAndEachRecordThatFailedByName() {
        System.runAs(TestUsers.admin()) {
            User admin = maria();
            List<Account> households = new List<Account>{
                new Account(Name = 'Rivera Household'),
                new Account(Name = 'Chen Household')
            };
            System.runAs(admin) {
                insert households;
            }
            RollupScheduler.jobNameInUse = 'BarnCRM Rollups test ' + Crypto.getRandomInteger();
            insert new List<Rollup_Queue__c>{
                entry(RollupQueue.STATUS_PENDING, new List<Id>{ households[0].Id }, 0),
                entry(
                    RollupQueue.STATUS_FAILED,
                    new List<Id>{ households[0].Id, households[1].Id },
                    RollupQueue.MAX_ATTEMPTS
                )
            };

            RollupAttentionController.Attention attention;
            System.runAs(admin) {
                attention = RollupAttentionController.getAttention();
            }

            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_Waiting,
                    new List<String>{ (1).format(), (0).format() }
                ),
                attention.waiting
            );
            System.Assert.areEqual(2, attention.failed.size(), 'One row per record, not per entry');
            Set<String> names = new Set<String>();
            for (RollupAttentionController.FailedRecord row : attention.failed) {
                names.add(row.name);
                System.Assert.areEqual('A validation rule refused it.', row.error);
                System.Assert.areEqual(RollupQueue.MAX_ATTEMPTS, row.attempts);
            }
            System.Assert.areEqual(new Set<String>{ 'Rivera Household', 'Chen Household' }, names);
            System.Assert.isFalse(attention.nightlyScheduled, 'The nightly run is off');
            System.Assert.areEqual(Label.Core_RollupBuilder_LastRunNever, attention.lastRun);
        }
    }

    @IsTest
    static void nothingWaitingSaysSo() {
        System.runAs(TestUsers.admin()) {
            RollupAttentionController.Attention attention;
            System.runAs(maria()) {
                attention = RollupAttentionController.getAttention();
            }
            System.Assert.areEqual(Label.Core_RollupBuilder_NothingWaiting, attention.waiting);
            System.Assert.isTrue(attention.failed.isEmpty());
        }
    }

    @IsTest
    static void retryPutsBackOnlyTheSelectedEntries() {
        System.runAs(TestUsers.admin()) {
            Account household = new Account(Name = 'Okafor Household');
            insert household;
            List<Rollup_Queue__c> failed = new List<Rollup_Queue__c>{
                entry(RollupQueue.STATUS_FAILED, new List<Id>{ household.Id }, 5),
                entry(RollupQueue.STATUS_FAILED, new List<Id>{ household.Id }, 5)
            };
            failed[0].Next_Attempt__c = Datetime.now().addMinutes(16);
            insert failed;

            System.runAs(maria()) {
                RollupAttentionController.retry(new List<Id>{ failed[0].Id });
            }

            Map<Id, Rollup_Queue__c> after = new Map<Id, Rollup_Queue__c>(
                [SELECT Status__c, Attempts__c, Next_Attempt__c FROM Rollup_Queue__c]
            );
            System.Assert.areEqual(RollupQueue.STATUS_PENDING, after.get(failed[0].Id).Status__c);
            System.Assert.areEqual(0, after.get(failed[0].Id).Attempts__c, 'Tries start again');
            System.Assert.isNull(after.get(failed[0].Id).Next_Attempt__c, 'Tried within minutes');
            System.Assert.areEqual(RollupQueue.STATUS_FAILED, after.get(failed[1].Id).Status__c);
        }
    }

    @IsTest
    static void retryAllPutsBackTwoHundredEntriesWithinLimits() {
        System.runAs(TestUsers.admin()) {
            Account household = new Account(Name = 'Bulk Household');
            insert household;
            List<Rollup_Queue__c> failed = new List<Rollup_Queue__c>();
            for (Integer i = 0; i < 200; i++) {
                failed.add(entry(RollupQueue.STATUS_FAILED, new List<Id>{ household.Id }, 5));
            }
            insert failed;

            RollupAttentionController.Attention attention;
            Integer queries;
            System.runAs(maria()) {
                attention = RollupAttentionController.retry(null);
                queries = Limits.getQueries();
            }

            System.Assert.areEqual(
                0,
                [SELECT COUNT() FROM Rollup_Queue__c WHERE Status__c = :RollupQueue.STATUS_FAILED]
            );
            System.Assert.isTrue(attention.failed.isEmpty(), 'The list is read again');
            System.Assert.isTrue(queries < 20, 'A fixed number of queries, not one per entry');
        }
    }

    @IsTest
    static void staffCannotRetry() {
        System.runAs(TestUsers.admin()) {
            Account household = new Account(Name = 'Staff Household');
            insert household;
            insert entry(RollupQueue.STATUS_FAILED, new List<Id>{ household.Id }, 5);
            String message;
            System.runAs(TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' })) {
                try {
                    RollupAttentionController.retry(null);
                } catch (AuraHandledException refused) {
                    message = refused.getMessage();
                }
            }
            System.Assert.areEqual(Label.Core_Rollups_ErrorNoPermission, message);
            System.Assert.areEqual(
                1,
                [SELECT COUNT() FROM Rollup_Queue__c WHERE Status__c = :RollupQueue.STATUS_FAILED]
            );
        }
    }

    @IsTest
    static void theLastFullRunIsDescribed() {
        System.runAs(TestUsers.admin()) {
            RollupFullRecalcBatch.Progress going = new RollupFullRecalcBatch.Progress();
            going.jobId = UserInfo.getUserId();
            going.running = true;
            going.chunksDone = 3;
            going.chunksTotal = 10;
            RollupFullRecalcBatch.Progress done = new RollupFullRecalcBatch.Progress();
            done.jobId = UserInfo.getUserId();
            done.status = 'Completed';
            done.finishedAt = Datetime.newInstance(2026, 10, 12, 2, 30, 0);
            done.chunksStopped = 1;

            System.Assert.areEqual(
                String.format(Label.Core_RollupBuilder_LastRunGoing, new List<String>{ '3', '10' }),
                RollupAttentionController.lastRun(going)
            );
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_LastRun,
                    new List<String>{ 'Completed', done.finishedAt.format(), '1' }
                ),
                RollupAttentionController.lastRun(done)
            );
        }
    }
}
