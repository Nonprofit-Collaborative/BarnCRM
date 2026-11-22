/**
 * A Forms administrator deletes a form that has submissions and the submissions stay, naming the
 * form and version they answered; anyone else is told to close the form instead; a form or
 * version nobody answered deletes as before (canonical model R-FM4, R-FS8).
 */
@IsTest(
	testFor='ApexClass:FormDeleteGuard, ApexClass:FormSubmissionNames, ApexTrigger:FormTrigger, ApexTrigger:FormVersionTrigger, ApexTrigger:FormSubmissionTrigger'
)
private class FormDeleteGuardTest {
	private static final String FORM_NAME = 'Zzdelete Volunteer Interest';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static User formsAdmin() {
		return TestUsers.adminWith(FormsTestData.ADMIN);
	}

	/** Someone who may delete any record (the running profile) but is not a Forms administrator. */
	private static User notFormsAdmin() {
		return TestUsers.onRunningProfileWith('Zzformdel', new List<String>{ TestUsers.CORE_ADMIN });
	}

	private static Form_Version__c versionOf(Id formId) {
		return [SELECT Id FROM Form_Version__c WHERE Form__c = :formId WITH SYSTEM_MODE LIMIT 1];
	}

	/** A published form with one submission, as a Forms administrator made them. */
	private static Form_Submission__c answered() {
		Form_Submission__c submission;
		System.runAs(formsAdmin()) {
			Form__c form = FormsTestData.published(FORM_NAME, FormsTestData.definition());
			submission = new Form_Submission__c(
				Form__c = form.Id,
				Form_Version__c = versionOf(form.Id).Id,
				Status__c = 'Needs Review',
				Answers__c = '{"last":"Zzdelete"}'
			);
			insert as user submission;
		}
		return submission;
	}

	private static Form_Submission__c reread(Id submissionId) {
		return [
			SELECT Id, Form__c, Form_Version__c, Form_Name__c, Version_Number__c, Answers__c
			FROM Form_Submission__c
			WHERE Id = :submissionId
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void aSubmissionNamesItsFormAndVersion() {
		Form_Submission__c submission = answered();

		System.runAs(formsAdmin()) {
			Form_Submission__c stored = [
				SELECT Form_Name__c, Version_Number__c
				FROM Form_Submission__c
				WHERE Id = :submission.Id
				WITH USER_MODE
			];
			Assert.areEqual(FORM_NAME, stored.Form_Name__c, 'The form name is stored');
			Assert.areEqual(1, stored.Version_Number__c, 'The version number is stored');
		}
	}

	@IsTest
	static void aFormsAdministratorDeletesTheFormAndTheSubmissionsStay() {
		Form_Submission__c submission = answered();

		System.runAs(formsAdmin()) {
			Test.startTest();
			delete as user new Form__c(Id = submission.Form__c);
			Test.stopTest();
		}

		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Form__c WHERE Id = :submission.Form__c WITH SYSTEM_MODE],
			'The form is deleted'
		);
		Form_Submission__c kept = reread(submission.Id);
		Assert.isNull(kept.Form__c, 'The form lookup is cleared');
		Assert.isNull(kept.Form_Version__c, 'The version lookup is cleared with the form');
		Assert.areEqual(FORM_NAME, kept.Form_Name__c, 'The submission still names its form');
		Assert.areEqual(1, kept.Version_Number__c, 'The submission still names its version');
		Assert.areEqual('{"last":"Zzdelete"}', kept.Answers__c, 'The answers are kept');
	}

	@IsTest
	static void anyoneElseIsToldToCloseTheForm() {
		User other = notFormsAdmin();
		Form_Submission__c submission = answered();

		Database.DeleteResult result;
		System.runAs(other) {
			Test.startTest();
			result = Database.delete(new Form__c(Id = submission.Form__c), false, AccessLevel.USER_MODE);
			Test.stopTest();
		}

		Assert.isFalse(result.isSuccess(), 'Only a Forms administrator may delete it');
		Assert.areEqual(
			BarnHelp.text('Forms', 'Forms_Delete_FormHasSubmissions', new List<Object>{ FORM_NAME }),
			result.getErrors()[0].getMessage(),
			'The message names the form and says to close it instead'
		);
		Form_Submission__c kept = reread(submission.Id);
		Assert.areEqual(submission.Form__c, kept.Form__c, 'The submission keeps its form');
	}

