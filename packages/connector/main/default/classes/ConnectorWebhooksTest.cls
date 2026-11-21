/**
 * Webhooks in and data sent back, outside the receiver (CN-04; canonical model R-CR1, R-CR10,
 * R-CR11; security review F1, F4, F13): the trigger and its reply on save, the token kept only as
 * its hash, the Webhook card for admins and viewers, the guest permission set, Health Check's
 * guest access, and every address read from data held to the connection's host (fetch back and
 * Send to Webhook callbacks).
 */
@IsTest(
	testFor='ApexClass:ConnectorWebhooks, ApexClass:ConnectorWebhooksController, ApexClass:ConnectorRecipeDocument, ApexClass:ConnectorStepRunner'
)
private class ConnectorWebhooksTest {
	private static final String VIEWER_SET = 'Connector_Viewer';
	private static final String BASE = 'https://api.example.com/v3';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static String webhookDocument(String replyJson, String stepsJson) {
		return '{"version":1,"trigger":{"kind":"webhook","eventId":"trigger.id","reply":' +
			replyJson +
			'},"steps":' +
			stepsJson +
			'}';
	}

	private static final String STOP = '[{"id":"done","kind":"stop","outcome":"Succeeded","message":""}]';

	private static void useEndpoint() {
		ConnectorWebhooks.testEndpoints = new Map<String, String>{ ConnectorRecipeTestData.CONNECTION => BASE };
	}

	// ---------------------------------------------------------------------------------------
	// The trigger and its reply on save (R-CR1, R-CR10)
	// ---------------------------------------------------------------------------------------

	@IsTest
	static void aWebhookTriggerWithAFixedReplyIsSaved() {
		System.runAs(admin()) {
			Map<String, Object> document = ConnectorRecipeDocument.parse(
				webhookDocument(
					'{"status":200,"body":"{\\"ok\\": true, \\"ref\\": \\"{reference}\\"}","challenge":"challenge"}',
					STOP
				)
			);
			Assert.areEqual(new List<String>(), ConnectorRecipeDocument.problems(document));
			Assert.areEqual(ConnectorWebhooks.WEBHOOK, ConnectorRecipes.kindOf(document));
		}
	}

	@IsTest
	static void aReplyHoldingAMergeFieldIsRefusedOnSave() {
		System.runAs(admin()) {
			try {
				ConnectorRecipeDocument.parse(
					webhookDocument('{"body":"{\\"key\\": \\"{!$Credential.X.Y}\\"}"}', STOP)
				);
				Assert.fail('A reply body holding a merge field must be refused (F1).');
			} catch (ConnectorRecipeDocument.DocumentException refused) {
				Assert.areEqual(BarnHelp.text('Connector', 'Connector_Recipe_ErrorMergeField'), refused.getMessage());
			}
		}
	}

	@IsTest
	static void aBadReplyStatusBodyOrChallengeIsRefused() {
		System.runAs(admin()) {
			String expected = BarnHelp.text('Connector', 'Connector_Recipe_ErrorWebhook');
			List<String> replies = new List<String>{
				'{"status":201}',
				'{"body":"not json"}',
				'{"body":"\\"' +
				'x'.repeat(4001) +
				'\\""}',
				'{"challenge":"token"}',
				'{"challenge":"a b"}'
			};
			for (String reply : replies) {
				List<String> found = ConnectorRecipeDocument.problems(
					ConnectorRecipeDocument.parse(webhookDocument(reply, STOP))
				);
				Assert.isTrue(found.contains(expected), 'Refused: ' + reply.left(40));
			}
		}
	}

	@IsTest
	static void theReplyNeverCarriesRecordDataOnlyTheFixedBodyAndReference() {
		System.runAs(admin()) {
			Map<String, Object> starter = new Map<String, Object>{ 'kind' => 'webhook' };
			Map<String, Object> payload = new Map<String, Object>{ 'email' => 'ada@example.org', 'amount' => 25 };

			ConnectorWebhooks.Reply reply = ConnectorWebhooks.reply(starter, payload, null, 'abc123');

			Assert.areEqual(202, reply.status, 'Accepted by default.');
			Assert.areEqual('{"received": true, "reference": "abc123"}', reply.body);
			Assert.isFalse(reply.body.contains('ada@example.org'), 'Nothing posted or computed is echoed.');
			Assert.areEqual('application/json', reply.contentType);
		}
	}

