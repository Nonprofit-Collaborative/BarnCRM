/**
 * The error digest panel (C-23): the scheduling entry point, sending now, and that only an
 * administrator can do either.
 */
@IsTest
private class ErrorDigestControllerTest {
    private static List<CronTrigger> digestJobs() {
        return [
            SELECT Id, CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name = :ErrorDigestScheduler.JOB_NAME
        ];
    }

    @IsTest
    static void mariaSchedulesSendsNowAndStops() {
        TestDataFactory.defaultSettings();
        User maria = TestDataFactory.createUser('Maria', new List<String>{ 'Nonprofit_Admin' });

        System.runAs(maria) {
            Test.startTest();
            ErrorDigestController.DigestView scheduled = ErrorDigestController.setSchedule(true);
            Assert.isTrue(scheduled.scheduled, 'Scheduling switches the digest on.');
            Assert.isNotNull(scheduled.nextRunAt, 'And says when it runs next.');
            Assert.isTrue(scheduled.canManage, 'Maria may change it.');
            Assert.isTrue(scheduled.toAdministrators, 'Nobody is listed, so it goes to admins.');

            ErrorDigestController.setSchedule(true);
            List<CronTrigger> jobs = digestJobs();
            Assert.areEqual(1, jobs.size(), 'Pressing Schedule twice keeps one job.');
            Assert.areEqual('0 0 7 * * ?', jobs[0].CronExpression, 'Every morning at 7:00.');

            ErrorDigestController.DigestView afterSend = ErrorDigestController.sendNow();
            Assert.isNotNull(afterSend.lastRun, 'Send now runs the digest.');
            Assert.isNotNull(afterSend.lastRunSummary, 'And the panel says what it did.');

            ErrorDigestController.DigestView stopped = ErrorDigestController.setSchedule(false);
            Assert.isFalse(stopped.scheduled, 'Stop switches it off.');
            Test.stopTest();
        }
        Assert.isTrue(digestJobs().isEmpty(), 'No job is left behind.');
    }

    @IsTest
    static void theScheduledJobRunsTheDigest() {
        TestDataFactory.defaultSettings();
        User maria = TestDataFactory.createUser('Maria', new List<String>{ 'Nonprofit_Admin' });

        System.runAs(maria) {
            Test.startTest();
            ErrorDigestScheduler.start();
            // The scheduled run happens here.
            Test.stopTest();
        }

        BarnCRM_Settings__c after = BarnCRM_Settings__c.getOrgDefaults();
        Assert.isNotNull(after.Error_Digest_Last_Run__c, 'The job ran the digest.');
        Assert.isTrue(
            after.Error_Digest_Last_Run_Summary__c.startsWith(
                Label.Core_ErrorDigest_SummaryNothingNew.substringBefore('{0}')
            ),
            'With nothing new, it sent nothing and said so.'
        );
    }

    @IsTest
    static void davidCanReadThePanelButNotScheduleOrSend() {
        TestDataFactory.defaultSettings();
        User david = TestDataFactory.createUser('David', new List<String>{ 'Nonprofit_Staff' });

        System.runAs(david) {
            Test.startTest();
            ErrorDigestController.DigestView view = ErrorDigestController.getDigest();
            Assert.isFalse(view.canManage, 'David may read the panel only.');
            Assert.isFalse(view.scheduled, 'And sees it is off.');
            for (String action : new List<String>{ 'schedule', 'send' }) {
                try {
                    if (action == 'schedule') {
                        ErrorDigestController.setSchedule(true);
                    } else {
                        ErrorDigestController.sendNow();
                    }
                    Assert.fail('David should not be able to ' + action + '.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        Label.Core_ErrorDigest_PermissionRequired,
                        expected.getMessage(),
                        'The message names the permission David needs.'
                    );
                }
            }
            Test.stopTest();
        }

        Assert.isTrue(digestJobs().isEmpty(), 'Nothing was scheduled.');
        Assert.isNull(
            BarnCRM_Settings__c.getOrgDefaults().Error_Digest_Last_Run__c,
            'And nothing was sent.'
        );
    }
}
