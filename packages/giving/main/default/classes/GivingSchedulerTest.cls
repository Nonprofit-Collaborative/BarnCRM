/**
 * Tests for the three nightly jobs and for the schedule an administrator starts from the
 * Nightly Jobs page of the settings console (ADR-0038).
 */
@IsTest
private class GivingSchedulerTest {
    @IsTest
    static void schedulesAllThreeNightlyJobs() {
        Test.startTest();
        GivingScheduler.scheduleAll();
        Test.stopTest();

        Assert.areEqual(
            3,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'BarnCRM Giving%'],
            'Switching the jobs on schedules the top up, the overdue pass and the donor levels pass.'
        );
        Assert.isTrue(
            GivingScheduler.isScheduled(),
            'All three jobs are scheduled, which is what the page reports as switched on.'
        );
        Assert.areNotEqual(
            null,
            GivingScheduler.nextRunAt(),
            'A scheduled job has a next run, which is what the page shows under the button.'
        );
    }

    @IsTest
    static void schedulingTwiceDoesNotCreateASecondSetOfJobs() {
        Test.startTest();
        GivingScheduler.scheduleAll();
        List<Id> second = GivingScheduler.scheduleAll();
        Test.stopTest();

        Assert.areEqual(
            3,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'BarnCRM Giving%'],
            'An administrator pressing Schedule twice gets three jobs, not six.'
        );
        Assert.areEqual(
            0,
            second.size(),
            'The second call scheduled nothing, because all three jobs were already there.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'GivingScheduler%'],
            'Pressing the button twice is ordinary and must not write a duplicate name failure to the Error Log.'
        );
    }

    @IsTest
    static void stopUnschedulesEveryJob() {
        Test.startTest();
        GivingScheduler.scheduleAll();
        GivingScheduler.stopAll();
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'BarnCRM Giving%'],
            'Stopping the nightly jobs leaves none of the three scheduled.'
        );
        Assert.isFalse(
            GivingScheduler.isScheduled(),
            'With nothing scheduled the page offers Schedule rather than Stop.'
        );
        Assert.areEqual(
            null,
            GivingScheduler.nextRunAt(),
            'There is no next run to show once the jobs are stopped.'
        );
    }

    @IsTest
    static void aPartlyScheduledOrgIsNotReportedAsSwitchedOn() {
        Test.startTest();
        System.schedule(
            GivingScheduler.OVERDUE_JOB_NAME,
            '0 45 1 * * ?',
            new InstallmentSchedulable()
        );
        Boolean scheduledWithOnlyOneJob = GivingScheduler.isScheduled();
        GivingScheduler.scheduleAll();
        Test.stopTest();

        Assert.isFalse(
            scheduledWithOnlyOneJob,
            'The overdue pass without the top up is not "on": it marks payments overdue on a schedule nothing is extending.'
        );
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'BarnCRM Giving%'],
            'Scheduling fills in the two jobs that were missing and leaves the one already there alone.'
        );
    }

    @IsTest
    static void theOverdueJobRuns() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = person.Id,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today().addMonths(-2),
            Expected_Total__c = 200,
            Installments_Planned__c = 2
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
        new InstallmentSchedulable().execute(null);
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Installment__c
                WHERE Status__c = 'Overdue' AND Commitment__c = :pledge.Id
            ],
            'The daily pass marks a payment forty days late Overdue.'
        );
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        Assert.areNotEqual(
            null,
            settings.Installment_Overdue_Last_Run__c,
            'The pass records when it finished, which is what the Nightly Jobs page shows.'
        );
        Assert.areEqual(
            String.format(
                System.Label.Giving_NightlyJobs_OverdueSummaryFormat,
                new List<String>{ '1' }
            ),
            settings.Installment_Overdue_Last_Run_Summary__c,
            'The pass says how many payments it marked, not just that it woke up.'
        );
    }

    @IsTest
    static void theOverdueJobLeavesAPaymentInsideTheGracePeriodAlone() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = person.Id,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today(),
            Expected_Total__c = 100,
            Installments_Planned__c = 1
        );
        insert pledge;
        delete [SELECT Id FROM Installment__c WHERE Commitment__c = :pledge.Id];
        insert new Installment__c(
            Commitment__c = pledge.Id,
            Sequence__c = 1,
            Due_Date__c = Date.today().addDays(-1),
            Expected_Amount__c = 100,
            Status__c = 'Scheduled'
        );

        Test.startTest();
        new InstallmentSchedulable().execute(null);
        Test.stopTest();

        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Installment__c
                WHERE Status__c = 'Overdue' AND Commitment__c = :pledge.Id
            ],
            'A payment one day late is inside the five day grace period, so it stays Scheduled.'
        );
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        Assert.areNotEqual(
            null,
            settings.Installment_Overdue_Last_Run__c,
            'A pass that found nothing still records that it ran, so a blank stamp means it has never run.'
        );
        Assert.areEqual(
            System.Label.Giving_NightlyJobs_OverdueNoneFound,
            settings.Installment_Overdue_Last_Run_Summary__c,
            'The page says the pass found nothing overdue rather than leaving the reader to guess.'
        );
    }

    @IsTest
    static void theTopUpJobRunsAndRecordsWhatItDid() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        insert new Commitment__c(
            Type__c = 'Recurring',
            Status__c = 'Active',
            Donor_Contact__c = person.Id,
            Amount__c = 25,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );

        Test.startTest();
        new InstallmentTopUpSchedulable().execute(null);
        Test.stopTest();
        // Test.stopTest() runs the batch the schedulable started, so its work is done here.

        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        Assert.areNotEqual(
            null,
            settings.Installment_Top_Up_Last_Run__c,
            'The job says when it last finished, so Maria can see it is running.'
        );
        Assert.areEqual(
            String.format(
                System.Label.Giving_NightlyJobs_TopUpSummaryFormat,
                new List<String>{ '1', '0' }
            ),
            settings.Installment_Top_Up_Last_Run_Summary__c,
            'The job says it extended one schedule and failed nowhere, which a timestamp alone cannot.'
        );
        Assert.isTrue(
            [SELECT COUNT() FROM Installment__c] > 0,
            'The top up puts a year of payments in front of a recurring gift.'
        );
    }
}