	@IsTest
	static void aChallengeValueIsEchoedAsPlainText() {
		System.runAs(admin()) {
			Map<String, Object> starter = new Map<String, Object>{
				'kind' => 'webhook',
				'reply' => new Map<String, Object>{ 'challenge' => 'challenge' }
			};

			ConnectorWebhooks.Reply fromBody = ConnectorWebhooks.reply(
				starter,
				new Map<String, Object>{ 'challenge' => 'xyz' },
				null,
				'r'
			);
			ConnectorWebhooks.Reply fromQuery = ConnectorWebhooks.reply(
				starter,
				new Map<String, Object>(),
				new Map<String, String>{ 'challenge' => 'q1' },
				'r'
			);

			Assert.areEqual(200, fromBody.status);
			Assert.areEqual('xyz', fromBody.body);
			Assert.areEqual('text/plain', fromBody.contentType);
			Assert.areEqual('q1', fromQuery.body);
		}
	}

	// ---------------------------------------------------------------------------------------
	// The token and the Webhook card (R-CR3, R-CR10)
	// ---------------------------------------------------------------------------------------

	@IsTest
	static void aNewTokenIsShownOnceAndKeptOnlyAsItsHash() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Gifts In',
				webhookDocument('{}', STOP),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorWebhooks.testSites = new List<ConnectorWebhooks.SiteInfo>{
				site('Giving', 'https://give.example.org')
			};

			Test.startTest();
			ConnectorWebhooks.View made = ConnectorWebhooksController.newWebhookToken(recipe.Id);
			ConnectorWebhooks.View later = ConnectorWebhooksController.getWebhook(recipe.Id);
			Test.stopTest();

