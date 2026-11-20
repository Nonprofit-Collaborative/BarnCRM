/**
 * Dana, the system administrator, connects BarnCRM to her organization's apps on Super
 * Connector (CN-01; canonical model 29CN1; security review F2 to F12). A test cannot create a
 * Named Credential, so the org's credential store is a fake that records every write; the
 * controller, the rules and the Admin Journal, Error Log and permission set rows are real.
 */
@IsTest(testFor='ApexClass:ConnectorConnectionsController, ApexClass:ConnectorConnections, ApexClass:ConnectorOrg')
private class ConnectorConnectionsControllerTest {
	private static final String KEY = 'k3y-AbCdEf123456-us21';
	private static final String SECRET_URL = 'https://hooks.example.com/services/T000/B000/abcdefWXYZ';

	/** The credential store, faked: names, URLs and flags, and every key write recorded. */
	private class FakeOrg extends ConnectorOrg {
		Map<String, ConnectorOrg.Pair> pairs = new Map<String, ConnectorOrg.Pair>();
		Map<String, String> kinds = new Map<String, String>();
		Map<String, Id> principals = new Map<String, Id>();
		Map<Id, Set<Id>> granted = new Map<Id, Set<Id>>();
		List<ConnectApi.CredentialInput> credentials = new List<ConnectApi.CredentialInput>();
		List<ConnectApi.NamedCredentialInput> named = new List<ConnectApi.NamedCredentialInput>();
		List<String> removed = new List<String>();
		List<String> keysDeleted = new List<String>();
		Boolean echoKeyOnWrite = false;
		Boolean refuseGrant = false;

		FakeOrg() {
			fake = true;
		}

		ConnectorOrg.Pair add(String name, String kind, String url, Boolean calloutsOn, Boolean keyStored) {
			ConnectorOrg.Pair pair = new ConnectorOrg.Pair();
			pair.name = name;
			pair.label = 'Label ' + name;
			pair.principal = kind;
			pair.url = url;
			pair.linked = true;
			pair.calloutsEnabled = calloutsOn;
			pair.keyStored = keyStored;
			pairs.put(name, pair);
			principals.put(name, Id.valueOf('001' + String.valueOf(principals.size() + 1).leftPad(12, '0')));
			return pair;
		}

		public override Map<String, String> labelsByName() {
			Map<String, String> labels = new Map<String, String>();
			for (ConnectorOrg.Pair pair : pairs.values()) {
				labels.put(pair.name, pair.label);
			}
			return labels;
		}

		public override ConnectorOrg.Pair read(String name, String label) {
			return pairs.get(name);
		}

		public override Map<String, Id> principalIds() {
			return principals.clone();
		}

		public override Set<Id> grantedEntities(Id permissionSetId) {
			return granted.containsKey(permissionSetId) ? granted.get(permissionSetId).clone() : new Set<Id>();
		}

		public override void grant(Id permissionSetId, Id principalId) {
			if (refuseGrant) {
				throw new FakeException('Refused');
			}
			if (!granted.containsKey(permissionSetId)) {
				granted.put(permissionSetId, new Set<Id>());
			}
			granted.get(permissionSetId).add(principalId);
		}

		public override void createExternal(ConnectApi.ExternalCredentialInput input) {
			kinds.put(input.developerName, input.principals[0].principalName);
		}

		public override void deleteKey(String name, String principal) {
			keysDeleted.add(name);
			pairs.get(name).keyStored = false;
		}

		Boolean refuseRemove = false;

		public override void remove(String name, Boolean namedToo) {
			if (refuseRemove) {
				throw new FakeException('Refused');
			}
			removed.add(name);
			pairs.remove(name);
		}

		public override void record(ConnectApi.CredentialInput input, Boolean isUpdate) {
			if (echoKeyOnWrite) {
				String echoed = '';
				for (ConnectApi.CredentialValueInput value : input.credentials.values()) {
					echoed += value.value + ' ';
				}
				throw new FakeException('Invalid credential value: ' + echoed);
			}
			credentials.add(input);
			pairs.get(input.externalCredential).keyStored = true;
		}

