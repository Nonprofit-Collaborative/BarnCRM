/**
 * A used job is deactivated, not deleted (R-VJ1), and the rule always runs.
 */
@IsTest(
    testFor='ApexClass:VolunteerJobTriggerHandler, ApexClass:VolunteerIntegritySelector, ApexTrigger:VolunteerJobTrigger'
)
private class VolunteerJobTriggerHandlerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith(VolunteersTestData.ADMIN);
    }

    private static List<Volunteer_Job__c> jobs(Integer howMany) {
        List<Volunteer_Job__c> records = new List<Volunteer_Job__c>();
        for (Integer i = 0; i < howMany; i++) {
            records.add(new Volunteer_Job__c(Name = 'Job ' + i, Active__c = true));
        }
        insert records;
        return records;
    }

    @IsTest
    static void jobsWithShiftsAreKeptAndUnusedJobsGo() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            List<Volunteer_Job__c> used = jobs(251);
            List<Volunteer_Shift__c> shifts = new List<Volunteer_Shift__c>();
            for (Volunteer_Job__c job : used) {
                shifts.add(VolunteersTestData.newShift(job.Id, VolunteersTestData.SHIFT_START, 2));
            }
            insert shifts;
            List<Volunteer_Job__c> unused = jobs(251);

            Test.startTest();
            List<Database.DeleteResult> usedResults = Database.delete(used, false);
            delete unused;
            Test.stopTest();

            for (Database.DeleteResult result : usedResults) {
                Assert.isFalse(result.isSuccess(), 'A job with shifts is kept.');
                Assert.areEqual(
                    Label.Volunteers_Job_InUseNotDeletable,
                    result.getErrors()[0].getMessage(),
                    'And the message says to clear Active instead.'
                );
            }
            Assert.areEqual(251, [SELECT COUNT() FROM Volunteer_Job__c], 'Only the unused went.');
            Assert.areEqual(251, [SELECT COUNT() FROM Volunteer_Shift__c], 'Shifts are untouched.');
        }
    }

    @IsTest
    static void aJobWithApprovedHoursIsKeptEvenWithAutomationPaused() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact person = VolunteersTestData.contact('Rivera', null);
            Volunteer_Job__c job = VolunteersTestData.job('Van driving');
            Volunteer_Hours__c hours = VolunteersTestData.newHours(person.Id, job.Id, 2);
            insert hours;
            VolunteerHoursService.approve(new Set<Id>{ hours.Id });
            TestDataFactory.pausedSettings(1);
            String message = '';

            Test.startTest();
            try {
                delete job;
            } catch (DmlException refused) {
                message = refused.getDmlMessage(0);
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Volunteers_Job_InUseNotDeletable,
                message,
                'Approved hours keep their job: the rule always runs, paused or not.'
            );
            Assert.areEqual(
                job.Id,
                [SELECT Volunteer_Job__c FROM Volunteer_Hours__c WHERE Id = :hours.Id]
                .Volunteer_Job__c,
                'The hours still name the job.'
            );
        }
    }
}
