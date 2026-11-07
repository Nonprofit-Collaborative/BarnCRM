/**
 * Public form processing (canonical model R-FS6; ADR-NEXT public forms on a Salesforce Site,
 * decision 2): four jobs a quarter hour apart, scheduled once; a run processes what waits as the
 * person who scheduled it.
 */
@IsTest(testFor='ApexClass:FormPublicProcessor')
private class FormPublicProcessorTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(FormsTestData.ADMIN);
	}

	@IsTest
	static void schedulingMakesFourJobsOnce() {
		System.runAs(admin()) {
			Assert.isFalse(FormPublicProcessor.isScheduled(), 'Not yet');
			Test.startTest();
			FormPublicProcessor.schedule();
			FormPublicProcessor.schedule();
			Test.stopTest();
			Assert.isTrue(FormPublicProcessor.isScheduled(), 'Scheduled');
			Assert.areEqual(
				4,
				[
					SELECT COUNT()
					FROM CronTrigger
					WHERE CronJobDetail.Name LIKE :FormPublicProcessor.JOB_NAME + '%'
					WITH SYSTEM_MODE
				],
				'Four jobs, not eight'
			);
		}
	}

	@IsTest
	static void aRunProcessesWhatWaits() {
		System.runAs(admin()) {
			AccountKindsTestData.useRecordTypeTheUserCanUse();
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			FormIntakeService.actAsGuest = true;
			String ticket = FormIntakeService.load(form.Id).ticket;
			FormIntakeService.clockShiftMs = 10000;
			FormIntakeService.submit(
				ticket,
				new Map<String, Object>{ 'first' => 'Lee', 'last' => 'Zzqueue' },
				null,
				null
			);
			Assert.areEqual(1, FormPublicProcessor.waiting(10).size(), 'One waits');

			Test.startTest();
			new FormPublicProcessor().execute((SchedulableContext) null);
			Test.stopTest();

			Assert.isTrue(FormPublicProcessor.waiting(10).isEmpty(), 'Nothing waits');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Contact WHERE LastName = 'Zzqueue' WITH USER_MODE],
				'The person was added'
			);
		}
	}
}
