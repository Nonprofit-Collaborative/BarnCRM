/**
 * A module's public page, such as an event's, is served on the Site page and the REST API with
 * its form only while that form is published and public; otherwise the page shows no form and
 * the module's offline message. A record no module publishes has no page (EV-16; ADR-0190 public
 * event pages, decisions 4, 6 and 7).
 */
@IsTest(
	testFor='ApexClass:FormIntakeService, ApexClass:FormPublicController, ApexClass:FormPublicRest'
)
private class FormPublicPageTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(FormsTestData.ADMIN);
	}

	/** Publishes a page for accounts, naming a form, with registration open. */
	private class EventLikePage implements PublicPageExtension {
		Id formId;

		EventLikePage(Id formId) {
			this.formId = formId;
		}

		public String kind() {
			return 'events';
		}

		public Boolean handles(Schema.SObjectType recordType) {
			return recordType == Account.SObjectType;
		}

		public Map<String, Object> page(Id recordId) {
			return new Map<String, Object>{
				'title' => 'Spring Gala',
				'registration' => 'Open',
				'formId' => formId,
				'message' => 'Register below.',
				'offlineMessage' => 'Not taken online.',
				'signed' => PublicPageExtensions.isSignedRequest()
			};
		}

		public Map<String, Object> listPage() {
			return new Map<String, Object>{
				'title' => 'Upcoming Events',
				'items' => new List<Object>()
			};
		}
	}

	/** A module whose page and list carry a value that cannot be sent as JSON. */
	private class UnsendablePage implements PublicPageExtension {
		public String kind() {
			return 'events';
		}

		public Boolean handles(Schema.SObjectType recordType) {
			return recordType == Account.SObjectType;
		}

		public Map<String, Object> page(Id recordId) {
			return new Map<String, Object>{
				'title' => 'Spring Gala',
				'registration' => 'None',
				'detail' => Account.SObjectType
			};
		}

		public Map<String, Object> listPage() {
			return new Map<String, Object>{ 'detail' => Account.SObjectType };
		}
	}

	private static Id venue() {
		Account record = new Account(Name = 'Grange Hall');
		insert as user record;
		return record.Id;
	}

	private static Map<String, Object> parsed(String body) {
		return (Map<String, Object>) JSON.deserializeUntyped(body);
	}

	@IsTest
	static void aPublicFormIsShownOnThePage() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			PublicPageExtensions.useForTest(new EventLikePage(form.Id));

			Map<String, Object> page = parsed(FormPublicController.getPage(venue()));

			Assert.areEqual('Spring Gala', page.get('title'));
			Assert.areEqual(String.valueOf(form.Id), page.get('formId'), 'The form is shown');
			Assert.areEqual('Open', page.get('registration'));
			Assert.isFalse(page.containsKey('offlineMessage'), 'Used by Forms only');
		}
	}

	/** V-09: a page for a person's own record is told the claim was checked, and only when right. */
	@IsTest
	static void aSignedAddressIsCheckedBeforeThePageIsTold() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			PublicPageExtensions.useForTest(new EventLikePage(form.Id));
			FormsTestModule.register();
			FormsTestModule.signed = true;
			FormsTestModule.attachedFormId = form.Id;
			Id recordId = venue();
			String claim = FormIntakeService.claimFor(form.Id, recordId);

			Map<String, Object> right = parsed(
				FormPublicController.getPage(recordId + '.' + claim)
			);
			Map<String, Object> wrong = parsed(
				FormPublicController.getPage(recordId + '.' + claim.reverse())
			);
			Map<String, Object> plain = parsed(FormPublicController.getPage(recordId));

			Assert.isTrue((Boolean) right.get('signed'), 'The right claim');
			Assert.isFalse((Boolean) wrong.get('signed'), 'A wrong claim');
			Assert.isFalse((Boolean) plain.get('signed'), 'No claim');
		}
	}

	@IsTest
	static void aFormThatIsNotPublicIsNotShown() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.volunteerInterest();
			PublicPageExtensions.useForTest(new EventLikePage(form.Id));

			Map<String, Object> page = parsed(FormIntakeService.publicPage(venue()));

			Assert.isNull(page.get('formId'), 'Not public: no form');
			Assert.areEqual('None', page.get('registration'));
			Assert.areEqual('Not taken online.', page.get('message'));
			Assert.isNull(FormPublicController.getPage('not an id'), 'No such record');
			Assert.isNull(FormPublicController.getPage(UserInfo.getUserId()), 'Not published');
		}
	}

	@IsTest
	static void aPageThatCannotBeSentFailsWithThePublicMessageAndIsLogged() {
		System.runAs(admin()) {
			PublicPageExtensions.useForTest(new UnsendablePage());
			Id recordId = venue();
			List<String> said = new List<String>();

			Test.startTest();
			try {
				FormPublicController.getPage(recordId);
			} catch (AuraHandledException e) {
				said.add(e.getMessage());
			}
			try {
				FormPublicController.listPages('events');
			} catch (AuraHandledException e) {
				said.add(e.getMessage());
			}
			Test.stopTest();

			String message = BarnHelp.text('Forms', 'Forms_Public_Failed');
			Assert.areEqual(new List<String>{ message, message }, said, 'Nothing internal shown');
			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c LIKE 'FormPublicController.%'
				],
				'Each failure is logged for the admin'
			);
		}
	}

	@IsTest
	static void aFormLinkThatNamesNoFormShowsNothing() {
		System.runAs(admin()) {
			Assert.isNull(FormPublicController.getForm('not an id', null), 'Not an id');
			Assert.isNull(
				FormPublicController.getForm(UserInfo.getUserId(), null),
				'An id, but not a form'
			);
		}
	}

	@IsTest
	static void theApiServesThePageAndTheList() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			PublicPageExtensions.useForTest(new EventLikePage(form.Id));
			Id recordId = venue();
			RestContext.request = new RestRequest();
			RestContext.response = new RestResponse();
			RestContext.request.requestURI = '/barncrm/forms/v1/pages/' + recordId;
			FormPublicRest.getForm();
			Assert.areEqual(200, RestContext.response.statusCode, 'The page is served');
			Assert.areEqual(
				String.valueOf(form.Id),
				parsed(RestContext.response.responseBody.toString()).get('formId')
			);

			RestContext.response = new RestResponse();
			RestContext.request.requestURI = '/barncrm/forms/v1/pages';
			RestContext.request.addParameter('kind', 'events');
			FormPublicRest.getForm();
			Assert.areEqual(200, RestContext.response.statusCode, 'The list is served');
			Assert.areEqual(
				'Upcoming Events',
				parsed(RestContext.response.responseBody.toString()).get('title')
			);
			Assert.isNotNull(FormPublicController.listPages('events'));

			RestContext.response = new RestResponse();
			RestContext.request.addParameter('kind', 'volunteers');
			FormPublicRest.getForm();
			Assert.areEqual(404, RestContext.response.statusCode, 'No such list');
		}
	}
}
