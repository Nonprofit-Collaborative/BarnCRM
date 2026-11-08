/**
 * Files on forms and answers saved for later (canonical model R-FS7; ADR-0184 public forms on a
 * Salesforce Site, decision 11): a file answered is kept on the submission and shared with the
 * person written; a file missing, of the wrong kind or too large is refused; saved answers are
 * found only by their emailed token, open the version they answer, are forgotten once sent, and
 * are deleted when their link expires.
 */
@IsTest(
	testFor='ApexClass:FormFiles, ApexClass:FormIntakeService, ApexClass:FormPublicController, ApexClass:FormPublicRest, ApexClass:FormPublicProcessor'
)
private class FormFilesTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static Map<String, Object> lee(String fileName) {
		Map<String, Object> answers = new Map<String, Object>{
			'first' => 'Lee',
			'last' => 'Zzfiles',
			'email' => 'lee.zzfiles@example.org'
		};
		if (fileName != null) {
			answers.put('cv', fileName);
		}
		return answers;
	}

	private static Map<String, Object> fileOf(String name, String text) {
		return new Map<String, Object>{
			'cv' => new Map<String, Object>{
				'name' => name,
				'data' => EncodingUtil.base64Encode(Blob.valueOf(text))
			}
		};
	}

	private static String ticketAfterWaiting(Id formId) {
		String ticket = FormIntakeService.load(formId).ticket;
		FormIntakeService.clockShiftMs = 10000;
		return ticket;
	}

	private static void useSite() {
		FormsSites.SiteInfo site = new FormsSites.SiteInfo();
		site.name = 'Zzforms Site';
		site.url = 'https://zzforms.example.org';
		FormsSites.testSites = new List<FormsSites.SiteInfo>{ site };
	}

	@IsTest
	static void aFileIsKeptOnTheSubmissionAndSharedWithThePerson() {
		System.runAs(admin()) {
			AccountKindsTestData.useRecordTypeTheUserCanUse();
			Form__c form = FormsTestData.publicWithFileAndSaving();
			FormIntakeService.actAsGuest = true;
			FormIntakeService.Receipt receipt = FormIntakeService.submit(
				ticketAfterWaiting(form.Id),
				lee('cv.pdf'),
				null,
				null,
				fileOf('cv.pdf', 'my resume'),
				null
			);
			Assert.areEqual(FormIntakeService.RECEIVED, receipt.status, 'Received');
			Form_Submission__c stored = [SELECT Id FROM Form_Submission__c WITH USER_MODE];
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM ContentDocumentLink
					WHERE LinkedEntityId = :stored.Id
					WITH USER_MODE
				],
				'Kept on the submission'
			);

			FormSubmitService.Result result = FormSubmitService.processReceived(stored.Id);
			Id person = [SELECT Person__c FROM Form_Submission__c WITH USER_MODE].Person__c;
			Assert.isNotNull(person, 'Processed: ' + result.message);
			FormFiles.share(stored.Id, new List<Id>{ person, null });
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM ContentDocumentLink
					WHERE LinkedEntityId = :person
					WITH USER_MODE
				],
				'Shared with the person once'
			);
		}
	}

	@IsTest
	static void aMissingWrongOrLargeFileIsRefused() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicWithFileAndSaving();
			FormIntakeService.actAsGuest = true;
			String ticket = ticketAfterWaiting(form.Id);
			Assert.areEqual(
				'badFileType',
				FormIntakeService.submit(ticket, lee('page.html'), null, null, null, null)
					.problems.get('cv'),
				'A page is not a document'
			);
			Assert.areEqual(
				'fileMissing',
				FormIntakeService.submit(ticket, lee('cv.pdf'), null, null, null, null)
					.problems.get('cv'),
				'Named but not sent'
			);
			Assert.areEqual(
				'fileMissing',
				FormIntakeService.submit(
						ticket,
						lee('cv.pdf'),
						null,
						null,
						fileOf('other.pdf', 'x'),
						null
					)
					.problems.get('cv'),
				'Sent under another name'
			);
			String large = 'x'.repeat(FormFiles.MAX_BYTES + 1);
			Assert.areEqual(
				'fileTooLarge',
				FormIntakeService.submit(
						ticket,
						lee('cv.pdf'),
						null,
						null,
						fileOf('cv.pdf', large),
						null
					)
					.problems.get('cv'),
				'Too large'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Form_Submission__c WITH USER_MODE],
				'Nothing stored'
			);
		}
	}

	@IsTest
	static void theStaffRunnerKeepsAFile() {
		System.runAs(admin()) {
			AccountKindsTestData.useRecordTypeTheUserCanUse();
			Form__c form = FormsTestData.publicWithFileAndSaving();
			FormSubmitService.Result result = FormRunnerController.submit(
				form.Id,
				JSON.serialize(lee('cv.txt')),
				null,
				JSON.serialize(fileOf('cv.txt', 'notes'))
			);
			Assert.areEqual(
				FormSubmitService.PROCESSED,
				result.status,
				'Processed: ' + result.message
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM ContentDocumentLink
					WHERE LinkedEntityId = :result.submissionId
					WITH USER_MODE
				],
				'Kept on the submission'
			);
		}
	}

	@IsTest
	static void answersAreSavedAndAnEmailedLinkIsSent() {
		System.runAs(admin()) {
			useSite();
			Form__c form = FormsTestData.publicWithFileAndSaving();
			FormIntakeService.actAsGuest = true;
			String ticket = ticketAfterWaiting(form.Id);
			Assert.areEqual(
				'badEmail',
				FormPublicController.saveDraft(ticket, '{"last":"Zzlater"}', '', 'nope', 0)
					.problems.get(FormIntakeService.SAVE_KEY),
				'An email address is needed'
			);
			Assert.areEqual(
				FormIntakeService.SAVED,
				FormIntakeService.saveDraft(ticket, lee(null), 'bot', 'a@example.org', 0).status,
				'A script is told it was saved'
			);

			FormIntakeService.Receipt receipt = FormPublicController.saveDraft(
				ticket,
				JSON.serialize(lee('cv.pdf')),
				'',
				'lee.zzfiles@example.org',
				0
			);

			List<Form_Draft__c> drafts = [
				SELECT Token_Hash__c, Answers__c, Expires__c
				FROM Form_Draft__c
				WITH SYSTEM_MODE
			];
			if (receipt.status == FormIntakeService.FAILED) {
				// The org cannot send email: nothing is kept that no one could come back to.
				Assert.isTrue(drafts.isEmpty(), 'No draft without its email');
				return;
			}
			Assert.areEqual(FormIntakeService.SAVED, receipt.status, 'Saved');
			Assert.areEqual(1, drafts.size(), 'One draft');
			String token = FormIntakeService.lastLink.substringAfter('resume=');
			Assert.isTrue(
				FormIntakeService.lastLink.startsWith('https://zzforms.example.org/FormsPublic'),
				'The link opens the Site page'
			);
			Assert.areNotEqual(token, drafts[0].Token_Hash__c, 'The token is not stored');
			Assert.areEqual(
				FormIntakeService.hashOf(token),
				drafts[0].Token_Hash__c,
				'Its hash is'
			);
			Assert.isFalse(drafts[0].Answers__c.contains('cv.pdf'), 'Files are not saved');
		}
	}

	@IsTest
	static void savedAnswersOpenTheirVersionAndAreForgottenOnceSent() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicWithFileAndSaving();
			Form_Version__c version = [
				SELECT Id
				FROM Form_Version__c
				WHERE Form__c = :form.Id
				WITH USER_MODE
			];
			// The intake inserts drafts in system mode; no permission set may create one.
			Database.insert(
				new Form_Draft__c(
					Form__c = form.Id,
					Form_Version__c = version.Id,
					Token_Hash__c = FormIntakeService.hashOf('zztoken'),
					Expires__c = Datetime.now().addDays(7),
					Answers__c = JSON.serialize(lee(null)),
					Step__c = 0
				),
				AccessLevel.SYSTEM_MODE
			);
			Assert.isNull(FormIntakeService.resume(form.Id, 'wrong'), 'Only the token finds it');
			Assert.isNull(
				FormPublicController.getForm(UserInfo.getUserId(), 'zztoken'),
				'Not a form'
			);
			FormIntakeService.PublicForm resumed = FormPublicController.getForm(form.Id, 'zztoken');
			Assert.isTrue(resumed.answers.contains('Zzfiles'), 'The saved answers');
			Assert.areEqual(0, resumed.step, 'The saved step');
			Assert.isTrue(resumed.canSave, 'Can be saved again');

			FormIntakeService.actAsGuest = true;
			FormIntakeService.clockShiftMs = 10000;
			FormIntakeService.Receipt receipt = FormPublicController.submit(
				resumed.ticket,
				resumed.answers,
				'',
				null,
				null,
				'zztoken'
			);
			Assert.areEqual(FormIntakeService.RECEIVED, receipt.status, 'Received');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Form_Draft__c WITH USER_MODE],
				'The draft is forgotten'
			);
			Assert.isNull(FormIntakeService.resume(form.Id, 'zztoken'), 'The link is used up');
		}
	}

	@IsTest
	static void expiredDraftsAreDeletedAndTheirLinksDoNotOpen() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicWithFileAndSaving();
			Form_Version__c version = [
				SELECT Id
				FROM Form_Version__c
				WHERE Form__c = :form.Id
				WITH USER_MODE
			];
			Database.insert(
				new Form_Draft__c(
					Form__c = form.Id,
					Form_Version__c = version.Id,
					Token_Hash__c = FormIntakeService.hashOf('zzold'),
					Expires__c = Datetime.now().addMinutes(-1),
					Answers__c = '{}'
				),
				AccessLevel.SYSTEM_MODE
			);
			Assert.isNull(FormIntakeService.resume(form.Id, 'zzold'), 'Expired');

			FormPublicProcessor.deleteExpiredDrafts();

			Assert.areEqual(0, [SELECT COUNT() FROM Form_Draft__c WITH USER_MODE], 'Deleted');
		}
	}

	@IsTest
	static void anApiCallerCanSaveAndResume() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicWithFileAndSaving();
			RestContext.request = new RestRequest();
			RestContext.response = new RestResponse();
			RestContext.request.requestURI = '/barncrm/forms/v1/' + form.Id;
			RestContext.request.params.put('resume', 'nothing');
			FormPublicRest.getForm();
			Assert.areEqual(404, RestContext.response.statusCode, 'An unknown link opens nothing');

			FormsSites.testSites = new List<FormsSites.SiteInfo>();
			RestContext.response = new RestResponse();
			RestContext.request.requestBody = Blob.valueOf(
				JSON.serialize(
					new Map<String, Object>{
						'ticket' => FormIntakeService.load(form.Id).ticket,
						'answers' => lee(null),
						'saveFor' => 'lee.zzfiles@example.org',
						'step' => 0
					}
				)
			);
			FormIntakeService.clockShiftMs = 10000;
			FormPublicRest.submit();
			Assert.isTrue(
				RestContext.response.responseBody.toString().contains(FormIntakeService.CLOSED),
				'With no Site there is nowhere for the link to go'
			);
		}
	}
}