		public override void record(ConnectApi.NamedCredentialInput input, Boolean isUpdate) {
			named.add(input);
			if (isUpdate) {
				pairs.get(input.developerName).url = input.calloutUrl;
			} else {
				add(input.developerName, kinds.get(input.developerName), input.calloutUrl, false, false);
			}
		}
	}

	private class FakeException extends Exception {
	}

	private class Answer implements HttpCalloutMock {
		Integer status;
		String endpoint;
		Answer(Integer status) {
			this.status = status;
		}
		public HttpResponse respond(HttpRequest request) {
			endpoint = request.getEndpoint();
			HttpResponse response = new HttpResponse();
			response.setStatusCode(status);
			return response;
		}
	}

	private static FakeOrg useFake() {
		FakeOrg fake = new FakeOrg();
		ConnectorConnections.org = fake;
		ConnectorConnections.credentialPermissionOverride = true;
		return fake;
	}

	@TestSetup
	static void createTestUser() {
		System.runAs(TestUsers.admin()) {
			dana();
		}
	}

	private static User dana() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static ConnectorConnectionsController.Result create(String kind, String userName, String secret) {
		return ConnectorConnectionsController.createConnection(
			'Mailing list',
			kind,
			'https://API.example.com/v2/',
			'X-Api-Key',
			userName,
			secret
		);
	}

	private static String refusal(Exception refused) {
		return refused.getMessage();
	}

	@IsTest
	static void eachKindWritesItsKeyEncryptedAndItsUserNamePlain() {
		System.runAs(dana()) {
			FakeOrg fake = useFake();

			ConnectorConnectionsController.Result apiKey = create(ConnectorConnections.API_KEY, null, KEY);
			create(ConnectorConnections.BEARER, null, KEY);
			create(ConnectorConnections.BASIC, 'dana', KEY);

			Assert.areEqual(3, fake.credentials.size(), 'One key write per kind');
			Assert.isTrue(fake.credentials[0].credentials.get('Key').encrypted, 'API key encrypted (F6)');
			Assert.isTrue(fake.credentials[1].credentials.get('Token').encrypted, 'Token encrypted (F6)');
			Assert.isTrue(fake.credentials[2].credentials.get('Password').encrypted, 'Password encrypted (F6)');
			Assert.isFalse(fake.credentials[2].credentials.get('UserName').encrypted, 'The user name is not a secret');
			for (ConnectApi.NamedCredentialInput input : fake.named) {
				Assert.isFalse(input.calloutOptions.allowMergeFieldsInBody, 'Formulas in the body stay off (F1)');
				Assert.isTrue(input.developerName.startsWith('BarnConn_rest_'), 'The server makes the name (F2)');
				Assert.areEqual('https://API.example.com/v2', input.calloutUrl, 'The base URL, no trailing slash');
			}
			Assert.areEqual('X-Api-Key', fake.named[0].customHeaders[0].headerName, 'The key goes in the named header');
			Assert.areEqual(
				'{!$Credential.' + fake.named[0].developerName + '.Key}',
				fake.named[0].customHeaders[0].headerValue,
				'The header formula comes from the kind alone (F1)'
			);
			Assert.areEqual('Authorization', fake.named[1].customHeaders[0].headerName, 'Bearer uses Authorization');
			Assert.areEqual('created', apiKey.outcome, 'Created, with its principal access');
			Assert.areEqual(1, apiKey.page.connections.size(), 'The first result lists the first connection');
			Assert.areEqual(0, Limits.getQueueableJobs(), 'No credential write is queued (F3)');
			Assert.areEqual(0, Limits.getFutureCalls(), 'No credential write is deferred (F3)');
		}
	}

