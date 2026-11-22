/**
 * Dana, the system administrator, makes a connection the backup destination, and Backup Sets
 * send their files through it (BK-10; canonical model R-CN11, R-SQ17). A test cannot create a
 * Named Credential, so the credential store is a fake; the callout is an HttpCalloutMock.
 */
@IsTest(
	testFor='ApexClass:ConnectorBackupDestination, ApexClass:ConnectorConnectionsController, ApexClass:ConnectorRecipeFiles'
)
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
			ConnectorConnectionsController.saveBackupDestination(FIRST, method, path, headers, null);
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
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Backup_ErrorMethod'),
				refusalOf('GET', '/{file}', null)
			);
			Assert.areEqual(badPath, refusalOf('PUT', '/backups', null), 'No file slot');
			Assert.areEqual(badPath, refusalOf('PUT', '/{file}/{file}', null), 'Two file slots');
			Assert.areEqual(badPath, refusalOf('PUT', '/{file}?sig=abc', null), 'A query');
			Assert.areEqual(badPath, refusalOf('PUT', '/{!$Credential.x}/{file}', null), 'A merge field');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'X-Api-Key: abc'), 'A sign-in header');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'Authorization: Basic abc'), 'Authorization');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'X-Folder'), 'No colon');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'X-Pass: Bearer abc'), 'A bearer value');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'X-Pass: basic abc'), 'A basic value, any case');
			Assert.areEqual(badPath, refusalOf('PUT', '/a/../{file}', null), 'A parent segment');
			Assert.areEqual(badHeader, refusalOf('PUT', '/{file}', 'A: 1\nB: 2\nC: 3\nD: 4\nE: 5\nF: 6'), 'Six');
			Assert.areEqual(0, [SELECT COUNT() FROM Connector_Connection__c], 'Nothing kept');
		}
	}

	@IsTest
	static void oneConnectionIsTheDestinationAndEachFileIsOneRequest() {
		System.runAs(dana()) {
			useFake();
			ConnectorConnectionsController.saveBackupDestination(FIRST, 'POST', '/old/{file}', null, null);
			ConnectorBackupDestination.Setup setup = ConnectorConnectionsController.saveBackupDestination(
				SECOND,
				'put',
				' /barncrm/{file} ',
				'Overwrite: T\n\nX-Folder: crm',
				null
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
			Assert.areEqual(
				'callout:' + SECOND + '/barncrm/Contact%202026-11-21%20part-1.csv',
				storage.received.getEndpoint()
			);
			Assert.areEqual('PUT', storage.received.getMethod());
			Assert.areEqual('text/csv', storage.received.getHeader('Content-Type'));
			Assert.areEqual('crm', storage.received.getHeader('X-Folder'));
			Assert.areEqual('Id\r\n1\r\n', storage.received.getBody());
			Assert.isNull(destination.partChars(), 'Without metadata, Core keeps its own part size');
			ConnectorConnectionsController.saveBackupDestination(
				SECOND,
				'POST',
				'/upload/{file}?uploadType=multipart',
				null,
				'{"name":"{file}"}'
			);
			Assert.areEqual(
				ConnectorBackupDestination.MULTIPART_PART_CHARS,
				destination.partChars(),
				'A multipart upload asks for smaller parts'
			);
		}
	}

	@IsTest
	static void aRefusedAnswerIsAFailureThatNamesTheStatus() {
		System.runAs(dana()) {
			useFake();
			ConnectorConnectionsController.saveBackupDestination(FIRST, 'PUT', '/{file}', null, null);
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
			ConnectorConnectionsController.saveBackupDestination(FIRST, 'PUT', '/{file}', null, null);
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
			ConnectorConnectionsController.saveBackupDestination(FIRST, 'PUT', '/{file}', null, null);
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
				ConnectorConnectionsController.saveBackupDestination(SECOND, 'PUT', '/{file}', null, null);
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
						'headers' => new List<Object>{
							new Map<String, Object>{ 'name' => 'Overwrite', 'value' => 'T' }
						}
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

	/** A storage template, as the files in docs/connector-templates hold it, imported. */
	private static ConnectorBackupDestination.Settings imported(
		String kind,
		String baseUrl,
		Map<String, Object> backup
	) {
		Map<String, Object> template = new Map<String, Object>{
			'key' => 'storage',
			'label' => 'Storage',
			'version' => 1,
			'auth' => new Map<String, Object>{ 'kind' => kind },
			'baseUrl' => baseUrl,
			'backup' => backup
		};
		if (baseUrl.contains('{bucket}')) {
			template.put(
				'urlParams',
				new List<Object>{
					new Map<String, Object>{ 'name' => 'bucket', 'label' => 'Bucket', 'pattern' => '^[a-z0-9-]+$' },
					new Map<String, Object>{ 'name' => 'region', 'label' => 'Region', 'pattern' => '^[a-z0-9-]+$' }
				}
			);
		}
		return ConnectorRecipesController.importFile(JSON.serialize(template)).connection.backup;
	}

	private static Map<String, Object> backup(String method, String path, List<Object> headers) {
		return new Map<String, Object>{ 'method' => method, 'path' => path, 'headers' => headers };
	}

	private static Map<String, Object> header(String name, String value) {
		return new Map<String, Object>{ 'name' => name, 'value' => value };
	}

	@IsTest
	static void s3OneDriveAndAzureNameTheFileInThePath() {
		System.runAs(dana()) {
			Blob body = Blob.valueOf('Id\r\n1\r\n');
			HttpRequest s3 = ConnectorBackupDestination.request(
				'BarnConn_rest_s3aaaa',
				imported(
					'AwsSigV4',
					'https://{bucket}.s3.{region}.amazonaws.com',
					backup('PUT', '/barncrm/{file}', null)
				),
				'Contact part-1.csv',
				body
			);
			Assert.areEqual('callout:BarnConn_rest_s3aaaa/barncrm/Contact%20part-1.csv', s3.getEndpoint());
			Assert.areEqual('PUT', s3.getMethod());
			Assert.areEqual('text/csv', s3.getHeader('Content-Type'));
			Assert.isNull(s3.getHeader('Authorization'), 'Salesforce signs it; Apex sets no sign-in');

			HttpRequest oneDrive = ConnectorBackupDestination.request(
				'BarnConn_onedrive',
				imported(
					'OAuth',
					'https://graph.microsoft.com',
					backup('PUT', '/v1.0/me/drive/root:/BarnCRM-Backups/{file}:/content', null)
				),
				'a.csv',
				body
			);
			Assert.areEqual(
				'callout:BarnConn_onedrive/v1.0/me/drive/root:/BarnCRM-Backups/a.csv:/content',
				oneDrive.getEndpoint()
			);

			HttpRequest azure = ConnectorBackupDestination.request(
				'BarnConn_azureblob',
				imported(
					'OAuth',
					'',
					backup(
						'PUT',
						'/barncrm-backups/{file}',
						new List<Object>{ header('x-ms-blob-type', 'BlockBlob'), header('x-ms-version', '2023-11-03') }
					)
				),
				'a.csv',
				body
			);
			Assert.areEqual('callout:BarnConn_azureblob/barncrm-backups/a.csv', azure.getEndpoint());
			Assert.areEqual('BlockBlob', azure.getHeader('x-ms-blob-type'));
			Assert.areEqual('2023-11-03', azure.getHeader('x-ms-version'));
			Assert.areEqual('Id\r\n1\r\n', azure.getBody());
		}
	}

	@IsTest
	static void dropboxNamesTheFileInAJsonHeader() {
		System.runAs(dana()) {
			ConnectorBackupDestination.Settings settings = imported(
				'OAuth',
				'https://content.dropboxapi.com',
				backup(
					'POST',
					'/2/files/upload',
					new List<Object>{
						header('Dropbox-API-Arg', '{"path":"/BarnCRM-Backups/{file}","mode":"overwrite","mute":true}'),
						header('Content-Type', 'application/octet-stream')
					}
				)
			);
			HttpRequest request = ConnectorBackupDestination.request(
				'BarnConn_dropbox',
				settings,
				'Café "x" part-1.csv',
				Blob.valueOf('Id\r\n1\r\n')
			);
			Assert.areEqual('callout:BarnConn_dropbox/2/files/upload', request.getEndpoint(), 'The path holds no file');
			Assert.areEqual(
				'{"path":"/BarnCRM-Backups/Caf\\u00e9 \\"x\\" part-1.csv","mode":"overwrite","mute":true}',
				request.getHeader('Dropbox-API-Arg'),
				'Escaped for JSON and kept ASCII'
			);
			Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
				request.getHeader('Dropbox-API-Arg')
			);
			Assert.areEqual(
				'/BarnCRM-Backups/Café "x" part-1.csv',
				parsed.get('path'),
				'A name no quote can break out of'
			);
			Assert.areEqual('application/octet-stream', request.getHeader('Content-Type'), 'The header names the type');
		}
	}

	@IsTest
	static void googleDriveSendsMetadataThenTheFile() {
		System.runAs(dana()) {
			Map<String, Object> part = backup('POST', '/upload/drive/v3/files?uploadType=multipart', null);
			part.put(
				'metadata',
				new Map<String, Object>{ 'name' => '{file}', 'parents' => new List<Object>{ 'folder1' } }
			);
			HttpRequest request = ConnectorBackupDestination.request(
				'BarnConn_gdrive',
				imported('OAuth', 'https://www.googleapis.com', part),
				'a.csv',
				Blob.valueOf('Id\r\n1\r\n')
			);
			Assert.areEqual(
				'callout:BarnConn_gdrive/upload/drive/v3/files?uploadType=multipart',
				request.getEndpoint()
			);
			String type = request.getHeader('Content-Type');
			Assert.isTrue(type.startsWith('multipart/related; boundary=barncrm'), type);
			String boundary = type.substringAfter('boundary=');
			String sent = request.getBody();
			Assert.isTrue(sent.startsWith('--' + boundary + '\r\nContent-Type: application/json'), 'Metadata first');
			Assert.isTrue(sent.contains('"name":"a.csv"'), 'Named for the file');
			Assert.isTrue(
				sent.contains('Content-Type: text/csv\r\n\r\nId\r\n1\r\n\r\n--' + boundary + '--'),
				'Then the file'
			);
		}
	}

	@IsTest
	static void aQueryMetadataAndANamelessFileAreChecked() {
		System.runAs(dana()) {
			String badPath = BarnHelp.text('Connector', 'Connector_Backup_ErrorPath');
			String badMetadata = BarnHelp.text('Connector', 'Connector_Backup_ErrorMetadata');
			Assert.areEqual(
				badPath,
				refusalOfChecked('/upload?uploadType=multipart&sig=abc', null, null),
				'A signature'
			);
			Assert.areEqual(badPath, refusalOfChecked('/upload?uploadType=a b', null, null), 'A value with a space');
			Assert.areEqual(
				badPath,
				refusalOfChecked('/2/files/upload', 'X-Folder: crm', null),
				'No file name anywhere'
			);
			Assert.areEqual(badMetadata, refusalOfChecked('/u?uploadType=multipart', null, '[1]'), 'Not an object');
			Assert.areEqual(
				badMetadata,
				refusalOfChecked('/u?uploadType=multipart', null, '{"name":"{!x}"}'),
				'A formula'
			);
			Assert.areEqual(
				badMetadata,
				refusalOfChecked('/u?uploadType=multipart', null, '{"name":"{file}","accessToken":"abc"}'),
				'A sign-in key'
			);
			Assert.isNull(refusalOfChecked('/u?uploadType=multipart', null, '{"name":"{file}"}'), 'Drive is accepted');
			Assert.isNull(refusalOfChecked('/{file}', 'X-Note: Basically fine', null), 'A word that only starts alike');
			Assert.areEqual('a\\nb', ConnectorBackupDestination.jsonText('a\nb'), 'A line break escaped');
			Assert.areEqual('\\u00f1', ConnectorBackupDestination.jsonText('ñ'), 'Outside ASCII as \\u');

			Map<String, Object> noBackup = new Map<String, Object>{
				'key' => 'x',
				'label' => 'X',
				'version' => 1,
				'auth' => new Map<String, Object>{ 'kind' => 'OAuth' },
				'baseUrl' => 'https://api.example.com'
			};
			try {
				ConnectorRecipesController.importFile(JSON.serialize(noBackup));
				Assert.fail('An OAuth template only fills Backup Settings');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused.getMessage(), 'Refused');
			}
		}
	}

	private static String refusalOfChecked(String path, String headerLines, String metadata) {
		try {
			ConnectorBackupDestination.checked(
				'POST',
				path,
				ConnectorBackupDestination.headersOf(headerLines),
				metadata
			);
			return null;
		} catch (ConnectorConnections.ConnectorException refused) {
			return refused.getMessage();
		}
	}
}
