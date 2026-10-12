/**
 * The pause ends on the record (C-23, R-A5): pausing schedules the resume, the resume clears an
 * expired pause and audits it like any other change, and a resume that fires early or after a
 * manual resume changes nothing.
 *
 * Scheduled Apex runs at `Test.stopTest()` whatever its cron expression says, which is what lets
 * these tests run the job without waiting for it.
 */
@IsTest
private class AutomationResumeJobTest {
    private static User barnCrmAdmin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static List<CronTrigger> resumeJobs() {
        return [
            SELECT Id, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name = :AutomationResumeJob.JOB_NAME
        ];
    }

    private static Datetime storedPause() {
        return BarnCRM_Settings__c.getOrgDefaults().Automation_Paused_Until__c;
    }

    @IsTest
    static void anExpiredPauseIsClearedAndTheResumeIsAudited() {
        Datetime ended = TestDataFactory.pausedSettings(-1).Automation_Paused_Until__c;
        User maria = barnCrmAdmin();

        System.runAs(maria) {
            Test.startTest();
            // A job set for a moment already past cannot be scheduled, so this one is set for
            // later; it carries the end it clears, and scheduled jobs run at stopTest anyway.
            AutomationResumeJob.schedule(ended, System.now().addHours(1));
            Test.stopTest();
        }

        Assert.isNull(storedPause(), 'The stored end is cleared, not just in the past.');
        List<Setting_Change__c> audit = [
            SELECT Setting_Name__c, Old_Value__c, New_Value__c, Changed_By__c
            FROM Setting_Change__c
        ];
        Assert.areEqual(1, audit.size(), 'The resume is one audited change.');
        Assert.areEqual(
            AutomationControl.PAUSE_SETTING_NAME,
            audit[0].Setting_Name__c,
            'Recorded against the pause setting, like the Resume button.'
        );
        Assert.isTrue(String.isNotBlank(audit[0].Old_Value__c), 'From the end the pause had.');
        Assert.isNull(audit[0].New_Value__c, 'To nothing: automation is running.');
        Assert.areEqual(maria.Id, audit[0].Changed_By__c, 'As the person whose pause it was.');
        Assert.isTrue(resumeJobs().isEmpty(), 'The spent job removes itself.');
    }

