/**
 * Tests for the Nightly Jobs page of the settings console (ADR-0038).
 *
 * The three states an administrator can be in are what is asserted here: nothing scheduled,
 * scheduled and running, and a user who may look but not change the schedule.
 */
@IsTest
private class GivingJobsControllerTest {
    private static final String PERMISSION_SET = 'GivingNightlyJobsTestAccess';
    private static final String TOP_UP = 'topUp';
    private static final String OVERDUE = 'overdue';
    private static final String LEVELS = 'levels';

    /**
     * The running user needs Manage Nonprofit Settings to schedule anything, and the assignment
     * has to be committed before a test method runs, which is what @TestSetup is for.
     */
    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo(PERMISSION_SET, UserInfo.getUserId());
    }

    @IsTest
    static void anOrgThatNeverSwitchedTheJobsOnIsToldThatRatherThanWarned() {
        Test.startTest();
        GivingJobsController.JobsView view = GivingJobsController.getJobs();
        Test.stopTest();

        Assert.isFalse(
            view.scheduled,
            'Nothing has scheduled the nightly jobs, which is the state every org shipped in.'
        );
        Assert.areEqual(
            null,
            view.nextRunAt,
            'There is no next run to show when nothing is scheduled.'
        );
        Assert.areEqual(3, view.jobs.size(), 'The page lists all three nightly jobs.');
        for (GivingJobsController.JobView job : view.jobs) {
            Assert.isFalse(
                job.stale,
                'An org that never switched the jobs on has not missed a run, so nothing is stale: ' +
                job.name
            );
            Assert.areEqual(
                null,
                job.lastRun,
                'A job that has never run has no last run: ' + job.name
            );
        }
    }

    @IsTest
    static void schedulingFromThePageStartsAllThreeJobs() {
        Test.startTest();
        GivingJobsController.JobsView view = GivingJobsController.setSchedule(true);
        Test.stopTest();

        Assert.isTrue(view.scheduled, 'The page reports the jobs as scheduled once they are.');
        Assert.areNotEqual(
            null,
            view.nextRunAt,
            'The page shows when the first of the three jobs is next due.'
        );
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'BarnCRM Giving%'],
            'Choosing Schedule from the console schedules all three jobs, which is the whole fix.'
        );
        for (GivingJobsController.JobView job : view.jobs) {
            Assert.isTrue(job.scheduled, 'Every one of the three jobs is scheduled: ' + job.name);
        }
    }

    @IsTest
    static void schedulingTwiceFromThePageLeavesThreeJobs() {
        Test.startTest();
        GivingJobsController.setSchedule(true);
        GivingJobsController.JobsView view = GivingJobsController.setSchedule(true);
        Test.stopTest();

        Assert.areEqual(
            3,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'BarnCRM Giving%'],
            'Pressing Schedule twice does not schedule a second copy of each job.'
        );
        Assert.isTrue(view.scheduled, 'The page still reports the jobs as scheduled.');
    }

    @IsTest
    static void stoppingFromThePageUnschedulesEveryJob() {
        Test.startTest();
        GivingJobsController.setSchedule(true);
        GivingJobsController.JobsView view = GivingJobsController.setSchedule(false);
        Test.stopTest();

        Assert.isFalse(view.scheduled, 'The page reports the jobs as stopped.');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'BarnCRM Giving%'],
            'Stopping leaves nothing scheduled.'
        );
    }

    @IsTest
    static void thePageShowsWhenEachJobLastRanAndWhatItDid() {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Installment_Top_Up_Last_Run__c = Datetime.now().addHours(-8);
        settings.Installment_Top_Up_Last_Run_Summary__c = 'Extended 4 recurring schedules.';
        settings.Installment_Overdue_Last_Run__c = Datetime.now().addHours(-8);
        settings.Installment_Overdue_Last_Run_Summary__c = 'Marked 2 payments Overdue.';
        settings.Donor_Levels_Last_Recalculated__c = Datetime.now().addHours(-7);
        insert settings;

        Test.startTest();
        GivingJobsController.JobsView view = GivingJobsController.getJobs();
        Test.stopTest();

        Map<String, GivingJobsController.JobView> byName = byName(view);
        Assert.areEqual(
            'Marked 2 payments Overdue.',
            byName.get(OVERDUE).lastRunSummary,
            'The overdue line says what last night marked, which is the evidence the job is working.'
        );
        Assert.areEqual(
            'Extended 4 recurring schedules.',
            byName.get(TOP_UP).lastRunSummary,
            'The top up line says what last night extended.'
        );
        Assert.areNotEqual(
            null,
            byName.get(LEVELS).lastRun,
            'The donor level line reads the stamp that pass already writes.'
        );
        for (GivingJobsController.JobView job : view.jobs) {
            Assert.isFalse(
                job.stale,
                'A job that is not scheduled is never reported as stale, however old its last run: ' +
                job.name
            );
        }
    }

    @IsTest
    static void runNowStartsTheTopUpAndTheOverduePass() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = person.Id,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today().addMonths(-2),
            Expected_Total__c = 100,
            Installments_Planned__c = 1
        );
        insert pledge;
        delete [SELECT Id FROM Installment__c WHERE Commitment__c = :pledge.Id];
        insert new Installment__c(
            Commitment__c = pledge.Id,
            Sequence__c = 1,
            Due_Date__c = Date.today().addDays(-40),
            Expected_Amount__c = 100,
            Status__c = 'Scheduled'
        );

        Test.startTest();
        GivingJobsController.runNow();
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Installment__c
                WHERE Status__c = 'Overdue' AND Commitment__c = :pledge.Id
            ],
            'An administrator who has just switched the jobs on does not have to wait a night for the Overdue list to fill.'
        );
        Assert.areNotEqual(
            null,
            Giving_Settings__c.getOrgDefaults().Installment_Overdue_Last_Run__c,
            'A run started by hand records itself the same way the nightly run does.'
        );
    }

    @IsTest
    static void aUserWhoMayNotManageSettingsCannotScheduleTheJobs() {
        User reader = readOnlyUser();
        Exception refused = null;

        Test.startTest();
        System.runAs(reader) {
            try {
                GivingJobsController.setSchedule(true);
            } catch (Exception caught) {
                refused = caught;
            }
        }
        Test.stopTest();

        Assert.areNotEqual(
            null,
            refused,
            'Scheduling a job that writes to every donor record needs the settings permission.'
        );
        Assert.areEqual(
            System.Label.Giving_NightlyJobs_PermissionRequired,
            refused.getMessage(),
            'The refusal says which permission is missing rather than showing a platform error.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'BarnCRM Giving%'],
            'The refusal is a refusal: nothing was scheduled.'
        );
    }

    @IsTest
    static void aUserWhoMayNotManageSettingsCanStillSeeWhetherTheJobsAreRunning() {
        User reader = readOnlyUser();
        GivingJobsController.JobsView view;

        Test.startTest();
        System.runAs(reader) {
            view = GivingJobsController.getJobs();
        }
        Test.stopTest();

        Assert.isFalse(
            view.canManage,
            'The page tells the component to disable its buttons for a reader.'
        );
        Assert.areEqual(
            3,
            view.jobs.size(),
            'A reader still sees all three jobs, because seeing whether they run is not a change.'
        );
    }

    private static Map<String, GivingJobsController.JobView> byName(
        GivingJobsController.JobsView view
    ) {
        return new Map<String, GivingJobsController.JobView>{
            TOP_UP => view.jobs[0],
            OVERDUE => view.jobs[1],
            LEVELS => view.jobs[2]
        };
    }

    /** A user holding no packaged permission set, so the custom permission is genuinely absent. */
    private static User readOnlyUser() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User reader = new User(
            Alias = 'oijobs',
            Email = 'nightly.jobs.reader@barncrm.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Reader',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'America/Chicago',
            UserName = 'nightly.jobs.reader.' + Datetime.now().getTime() + '@barncrm.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert reader;
        }
        return reader;
    }
}
