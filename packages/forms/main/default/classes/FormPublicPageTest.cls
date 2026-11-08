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
				'offlineMessage' => 'Not taken online.'
			};
		}

		public Map<String, Object> listPage() {
			return new Map<String, Object>{
				'title' => 'Upcoming Events',
				'items' => new List<Object>()
			};
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
