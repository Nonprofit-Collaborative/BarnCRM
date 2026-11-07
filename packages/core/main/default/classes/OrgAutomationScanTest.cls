/**
 * The Automation tab's scan through the org connection (canonical model Section 10A, R-AS1 to
 * R-AS3): validation and workflow rules and what checks the setting, read by a queued job with a
 * mocked Tooling API, saved as one Scan snapshot and merged into the inventory.
 */
@IsTest(testFor='ApexClass:OrgAutomationScan, ApexClass:OrgToolingApi')
private class OrgAutomationScanTest {
	private static final List<String> CONNECTION_ADMIN = new List<String>{
		'BarnCRM_Admin',
		'BarnCRM_Metadata_Admin'
	};
	private static final String RULE_ID = '03d000000000001AAA';
	private static final String OTHER_RULE_ID = '03d000000000002AAA';

	/** Answers each Tooling query by the object it reads. */
	private class ToolingMock implements HttpCalloutMock {
		private final Integer status;

		ToolingMock(Integer status) {
			this.status = status;
		}

		public HttpResponse respond(HttpRequest request) {
			HttpResponse response = new HttpResponse();
			response.setStatusCode(status);
			if (status != 200) {
				response.setBody(
					'[{"message":"Session expired or invalid","errorCode":"INVALID_SESSION_ID"}]'
				);
				return response;
			}
			String query = EncodingUtil.urlDecode(request.getEndpoint(), 'UTF-8');
			List<Map<String, Object>> records = new List<Map<String, Object>>();
			if (query.contains('FROM ValidationRule')) {
				records.add(
					new Map<String, Object>{
						'Id' => RULE_ID,
						'ValidationName' => 'Amount_Required',
						'Active' => true,
						'EntityDefinitionId' => 'Account'
					}
				);
				records.add(
					new Map<String, Object>{
						'Id' => OTHER_RULE_ID,
						'ValidationName' => 'Pkg_Rule',
						'Active' => true,
						'EntityDefinitionId' => 'Account',
						'NamespacePrefix' => 'otherpkg'
					}
				);
			} else if (query.contains('FROM WorkflowRule')) {
				records.add(
					new Map<String, Object>{
						'Id' => '01Q000000000001AAA',
						'Name' => 'Old Rule',
						'TableEnumOrId' => 'Contact'
					}
				);
			} else if (query.contains('FROM MetadataComponentDependency')) {
				records.add(
					new Map<String, Object>{
						'MetadataComponentId' => RULE_ID,
						'MetadataComponentName' => 'Amount_Required'
					}
				);
			}
			response.setBody(JSON.serialize(new Map<String, Object>{ 'records' => records }));
			return response;
		}
	}

	@TestSetup
	static void createUsers() {
		TestUsers.withPermissionSets(CONNECTION_ADMIN);
		TestUsers.admin();
	}

	private static void connected() {
		ImportNewFieldService.systemPermissionOverride = true;
		ImportNewFieldService.connectedOverride = true;
		ImportNewFieldService.calloutStatusOverride = 'Enabled';
	}

	@IsTest
	static void aScanSavesTheRulesAndTheInventoryListsThem() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			connected();
			Test.setMock(HttpCalloutMock.class, new ToolingMock(200));
			Test.startTest();
			OrgAutomationController.startScan();
			Test.stopTest();

			Automation_Snapshot__c scan = OrgAutomationScan.latest();
			Assert.areEqual(
				OrgAutomationScan.STATUS_DONE,
				scan.Status__c,
				'Scan: ' + scan.Message__c
			);

			Map<String, OrgAutomationInventory.Row> rows = new Map<String, OrgAutomationInventory.Row>();
			OrgAutomationInventory.Result result = OrgAutomationController.getInventory();
			for (OrgAutomationInventory.Row row : result.rows) {
				rows.put(row.key, row);
			}
			Assert.areEqual(OrgAutomationScan.STATUS_DONE, result.scanStatus);
			Assert.isTrue(result.connected, 'The connection is ready.');

			OrgAutomationInventory.Row own = rows.get('ValidationRule|' + RULE_ID);
			Assert.areEqual(OrgAutomationInventory.OWNER_ORG, own.owner);
			Assert.areEqual(OrgAutomationInventory.STATUS_ACTIVE, own.status);
			Assert.areEqual(
				OrgAutomationInventory.COVERED_YES,
				own.covered,
				'It refers to the setting.'
			);
			Assert.isTrue(own.canDeactivate);

			OrgAutomationInventory.Row managed = rows.get('ValidationRule|' + OTHER_RULE_ID);
			Assert.areEqual('otherpkg', managed.owner);
			Assert.areEqual(OrgAutomationInventory.COVERED_NO, managed.covered);
			Assert.isFalse(managed.canDeactivate, 'A managed package rule is never offered.');

			OrgAutomationInventory.Row workflow = rows.get('WorkflowRule|01Q000000000001AAA');
			Assert.areEqual('Contact', workflow.objectName);
			Assert.isNull(workflow.status, 'A workflow rule\'s state is not read.');
			Assert.isFalse(workflow.canDeactivate);
		}
	}

	@IsTest
	static void aSecondScanReplacesTheFirst() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			connected();
			insert new Automation_Snapshot__c(Kind__c = 'Scan', Status__c = 'Done');
			Test.setMock(HttpCalloutMock.class, new ToolingMock(200));
			Test.startTest();
			OrgAutomationScan.start();
			Test.stopTest();
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Automation_Snapshot__c WHERE Kind__c = 'Scan'],
				'One scan is kept.'
			);
		}
	}

	@IsTest
	static void aRefusedCallIsSavedAsAFailedScanInWords() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			connected();
			Test.setMock(HttpCalloutMock.class, new ToolingMock(401));
			Test.startTest();
			OrgAutomationScan.start();
			Test.stopTest();
			Automation_Snapshot__c scan = OrgAutomationScan.latest();
			Assert.areEqual(OrgAutomationScan.STATUS_FAILED, scan.Status__c);
			Assert.isTrue(scan.Message__c.contains('Session expired or invalid'), scan.Message__c);
		}
	}

	@IsTest
	static void aScanNeedsTheConnectionAndItsPermissions() {
		System.runAs(TestUsers.admin()) {
			User maria = TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
			String refused;
			System.runAs(maria) {
				try {
					OrgAutomationController.startScan();
				} catch (AuraHandledException caught) {
					refused = caught.getMessage();
				}
			}
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_AutomationInventory_NoConnectionPermission'),
				refused
			);
		}
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			ImportNewFieldService.systemPermissionOverride = true;
			ImportNewFieldService.connectedOverride = false;
			String refused;
			try {
				OrgAutomationController.startScan();
			} catch (AuraHandledException caught) {
				refused = caught.getMessage();
			}
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_AutomationInventory_ConnectionNeeded'),
				refused
			);
		}
	}
}
