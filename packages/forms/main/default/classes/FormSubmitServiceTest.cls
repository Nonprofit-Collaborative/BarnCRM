/**
 * Pat fills in the volunteer interest form and BarnCRM writes the right records: a new person and
 * organization with their affiliation, or the person already on file with only blanks filled; a
 * shared email is held for review, never guessed, and Process Again finishes it; a failure keeps
 * the answers and writes nothing; a module that attached the form hears about it (canonical model
 * R-FS1 to R-FS4).
 */
@IsTest(testFor='ApexClass:FormSubmitService')
private class FormSubmitServiceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(FormsTestData.ADMIN);
	}

	/** Answers submitted with no files. */
	private static FormSubmitService.Result submit(
		Id formId,
		Map<String, Object> answers,
		Id contextRecordId
	) {
		return FormSubmitService.submit(formId, answers, contextRecordId, null);
	}

	private static Map<String, Object> pat() {
		return new Map<String, Object>{
			'first' => 'Pat',
			'last' => 'Zzform',
			'email' => 'pat.zzform@example.org',
			'postal' => '12345',
			'employer' => 'Zzform Riverside Trust',
			'role' => 'Board Chair',
			'age' => 40
		};
	}

	private static Form_Submission__c submission(Id submissionId) {
		return [
			SELECT Id, Status__c, Message__c, Person__c, Organization__c, Answers__c, Outcome__c
			FROM Form_Submission__c
			WHERE Id = :submissionId
			WITH USER_MODE
		];
	}

	@IsTest
	static void aNewPersonGetsTheirRecordsAndTheModuleHearsIt() {
		System.runAs(admin()) {
			AccountKindsTestData.useRecordTypeTheUserCanUse();
			Form__c form = FormsTestData.volunteerInterest();
			Account gala = AccountKindsTestData.organization('Zzform Spring Gala');
			insert as user gala;
			FormsTestModule.register();

			Test.startTest();
			FormSubmitService.Result result = submit(form.Id, pat(), gala.Id);
			Test.stopTest();

			Assert.areEqual(
				FormSubmitService.PROCESSED,
				result.status,
				'Processed: ' + result.message
			);
			Contact person = [
				SELECT Id, FirstName, Email, MailingPostalCode
				FROM Contact
				WHERE LastName = 'Zzform'
				WITH USER_MODE
			];
			Assert.areEqual('pat.zzform@example.org', person.Email, 'Written from the answers');
			Account employer = [
				SELECT Id, RecordTypeId
				FROM Account
				WHERE Name = 'Zzform Riverside Trust'
				WITH USER_MODE
			];
			Id organizationType = AccountKinds.organizationRecordTypeId();
			if (organizationType != null) {
				Assert.areEqual(organizationType, employer.RecordTypeId, 'An organization');
			}
			Affiliation__c link = [
				SELECT Contact__c, Organization__c, Role__c, Status__c
				FROM Affiliation__c
				WHERE Contact__c = :person.Id
				WITH USER_MODE
			];
			Assert.areEqual(employer.Id, link.Organization__c, 'Linked to the organization');
			Assert.areEqual('Board Chair', link.Role__c, 'With the mapped answer');
			Assert.areEqual('Current', link.Status__c, 'And the constant');
			Form_Submission__c saved = submission(result.submissionId);
			Assert.areEqual(person.Id, saved.Person__c, 'The submission names the person');
			Assert.areEqual(employer.Id, saved.Organization__c, 'And the organization');
			Assert.isFalse(saved.Answers__c.contains('guardian'), 'A hidden question is dropped');
			Assert.areEqual(3, result.records.size(), 'Three records written');
			Assert.areEqual(1, FormsTestModule.heard.size(), 'The module heard it');
			Assert.areEqual(person.Id, FormsTestModule.heard[0].personId, 'With the person');
			Assert.areEqual(
				link.Id,
				FormsTestModule.heard[0].recordIds.get('link'),
				'And every record'
			);
		}
	}

	@IsTest
	static void thePersonOnFileHasOnlyBlanksFilledUnlessTheFormOverwrites() {
		System.runAs(admin()) {
			Contact onFile = new Contact(
				FirstName = 'Pat',
				LastName = 'Zzform',
				Email = 'pat.zzform@example.org',
				Description = 'Keep this'
			);
			insert as user onFile;
			Map<String, Object> answers = pat();
			answers.remove('employer');
			answers.put('age', 15);
			answers.put('guardian', 'Jo Zzform');

			Test.startTest();
			FormSubmitService.Result kept = submit(
				FormsTestData.volunteerInterest().Id,
				answers,
				null
			);
			Map<String, Object> overwriting = FormsTestData.definition();
			((Map<String, Object>) ((List<Object>) overwriting.get('records'))[0])
				.put(
					'matching',
					new Map<String, Object>{ 'rule' => 'email', 'onMatch' => 'overwrite' }
				);
			FormSubmitService.Result overwritten = submit(
				FormsTestData.published('Overwrite', overwriting).Id,
				answers,
				null
			);
			Test.stopTest();

			Assert.areEqual(FormSubmitService.PROCESSED, kept.status, 'Kept: ' + kept.message);
			Assert.areEqual('updated', kept.records[0].action, 'Found and filled');
			Assert.areEqual(onFile.Id, kept.records[0].recordId, 'The person on file');
			Assert.areEqual(1, kept.records.size(), 'No organization named, so none and no link');
			Assert.areEqual(
				FormSubmitService.PROCESSED,
				overwritten.status,
				'Overwritten: ' + overwritten.message
			);
			Contact after = [
				SELECT Description, MailingPostalCode
				FROM Contact
				WHERE Id = :onFile.Id
				WITH USER_MODE
			];
			Assert.areEqual('12345', after.MailingPostalCode, 'A blank was filled');
			Assert.areEqual('Jo Zzform', after.Description, 'Overwritten by the second form');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Contact WHERE LastName = 'Zzform' WITH USER_MODE],
				'Never created twice'
			);
		}
	}

	@IsTest
	static void aSharedEmailIsHeldForReviewAndProcessedAgain() {
		System.runAs(admin()) {
			List<Contact> couple = new List<Contact>{
				new Contact(FirstName = 'Pat', LastName = 'Zzform', Email = 'home@example.org'),
				new Contact(FirstName = 'Pat', LastName = 'Zzform', Email = 'home@example.org'),
				new Contact(FirstName = 'Sam', LastName = 'Zzform', Email = 'home@example.org')
			};
			insert as user couple;
			Form__c form = FormsTestData.volunteerInterest();
			Map<String, Object> answers = pat();
			answers.remove('employer');
			answers.put('email', 'home@example.org');
			Map<String, Object> sam = answers.clone();
			sam.put('first', 'Sam');

			Test.startTest();
			FormSubmitService.Result held = submit(form.Id, answers, null);
			FormSubmitService.Result samResult = submit(form.Id, sam, null);
			update as user new Form_Submission__c(Id = held.submissionId, Person__c = couple[1].Id);
			FormSubmitService.Result again = FormSubmitService.reprocess(held.submissionId);
			Test.stopTest();

			Assert.areEqual(FormSubmitService.NEEDS_REVIEW, held.status, 'Two Pats: never guessed');
			Assert.isTrue(held.records.isEmpty(), 'Nothing written while held');
			Assert.areEqual(couple[2].Id, samResult.records[0].recordId, 'Sam is told apart');
			Assert.areEqual(
				FormSubmitService.PROCESSED,
				again.status,
				'Processed again: ' + again.message
			);
			Assert.areEqual(couple[1].Id, again.records[0].recordId, 'The person staff chose');
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Contact WHERE LastName = 'Zzform' WITH USER_MODE],
				'Nobody created'
			);
			try {
				FormSubmitService.reprocess(held.submissionId);
				Assert.fail('A processed submission is not processed twice');
			} catch (FormSubmitService.FormException expected) {
				Assert.isTrue(String.isNotBlank(expected.getMessage()), 'Said in plain words');
			}
		}
	}

	@IsTest
	static void refusedAnswersSaveNothing() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.volunteerInterest();
			Map<String, Object> answers = pat();
			answers.remove('last');
			answers.put('email', 'not an email');

			FormSubmitService.Result result = submit(form.Id, answers, null);

			Assert.areEqual(FormSubmitService.INVALID, result.status);
			Assert.areEqual(
				new Map<String, String>{ 'last' => 'required', 'email' => 'badEmail' },
				result.problems
			);
			Assert.areEqual(0, [SELECT COUNT() FROM Form_Submission__c WITH USER_MODE]);
		}
	}

	@IsTest
	static void aFailureRollsBackTheRecordsAndKeepsTheAnswers() {
		System.runAs(admin()) {
			Map<String, Object> broken = FormsTestData.definition();
			((List<Object>) broken.get('records'))
				.add(
					new Map<String, Object>{
						'key' => 'extra',
						'kind' => 'related',
						'object' => 'No_Such_Object__c'
					}
				);
			Form__c form = FormsTestData.published('Broken', broken);
			Map<String, Object> answers = pat();
			answers.remove('employer');

			Test.startTest();
			FormSubmitService.Result result = submit(form.Id, answers, null);
			Test.stopTest();

			Assert.areEqual(FormSubmitService.FAILED, result.status);
			Form_Submission__c saved = submission(result.submissionId);
			Assert.isTrue(saved.Message__c.contains('No_Such_Object__c'), saved.Message__c);
			Assert.isTrue(saved.Answers__c.contains('pat.zzform@example.org'), 'Answers kept');
			Assert.isNull(saved.Person__c, 'No person recorded');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Contact WHERE LastName = 'Zzform' WITH USER_MODE],
				'The person written first was rolled back'
			);
		}
	}

	@IsTest
	static void aModuleThatRefusesLeavesTheSubmissionForReview() {
		System.runAs(admin()) {
			Account gala = AccountKindsTestData.organization('Zzform Spring Gala');
			insert as user gala;
			FormsTestModule.register();
			FormsTestModule.fail = true;
			Map<String, Object> answers = pat();
			answers.remove('employer');

			Test.startTest();
			FormSubmitService.Result result = submit(
				FormsTestData.volunteerInterest().Id,
				answers,
				gala.Id
			);
			Test.stopTest();

			Assert.areEqual(FormSubmitService.NEEDS_REVIEW, result.status);
			Assert.isTrue(result.message.contains('Registration closed'), result.message);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Contact WHERE LastName = 'Zzform' WITH USER_MODE],
				'The person stays'
			);
		}
	}

	@IsTest
	static void aFormThatIsNotPublishedCannotBeFilledIn() {
		System.runAs(admin()) {
			Form__c draft = new Form__c(Name = 'Draft', Status__c = 'Draft');
			insert as user draft;
			try {
				submit(draft.Id, pat(), null);
				Assert.fail('A draft is refused');
			} catch (FormSubmitService.FormException expected) {
				Assert.isTrue(String.isNotBlank(expected.getMessage()), 'Said in plain words');
			}
		}
	}
}