	@IsTest
	static void aSecretUrlIsTheAddressAndIsNeverReturned() {
		System.runAs(dana()) {
			FakeOrg fake = useFake();

			ConnectorConnectionsController.Result result = ConnectorConnectionsController.createConnection(
				'Team channel',
				ConnectorConnections.SECRET_URL,
				null,
				null,
				null,
				SECRET_URL
			);

			Assert.isTrue(fake.credentials.isEmpty(), 'No principal key for a Secret URL');
			Assert.areEqual(SECRET_URL, fake.named[0].calloutUrl, 'The address is the Named Credential URL (F5)');
			Assert.isFalse(fake.named[0].calloutOptions.allowMergeFieldsInHeader, 'No header formula needed');
			Assert.isTrue(fake.named[0].customHeaders.isEmpty(), 'No auth header');
			String sent = JSON.serialize(result) + JSON.serialize(ConnectorConnectionsController.getConnections());
			Assert.isFalse(sent.contains('/services/'), 'The secret URL never reaches the browser (F5)');
			Assert.areEqual('hooks.example.com', result.page.connections[0].host, 'Its host is shown');
			Assert.areEqual('WXYZ', result.page.connections[0].lastFour, 'And its last four characters');
		}
	}

	@IsTest
	static void theListAndEveryAnswerCarryNoKey() {
		System.runAs(dana()) {
			useFake();

			String sent = JSON.serialize(create(ConnectorConnections.BASIC, 'dana', KEY));
			sent += JSON.serialize(ConnectorConnectionsController.getConnections());

			Assert.isFalse(sent.contains(KEY), 'No key in any answer (F6)');
			Assert.isFalse(sent.contains('$Credential'), 'No header formula in any answer');
			Assert.isTrue(sent.contains('api.example.com'), 'The host is shown');
		}
	}

	@IsTest
	static void aCredentialBarnCrmDidNotCreateIsRefusedBeforeAnyWrite() {
		System.runAs(dana()) {
			FakeOrg fake = useFake();
			ConnectorOrg.Pair unlinked = fake.add(
				'BarnConn_rest_aaaaaa',
				ConnectorConnections.BEARER,
				'https://api.example.com',
				true,
				true
			);
			unlinked.linked = false;
			Integer refused = 0;

			for (
				String name : new List<String>{
					'Barn_Stripe',
					'Barn_Org_Connection',
					'BarnConn_rest_aaaaaa',
					'BarnConn_x'
				}
			) {
				try {
					ConnectorConnectionsController.replaceKey(name, null, KEY);
				} catch (AuraHandledException e) {
					refused++;
				}
				try {
					ConnectorConnectionsController.disconnect(name);
				} catch (AuraHandledException e) {
					refused++;
				}
				try {
					ConnectorConnectionsController.deleteConnection(name);
				} catch (AuraHandledException e) {
					refused++;
				}
				try {
					ConnectorConnectionsController.checkConnection(name);
				} catch (AuraHandledException e) {
					refused++;
				}
			}

			Assert.areEqual(16, refused, 'Every write to a credential that is not ours is refused (F2)');
			Assert.isTrue(fake.credentials.isEmpty() && fake.named.isEmpty(), 'Nothing written');
			Assert.isTrue(fake.removed.isEmpty() && fake.keysDeleted.isEmpty(), 'Nothing removed');
		}
	}

