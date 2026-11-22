/**
 * Dana, the system administrator, makes a connection the backup destination, and Backup Sets
 * send their files through it (BK-10; canonical model R-CN11, R-SQ17). A test cannot create a
 * Named Credential, so the credential store is a fake; the callout is an HttpCalloutMock.
 */
@IsTest(testFor='ApexClass:ConnectorBackupDestination, ApexClass:ConnectorConnectionsController, ApexClass:ConnectorRecipeFiles')
private class ConnectorBackupDestinationTest {
	private static final String FIRST = 'BarnConn_rest_aaaaaa';
	private static final String SECOND = 'BarnConn_rest_bbbbbb';

	/** The credential store, faked: two connections of this org. */
	private class FakeOrg extends ConnectorOrg {
		Map<String, ConnectorOrg.Pair> pairs = new Map<String, ConnectorOrg.Pair>();

		FakeOrg() {
			fake = true;
			for (String name : new List<String>{ FIRST, SECOND }) {
				ConnectorOrg.Pair pair = new ConnectorOrg.Pair();
				pair.name = name;
				pair.label = 'Storage ' + name.right(1);
				pair.principal = ConnectorConnections.BASIC;
				pair.url = 'https://files.example.org';
				pair.linked = true;
				pair.calloutsEnabled = true;
				pair.keyStored = true;
				pairs.put(name, pair);
			}
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
	}

	/** The storage service: answers `status` and keeps the request it was sent. */
	private class Storage implements HttpCalloutMock {
		Integer status;
		HttpRequest received;
		Storage(Integer status) {
			this.status = status;
		}
		public HttpResponse respond(HttpRequest request) {
			received = request;
			HttpResponse response = new HttpResponse();
			response.setStatusCode(status);
			return response;
		}
	}

	@TestSetup
	static void createTestUsers() {
		User dana;
		System.runAs(TestUsers.admin()) {
			dana = dana();
		}
		System.runAs(TestUsers.admin()) {
			PermissionSet access = new PermissionSet(
				Name = ConnectorConnections.ACCESS_SET,
				Label = ConnectorConnections.ACCESS_SET_LABEL
			);
			insert access;
			insert new PermissionSetAssignment(AssigneeId = dana.Id, PermissionSetId = access.Id);
		}
	}

	private static User dana() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static void useFake() {
		ConnectorConnections.org = new FakeOrg();
		ConnectorConnections.credentialPermissionOverride = true;
	}

	private static String refusalOf(String method, String path, String headers) {
		try {
			ConnectorConnectionsController.saveBackupDestination(FIRST, method, path, headers);
			return null;
		} catch (AuraHandledException refused) {
			return refused.getMessage();
		}
	}

