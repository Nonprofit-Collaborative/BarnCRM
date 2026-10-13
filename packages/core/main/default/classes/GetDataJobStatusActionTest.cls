/**
 * The Get Data Job Status action (Q-14): a job reported by its id, the most recent import
 * when no id is given, anything else answered as not found, and a user who cannot read data
 * jobs refused in plain words.
 */
@IsTest
private class GetDataJobStatusActionTest {
    @IsTest
    static void aJobIsReportedByItsId() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c job = completedImport();

            Test.startTest();
            List<GetDataJobStatusAction.Result> results = GetDataJobStatusAction.getStatus(
                new List<GetDataJobStatusAction.Request>{ request(job.Id) }
            );
            Test.stopTest();

            GetDataJobStatusAction.Result result = results[0];
            Assert.isNull(result.errorMessage, 'The job was found');
            Assert.areEqual(job.Id, result.jobId);
            Assert.areEqual('Import', result.operation, 'A job with no operation is an import');
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, result.status);
            Assert.isFalse(result.isDryRun);
            Assert.areEqual('donors.csv', result.fileName);
            Assert.areEqual(10, result.rowCount);
            Assert.areEqual(7, result.rowsCreated);
            Assert.areEqual(2, result.rowsUpdated);
            Assert.areEqual(1, result.rowsRejected);
            Assert.isNotNull(result.undoDeadline, 'The undo deadline is given');
        }
    }

    @IsTest
    static void noIdReportsTheMostRecentImport() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c job = completedImport();

            Test.startTest();
            List<GetDataJobStatusAction.Result> results = GetDataJobStatusAction.getStatus(
                new List<GetDataJobStatusAction.Request>{ request(null), null }
            );
            Test.stopTest();

            Assert.areEqual(job.Id, results[0].jobId, 'The latest import is reported');
            Assert.areEqual(job.Id, results[1].jobId, 'An empty request asks the same');
        }
    }

    @IsTest
    static void anythingElseIsNotFound() {
        System.runAs(TestUsers.admin()) {
            Account notAJob = new Account(Name = 'The Union Foundation');
            insert notAJob;

            Test.startTest();
            List<GetDataJobStatusAction.Result> results = GetDataJobStatusAction.getStatus(
                new List<GetDataJobStatusAction.Request>{
                    request(notAJob.Id),
                    request('not an id'),
                    request(null)
                }
            );
            Test.stopTest();

            Assert.areEqual(Label.Core_AgentActions_DataJobNotFound, results[0].errorMessage);
            Assert.areEqual(Label.Core_AgentActions_DataJobNotFound, results[1].errorMessage);
            Assert.areEqual(
                Label.Core_AgentActions_NoDataJobs,
                results[2].errorMessage,
                'With no import yet, the user is told so'
            );
        }
    }

    @IsTest
    static void twoHundredRequestsAreAnsweredInOrderFromOneQuery() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c job = completedImport();
            List<GetDataJobStatusAction.Request> requests = new List<GetDataJobStatusAction.Request>();
            for (Integer i = 0; i < 200; i++) {
                requests.add(request(Math.mod(i, 2) == 0 ? (String) job.Id : 'unknown' + i));
            }

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            List<GetDataJobStatusAction.Result> results = GetDataJobStatusAction.getStatus(
                requests
            );
            Integer queriesUsed = Limits.getQueries() - queriesBefore;
            Test.stopTest();

            Assert.areEqual(200, results.size());
            for (Integer i = 0; i < 200; i++) {
                if (Math.mod(i, 2) == 0) {
                    Assert.areEqual(job.Id, results[i].jobId, 'Request ' + i + ' found');
                } else {
                    Assert.areEqual(
                        Label.Core_AgentActions_DataJobNotFound,
                        results[i].errorMessage,
                        'Request ' + i + ' answered in its own position'
                    );
                }
            }
            Assert.areEqual(1, queriesUsed, 'One query for every request');
        }
    }

    @IsTest
    static void aUserWhoCannotReadDataJobsIsToldSo() {
        Import_Batch__c job;
        System.runAs(TestUsers.admin()) {
            job = completedImport();
        }
        User outsider = HouseholdTestDataFactory.standardUser('jobs');
        List<GetDataJobStatusAction.Result> results;

        Test.startTest();
        System.runAs(outsider) {
            results = GetDataJobStatusAction.getStatus(
                new List<GetDataJobStatusAction.Request>{ request(job.Id) }
            );
        }
        Test.stopTest();

        Assert.areEqual(Label.Core_AgentActions_NoAccess, results[0].errorMessage);
        Assert.isNull(results[0].status, 'Nothing of the job is shown');
    }

    // ------------------------------------------------------------------ helpers

    private static GetDataJobStatusAction.Request request(String jobId) {
        GetDataJobStatusAction.Request result = new GetDataJobStatusAction.Request();
        result.jobId = jobId;
        return result;
    }

    private static Import_Batch__c completedImport() {
        Import_Batch__c job = ImportTestDataFactory.batch(
            ImportTestDataFactory.template(ImportTestDataFactory.donorMapping(), null)
        );
        job.Is_Dry_Run__c = false;
        job.Status__c = ImportBatchService.STATUS_COMPLETE;
        job.Row_Count__c = 10;
        job.Rows_Created__c = 7;
        job.Rows_Updated__c = 2;
        job.Rows_Rejected__c = 1;
        job.Started_At__c = Datetime.now().addMinutes(-5);
        job.Completed_At__c = Datetime.now();
        job.Undo_Deadline__c = Datetime.now().addDays(30);
        update job;
        return job;
    }
}
