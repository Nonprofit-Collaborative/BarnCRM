/**
 * The Log Hours action's starting values (modules-14): a shift fills the job, the shift, the
 * date and its length; a job fills the job; a contact fills the person.
 */
@IsTest(testFor='ApexClass:VolunteerLogHoursController')
private class VolunteerLogHoursControllerTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.job('Food pantry sort');
		}
	}

	@IsTest
	static void aShiftFillsTheJobTheShiftTheDateAndItsLength() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Volunteer_Job__c job = [SELECT Id FROM Volunteer_Job__c LIMIT 1];
			Volunteer_Shift__c shift = VolunteersTestData.shift(job.Id);

			Test.startTest();
			VolunteerLogHoursController.Context context = VolunteerLogHoursController.getContext(
				shift.Id
			);
			Test.stopTest();

			Assert.isTrue(context.canCreate, 'An admin can log hours.');
			Assert.areEqual(job.Id, context.jobId, 'The shift fills its job.');
			Assert.areEqual(shift.Id, context.shiftId, 'And itself.');
			Assert.areEqual(3, context.hours, 'Its three hours.');
			Assert.areEqual(
				ShiftScheduleService.orgDate(VolunteersTestData.SHIFT_START),
				context.dateWorked,
				'Its day.'
			);
			Assert.isNull(context.personId, 'No person from a shift.');
		}
	}

	@IsTest
	static void aJobFillsTheJobAndAContactFillsThePerson() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Volunteer_Job__c job = [SELECT Id FROM Volunteer_Job__c LIMIT 1];
			Contact person = VolunteersTestData.contacts(1)[0];

			Test.startTest();
			VolunteerLogHoursController.Context fromJob = VolunteerLogHoursController.getContext(
				job.Id
			);
			VolunteerLogHoursController.Context fromPerson = VolunteerLogHoursController.getContext(
				person.Id
			);
			Test.stopTest();

			Assert.areEqual(job.Id, fromJob.jobId, 'The job is filled.');
			Assert.isNull(fromJob.shiftId, 'No shift from a job.');
			Assert.areEqual(person.Id, fromPerson.personId, 'The person is filled.');
			Assert.areEqual('Contact', fromPerson.personObject, 'Picked as a contact.');
		}
	}
}