	@IsTest
	static void unsafeSettingsAreRefusedAndNothingSecretIsKept() {
		System.runAs(dana()) {
			useFake();
			String badPath = BarnHelp.text('Connector', 'Connector_Backup_ErrorPath');
			String badHeader = BarnHelp.text('Connector', 'Connector_Backup_ErrorHeader');
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Backup_ErrorMethod'), refusalOf('GET', '/{file}', null));
			Assert.areEqual(badPath, refusalOf('PUT', '/backups', null), 'No file slot');
			Assert.areEqual(badPath, refusalOf('PUT', '/{file}/{file}', null), 'Two file slots');
			Assert.areEqual(badPath, refusalOf('PUT', '/{file}?sig=abc', null), 'A query');
			Assert.areEqual(badPath, refusalOf('PUT', '/{!$Credential.x}/{file}', null), 'A merge field');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'X-Api-Key: abc'), 'A sign-in header');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'Authorization: Basic abc'), 'Authorization');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'X-Folder'), 'No colon');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'A: 1\nB: 2\nC: 3\nD: 4\nE: 5\nF: 6'), 'Six');
			Assert.areEqual(0, [SELECT COUNT() FROM Connector_Connection__c], 'Nothing kept');
		}
	}

	@IsTest
	static void oneConnectionIsTheDestinationAndEachFileIsOneRequest() {
		System.runAs(dana()) {
			useFake();
			ConnectorConnectionsController.saveBackupDestination(FIRST, 'POST', '/old/{file}', null);
			ConnectorBackupDestination.Setup setup = ConnectorConnectionsController.saveBackupDestination(
				SECOND,
				'put',
				' /barncrm/{file} ',
				'Overwrite: T\n\nX-Folder: crm'
			);
			Assert.areEqual(SECOND, setup.name, 'The last saved is the destination');
			Assert.areEqual('PUT', setup.settings.method);
			Assert.areEqual('/barncrm/{file}', setup.settings.path);
			Assert.areEqual(2, setup.settings.headers.size(), 'Blank lines skipped');
			Assert.isNull(setup.note, 'Dana holds BarnCRM Connections');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Connector_Connection__c WHERE Name = :FIRST],
				'The first row is kept, without settings'
			);

			Storage storage = new Storage(201);
			Test.setMock(HttpCalloutMock.class, storage);
			OffPlatformDestination destination = (OffPlatformDestination) new ConnectorBackupDestination();
			Test.startTest();
			String sent = destination.send('Contact 2026-11-21 part-1.csv', Blob.valueOf('Id\r\n1\r\n'));
			Test.stopTest();

			Assert.isNull(sent, 'A 2xx answer is sent');
			Assert.areEqual('offPlatform', destination.key());
			Assert.areEqual('callout:' + SECOND + '/barncrm/Contact%202026-11-21%20part-1.csv', storage.received.getEndpoint());
			Assert.areEqual('PUT', storage.received.getMethod());
			Assert.areEqual('text/csv', storage.received.getHeader('Content-Type'));
			Assert.areEqual('crm', storage.received.getHeader('X-Folder'));
			Assert.areEqual('Id\r\n1\r\n', storage.received.getBody());
		}
	}

	@IsTest
	static void aRefusedAnswerIsAFailureThatNamesTheStatus() {
		System.runAs(dana()) {
			useFake();
			ConnectorConnectionsController.saveBackupDestination(FIRST, 'PUT', '/{file}', null);
			Test.setMock(HttpCalloutMock.class, new Storage(403));
			Test.startTest();
			String failure = new ConnectorBackupDestination().send('a.csv', Blob.valueOf('x'));
			Test.stopTest();
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Backup_Refused', new List<Object>{ 403 }), failure);
		}
	}

	@IsTest
	static void stopUsingLeavesNoDestinationAndSaysWhy() {
		System.runAs(dana()) {
			useFake();
			ConnectorConnectionsController.saveBackupDestination(FIRST, 'PUT', '/{file}', null);
			ConnectorBackupDestination.Setup setup = ConnectorConnectionsController.stopBackupDestination();
			Assert.isNull(setup.name, 'None');
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Backup_NotSet'), setup.note);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Backup_NotSet'),
				new ConnectorBackupDestination().send('a.csv', Blob.valueOf('x')),
				'Nothing is sent'
			);
		}
	}

	@IsTest
	static void staffWithoutTheConnectionsSetAreToldWhyTheyCannotSend() {
		System.runAs(dana()) {
			useFake();
			ConnectorConnectionsController.saveBackupDestination(FIRST, 'PUT', '/{file}', null);
		}
		User staff = TestUsers.standardUserWith('BackupStaff', new List<String>{ 'BarnCRM_Find_And_Export' });
		System.runAs(staff) {
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Backup_NoAccess'),
				new ConnectorBackupDestination().notReady()
			);
			try {
				ConnectorBackupDestination.setup();
				Assert.fail('Only Connector admins see the section');
			} catch (ConnectorConnections.ConnectorException refused) {
				Assert.areEqual(BarnHelp.text('Connector', 'Connector_Error_NoManage'), refused.getMessage());
			}
			try {
				ConnectorConnectionsController.saveBackupDestination(SECOND, 'PUT', '/{file}', null);
				Assert.fail('Refused');
			} catch (AuraHandledException refused) {
				Assert.areEqual(BarnHelp.text('Connector', 'Connector_Error_NoManage'), refused.getMessage());
			}
		}
	}

	@IsTest
	static void aTemplateMayPrefillTheBackupPart() {
		System.runAs(dana()) {
			String template = JSON.serialize(
				new Map<String, Object>{
					'key' => 'webdav',
					'label' => 'WebDAV Folder',
					'version' => 1,
					'auth' => new Map<String, Object>{ 'kind' => 'BasicAuth' },
					'baseUrl' => '',
					'backup' => new Map<String, Object>{
						'method' => 'PUT',
						'path' => '/{file}',
						'headers' => new List<Object>{ new Map<String, Object>{ 'name' => 'Overwrite', 'value' => 'T' } }
					}
				}
			);
			ConnectorRecipeFiles.Imported imported = ConnectorRecipesController.importFile(template);
			Assert.areEqual('PUT', imported.connection.backup.method);
			Assert.areEqual('Overwrite', imported.connection.backup.headers[0].name);
			Assert.isTrue(String.isBlank(imported.connection.baseUrl), 'Storage of its own: the address is typed');

			Map<String, Object> app = (Map<String, Object>) JSON.deserializeUntyped(template);
			app.remove('backup');
			try {
				ConnectorRecipesController.importFile(JSON.serialize(app));
				Assert.fail('An app template keeps its address');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused.getMessage(), 'Refused');
			}

			Map<String, Object> unsafe = (Map<String, Object>) JSON.deserializeUntyped(template);
			((Map<String, Object>) unsafe.get('backup')).put('path', '/{file}?key=abc');
			try {
				ConnectorRecipesController.importFile(JSON.serialize(unsafe));
				Assert.fail('Refused');
			} catch (AuraHandledException refused) {
				Assert.isTrue(refused.getMessage().contains('backup'), 'Names the part');
			}
		}
	}
}