    @IsTest
    static void pausingSchedulesTheResumeForTheEndAndResumingCancelsIt() {
        TestDataFactory.defaultSettings();
        User maria = barnCrmAdmin();

        System.runAs(maria) {
            Test.startTest();
            Datetime until = AutomationControl.pauseAll(2);

            List<CronTrigger> jobs = resumeJobs();
            Assert.areEqual(1, jobs.size(), 'Pausing schedules exactly one resume.');
            Assert.isTrue(
                jobs[0].NextFireTime >= until.addSeconds(-1) &&
                    jobs[0].NextFireTime <= until.addSeconds(2),
                'For the moment the pause ends.'
            );
            Assert.isFalse(AutomationControl.isPauseWithoutResume(), 'So the pause has an end.');

            AutomationControl.resumeAll();
            Assert.isNull(AutomationResumeJob.scheduledAt(), 'Resuming by hand cancels it.');
            Test.stopTest();
        }

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Setting_Change__c],
            'The pause and the resume, and no third row from a job.'
        );
    }

    @IsTest
    static void pausingAgainReplacesTheScheduledResume() {
        TestDataFactory.defaultSettings();
        User maria = barnCrmAdmin();

        System.runAs(maria) {
            Test.startTest();
            AutomationControl.pauseAll(1);
            Datetime later = AutomationControl.pauseAll(4);

            List<CronTrigger> jobs = resumeJobs();
            Assert.areEqual(1, jobs.size(), 'Still one resume, never two.');
            Assert.isTrue(
                jobs[0].NextFireTime >= later.addSeconds(-1),
                'Set for the new end, not the old one.'
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void aJobForAnEarlierPauseLeavesTheNewerOneAlone() {
        Datetime stored = TestDataFactory.pausedSettings(-1).Automation_Paused_Until__c;
        User maria = barnCrmAdmin();

        System.runAs(maria) {
            Test.startTest();
            AutomationResumeJob.schedule(stored.addMinutes(-30), System.now().addHours(1));
            Test.stopTest();
        }

        Assert.areEqual(stored, storedPause(), 'Not the pause this job was set for: untouched.');
        Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'And no resume is audited.');
    }

    @IsTest
    static void aPauseStillPausesWhenItsResumeCannotBeScheduled() {
        TestDataFactory.defaultSettings();
        User maria = barnCrmAdmin();
        AutomationControl.schedulingFailsForTest = true;

        System.runAs(maria) {
            Test.startTest();
            AutomationControl.pauseAll(2);
            Test.stopTest();
        }

        Assert.isTrue(AutomationControl.isPaused(), 'The pause happens anyway.');
        Assert.isTrue(resumeJobs().isEmpty(), 'With no resume scheduled.');
        Assert.isTrue(AutomationControl.isPauseWithoutResume(), 'Which Health Check reports.');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'Automation pause%'],
            'And the failure is in the Error Log.'
        );
    }

    @IsTest
    static void aResumeThatFiresBeforeTheEndLeavesThePauseAlone() {
        TestDataFactory.defaultSettings();
        User maria = barnCrmAdmin();

        System.runAs(maria) {
            Test.startTest();
            AutomationControl.pauseAll(2);
            // The job runs here, two hours early.
            Test.stopTest();
        }

        Assert.isTrue(AutomationControl.isPaused(), 'The pause still has two hours to run.');
        Assert.areEqual(1, [SELECT COUNT() FROM Setting_Change__c], 'Only the pause is audited.');
        Assert.areEqual(1, resumeJobs().size(), 'The early job set itself again for the end.');
    }

    @IsTest
    static void nothingToResumeWritesNothing() {
        TestDataFactory.defaultSettings();

        Test.startTest();
        Boolean cleared = AutomationControl.resumeExpiredPause();
        Test.stopTest();

        Assert.isFalse(cleared, 'There was no pause.');
        Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'And nothing is audited.');
    }

    @IsTest
    static void theConsoleNamesWhoPaused() {
        TestDataFactory.defaultSettings();
        TestDataFactory.insertAutomationSettings(
            new Map<String, Boolean>{ 'Household_Naming' => true }
        );
        User maria = barnCrmAdmin();

        System.runAs(maria) {
            Test.startTest();
            AutomationControlController.AutomationPageView paused = AutomationControlController.pauseAll(
                2
            );
            Assert.areEqual(
                [SELECT Name FROM User WHERE Id = :maria.Id].Name,
                paused.pausedBy,
                'The page says Maria paused.'
            );

            AutomationControlController.AutomationPageView running = AutomationControlController.resumeAll();
            Assert.isNull(running.pausedBy, 'And names nobody once automation runs again.');
            Test.stopTest();
        }
    }

    @IsTest
    static void onlyAnAdministratorCanPauseOrScheduleAResume() {
        TestDataFactory.defaultSettings();
        User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });

        System.runAs(david) {
            Test.startTest();
            try {
                AutomationControl.pauseAll(2);
                Assert.fail('David may not pause.');
            } catch (AutomationControl.AutomationControlException expected) {
                Assert.areEqual(Label.Core_Automation_NoPermission, expected.getMessage(), 'Why.');
            }
            try {
                AutomationControl.resumeAll();
                Assert.fail('David may not resume.');
            } catch (AutomationControl.AutomationControlException expected) {
                Assert.areEqual(Label.Core_Automation_NoPermission, expected.getMessage(), 'Why.');
            }
            Test.stopTest();
        }

        Assert.isTrue(resumeJobs().isEmpty(), 'No resume was scheduled for him.');
        Assert.isFalse(AutomationControl.isPaused(), 'And nothing is paused.');
    }
}
