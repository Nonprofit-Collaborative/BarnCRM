/**
 * Someone with no login fills in a public form (canonical model R-FS5, R-FS6; ADR-0184 public
 * forms on a Salesforce Site): a script that fills the hidden question, sends too fast, forges
 * the ticket or sends too often stores nothing; good answers are stored as Received and Public,
 * with nothing about any record coming back; processing then finds the person on file and only
 * fills their blanks; a signed-in caller is processed at once.
 */
@IsTest(
	testFor='ApexClass:FormIntakeService, ApexClass:FormPublicController, ApexClass:FormPublicRest, ApexClass:FormSubmitService'
)
private class FormIntakeServiceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(FormsTestData.ADMIN);
	}

	/** Answers sent with no files and no resume token. */
	private static FormIntakeService.Receipt submit(
		String ticket,
		Map<String, Object> answers,
		String trap,
		String contextRecordId
	) {
		return FormIntakeService.submit(ticket, answers, trap, contextRecordId, null, null);
	}

	private static Map<String, Object> sam() {
		return new Map<String, Object>{
			'first' => 'Sam',
			'last' => 'Zzpublic',
			'email' => 'sam.zzpublic@example.org',
			'postal' => '54321'
		};
	}

	private static List<Form_Submission__c> submissions() {
		return [
			SELECT Id, Status__c, Source__c, Person__c, Message__c, Context_Record_Id__c
			FROM Form_Submission__c
			WITH USER_MODE
		];
	}

	/** Loads the form and waits long enough to send, as a person would. */
	private static String ticketAfterWaiting(Id formId) {
		FormIntakeService.PublicForm view = FormIntakeService.load(formId);
		FormIntakeService.clockShiftMs = 10000;
		return view.ticket;
	}

	@IsTest
	static void aPublicFormLoadsWithoutItsRecordsOrTargets() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			FormIntakeService.PublicForm view = FormPublicController.getForm(form.Id, null);
			Assert.isNotNull(view, 'The public form loads');
			Assert.isFalse(view.definition.contains('records'), 'No records are published');
			Assert.isFalse(view.definition.contains('LastName'), 'No field names are published');
			Assert.areEqual(
				3,
				view.ticket.split(':').size(),
				'The ticket is version, time, signature'
			);
			Assert.isNull(
				FormPublicController.getForm('not an id', null),
				'Nonsense finds nothing'
			);
			Assert.isNull(
				FormPublicController.getForm(FormsTestData.volunteerInterest().Id, null),
				'A form that is not public is not served'
			);
		}
	}

	@IsTest
	static void scriptsAreStoppedBeforeAnythingIsStored() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			FormIntakeService.actAsGuest = true;
			String ticket = FormIntakeService.load(form.Id).ticket;

			Assert.areEqual(
				FormIntakeService.RETRY,
				submit(ticket, sam(), null, null).status,
				'Sent in under three seconds: asked to send again'
			);
			Assert.areEqual(
				FormIntakeService.RECEIVED,
				submit(ticket, sam(), 'http://spam.example', null).status,
				'The hidden question filled: told received'
			);
			FormIntakeService.clockShiftMs = 10000;
			Assert.areEqual(
				FormIntakeService.EXPIRED,
				submit(ticket.left(ticket.length() - 2) + 'xx', sam(), null, null).status,
				'A forged signature is refused'
			);
			Assert.areEqual(
				FormIntakeService.EXPIRED,
				submit(
						ticket.substringBeforeLast(':') +
							':' +
							ticket.substringAfterLast(':').swapCase(),
						sam(),
						null,
						null
					)
					.status,
				'A signature in other letter case is refused'
			);
			Assert.areEqual(
				FormIntakeService.EXPIRED,
				submit('nonsense', sam(), null, null).status,
				'Something that is not a ticket is refused'
			);
			FormIntakeService.clockShiftMs = 25L * 60 * 60 * 1000;
			Assert.areEqual(
				FormIntakeService.EXPIRED,
				submit(ticket, sam(), null, null).status,
				'A ticket over a day old is refused'
			);
			Assert.isTrue(submissions().isEmpty(), 'Nothing was stored');
		}
	}

	@IsTest
	static void goodAnswersAreStoredAndTheRateLimitHolds() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(1);
			FormIntakeService.actAsGuest = true;
			String ticket = ticketAfterWaiting(form.Id);

			FormIntakeService.Receipt bad = submit(
				ticket,
				new Map<String, Object>{ 'email' => 'not an email' },
				null,
				null
			);
			Assert.areEqual(FormIntakeService.INVALID, bad.status, 'Bad answers are refused');
			Assert.isTrue(bad.problems.containsKey('last'), 'The missing last name is named');

			FormIntakeService.Receipt good = submit(ticket, sam(), '', '');
			Assert.areEqual(FormIntakeService.RECEIVED, good.status, 'Stored');
			Assert.areEqual('Thanks for signing up.', good.message, 'The form says thank you');
			Assert.isFalse(JSON.serialize(good).contains('003'), 'No record identifier comes back');
			List<Form_Submission__c> stored = submissions();
			Assert.areEqual(1, stored.size(), 'One submission');
			Assert.areEqual('Received', stored[0].Status__c, 'Waiting for processing');
			Assert.areEqual('Public', stored[0].Source__c, 'From the public form');
			Assert.isNull(stored[0].Person__c, 'Nobody was matched by the guest');

			Assert.areEqual(
				FormIntakeService.BUSY,
				submit(ticket, sam(), null, null).status,
				'Over the hourly limit: asked to try later'
			);
		}
	}

	@IsTest
	static void processingFindsThePersonAndOnlyFillsTheirBlanks() {
		System.runAs(admin()) {
			AccountKindsTestData.useRecordTypeTheUserCanUse();
			Contact onFile = TestDataFactory.person(
				new Contact(
					FirstName = 'Sam',
					LastName = 'Zzpublic',
					Email = 'sam.zzpublic@example.org',
					MailingPostalCode = '11111'
				)
			);
			insert as user onFile;
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			FormIntakeService.actAsGuest = true;
			submit(ticketAfterWaiting(form.Id), sam(), null, null);
			Id submissionId = submissions()[0].Id;

			Test.startTest();
			FormSubmitService.Result result = FormSubmitService.processReceived(submissionId);
			Test.stopTest();

			Assert.areEqual(
				FormSubmitService.PROCESSED,
				result.status,
				'Processed: ' + result.message
			);
			Contact after = [
				SELECT MailingPostalCode
				FROM Contact
				WHERE Id = :onFile.Id
				WITH USER_MODE
			];
			Assert.areEqual('11111', after.MailingPostalCode, 'What is on file is kept');
			Assert.areEqual(onFile.Id, submissions()[0].Person__c, 'Matched, not duplicated');
		}
	}

	@IsTest
	static void aRecordThatDoesNotUseTheFormIsHeld() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			Account gala = AccountKindsTestData.organization('Zzpublic Gala');
			insert as user gala;
			FormIntakeService.actAsGuest = true;
			submit(ticketAfterWaiting(form.Id), sam(), null, gala.Id);

			FormSubmitService.Result result = FormSubmitService.processReceived(
				submissions()[0].Id
			);

			Assert.areEqual(FormSubmitService.NEEDS_REVIEW, result.status, 'Held');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Contact WHERE LastName = 'Zzpublic' WITH USER_MODE],
				'Nobody was written'
			);
		}
	}

	@IsTest
	static void aRecordThatNeedsASignedClaimIsClosedWithoutOne() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			Account gala = AccountKindsTestData.organization('Zzpublic Gala');
			insert as user gala;
			FormsTestModule.register();
			FormsTestModule.signed = true;
			FormsTestModule.attachedFormId = form.Id;
			FormIntakeService.actAsGuest = true;
			String claim = FormIntakeService.claimFor(form.Id, gala.Id);
			Assert.isNotNull(claim, 'A public form signs a claim');

			String ticket = ticketAfterWaiting(form.Id);
			Assert.areEqual(
				FormIntakeService.CLOSED,
				submit(ticket, sam(), null, gala.Id).status,
				'No signature'
			);
			Assert.areEqual(
				FormIntakeService.CLOSED,
				submit(ticket, sam(), null, gala.Id + '.' + claim.reverse()).status,
				'A wrong signature'
			);
			Assert.areEqual(
				FormIntakeService.CLOSED,
				submit(ticket, sam(), null, gala.Id + '.').status,
				'An empty signature'
			);
			Assert.areEqual(
				FormIntakeService.CLOSED,
				submit(ticket, sam(), null, gala.Id + '.' + claim.swapCase()).status,
				'The signature in other letter case'
			);
			Assert.areEqual(0, submissions().size(), 'Nothing was stored');

			Assert.areEqual(
				FormIntakeService.RECEIVED,
				submit(ticket, sam(), null, gala.Id + '.' + claim).status,
				'The right signature'
			);
			Assert.areEqual(gala.Id, Id.valueOf(submissions()[0].Context_Record_Id__c));
		}
	}

	@IsTest
	static void aSignedInCallerIsProcessedAtOnceThroughRest() {
		System.runAs(admin()) {
			AccountKindsTestData.useRecordTypeTheUserCanUse();
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			RestContext.request = new RestRequest();
			RestContext.response = new RestResponse();
			RestContext.request.requestURI = '/barncrm/forms/v1/' + form.Id;
			FormPublicRest.getForm();
			Assert.areEqual(200, RestContext.response.statusCode, 'The form is served');
			Map<String, Object> view = (Map<String, Object>) JSON.deserializeUntyped(
				RestContext.response.responseBody.toString()
			);
			FormIntakeService.clockShiftMs = 10000;

			RestContext.response = new RestResponse();
			RestContext.request.requestBody = Blob.valueOf(
				JSON.serialize(
					new Map<String, Object>{ 'ticket' => view.get('ticket'), 'answers' => sam() }
				)
			);
			FormPublicRest.submit();

			Assert.isTrue(
				RestContext.response.responseBody.toString().contains('Received'),
				'Received'
			);
			Assert.areEqual('Processed', submissions()[0].Status__c, 'Processed as the caller');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Contact WHERE LastName = 'Zzpublic' WITH USER_MODE],
				'The person was added'
			);

			RestContext.response = new RestResponse();
			RestContext.request.requestBody = Blob.valueOf('[1]');
			FormPublicRest.submit();
			Assert.areEqual(400, RestContext.response.statusCode, 'Not an object');
			RestContext.request.requestURI = '/barncrm/forms/v1/nothing';
			FormPublicRest.getForm();
			Assert.areEqual(404, RestContext.response.statusCode, 'No such form');
		}
	}

	/** A failure inside the REST API is logged and answered Failed, never as an exception. */
	@IsTest
	static void aRestFailureIsLoggedAndAnsweredFailed() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			RestContext.request = new RestRequest();
			RestContext.request.requestURI = '/barncrm/forms/v1/' + form.Id;
			RestContext.request.requestBody = Blob.valueOf('{"ticket":"x","answers":{}}');
			FormPublicRest.failureForTest = new System.IllegalArgumentException('Zzrest broke');

			Test.startTest();
			RestContext.response = new RestResponse();
			FormPublicRest.submit();
			RestResponse posted = RestContext.response;
			RestContext.response = new RestResponse();
			FormPublicRest.getForm();
			RestResponse got = RestContext.response;
			Test.stopTest();

			for (RestResponse answer : new List<RestResponse>{ posted, got }) {
				Assert.areEqual(500, answer.statusCode, 'A server failure');
				Assert.areEqual(
					'{"status":"Failed"}',
					answer.responseBody.toString(),
					'Only Failed, no exception text'
				);
			}
			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c IN ('FormPublicRest.submit', 'FormPublicRest.getForm')
					WITH SYSTEM_MODE
				],
				'Both are in the Error Log'
			);
		}
	}

	@IsTest
	static void theControllerSendsAnswers() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			FormIntakeService.actAsGuest = true;
			String ticket = ticketAfterWaiting(form.Id);
			FormIntakeService.Receipt receipt = FormPublicController.submit(
				ticket,
				JSON.serialize(sam()),
				'',
				null,
				null,
				null
			);
			Assert.areEqual(FormIntakeService.RECEIVED, receipt.status, 'Received');
			update as user new Form__c(Id = form.Id, Status__c = 'Closed');
			Assert.areEqual(
				FormIntakeService.CLOSED,
				FormPublicController.submit(ticket, '{}', '', null, null, null).status,
				'A closed form takes nothing'
			);
		}
	}
}
