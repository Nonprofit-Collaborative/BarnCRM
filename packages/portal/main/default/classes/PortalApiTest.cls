/**
 * The portal client's whole conversation through the REST API: sign in, read the menu and a
 * page, save, sign out; and the error codes and statuses it gets back.
 */
@IsTest(testFor='ApexClass:PortalApi')
private class PortalApiTest {
	private static final String EMAIL = 'pat.zzapi@example.org';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Portal_Admin');
	}

	private static Map<String, Object> call(
		String method,
		String route,
		Map<String, Object> body,
		String token
	) {
		RestRequest request = new RestRequest();
		request.requestURI = '/services/apexrest/barncrm/portal/v1/' + route;
		request.httpMethod = method;
		if (route.contains('?')) {
			request.addParameter(
				route.substringAfter('?').substringBefore('='),
				route.substringAfter('=')
			);
		}
		if (body != null) {
			request.requestBody = Blob.valueOf(JSON.serialize(body));
		}
		if (token != null) {
			request.addHeader(PortalApi.SESSION_HEADER, token);
		}
		RestContext.request = request;
		RestContext.response = new RestResponse();
		if (method == 'GET') {
			PortalApi.doGet();
		} else {
			PortalApi.doPost();
		}
		Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(
			RestContext.response.responseBody.toString()
		);
		result.put('httpStatus', RestContext.response.statusCode);
		return result;
	}

	@IsTest
	static void signsInReadsSavesAndSignsOut() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();
			Portal__c portal = PortalTestData.portal('Invited', 'Off');
			Contact pat = PortalTestData.person('Zzapi', EMAIL);
			PortalTestData.access(portal, pat);

			Test.startTest();
			Map<String, Object> started = call(
				'POST',
				'login/start',
				new Map<String, Object>{ 'portal' => PortalTestData.KEY, 'email' => EMAIL },
				null
			);
			Map<String, Object> verified = call(
				'POST',
				'login/verify',
				new Map<String, Object>{
					'challenge' => started.get('challenge'),
					'code' => PortalAuth.lastCodeForTest
				},
				null
			);
			String token = (String) verified.get('session');
			Map<String, Object> me = call('GET', 'me', null, token);
			Map<String, Object> page = call('GET', 'page?key=profile', null, token);
			Map<String, Object> saved = call(
				'POST',
				'page/save',
				new Map<String, Object>{
					'page' => 'profile',
					'recordId' => pat.Id,
					'values' => new Map<String, Object>{ 'Description' => 'Prefers mornings' }
				},
				token
			);
			Map<String, Object> out = call('POST', 'logout', new Map<String, Object>(), token);
			Map<String, Object> afterOut = call('GET', 'me', null, token);
			Test.stopTest();

			Assert.areEqual(true, started.get('ok'), 'Started');
			Assert.areEqual('signedIn', verified.get('status'), 'Signed in');
			Assert.areEqual('Pat', me.get('firstName'), 'The menu greets the person');
			Assert.areEqual('profile', page.get('key'), 'The page');
			Assert.areEqual(pat.Id, saved.get('id'), 'Saved');
			Assert.areEqual(true, out.get('ok'), 'Signed out');
			Assert.areEqual(401, afterOut.get('httpStatus'), 'Then refused');
			Assert.areEqual('not_signed_in', afterOut.get('error'), 'With its code');
			Assert.areEqual(
				'Prefers mornings',
				[SELECT Description FROM Contact WHERE Id = :pat.Id].Description,
				'The change is in Salesforce'
			);
		}
	}

	@IsTest
	static void answersErrorsWithShortCodes() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();

			Test.startTest();
			Map<String, Object> noPortal = call(
				'POST',
				'login/start',
				new Map<String, Object>{ 'portal' => 'missing', 'email' => EMAIL },
				null
			);
			Map<String, Object> noSession = call('GET', 'me', null, null);
			RestContext.request = new RestRequest();
			RestContext.request.requestURI = '/services/apexrest/barncrm/portal/v1/login/start';
			RestContext.request.requestBody = Blob.valueOf('not json');
			RestContext.response = new RestResponse();
			PortalApi.doPost();
			Integer badBody = RestContext.response.statusCode;
			Test.stopTest();

			Assert.areEqual(503, noPortal.get('httpStatus'), 'An unknown portal is unavailable');
			Assert.areEqual('portal_unavailable', noPortal.get('error'), 'With its code');
			Assert.areEqual(401, noSession.get('httpStatus'), 'No session');
			Assert.areEqual(400, badBody, 'A body that is not JSON');
			Assert.areEqual(
				'login/start',
				PortalApi.routeOf('/services/apexrest/barncrm/portal/v1/login/start/'),
				'Route'
			);
		}
	}
}
