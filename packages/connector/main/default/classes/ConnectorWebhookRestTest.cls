/**
 * The webhook receiver (CN-04; canonical model R-CR10; design Sections 3.3 and 3.3a; security
 * review F13): the token in the header or the query, 404 with an empty body for anything else,
 * the body and hourly caps, duplicates by event id, the Received run it stores and the reply.
 */
@IsTest(testFor='ApexClass:ConnectorWebhookRest, ApexClass:ConnectorWebhooks, ApexClass:ConnectorRunStore')
private class ConnectorWebhookRestTest {
	private static final String STOP = '[{"id":"done","kind":"stop","outcome":"Succeeded","message":""}]';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	/** A published webhook recipe and its token. */
	private static String hookedRecipe(String triggerExtras, String status) {
		String document = '{"version":1,"trigger":{"kind":"webhook"' + triggerExtras + '},"steps":' + STOP + '}';
		Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
			'Gifts In ' + status,
			document,
			true,
			ConnectorRecipes.RUN_AS_AUTOMATION
		);
		String token = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
		recipe.Trigger_Kind__c = ConnectorWebhooks.WEBHOOK;
		recipe.Status__c = status;
		recipe.Webhook_Token_Hash__c = ConnectorWebhooks.hashOf(token);
		update as system recipe;
		return token;
	}

	private static RestRequest post(String body, String contentType) {
		RestRequest request = new RestRequest();
		request.httpMethod = 'POST';
		request.requestURI = '/services/apexrest/barncrm/connector/v1/hook';
		request.requestBody = body == null ? null : Blob.valueOf(body);
		if (contentType != null) {
			request.addHeader('Content-Type', contentType);
		}
		return request;
	}

	private static RestResponse receive(RestRequest request) {
		RestContext.request = request;
		RestContext.response = new RestResponse();
		ConnectorWebhookRest.receive();
		return RestContext.response;
	}

	private static List<Connector_Run__c> runs() {
		return [
			SELECT Status__c, Started_By__c, Input_JSON__c, Reference__c, Event_Key__c, Ran_As__c
			FROM Connector_Run__c
			WITH SYSTEM_MODE
			ORDER BY CreatedDate
		];
	}

	@IsTest
	static void theTokenInTheHeaderStoresOneReceivedRunAndRepliesAtOnce() {
		System.runAs(admin()) {
			String token = hookedRecipe('', ConnectorRunStore.ACTIVE);
			RestRequest request = post('{"amount":25,"email":"ada@example.org"}', 'application/json; charset=utf-8');
			request.addHeader('x-barncrm-token', token.toUpperCase());

			Test.startTest();
			RestResponse response = receive(request);
			Test.stopTest();

			Assert.areEqual(202, response.statusCode);
			List<Connector_Run__c> stored = runs();
			Assert.areEqual(1, stored.size());
			Assert.areEqual(ConnectorRunStore.RECEIVED, stored[0].Status__c);
			Assert.areEqual(ConnectorWebhooks.WEBHOOK, stored[0].Started_By__c);
			Assert.areEqual(ConnectorRecipes.RUN_AS_AUTOMATION, stored[0].Ran_As__c);
			Assert.areEqual(25, ((Map<String, Object>) JSON.deserializeUntyped(stored[0].Input_JSON__c)).get('amount'));
			Assert.areEqual(20, stored[0].Reference__c.length());
			Assert.areEqual(
				'{"received": true, "reference": "' + stored[0].Reference__c + '"}',
				response.responseBody.toString()
			);
			Assert.isFalse(stored[0].Input_JSON__c.contains(token), 'The token is never stored.');
		}
	}

	@IsTest
	static void theTokenInTheQueryIsAcceptedToo() {
		System.runAs(admin()) {
			String token = hookedRecipe('', ConnectorRunStore.ACTIVE);
			RestRequest request = post('{"a":1}', 'application/json');
			request.addParameter('token', token);

			RestResponse response = receive(request);

			Assert.areEqual(202, response.statusCode);
			Assert.areEqual(1, runs().size());
		}
	}

	@IsTest
	static void aMissingWrongOrUnpublishedTokenIs404WithAnEmptyBody() {
		System.runAs(admin()) {
			String token = hookedRecipe('', ConnectorRunStore.ACTIVE);
			String draftToken = hookedRecipe('', ConnectorRecipes.DRAFT);
			List<RestRequest> requests = new List<RestRequest>();
			requests.add(post('{"a":1}', 'application/json'));
			RestRequest wrong = post('{"a":1}', 'application/json');
			wrong.addHeader(ConnectorWebhooks.HEADER, token.reverse());
			requests.add(wrong);
			RestRequest malformed = post('{"a":1}', 'application/json');
			malformed.addParameter('token', 'not-a-token');
			requests.add(malformed);
			RestRequest draft = post('{"a":1}', 'application/json');
			draft.addHeader(ConnectorWebhooks.HEADER, draftToken);
			requests.add(draft);

			for (RestRequest request : requests) {
				RestResponse response = receive(request);
				Assert.areEqual(404, response.statusCode);
				Assert.isNull(response.responseBody, 'Nothing tells a caller a recipe exists.');
			}
			Assert.areEqual(0, runs().size(), 'Nothing stored.');
		}
	}

	@IsTest
	static void aPausedRecipeStillKeepsPosts() {
		System.runAs(admin()) {
			String token = hookedRecipe('', ConnectorRunStore.PAUSED);
			RestRequest request = post('{"a":1}', 'application/json');
			request.addHeader(ConnectorWebhooks.HEADER, token);

			Assert.areEqual(202, receive(request).statusCode);
			Assert.areEqual(1, runs().size());
			Assert.isTrue(
				ConnectorRunStore.queued(50, ConnectorRunStore.ALL_RUN_AS, false).isEmpty(),
				'Not run until Resume.'
			);
		}
	}

	@IsTest
	static void tooLargeUnreadableOrAnotherTypeIsRefused() {
		System.runAs(admin()) {
			String token = hookedRecipe('', ConnectorRunStore.ACTIVE);
			Map<Integer, RestRequest> expected = new Map<Integer, RestRequest>{
				413 => post('{"a":"' + 'x'.repeat(131072) + '"}', 'application/json'),
				400 => post('{not json', 'application/json'),
				415 => post('<a/>', 'application/xml')
			};
			for (Integer status : expected.keySet()) {
				RestRequest request = expected.get(status);
				request.addHeader(ConnectorWebhooks.HEADER, token);
				RestResponse response = receive(request);
				Assert.areEqual(status, response.statusCode);
				Assert.isNull(response.responseBody);
			}
			Assert.areEqual(0, runs().size());
		}
	}

	@IsTest
	static void formFieldsAreStoredAsTextWithoutTheToken() {
		System.runAs(admin()) {
			String token = hookedRecipe('', ConnectorRunStore.ACTIVE);
			RestRequest request = post(
				'first=Ada&amount=25&note=a%20b&token=' + token,
				'application/x-www-form-urlencoded'
			);

			Assert.areEqual(202, receive(request).statusCode);
			Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(runs()[0].Input_JSON__c);
			Assert.areEqual('Ada', input.get('first'));
			Assert.areEqual('a b', input.get('note'));
			Assert.isFalse(input.containsKey('token'), 'The token is never stored.');
		}
	}

	@IsTest
	static void aResendWithTheSameEventIdIsAnsweredAsTheFirstAndNotStored() {
		System.runAs(admin()) {
			String token = hookedRecipe(',"eventId":"trigger.id","reply":{"status":200}', ConnectorRunStore.ACTIVE);
			RestRequest first = post('{"id":"evt_1","amount":5}', 'application/json');
			first.addHeader(ConnectorWebhooks.HEADER, token);
			RestRequest again = post('{"id":"evt_1","amount":5}', 'application/json');
			again.addHeader(ConnectorWebhooks.HEADER, token);

			RestResponse one = receive(first);
			RestResponse two = receive(again);

			Assert.areEqual(200, one.statusCode);
			Assert.areEqual(200, two.statusCode);
			List<Connector_Run__c> stored = runs();
			Assert.areEqual(1, stored.size(), 'A resend is dropped.');
			Assert.isTrue(stored[0].Event_Key__c.endsWith(':evt_1'));
			Assert.areEqual(one.responseBody.toString(), two.responseBody.toString(), 'Same reference.');
		}
	}

	@IsTest
	static void pastTheHourlyCapIs429AndOneWarningIsWritten() {
		System.runAs(admin()) {
			String token = hookedRecipe('', ConnectorRunStore.ACTIVE);
			Connector_Recipe__c recipe = [SELECT Id FROM Connector_Recipe__c WITH SYSTEM_MODE LIMIT 1];
			recipe.Webhook_Hourly_Cap__c = 1;
			update as system recipe;
			RestRequest first = post('{"a":1}', 'application/json');
			first.addHeader(ConnectorWebhooks.HEADER, token);
			RestRequest second = post('{"a":2}', 'application/json');
			second.addHeader(ConnectorWebhooks.HEADER, token);

			Test.startTest();
			Assert.areEqual(202, receive(first).statusCode);
			RestResponse refused = receive(second);
			Test.stopTest();

			Assert.areEqual(429, refused.statusCode);
			Assert.isNull(refused.responseBody);
			Assert.areEqual(1, runs().size());
			Assert.isTrue(
				ConnectorRunStore.loggedSince(ConnectorWebhookRest.CONTEXT, recipe.Id, Datetime.now().addHours(-1)),
				'One warning names the recipe.'
			);
		}
	}

	@IsTest
	static void theRunnerTakesReceivedRunsAsItTakesQueuedOnes() {
		System.runAs(admin()) {
			String token = hookedRecipe('', ConnectorRunStore.ACTIVE);
			RestRequest request = post('{"a":1}', 'application/json');
			request.addHeader(ConnectorWebhooks.HEADER, token);
			receive(request);

			Test.startTest();
			ConnectorRunner.process(
				ConnectorRunStore.queued(50, ConnectorRunStore.ALL_RUN_AS, false),
				new ConnectorRunner.Guard()
			);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SUCCEEDED, runs()[0].Status__c);
		}
	}
}
