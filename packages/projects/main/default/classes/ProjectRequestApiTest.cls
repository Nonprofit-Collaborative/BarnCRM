/**
 * The request intake API (D-201): refused while Take requests from outside is off or for an org
 * id the calling user has no Active connection for; a new request answers 201 and the same
 * reference again answers 200 without a second request; the hourly limit answers 429; status
 * comes back by reference; an oversized or malformed body answers 400. Calls run as an
 * integration user holding only Projects Request Intake, as in an org.
 */
@IsTest(testFor='ApexClass:ProjectRequestApi')
private class ProjectRequestApiTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static User intake() {
		return TestUsers.minimumAccessUserWith(
			'Intake',
			new List<String>{ 'Projects_Request_Intake' }
		);
	}

	/** Turns requests on (and outside requests when asked) and connects the caller. */
	private static void connect(User caller, Boolean external, Integer hourlyLimit) {
		System.runAs(ProjectsTestData.admin()) {
			SettingsService.saveValues(
				'Projects_Settings__c',
				new Map<String, Object>{
					'Requests_Enabled__c' => true,
					'Requests_External_Enabled__c' => external
				}
			);
			insert new Request_Connection__c(
				Name = 'Partner Org',
				Org_Id__c = UserInfo.getOrganizationId(),
				Integration_User__c = caller.Id,
				Hourly_Limit__c = hourlyLimit
			);
		}
	}

	private static Integer post(String body) {
		RestRequest request = new RestRequest();
		request.requestURI = '/barncrm/requests/v1/requests';
		request.httpMethod = 'POST';
		request.requestBody = body == null ? null : Blob.valueOf(body);
		RestContext.request = request;
		RestContext.response = new RestResponse();
		ProjectRequestApi.submit();
		return RestContext.response.statusCode;
	}

	private static String send(String reference, String orgId) {
		return JSON.serialize(
			new Map<String, Object>{
				'orgId' => orgId,
				'reference' => reference,
				'subject' => 'Export fails for ' + reference,
				'description' => 'Every export since Monday',
				'priority' => 'High',
				'type' => 'Not a type',
				'requesterName' => 'Pat Partner',
				'requesterEmail' => 'pat@example.org'
			}
		);
	}

	private static Map<String, Object> answer() {
		return (Map<String, Object>) JSON.deserializeUntyped(
			RestContext.response.responseBody.toString()
		);
	}

	@IsTest
	static void refusedWhileOffOrForAnotherOrg() {
		User caller = intake();
		connect(caller, false, 60);
		System.runAs(caller) {
			Assert.areEqual(403, post(send('A-1', UserInfo.getOrganizationId())), 'Off');
			Assert.areEqual('not_allowed', answer().get('error'), 'Short code');
		}
		System.runAs(ProjectsTestData.admin()) {
			SettingsService.saveValues(
				'Projects_Settings__c',
				new Map<String, Object>{ 'Requests_External_Enabled__c' => true }
			);
		}
		System.runAs(caller) {
			Assert.areEqual(403, post(send('A-1', '00D000000000001')), 'Another org');
			Assert.areEqual(403, post(send('A-1', 'not-an-id')), 'Not an id');
		}
		Assert.areEqual(0, [SELECT COUNT() FROM Project_Request__c], 'Nothing saved');
	}

	@IsTest
	static void aNewRequestThenTheSameOneAgain() {
		User caller = intake();
		connect(caller, true, 60);
		System.runAs(caller) {
			Assert.areEqual(201, post(send('A-2', UserInfo.getOrganizationId())), 'Created');
			Assert.areEqual('A-2', answer().get('reference'), 'Their reference');
			Assert.areEqual('New', answer().get('status'), 'New');
			Assert.areEqual(200, post(send('A-2', UserInfo.getOrganizationId())), 'Found again');
		}
		System.runAs(ProjectsTestData.admin()) {
			Project_Request__c saved = [
				SELECT Channel__c, Type__c, Priority__c, Description__c, OwnerId, Connection__c
				FROM Project_Request__c
			];
			Assert.areEqual(ProjectRequestHandler.PARTNER, saved.Channel__c, 'Partner channel');
			Assert.areEqual('Service Request', saved.Type__c, 'Unknown type falls back');
			Assert.areEqual('High', saved.Priority__c, 'Known priority kept');
			Assert.isTrue(saved.Description__c.contains('pat@example.org'), 'Who asked');
			Assert.areEqual(
				ProjectsTestData.requestsQueueId(),
				saved.OwnerId,
				'Lands in the Requests queue'
			);
			Assert.isNotNull(saved.Connection__c, 'Connection linked');
		}
	}

	@IsTest
	static void theHourlyLimitAndStatus() {
		User caller = intake();
		connect(caller, true, 1);
		String org = UserInfo.getOrganizationId();
		System.runAs(caller) {
			Assert.areEqual(201, post(send('B-1', org)), 'First');
			Assert.areEqual(429, post(send('B-2', org)), 'Over the hourly limit');

			RestRequest request = new RestRequest();
			request.requestURI = '/barncrm/requests/v1/requests';
			request.httpMethod = 'GET';
			request.addParameter('orgId', org);
			request.addParameter('refs', 'B-1, B-2,');
			RestContext.request = request;
			RestContext.response = new RestResponse();
			ProjectRequestApi.status();
			Assert.areEqual(200, RestContext.response.statusCode, 'Status');
			List<Object> found = (List<Object>) answer().get('requests');
			Assert.areEqual(1, found.size(), 'Only B-1 exists');
			Assert.areEqual('B-1', ((Map<String, Object>) found[0]).get('reference'), 'B-1');
		}
	}

	@IsTest
	static void malformedBodiesAreRefused() {
		User caller = intake();
		connect(caller, true, 60);
		System.runAs(caller) {
			Assert.areEqual(400, post(null), 'No body');
			Assert.areEqual(400, post('x'.repeat(ProjectRequestApi.MAX_BYTES + 1)), 'Too large');
			Assert.areEqual(400, post('[1, 2]'), 'Not an object');
			Assert.areEqual(400, post('{not json'), 'Not JSON');
			Assert.areEqual(
				400,
				post(
					JSON.serialize(
						new Map<String, Object>{ 'orgId' => UserInfo.getOrganizationId() }
					)
				),
				'No reference or subject'
			);
		}
		Assert.areEqual(0, [SELECT COUNT() FROM Project_Request__c], 'Nothing saved');
	}
}
