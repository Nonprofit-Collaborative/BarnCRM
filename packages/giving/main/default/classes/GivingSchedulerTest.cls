/**
 * Tests for the four nightly jobs and for the schedule an administrator starts from the
 * Nightly Jobs page of the settings console (ADR-0038).
 */
@IsTest(testFor='ApexClass:GivingScheduler')
private class GivingSchedulerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    // Switching the four jobs on and off: GivingNightlyJobProviderTest.

    @IsTest
    static void theOverdueJobRuns() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
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
    }

    @IsTest
    static void theOverdueJobLeavesAPaymentInsideTheGracePeriodAlone() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
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
    }

    @IsTest
    static void theTopUpJobRunsAndRecordsWhatItDid() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
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
}