			Assert.isTrue(Pattern.matches('[0-9a-f]{64}', made.token), '256 random bits as hexadecimal.');
			Assert.isNull(later.token, 'Never shown again.');
			Assert.isTrue(later.hasToken);
			Assert.areEqual(500, later.hourlyCap, 'The default cap is shown.');
			Assert.areEqual(
				new List<String>{ 'https://give.example.org' + ConnectorWebhooks.RECEIVER_PATH },
				later.addresses
			);
			Assert.areEqual('X-BarnCRM-Token', later.header);
			Connector_Recipe__c stored = [
				SELECT Webhook_Token_Hash__c
				FROM Connector_Recipe__c
				WHERE Id = :recipe.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(ConnectorWebhooks.hashOf(made.token), stored.Webhook_Token_Hash__c);
			Assert.areNotEqual(made.token, stored.Webhook_Token_Hash__c, 'The token itself is never stored.');
		}
	}

	@IsTest
	static void theHourlyCapIsSavedWithinItsRange() {
		System.runAs(admin()) {
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Capped',
				webhookDocument('{}', STOP),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorWebhooks.testSites = new List<ConnectorWebhooks.SiteInfo>();

			Assert.areEqual(1200, ConnectorWebhooksController.saveWebhookCap(recipe.Id, 1200).hourlyCap);
			try {
				ConnectorWebhooksController.saveWebhookCap(recipe.Id, 5001);
				Assert.fail('Over 5,000 is refused.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(BarnHelp.text('Connector', 'Connector_Webhook_ErrorCap'), refused.getMessage());
			}
		}
	}

	@IsTest
	static void aViewerSeesTheCardButCannotMakeAToken() {
		Connector_Recipe__c recipe;
		System.runAs(admin()) {
			recipe = ConnectorRecipeTestData.recipe(
				'Read Only',
				webhookDocument('{}', STOP),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
		}
		System.runAs(TestUsers.standardUserWith('Sam', new List<String>{ VIEWER_SET })) {
			ConnectorWebhooks.testSites = new List<ConnectorWebhooks.SiteInfo>();
			Assert.isFalse(ConnectorWebhooksController.getWebhook(recipe.Id).hasToken);
			try {
				ConnectorWebhooksController.newWebhookToken(recipe.Id);
				Assert.fail('Only Connector admins make tokens (R-CR3).');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused.getMessage());
			}
		}
	}

	// ---------------------------------------------------------------------------------------
	// The guest permission set and Health Check
	// ---------------------------------------------------------------------------------------

	@IsTest
	static void theGuestSetHoldsOnlyTheReceiverAndCreateOnTheStartEvents() {
		System.runAs(admin()) {
			PermissionSet guest = [
				SELECT Id
				FROM PermissionSet
				WHERE Name = :ConnectorWebhooks.GUEST_SET
				WITH SYSTEM_MODE
				LIMIT 1
			];
			Set<String> classes = new Set<String>();
			for (SetupEntityAccess row : [
				SELECT SetupEntityId
				FROM SetupEntityAccess
				WHERE ParentId = :guest.Id
				WITH SYSTEM_MODE
			]) {
				classes.add(String.valueOf(row.SetupEntityId));
			}
			ApexClass receiver = [
				SELECT Id
				FROM ApexClass
				WHERE Name = 'ConnectorWebhookRest'
				WITH SYSTEM_MODE
				LIMIT 1
			];
			Assert.areEqual(new Set<String>{ String.valueOf(receiver.Id) }, classes, 'The receiver class only.');
			Set<String> objects = new Set<String>();
			for (ObjectPermissions row : [
				SELECT SobjectType, PermissionsCreate, PermissionsRead, PermissionsEdit, PermissionsDelete
				FROM ObjectPermissions
				WHERE ParentId = :guest.Id
				WITH SYSTEM_MODE
			]) {
				objects.add(row.SobjectType.substringAfter('Connector_'));
				Assert.isTrue(row.PermissionsCreate, 'Create on the start event (Read comes with it).');
				Assert.isFalse(row.PermissionsEdit || row.PermissionsDelete, 'Nothing else.');
				Assert.isTrue(row.SobjectType.endsWith('__e'), 'Platform events only: ' + row.SobjectType);
			}
			Assert.areEqual(new Set<String>{ 'Start__e', 'Start_User__e' }, objects);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM FieldPermissions WHERE ParentId = :guest.Id WITH SYSTEM_MODE],
				'No field.'
			);
		}
	}

	@IsTest
	static void healthCheckOffersGuestAccessOnlyWhileARecipeReceivesWebhooks() {
		System.runAs(admin()) {
			ConnectorWebhooks.testSites = new List<ConnectorWebhooks.SiteInfo>();
			Assert.isTrue(ConnectorWebhooks.findings().isEmpty(), 'No webhook recipe, nothing to say.');

			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Hooked',
				webhookDocument('{}', STOP),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			recipe.Trigger_Kind__c = ConnectorWebhooks.WEBHOOK;
			update as system recipe;

			List<HealthCheckService.Finding> found = ConnectorWebhooks.findings();
			Assert.areEqual(1, found.size(), 'No Site.');
			Assert.areEqual('connector_webhook_no_site', found[0].key);

			ConnectorWebhooks.SiteInfo giving = site('Giving', 'https://give.example.org');
			giving.guestUserId = UserInfo.getUserId();
			ConnectorWebhooks.testSites = new List<ConnectorWebhooks.SiteInfo>{ giving };
			ConnectorHealthCheckExtension extension = new ConnectorHealthCheckExtension();
			Assert.areEqual(new List<String>{ 'Giving' }, extension.fixScope(ConnectorWebhooks.FIX_GUEST));
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Health_WebhookGuest_Fix'),
				extension.fixLabel(ConnectorWebhooks.FIX_GUEST)
			);
			Assert.isNull(extension.fixScope('another_key'), 'Other keys are not ours.');
		}
	}

	// ---------------------------------------------------------------------------------------
	// Addresses read from data: fetch back and callbacks (R-CR11, F4)
	// ---------------------------------------------------------------------------------------

	@IsTest
	static void anAddressOnTheConnectionsHostGivesItsPathAndQueryOnly() {
		System.runAs(admin()) {
			useEndpoint();
			Assert.areEqual(
				'/events/42/attendees/?expand=profile',
				ConnectorWebhooks.calloutAddress(
					'https://API.example.com/v3/events/42/attendees/?expand=profile',
					ConnectorRecipeTestData.CONNECTION
				)
			);
			Assert.areEqual(
				'/x',
				ConnectorWebhooks.calloutAddress(
					'https://api.example.com:443/v3/x',
					ConnectorRecipeTestData.CONNECTION
				),
				'The default port is the same port.'
			);
		}
	}

	@IsTest
	static void fetchBackRefusesAnotherSchemeUserInfoSuffixHostPortOrPath() {
		System.runAs(admin()) {
			useEndpoint();
			List<String> refusedAddresses = new List<String>{
				'http://api.example.com/v3/x',
				'https://api.example.com@attacker.net/v3/x',
				'https://user:pass@api.example.com/v3/x',
				'https://api.example.com.attacker.net/v3/x',
				'https://attacker.net/v3/x',
				'https://api.example.com:8443/v3/x',
				'https://api.example.com/v2/x',
				'https://api.example.com/v3x/y',
				'https://api.example.com/v3/x#frag',
				'https://api.example.com/v3/a b',
				'https://api.example.com/v3/x?q={!$Credential.A.B}',
				'//api.example.com/v3/x',
				'not an address',
				''
			};
			for (String posted : refusedAddresses) {
				try {
					ConnectorWebhooks.calloutAddress(posted, ConnectorRecipeTestData.CONNECTION);
					Assert.fail('Refused: ' + posted);
				} catch (ConnectorRecipeDocument.DocumentException refused) {
					Assert.areEqual(BarnHelp.text('Connector', 'Connector_Run_ErrorDataAddress'), refused.getMessage());
				}
			}
		}
	}

	@IsTest
	static void fetchBackCallsTheConnectionWithThePostedPathAndQueryOnly() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.readyConnection();
			useEndpoint();
			String steps =
				'[{"id":"fetch","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"GET","path":"","urlFrom":"trigger.api_url"}]';
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Fetch Back',
				ConnectorRecipeTestData.document(steps),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(
				recipe,
				'{"api_url":"https://api.example.com/v3/orders/7/?expand=attendees"}',
				false
			);
			ConnectorRecipeTestData.App app = new ConnectorRecipeTestData.App(200, '{"id":"7"}');
			Test.setMock(HttpCalloutMock.class, app);

			Test.startTest();
			Connector_Run__c done = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SUCCEEDED, done.Status__c, 'Message: ' + done.Error_Message__c);
			Assert.areEqual(1, app.requests.size());
			Assert.areEqual(
				'callout:' + ConnectorRecipeTestData.CONNECTION + '/orders/7/?expand=attendees',
				app.requests[0].getEndpoint(),
				'The posted address is never the endpoint.'
			);
		}
	}

	@IsTest
	static void sendToWebhookRefusesACallbackOnAnotherHostAndSendsNothing() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.readyConnection();
			useEndpoint();
			String steps =
				'[{"id":"reply","kind":"sendWebhook","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","urlFrom":"trigger.response_url"}]';
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Callback',
				ConnectorRecipeTestData.document(steps),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorRecipeTestData.App app = new ConnectorRecipeTestData.App(200, '{}');
			Test.setMock(HttpCalloutMock.class, app);
			List<String> callbacks = new List<String>{
				'https://hooks.attacker.net/v3/x',
				'https://api.example.com@attacker.net/v3/x',
				'https://api.example.com:8443/v3/x'
			};
			List<Id> runIds = new List<Id>();
			for (String callback : callbacks) {
				runIds.add(ConnectorRecipeTestData.queuedRun(recipe, '{"response_url":"' + callback + '"}', false).Id);
			}

			Test.startTest();
			ConnectorRunner.process(
				ConnectorRunStore.queued(50, ConnectorRunStore.ALL_RUN_AS, false),
				new ConnectorRunner.Guard()
			);
			Test.stopTest();

			for (Connector_Run__c run : [
				SELECT Status__c, Error_Message__c
				FROM Connector_Run__c
				WHERE Id IN :runIds
				WITH SYSTEM_MODE
			]) {
				Assert.areEqual(ConnectorRunStore.FAILED, run.Status__c);
				Assert.areEqual(BarnHelp.text('Connector', 'Connector_Run_ErrorDataAddress'), run.Error_Message__c);
			}
			Assert.areEqual(0, app.requests.size(), 'Nothing is sent to another host.');
		}
	}

	@IsTest
	static void sendToWebhookPostsAMappedBodyToTheConnectionsOwnAddress() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.readyConnection();
			Id bodyMap = ConnectorRecipeTestData.bodyMap('Name Body');
			String steps =
				'[{"id":"tell","kind":"sendWebhook","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","path":"","bodyMap":"' +
				bodyMap +
				'","bodyInput":"trigger","success":[200]}]';
			Map<String, Object> document = ConnectorRecipeDocument.parse(ConnectorRecipeTestData.document(steps));
			Assert.areEqual(new List<String>(), ConnectorRecipeDocument.problems(document), 'A blank path is allowed.');
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Tell Slack',
				JSON.serialize(document),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			Connector_Run__c run = ConnectorRecipeTestData.queuedRun(recipe, '{"last":"Lovelace"}', false);
			ConnectorRecipeTestData.App app = new ConnectorRecipeTestData.App(200, 'ok');
			Test.setMock(HttpCalloutMock.class, app);

			Test.startTest();
			Connector_Run__c done = ConnectorRecipeTestData.runAll(run.Id);
			Test.stopTest();

			Assert.areEqual(ConnectorRunStore.SUCCEEDED, done.Status__c, 'Message: ' + done.Error_Message__c);
			Assert.areEqual('POST', app.requests[0].getMethod(), 'Always POST.');
			Assert.areEqual('callout:' + ConnectorRecipeTestData.CONNECTION, app.requests[0].getEndpoint());
			Assert.areEqual('{"name":"Lovelace"}', app.requests[0].getBody());
		}
	}

	@IsTest
	static void anAddressFromTheDataCannotBeMixedWithAPathOrQuery() {
		System.runAs(admin()) {
			String steps =
				'[{"id":"fetch","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"GET","path":"/orders","urlFrom":"trigger.api_url"}]';
			List<String> found = ConnectorRecipeDocument.problems(
				ConnectorRecipeDocument.parse(ConnectorRecipeTestData.document(steps))
			);
			Assert.isTrue(
				found.contains(
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorRequestPath', new List<Object>{ 'fetch' })
				),
				String.join(found, ' ')
			);
		}
	}

	// ---------------------------------------------------------------------------------------
	// Replies, references, caps and the real Site and credential reads
	// ---------------------------------------------------------------------------------------

	@IsTest
	static void aNumberIsEchoedAsTextAndAnUnusableChallengeFallsBackToTheFixedReply() {
		System.runAs(admin()) {
			Map<String, Object> starter = new Map<String, Object>{
				'kind' => 'webhook',
				'reply' => new Map<String, Object>{ 'challenge' => 'n' }
			};

			ConnectorWebhooks.Reply asInteger = ConnectorWebhooks.reply(
				starter,
				new Map<String, Object>{ 'n' => 42 },
				null,
				'r1'
			);
			ConnectorWebhooks.Reply asLong = ConnectorWebhooks.reply(
				starter,
				new Map<String, Object>{ 'n' => 9000000000L },
				null,
				'r1'
			);
			ConnectorWebhooks.Reply asDecimal = ConnectorWebhooks.reply(
				starter,
				new Map<String, Object>{ 'n' => 4.5 },
				null,
				'r1'
			);
			ConnectorWebhooks.Reply tooLong = ConnectorWebhooks.reply(
				starter,
				new Map<String, Object>{ 'n' => 'x'.repeat(ConnectorWebhooks.MAX_ECHO + 1) },
				null,
				'r2'
			);
			ConnectorWebhooks.Reply blank = ConnectorWebhooks.reply(
				starter,
				new Map<String, Object>{ 'n' => '' },
				null,
				'r3'
			);
			ConnectorWebhooks.Reply notScalar = ConnectorWebhooks.reply(
				starter,
				new Map<String, Object>{ 'n' => new List<Object>{ 1 } },
				null,
				'r4'
			);
			ConnectorWebhooks.Reply noReference = ConnectorWebhooks.reply(
				new Map<String, Object>{ 'kind' => 'webhook' },
				null,
				null,
				null
			);

			Assert.areEqual('42', asInteger.body);
			Assert.areEqual('9000000000', asLong.body);
			Assert.areEqual('4.5', asDecimal.body);
			for (ConnectorWebhooks.Reply echoed : new List<ConnectorWebhooks.Reply>{ asInteger, asLong, asDecimal }) {
				Assert.areEqual(200, echoed.status);
				Assert.areEqual('text/plain', echoed.contentType);
			}
			Assert.areEqual(202, tooLong.status, 'A value past the echo limit is never echoed.');
			Assert.areEqual('{"received": true, "reference": "r2"}', tooLong.body);
			Assert.areEqual('{"received": true, "reference": "r3"}', blank.body);
			Assert.areEqual('{"received": true, "reference": "r4"}', notScalar.body);
			Assert.areEqual('{"received": true, "reference": ""}', noReference.body, 'No reference leaves it empty.');
		}
	}

	@IsTest
	static void tokensAreHashedAsLowerCaseHexAndReferencesAreOpaqueAndNew() {
		// runs-as: deploying user (pure logic: hashing, references and the cap, no DML or SOQL)
		String token = 'ab'.repeat(32);

		String hashed = ConnectorWebhooks.hashOf(token);
		String first = ConnectorWebhooks.newReference();
		String second = ConnectorWebhooks.newReference();

		Assert.isTrue(Pattern.matches('[0-9a-f]{64}', hashed));
		Assert.areNotEqual(token, hashed);
		Assert.areEqual(
			hashed,
			ConnectorWebhooks.hashOf(' ' + token.toUpperCase() + ' '),
			'Upper or lower case and spaces do not matter.'
		);
		Assert.isNull(ConnectorWebhooks.hashOf(null));
		Assert.isNull(ConnectorWebhooks.hashOf('not a token'));
		Assert.isNull(ConnectorWebhooks.hashOf('ab'.repeat(31)), 'Too short.');
		Assert.isTrue(Pattern.matches('[0-9a-f]{20}', first));
		Assert.areNotEqual(first, second);
		Assert.areEqual(500, ConnectorWebhooks.hourlyCap(null));
		Assert.areEqual(500, ConnectorWebhooks.hourlyCap(new Connector_Recipe__c(Webhook_Hourly_Cap__c = 0)));
		Assert.areEqual(500, ConnectorWebhooks.hourlyCap(new Connector_Recipe__c(Webhook_Hourly_Cap__c = 5001)));
		Assert.areEqual(5000, ConnectorWebhooks.hourlyCap(new Connector_Recipe__c(Webhook_Hourly_Cap__c = 5000)));
	}

	@IsTest
	static void aRecipeThatIsGoneHasNoWebhookCardTokenOrCap() {
		Id gone = Id.valueOf(
			Connector_Recipe__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001'
		);
		System.runAs(admin()) {
			ConnectorWebhooks.testSites = new List<ConnectorWebhooks.SiteInfo>();
			Integer refused = 0;
			String goneText = BarnHelp.text('Connector', 'Connector_Recipe_ErrorGone');
			try {
				ConnectorWebhooks.view(gone);
			} catch (ConnectorConnections.ConnectorException e) {
				Assert.areEqual(goneText, e.getMessage());
				refused++;
			}
			try {
				ConnectorWebhooks.newToken(gone);
			} catch (ConnectorConnections.ConnectorException e) {
				Assert.areEqual(goneText, e.getMessage());
				refused++;
			}
			try {
				ConnectorWebhooks.saveCap(gone, 10);
			} catch (ConnectorConnections.ConnectorException e) {
				Assert.areEqual(goneText, e.getMessage());
				refused++;
			}
			Assert.areEqual(3, refused, 'Each is refused in words.');
		}
	}

	@IsTest
	static void theOrgsRealSitesAreListedWithTheirAddressesAndAGuestCheckNamesOnlyThem() {
		System.runAs(admin()) {
			List<ConnectorWebhooks.SiteInfo> listed = ConnectorWebhooks.sites();
			List<String> unguarded = ConnectorWebhooks.sitesWithoutGuestAccess();

			Assert.isNotNull(listed, 'A list, empty when the org has no active Site.');
			Set<String> names = new Set<String>();
			for (ConnectorWebhooks.SiteInfo info : listed) {
				names.add(info.name);
				Assert.isTrue(info.url == null || !info.url.endsWith('/'), 'An address has no trailing slash.');
			}
			Assert.isTrue(names.containsAll(unguarded), 'Only listed Sites can lack guest access.');
		}
	}

	@IsTest
	static void anAddressIsRefusedWhenTheConnectionHasNoNamedCredentialToHoldItTo() {
		System.runAs(admin()) {
			String refusal = BarnHelp.text('Connector', 'Connector_Run_ErrorDataAddress');
			Integer refused = 0;
			for (Integer attempt = 0; attempt < 2; attempt++) {
				try {
					ConnectorWebhooks.calloutAddress('https://api.example.com/v3/x', 'BarnConn_Rest_NoSuchConnection');
				} catch (ConnectorRecipeDocument.DocumentException e) {
					Assert.areEqual(refusal, e.getMessage());
					refused++;
				}
			}
			Assert.areEqual(2, refused, 'There is no host to compare with, so nothing is called, on every read.');
		}
	}

	@IsTest
	static void healthCheckNamesASiteWhoseGuestLacksTheReceiverAndLeavesOnesThatHoldIt() {
		User bare = TestUsers.standardUser('GuestBare');
		User covered = TestUsers.standardUserWith('GuestCovered', new List<String>{ ConnectorWebhooks.GUEST_SET });
		System.runAs(admin()) {
			Connector_Recipe__c recipe = ConnectorRecipeTestData.recipe(
				'Hooked',
				webhookDocument('{}', STOP),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			recipe.Trigger_Kind__c = ConnectorWebhooks.WEBHOOK;
			update as system recipe;
			ConnectorWebhooks.SiteInfo open = site('Open Site', 'https://open.example.org');
			open.guestUserId = bare.Id;
			ConnectorWebhooks.SiteInfo ready = site('Ready Site', 'https://ready.example.org');
			ready.guestUserId = covered.Id;
			ConnectorWebhooks.testSites = new List<ConnectorWebhooks.SiteInfo>{ open, ready };

			List<HealthCheckService.Finding> found = ConnectorWebhooks.findings();

			Assert.areEqual(1, found.size());
			Assert.areEqual(ConnectorWebhooks.FIX_GUEST, found[0].getKey());
			Assert.isTrue(found[0].getDetail().contains('Open Site'), 'The Site without access is named.');
			Assert.isFalse(found[0].getDetail().contains('Ready Site'), 'One that holds the set is not.');
			Assert.areEqual(new List<String>{ 'Open Site' }, ConnectorWebhooks.sitesWithoutGuestAccess());
		}
	}

	@IsTest
	static void theFixGivesTheReceiversSetToTheNamedSitesGuestsOnly() {
		User named = TestUsers.standardUser('GuestNamed');
		User other = TestUsers.standardUser('GuestOther');
		System.runAs(admin()) {
			ConnectorWebhooks.SiteInfo first = site('Named Site', 'https://named.example.org');
			first.guestUserId = named.Id;
			ConnectorWebhooks.SiteInfo second = site('Other Site', 'https://other.example.org');
			second.guestUserId = other.Id;
			ConnectorWebhooks.SiteInfo noGuest = site('Guestless Site', 'https://none.example.org');
			ConnectorWebhooks.testSites = new List<ConnectorWebhooks.SiteInfo>{ first, second, noGuest };

			Test.startTest();
			String done = ConnectorWebhooks.grantGuestAccess(new List<String>{ 'Named Site', 'Guestless Site' });
			Test.stopTest();

			Assert.isTrue(done.contains('Named Site'), 'The message names what was done.');
			Assert.areEqual(new List<String>{ 'Other Site' }, ConnectorWebhooks.sitesWithoutGuestAccess());
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :named.Id AND PermissionSet.Name = :ConnectorWebhooks.GUEST_SET
					WITH SYSTEM_MODE
				]
			);
		}
	}

	private static ConnectorWebhooks.SiteInfo site(String name, String url) {
		ConnectorWebhooks.SiteInfo info = new ConnectorWebhooks.SiteInfo();
		info.name = name;
		info.url = url;
		return info;
	}
}
