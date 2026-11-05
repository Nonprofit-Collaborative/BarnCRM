/**
 * The error digest panel (C-23): switching the digest on and off as a step of the nightly run
 * (ADR-0166 nightly-job-dispatcher), sending now, and that only an administrator can do either.
 */
@IsTest(testFor='ApexClass:ErrorDigestController, ApexClass:ErrorDigestScheduler')
private class ErrorDigestControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** The nightly run's schedule, which sends the digest. */
    private static List<CronTrigger> runJobs() {
        return [
            SELECT Id, CronExpression, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name = :NightlyJobs.jobName()
        ];
    }

    @IsTest
    static void mariaSchedulesSendsNowAndStops() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
            TestDataFactory.defaultSettings();
            User maria = TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });

            System.runAs(maria) {
                Test.startTest();
                ErrorDigestController.DigestView scheduled = ErrorDigestController.setSchedule(
                    true
                );
                Assert.isTrue(scheduled.scheduled, 'Scheduling switches the digest on.');
                Assert.isNotNull(scheduled.nextRunAt, 'And says when it runs next.');
                Assert.areEqual(7, scheduled.nextRunAt.hour(), 'Every morning at 7:00.');
                Assert.isTrue(scheduled.canManage, 'Maria may change it.');
                Assert.isTrue(
                    scheduled.toAdministrators,
                    'Nobody is listed, so it goes to admins.'
                );

                ErrorDigestController.setSchedule(true);
                Assert.areEqual(1, runJobs().size(), 'Pressing Schedule twice keeps one run.');

                ErrorDigestController.DigestView afterSend = ErrorDigestController.sendNow();
                Assert.isNotNull(afterSend.lastRun, 'Send now runs the digest.');
                Assert.isNotNull(afterSend.lastRunSummary, 'And the panel says what it did.');

                ErrorDigestController.DigestView stopped = ErrorDigestController.setSchedule(false);
                Assert.isFalse(stopped.scheduled, 'Stop switches it off.');
                Test.stopTest();
            }
            NightlyJobs.forget();
            Assert.isFalse(
                NightlyJobs.isSwitchedOn(ErrorDigestScheduler.JOB_NAME, true),
                'The step stays off in tonight\'s run.'
            );
        }
    }

    @IsTest
    static void theNightlyStepRunsTheDigest() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User maria = TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });

            System.runAs(maria) {
                Test.startTest();
                ErrorDigestScheduler.step().run();
                Test.stopTest();
            }

            BarnCRM_Settings__c after = BarnCRM_Settings__c.getOrgDefaults();
            Assert.isNotNull(after.Error_Digest_Last_Run__c, 'The step ran the digest.');
            Assert.isTrue(
                after.Error_Digest_Last_Run_Summary__c.startsWith(
                    Label.Core_ErrorDigest_SummaryNothingNew.substringBefore('{0}')
                ),
                'With nothing new, it sent nothing and said so.'
            );
        }
    }

    @IsTest
    static void davidCanReadThePanelButNotScheduleOrSend() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
            TestDataFactory.defaultSettings();
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });

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
                            BarnHelp.text('Core', 'Core_ErrorDigest_PermissionRequired'),
                            expected.getMessage(),
                            'The message names the permission David needs.'
                        );
                    }
                }
                Test.stopTest();
            }

            Assert.isTrue(runJobs().isEmpty(), 'Nothing was scheduled.');
            Assert.isNull(
                BarnCRM_Settings__c.getOrgDefaults().Error_Digest_Last_Run__c,
                'And nothing was sent.'
            );
        }
    }
}
