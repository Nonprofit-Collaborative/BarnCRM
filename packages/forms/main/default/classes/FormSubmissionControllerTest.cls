/**
 * The Submission panel shows the answers by question, as the version asked them, and what was
 * written, and processes a held submission again.
 */
@IsTest(testFor='ApexClass:FormSubmissionController')
private class FormSubmissionControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	@IsTest
	static void showsAnswersByQuestionAndProcessesAHeldOneAgain() {
		System.runAs(TestUsers.adminWith(FormsTestData.ADMIN)) {
			List<Contact> twins = new List<Contact>{
				new Contact(FirstName = 'Pat', LastName = 'Zzpanel', Email = 'twins@example.org'),
				new Contact(FirstName = 'Pat', LastName = 'Zzpanel', Email = 'twins@example.org')
			};
			insert as user twins;
			Form__c form = FormsTestData.volunteerInterest();

			Test.startTest();
			FormSubmitService.Result held = FormSubmitService.submit(
				form.Id,
				new Map<String, Object>{
					'first' => 'Pat',
					'last' => 'Zzpanel',
					'email' => 'twins@example.org'
				},
				null,
				null
			);
			FormSubmissionController.SubmissionView before = FormSubmissionController.getSubmission(
				held.submissionId
			);
			update as user new Form_Submission__c(Id = held.submissionId, Person__c = twins[0].Id);
			FormSubmitService.Result again = FormSubmissionController.processAgain(
				held.submissionId
			);
			FormSubmissionController.SubmissionView after = FormSubmissionController.getSubmission(
				held.submissionId
			);
			Test.stopTest();

			Assert.areEqual(FormSubmitService.NEEDS_REVIEW, before.status);
			Assert.isTrue(before.canProcess, 'Process Again is offered');
			Assert.areEqual('Volunteer Interest', before.formName);
			Assert.areEqual(
				new List<String>{ 'First', 'Last', 'Email' },
				new List<String>{
					before.answers[0].label,
					before.answers[1].label,
					before.answers[2].label
				},
				'In the order the form asks'
			);
			Assert.areEqual(
				FormSubmitService.PROCESSED,
				again.status,
				'Processed again: ' + again.message
			);
			Assert.isFalse(after.canProcess, 'Nothing left to process');
			Assert.areEqual(twins[0].Id, after.records[0].recordId, 'What was written');
			try {
				FormSubmissionController.processAgain(held.submissionId);
				Assert.fail('Not processed twice');
			} catch (AuraHandledException expected) {
				Assert.isTrue(String.isNotBlank(expected.getMessage()), 'In plain words');
			}
			Assert.isNull(
				FormSubmissionController.getSubmission(form.Id),
				'Not a submission, nothing shown'
			);
		}
	}
}
