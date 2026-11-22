/**
 * Process Again on the Submission panel processes a held submission again and stores what it
 * wrote; the panel reads the submission through GraphQL (ADR-0093) and shapes it in
 * `c/formSubmissionModel`.
 */
@IsTest(testFor='ApexClass:FormSubmissionController')
private class FormSubmissionControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static Form_Submission__c reread(Id submissionId) {
		return [
			SELECT Status__c, Form_Version__c, Outcome__c
			FROM Form_Submission__c
			WHERE Id = :submissionId
			WITH USER_MODE
		];
	}

	@IsTest
	static void processesAHeldOneAgain() {
		System.runAs(TestUsers.adminWith(FormsTestData.ADMIN)) {
			List<Contact> twins = new List<Contact>{
				TestDataFactory.person(
					new Contact(FirstName = 'Pat', LastName = 'Zzpanel', Email = 'twins@example.org')
				),
				TestDataFactory.person(
					new Contact(FirstName = 'Pat', LastName = 'Zzpanel', Email = 'twins@example.org')
				)
			};
			insert as user twins;
			Form__c form = FormsTestData.volunteerInterest();

			Test.startTest();
			FormSubmitService.Result held = FormSubmitService.submit(
				form.Id,
				new Map<String, Object>{ 'first' => 'Pat', 'last' => 'Zzpanel', 'email' => 'twins@example.org' },
				null,
				null
			);
			Form_Submission__c before = reread(held.submissionId);
			update as user new Form_Submission__c(Id = held.submissionId, Person__c = twins[0].Id);
			FormSubmitService.Result again = FormSubmissionController.processAgain(held.submissionId);
			Form_Submission__c after = reread(held.submissionId);
			Test.stopTest();

			Assert.areEqual(FormSubmitService.NEEDS_REVIEW, before.Status__c);
			Assert.isNotNull(before.Form_Version__c, 'Names the version, so Process Again is offered');
			Assert.areEqual(FormSubmitService.PROCESSED, again.status, 'Processed again: ' + again.message);
			Assert.areEqual(FormSubmitService.PROCESSED, after.Status__c, 'Nothing left to process');
			Assert.isTrue(after.Outcome__c.contains(twins[0].Id), 'What was written');
			try {
				FormSubmissionController.processAgain(held.submissionId);
				Assert.fail('Not processed twice');
			} catch (AuraHandledException expected) {
				Assert.isTrue(String.isNotBlank(expected.getMessage()), 'In plain words');
			}
		}
	}

	@IsTest
	static void aPersonWithoutFormsAccessGetsAPlainMessage() {
		Id someSubmission =
			Form_Submission__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001';
		System.runAs(TestUsers.standardUser('Zzformless')) {
			try {
				FormSubmissionController.processAgain(someSubmission);
				Assert.fail('Refused without access to submissions');
			} catch (AuraHandledException expected) {
				Assert.isTrue(String.isNotBlank(expected.getMessage()), 'In plain words');
			}
		}
	}
}