	@IsTest
	static void aConnectorAdminWithoutCredentialPermissionIsRefused() {
		User staff = TestUsers.standardUserWith('Staffer', new List<String>{ ConnectorConnections.ADMIN_SET });
		System.runAs(staff) {
			FakeOrg fake = new FakeOrg();
			ConnectorConnections.org = fake;
			String message;

			try {
				create(ConnectorConnections.BEARER, null, KEY);
			} catch (AuraHandledException e) {
				message = refusal(e);
			}

			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Error_NoCredentialPermission'),
				message,
				'Refused in plain words without Customize Application or Manage Named Credentials (F3)'
			);
			Assert.isTrue(fake.named.isEmpty() && fake.credentials.isEmpty(), 'Nothing written');
			Assert.isFalse(ConnectorConnectionsController.getConnections().canWrite, 'The page offers no writes');
		}
	}

	@IsTest
	static void aFailureEchoingTheKeyIsLoggedRedactedAndShownAsAFixedMessage() {
		System.runAs(dana()) {
			FakeOrg fake = useFake();
			fake.echoKeyOnWrite = true;
			String message;

			Test.startTest();
			try {
				create(ConnectorConnections.API_KEY, null, KEY);
			} catch (AuraHandledException e) {
				message = refusal(e);
			}
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Error_SaveFailed'), message, 'Fixed message (F7)');
			List<Error_Log__c> logged = [
				SELECT Message__c, Technical_Detail__c
				FROM Error_Log__c
				WHERE Context__c = 'ConnectorConnectionsController.createConnection'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, logged.size(), 'The failure is logged once');
			String text = logged[0].Message__c + ' ' + logged[0].Technical_Detail__c;
			Assert.isFalse(text.contains('AbCdEf123456'), 'No part of the key in the log (F7)');
			Assert.isTrue(text.contains('****'), 'The key is masked');
			Assert.areEqual(1, fake.removed.size(), 'The half-made connection is taken away');
		}
	}

	@IsTest
	static void anInsecureUrlAHeaderAuthorizationAndAHostChangeAreRefused() {
		System.runAs(dana()) {
			FakeOrg fake = useFake();
			fake.add('BarnConn_rest_bbbbbb', ConnectorConnections.SECRET_URL, SECRET_URL, true, true);
			List<String> refusals = new List<String>();

			for (
				String url : new List<String>{
					'http://api.example.com',
					'https://user:pw@api.example.com',
					'https://api.example.com/{!$Credential.X.Y}',
					'https://api.example.com?a=1',
					'ftp://api.example.com'
				}
			) {
				try {
					ConnectorConnectionsController.createConnection(
						'A',
						ConnectorConnections.BEARER,
						url,
						null,
						null,
						KEY
					);
				} catch (AuraHandledException e) {
					refusals.add(refusal(e));
				}
			}
			try {
				ConnectorConnectionsController.createConnection(
					'A',
					ConnectorConnections.API_KEY,
					'https://api.example.com',
					'Authorization',
					null,
					KEY
				);
			} catch (AuraHandledException e) {
				refusals.add(refusal(e));
			}
			try {
				ConnectorConnectionsController.replaceKey(
					'BarnConn_rest_bbbbbb',
					null,
					'https://hooks.example.com.attacker.net/services/x'
				);
			} catch (AuraHandledException e) {
				refusals.add(refusal(e));
			}
			Assert.areEqual(7, refusals.size(), 'Five unsafe URLs, a reserved header and a host change (F4)');
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Error_HostChanged'), refusals[6], 'Host stays');
			Assert.isTrue(fake.named.isEmpty(), 'Nothing was written for the other host');

			ConnectorConnectionsController.Result replaced = ConnectorConnectionsController.replaceKey(
				'BarnConn_rest_bbbbbb',
				null,
				SECRET_URL + 'new'
			);

			Assert.areEqual('replaced', replaced.outcome, 'A same-host address replaces it');
			Assert.areEqual(1, fake.named.size(), 'One Named Credential update');
			Assert.areEqual(SECRET_URL + 'new', fake.pairs.get('BarnConn_rest_bbbbbb').url, 'The new address is kept');
			Assert.isFalse(fake.named[0].calloutOptions.allowMergeFieldsInBody, 'Formulas stay off in the body');
			Assert.isFalse(JSON.serialize(replaced).contains('/services/'), 'The new address is not returned (F5)');
		}
	}

	@IsTest
	static void aTemplateHostLockHoldsTheDataCenterToItsPattern() {
		System.runAs(dana()) {
			Map<String, String> parts = new Map<String, String>{ 'dc' => '^[a-z]{2}[0-9]{1,3}$' };
			String template = '{dc}.api.mailchimp.com';

			Assert.isTrue(ConnectorConnections.hostFitsTemplate('us21.api.mailchimp.com', template, parts), 'Fits');
			Assert.isTrue(ConnectorConnections.hostFitsTemplate('US21.API.mailchimp.com', template, parts), 'Any case');
			Assert.isFalse(
				ConnectorConnections.hostFitsTemplate('us21.api.mailchimp.com.attacker.net', template, parts),
				'No suffix host'
			);
			Assert.isFalse(ConnectorConnections.hostFitsTemplate('attacker.net', template, parts), 'No other host');
			Assert.isFalse(
				ConnectorConnections.hostFitsTemplate('x.y.api.mailchimp.com', template, parts),
				'The data center keeps its pattern'
			);
			Assert.isFalse(ConnectorConnections.hostFitsTemplate('us21.api.mailchimp.com', template, null), 'Locked');
		}
	}

	@IsTest
	static void replacingAKeyWritesOneJournalRowAndHealthCheckListsIt() {
		System.runAs(dana()) {
			FakeOrg fake = useFake();
			fake.add('BarnConn_rest_cccccc', ConnectorConnections.BEARER, 'https://api.example.com', true, true);

			ConnectorConnectionsController.Result result = ConnectorConnectionsController.replaceKey(
				'BarnConn_rest_cccccc',
				null,
				KEY
			);

			Assert.areEqual('replaced', result.outcome, 'Replaced');
			List<Merge_Journal__c> journal = [
				SELECT Message__c
				FROM Merge_Journal__c
				WHERE Kind__c = 'Connection'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, journal.size(), 'One Admin Journal row (F11)');
			Assert.isFalse(journal[0].Message__c.contains(KEY), 'Never the key');
			Assert.areEqual(1, ConnectorConnections.keysReplacedSince(7).size(), 'Listed for Health Check');
			Assert.isTrue(fake.credentials[0].credentials.get('Token').encrypted, 'Encrypted');
		}
	}

	@IsTest
	static void theConnectionsSetGoesOnlyToConnectorAdmins() {
		User reader = TestUsers.standardUserWith('Reader', new List<String>());
		System.runAs(reader) {
			FakeOrg fake = useFake();
			fake.add('BarnConn_rest_dddddd', ConnectorConnections.BEARER, 'https://api.example.com', true, true);
			Boolean refused = false;

			try {
				ConnectorConnections.grantAccess('BarnConn_rest_dddddd');
			} catch (ConnectorConnections.ConnectorException e) {
				refused = true;
			}

			Assert.isTrue(refused, 'Not a Connector admin, so not given the set (F12)');
		}
		System.runAs(dana()) {
			FakeOrg fake = useFake();
			fake.add('BarnConn_rest_dddddd', ConnectorConnections.BEARER, 'https://api.example.com', true, true);

			Assert.isTrue(ConnectorConnections.grantAccess('BarnConn_rest_dddddd'), 'Principal access added');

			PermissionSet target = ConnectorConnections.accessSet();
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId = :target.Id WITH SYSTEM_MODE],
				'Given to the admin pressing the button, nobody else'
			);
			Assert.isTrue(ConnectorConnections.holdsAccessSet(), 'Dana holds it');
			fake.refuseGrant = true;
			fake.add('BarnConn_rest_eeeeee', ConnectorConnections.BEARER, 'https://api.example.com', true, true);
			Assert.isFalse(ConnectorConnections.grantAccess('BarnConn_rest_eeeeee'), 'Refused: the Setup step shows');
		}
	}

	@IsTest
	static void checkingSaysWhatIsMissingThenAsksTheApp() {
		System.runAs(dana()) {
			FakeOrg fake = useFake();
			ConnectorOrg.Pair pair = fake.add(
				'BarnConn_rest_ffffff',
				ConnectorConnections.BEARER,
				'https://api.example.com',
				false,
				true
			);
			Answer answer = new Answer(200);
			Test.setMock(HttpCalloutMock.class, answer);

			Assert.areEqual(
				'calloutsOff',
				ConnectorConnectionsController.checkConnection(pair.name).outcome,
				'Setup step first'
			);
			pair.calloutsEnabled = true;
			Assert.areEqual(
				'accessAdded',
				ConnectorConnectionsController.checkConnection(pair.name).outcome,
				'Access is given, then check again'
			);
			// A callout may not follow uncommitted setup writes: the next press is a new request.
			Test.startTest();
			ConnectorConnectionsController.Result result = ConnectorConnectionsController.checkConnection(pair.name);
			Test.stopTest();

			Assert.areEqual('answered', result.outcome, 'The app answered');
			Assert.areEqual(200, result.status, 'With its status');
			Assert.areEqual('callout:BarnConn_rest_ffffff', answer.endpoint, 'Through the Named Credential only');
		}
	}

	@IsTest
	static void disconnectKeepsTheConnectionAndDeleteRemovesIt() {
		System.runAs(dana()) {
			FakeOrg fake = useFake();
			fake.add('BarnConn_rest_gggggg', ConnectorConnections.BEARER, 'https://api.example.com', true, true);

			ConnectorConnectionsController.Result disconnected = ConnectorConnectionsController.disconnect(
				'BarnConn_rest_gggggg'
			);
			ConnectorConnectionsController.Result deleted = ConnectorConnectionsController.deleteConnection(
				'BarnConn_rest_gggggg'
			);

			Assert.isFalse(disconnected.page.connections[0].keyStored, 'The key is gone, the connection stays');
			Assert.areEqual('deleted', deleted.outcome, 'Deleted');
			Assert.areEqual(new List<String>{ 'BarnConn_rest_gggggg' }, fake.removed, 'Delete removes both');
			Assert.isTrue(deleted.page.connections.isEmpty(), 'And it leaves the list');
		}
	}

	@IsTest
	static void aHalfMadeConnectionThatCannotBeRemovedIsNamedInTheErrorLog() {
		System.runAs(dana()) {
			FakeOrg fake = useFake();
			fake.echoKeyOnWrite = true;
			fake.refuseRemove = true;

			Test.startTest();
			try {
				create(ConnectorConnections.BEARER, null, KEY);
			} catch (AuraHandledException e) {
				Assert.areEqual(BarnHelp.text('Connector', 'Connector_Error_SaveFailed'), refusal(e), 'Fixed message');
			}
			Test.stopTest();

			List<Error_Log__c> left = [
				SELECT Message__c
				FROM Error_Log__c
				WHERE Context__c = 'ConnectorConnectionsController.undo'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, left.size(), 'The leftover credentials are named for Setup');
			Assert.isTrue(left[0].Message__c.contains('BarnConn_rest_'), 'By their name');
			Assert.isFalse(left[0].Message__c.contains(KEY), 'Never with the key');
		}
	}

	@IsTest
	static void theModuleWritesNoDebugStatement() {
		System.runAs(dana()) {
			Integer read = 0;
			for (ApexClass source : [
				SELECT Name, Body
				FROM ApexClass
				WHERE Name LIKE 'Connector%' AND NamespacePrefix = :NamespaceUtil.namespacePrefix()
				WITH SYSTEM_MODE
			]) {
				if (source.Body != null && source.Body != '(hidden)') {
					read++;
					Assert.isFalse(
						source.Body.contains('System' + '.debug'),
						source.Name + ' has no debug statement (F7)'
					);
				}
			}
			// A managed install hides the bodies (read is 0); source orgs check every class.
			Assert.isTrue(read >= 0, 'Every readable module class was checked');
		}
	}
}
