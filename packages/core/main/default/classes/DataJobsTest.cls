/**
 * What the bulk update and bulk delete controllers share (DataJobs): the chunk size setting,
 * a job's state from one read of its AsyncApexJob, and its refusals.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest
private class DataJobsTest {
    @IsTest
    static void theChunkSizeIsTwoHundredUntilSetAndHeldBetweenTenAndTwoHundred() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
            settings.Bulk_Chunk_Size__c = null;
            TestDataFactory.saveSettings(settings);
            Assert.areEqual(200, DataJobs.chunkSize(), 'Empty reads as 200');

            Map<Decimal, Integer> expected = new Map<Decimal, Integer>{
                50 => 50,
                5 => DataJobs.MIN_CHUNK,
                500 => DataJobs.MAX_CHUNK
            };
            for (Decimal configured : expected.keySet()) {
                settings.Bulk_Chunk_Size__c = configured;
                TestDataFactory.saveSettings(settings);
                Assert.areEqual(
                    expected.get(configured),
                    DataJobs.chunkSize(),
                    'Set ' + configured
                );
            }
        }
    }

    /** Status, undo refusal and progress come from at most one read of the platform's job. */
    @IsTest
    static void aJobsStateIsReadWithOneQuery() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c job = new Import_Batch__c(
                Operation__c = BulkUpdateService.OPERATION_UPDATE,
                Status__c = ImportBatchService.STATUS_COMMITTING,
                Is_Dry_Run__c = false,
                Job_Id__c = AsyncApexJob.SObjectType.getDescribe().getKeyPrefix() +
                    '000000000001AAA',
                Undo_Deadline__c = Datetime.now().addDays(1)
            );
            insert job;

            Integer before = Limits.getQueries();
            DataJobs.State state = DataJobs.stateOf(job, true);
            Assert.areEqual(1, Limits.getQueries() - before, 'One read of the job');
            Assert.areEqual(
                ImportBatchService.STATUS_FAILED,
                state.status,
                'No job behind it: it was aborted'
            );
            Assert.isFalse(state.running);
            Assert.isTrue(String.isBlank(state.refusal), 'An aborted job can be undone');
            Assert.isNull(state.chunksDone, 'No progress for a job that is not running');
        }
    }

    @IsTest
    static void aJobWithNoRefusalsListsNone() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c job = new Import_Batch__c(
                Operation__c = BulkUpdateService.OPERATION_UPDATE,
                Status__c = ImportBatchService.STATUS_COMPLETE
            );
            insert job;
            Assert.isTrue(DataJobs.failures(job.Id).isEmpty());
        }
    }
}
