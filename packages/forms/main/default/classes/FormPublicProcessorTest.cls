/**
 * Public form processing (canonical model R-FS6; ADR-0184 public forms on a Salesforce Site,
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
				null,
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

	@IsTest
	static void theRunChainsOnlyWhileAQueueableSlotIsFree() {
		// runs-as: deploying user (counts queueable slots only, no record access)
		Assert.isTrue(FormPublicProcessor.canChain(), 'A free slot');
		for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) {
			System.enqueueJob(new FormPublicProcessor.Run());
		}
		Assert.isFalse(FormPublicProcessor.canChain(), 'No slot left to chain on');
	}

	@IsTest
	static void aSubmissionThatCannotBeProcessedIsMarkedFailed() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			FormIntakeService.actAsGuest = true;
			String ticket = FormIntakeService.load(form.Id).ticket;
			FormIntakeService.clockShiftMs = 10000;
			FormIntakeService.submit(
				ticket,
				new Map<String, Object>{ 'first' => 'Lee', 'last' => 'Zzfail' },
				null,
				null,
				null,
				null
			);
			Id waitingId = FormPublicProcessor.waiting(1)[0].Id;

			FormPublicProcessor.markFailed(waitingId, new DmlException('Zzbroken'));

			Form_Submission__c after = [
				SELECT Status__c, Message__c
				FROM Form_Submission__c
				WHERE Id = :waitingId
				WITH USER_MODE
			];
			Assert.areEqual(FormSubmitService.FAILED, after.Status__c, 'Failed');
			Assert.isTrue(after.Message__c.contains('Zzbroken'), 'Says why');
			Assert.isTrue(FormPublicProcessor.waiting(1).isEmpty(), 'Not taken up again');
			FormsSites.testSites = null;
			Assert.isNotNull(FormsSites.active(), 'The org is asked for its Sites');
		}
	}
}