	@IsTest
	static void anyoneElseCannotDeleteAnAnsweredVersion() {
		User other = notFormsAdmin();
		Form_Submission__c submission = answered();

		Database.DeleteResult result;
		System.runAs(other) {
			Test.startTest();
			result = Database.delete(
				new Form_Version__c(Id = submission.Form_Version__c),
				false,
				AccessLevel.USER_MODE
			);
			Test.stopTest();
		}

		Assert.isFalse(result.isSuccess(), 'An answered version is protected too');
		Assert.areEqual(
			BarnHelp.text('Forms', 'Forms_Delete_VersionHasSubmissions'),
			result.getErrors()[0].getMessage(),
			'The message says to close the form instead'
		);
	}

	@IsTest
	static void aFormsAdministratorDeletesAnAnsweredVersion() {
		Form_Submission__c submission = answered();

		System.runAs(formsAdmin()) {
			Test.startTest();
			delete as user new Form_Version__c(Id = submission.Form_Version__c);
			Test.stopTest();
		}

		Form_Submission__c kept = reread(submission.Id);
		Assert.areEqual(submission.Form__c, kept.Form__c, 'The submission keeps its form');
		Assert.isNull(kept.Form_Version__c, 'The version lookup is cleared');
		Assert.areEqual(1, kept.Version_Number__c, 'The submission still names its version');
	}

	@IsTest
	static void aFormNobodyAnsweredDeletesAsBefore() {
		User other = notFormsAdmin();
		Form__c form;
		System.runAs(formsAdmin()) {
			form = FormsTestData.published(FORM_NAME, FormsTestData.definition());
		}

		Database.DeleteResult result;
		System.runAs(other) {
			Test.startTest();
			result = Database.delete(new Form__c(Id = form.Id), false, AccessLevel.USER_MODE);
			Test.stopTest();
		}

		Assert.isTrue(result.isSuccess(), 'A form nobody answered needs no Forms administrator');
		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Form_Version__c WHERE Form__c = :form.Id WITH SYSTEM_MODE],
			'Its versions go with it'
		);
	}

	@IsTest
	static void aSubmissionWhoseVersionIsGoneIsShownButNotProcessedAgain() {
		Form_Submission__c submission = answered();
		System.runAs(formsAdmin()) {
			delete as user new Form__c(Id = submission.Form__c);

			Test.startTest();
			// The Submission panel reads these fields through GraphQL (ADR-0093).
			Form_Submission__c view = [
				SELECT Form__c, Form_Name__c, Form_Version__c, Answers__c
				FROM Form_Submission__c
				WHERE Id = :submission.Id
				WITH USER_MODE
			];
			String refused;
			try {
				FormSubmitService.reprocess(submission.Id);
			} catch (FormSubmitService.FormException expected) {
				refused = expected.getMessage();
			}
			Test.stopTest();

			Assert.isNull(view.Form__c, 'The form is gone');
			Assert.areEqual(FORM_NAME, view.Form_Name__c, 'The panel names the deleted form');
			Assert.isNull(view.Form_Version__c, 'No version, so Process Again is not offered');
			Assert.isTrue(String.isNotBlank(view.Answers__c), 'The answers are still shown');
			Assert.areEqual(
				BarnHelp.text('Forms', 'Forms_Submit_FormDeleted'),
				refused,
				'Processing again says the form is gone'
			);
		}
	}

	@IsTest
	static void namesFillOnlyBlankSubmissions() {
		Form_Submission__c submission = answered();
		Form_Submission__c named = new Form_Submission__c(
			Form_Version__c = submission.Form_Version__c,
			Form_Name__c = 'Kept As Given'
		);
		Form_Submission__c formOnly = new Form_Submission__c(Form__c = submission.Form__c);
		Form_Submission__c neither = new Form_Submission__c();

		System.runAs(formsAdmin()) {
			Test.startTest();
			FormSubmissionNames.fill(new List<Form_Submission__c>{ named, formOnly, neither });
			Test.stopTest();
		}

		Assert.areEqual('Kept As Given', named.Form_Name__c, 'A stored name is never replaced');
		Assert.areEqual(FORM_NAME, formOnly.Form_Name__c, 'A form alone gives its name');
		Assert.isNull(formOnly.Version_Number__c, 'No version, no number');
		Assert.isNull(neither.Form_Name__c, 'Nothing to name it from');
	}
}
