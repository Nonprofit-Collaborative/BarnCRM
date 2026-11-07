/**
 * Deactivate Org Flows and Validation Rules, and Restore (canonical model Section 10A, R-AS4 to
 * R-AS8): the snapshot is saved before any change, only the org's own active items change, each
 * result is kept, and Restore puts back exactly the snapshot. The Tooling API is mocked.
 */
@IsTest(testFor='ApexClass:OrgAutomationDeactivation')
private class OrgAutomationDeactivationTest {
	private static final List<String> CONNECTION_ADMIN = new List<String>{
		'BarnCRM_Admin',
		'BarnCRM_Metadata_Admin'
	};
	private static final String FLOW_ID = '300000000000001AAA';
	private static final String PKG_FLOW_ID = '300000000000002AAA';
	private static final String RULE_ID = '03d000000000001AAA';
	private static final String REFUSED_RULE_ID = '03d000000000002AAA';

	/** Answers reads by object, and records each write's path and body. */
	private class ToolingMock implements HttpCalloutMock {
		public List<String> writes = new List<String>();

		public HttpResponse respond(HttpRequest request) {
			HttpResponse response = new HttpResponse();
			response.setStatusCode(200);
			String endpoint = EncodingUtil.urlDecode(request.getEndpoint(), 'UTF-8');
			if (request.getMethod() == 'PATCH') {
				writes.add(endpoint.substringAfter('sobjects/') + ' ' + request.getBody());
				if (endpoint.contains(REFUSED_RULE_ID)) {
					response.setStatusCode(400);
					response.setBody(
						'[{"message":"The formula has an error","errorCode":"FIELD_INTEGRITY_EXCEPTION"}]'
					);
				} else {
					response.setStatusCode(204);
				}
				return response;
			}
			if (endpoint.contains('sobjects/ValidationRule/')) {
				response.setBody(
					JSON.serialize(
						new Map<String, Object>{
							'Metadata' => new Map<String, Object>{
								'active' => true,
								'errorConditionFormula' => 'Amount__c = null',
								'errorMessage' => 'Amount is required.'
							}
						}
					)
				);
				return response;
			}
			List<Object> records = new List<Object>();
			if (endpoint.contains('FROM FlowDefinition')) {
				records.add(
					new Map<String, Object>{
						'Id' => FLOW_ID,
						'DeveloperName' => 'My_Gift_Flow',
						'ActiveVersion' => new Map<String, Object>{ 'VersionNumber' => 3 }
					}
				);
				records.add(
					new Map<String, Object>{
						'Id' => PKG_FLOW_ID,
						'DeveloperName' => 'Pkg_Flow',
						'NamespacePrefix' => 'otherpkg',
						'ActiveVersion' => new Map<String, Object>{ 'VersionNumber' => 1 }
					}
				);
			} else if (endpoint.contains('FROM ValidationRule')) {
				records.add(new Map<String, Object>{ 'Id' => RULE_ID, 'Active' => true });
				records.add(new Map<String, Object>{ 'Id' => REFUSED_RULE_ID, 'Active' => true });
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

	private static OrgAutomationDeactivation.Item item(String kind, String recordId) {
		OrgAutomationDeactivation.Item item = new OrgAutomationDeactivation.Item();
		item.kind = kind;
		item.recordId = recordId;
		item.name = recordId;
		return item;
	}

	private static Map<String, OrgAutomationDeactivation.Item> itemsOf(Id snapshotId) {
		Automation_Snapshot__c snapshot = [
			SELECT Items__c
			FROM Automation_Snapshot__c
			WHERE Id = :snapshotId
		];
		Map<String, OrgAutomationDeactivation.Item> byId = new Map<String, OrgAutomationDeactivation.Item>();
		for (
			OrgAutomationDeactivation.Item each : (List<OrgAutomationDeactivation.Item>) JSON.deserialize(
				snapshot.Items__c,
				List<OrgAutomationDeactivation.Item>.class
			)
		) {
			byId.put(each.recordId, each);
		}
		return byId;
	}

	@IsTest
	static void theSnapshotIsSavedBeforeAnythingChanges() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			connected();
			ToolingMock mock = new ToolingMock();
			Test.setMock(HttpCalloutMock.class, mock);
			Test.startTest();
			Id snapshotId = OrgAutomationController.deactivate(
				JSON.serialize(
					new List<OrgAutomationDeactivation.Item>{
						item('Flow', FLOW_ID),
						item('ProcessBuilder', PKG_FLOW_ID),
						item('ValidationRule', RULE_ID)
					}
				)
			);
			Test.stopTest();

			Assert.isTrue(mock.writes.isEmpty(), 'Nothing changes in the snapshot job.');
			Map<String, OrgAutomationDeactivation.Item> items = itemsOf(snapshotId);
			Assert.areEqual(OrgAutomationDeactivation.RESULT_PENDING, items.get(FLOW_ID).result);
			Assert.areEqual(3, items.get(FLOW_ID).activeVersion, 'The active version is kept.');
			Assert.areEqual(
				OrgAutomationDeactivation.RESULT_UNCHANGED,
				items.get(PKG_FLOW_ID).result,
				'A managed package flow is never changed.'
			);
			Assert.areEqual(OrgAutomationDeactivation.RESULT_PENDING, items.get(RULE_ID).result);
			Assert.isTrue(items.get(RULE_ID).wasActive);
		}
	}

	@IsTest
	static void eachItemIsChangedAndAFailureIsKeptWithItsReason() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			OrgAutomationDeactivation.Item flow = item('Flow', FLOW_ID);
			flow.wasActive = true;
			flow.activeVersion = 3;
			flow.result = OrgAutomationDeactivation.RESULT_PENDING;
			OrgAutomationDeactivation.Item rule = item('ValidationRule', RULE_ID);
			rule.wasActive = true;
			rule.result = OrgAutomationDeactivation.RESULT_PENDING;
			OrgAutomationDeactivation.Item refused = item('ValidationRule', REFUSED_RULE_ID);
			refused.wasActive = true;
			refused.result = OrgAutomationDeactivation.RESULT_PENDING;
			Automation_Snapshot__c snapshot = new Automation_Snapshot__c(
				Kind__c = 'Deactivation',
				Status__c = 'Running',
				Items__c = JSON.serialize(
					new List<OrgAutomationDeactivation.Item>{ flow, rule, refused }
				)
			);
			insert snapshot;
			ToolingMock mock = new ToolingMock();
			Test.setMock(HttpCalloutMock.class, mock);
			Test.startTest();
			System.enqueueJob(
				new OrgAutomationDeactivation(snapshot.Id, OrgAutomationDeactivation.MODE_APPLY)
			);
			Test.stopTest();

			Map<String, OrgAutomationDeactivation.Item> items = itemsOf(snapshot.Id);
			Assert.areEqual(OrgAutomationDeactivation.RESULT_CHANGED, items.get(FLOW_ID).result);
			Assert.areEqual(OrgAutomationDeactivation.RESULT_CHANGED, items.get(RULE_ID).result);
			Assert.areEqual(
				OrgAutomationDeactivation.RESULT_FAILED,
				items.get(REFUSED_RULE_ID).result
			);
			Assert.isTrue(items.get(REFUSED_RULE_ID).message.contains('The formula has an error'));
			Assert.areEqual(
				'Partial',
				[SELECT Status__c FROM Automation_Snapshot__c WHERE Id = :snapshot.Id].Status__c
			);
			Assert.isTrue(mock.writes[0].contains('"activeVersionNumber":0'), mock.writes[0]);
			Assert.isTrue(mock.writes[1].contains('"active":false'), mock.writes[1]);
		}
	}

	@IsTest
	static void restorePutsBackExactlyWhatChanged() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			connected();
			OrgAutomationDeactivation.Item flow = item('Flow', FLOW_ID);
			flow.wasActive = true;
			flow.activeVersion = 3;
			flow.result = OrgAutomationDeactivation.RESULT_CHANGED;
			OrgAutomationDeactivation.Item untouched = item('Flow', PKG_FLOW_ID);
			untouched.result = OrgAutomationDeactivation.RESULT_UNCHANGED;
			Automation_Snapshot__c snapshot = new Automation_Snapshot__c(
				Kind__c = 'Deactivation',
				Status__c = 'Done',
				Items__c = JSON.serialize(
					new List<OrgAutomationDeactivation.Item>{ flow, untouched }
				)
			);
			insert snapshot;
			ToolingMock mock = new ToolingMock();
			Test.setMock(HttpCalloutMock.class, mock);
			Test.startTest();
			OrgAutomationController.restore(snapshot.Id);
			Test.stopTest();

			Assert.areEqual(1, mock.writes.size(), 'Only what changed is put back.');
			Assert.isTrue(mock.writes[0].contains('"activeVersionNumber":3'), mock.writes[0]);
			Automation_Snapshot__c after = [
				SELECT Status__c, Restored_At__c
				FROM Automation_Snapshot__c
				WHERE Id = :snapshot.Id
			];
			Assert.areEqual('Restored', after.Status__c);
			Assert.isNotNull(after.Restored_At__c);
			Assert.areEqual(
				OrgAutomationDeactivation.RESULT_CHANGED,
				itemsOf(snapshot.Id).get(FLOW_ID).restoreResult
			);
		}
	}

	@IsTest
	static void oneRunAtATimeAndOnlyFlowsAndRules() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			connected();
			String refused;
			try {
				OrgAutomationController.deactivate(
					JSON.serialize(
						new List<OrgAutomationDeactivation.Item>{
							item('ApexTrigger', '01q000000000001AAA')
						}
					)
				);
			} catch (AuraHandledException caught) {
				refused = caught.getMessage();
			}
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_AutomationDeactivate_ChooseItems'),
				refused
			);

			insert new Automation_Snapshot__c(Kind__c = 'Deactivation', Status__c = 'Running');
			try {
				OrgAutomationController.deactivate(
					JSON.serialize(
						new List<OrgAutomationDeactivation.Item>{ item('Flow', FLOW_ID) }
					)
				);
			} catch (AuraHandledException caught) {
				refused = caught.getMessage();
			}
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_AutomationDeactivate_AlreadyRunning'),
				refused
			);
		}
	}

	@IsTest
	static void theStatusSaysHowItWent() {
		// runs-as: deploying user (in-memory items only; nothing is read or saved)
		OrgAutomationDeactivation.Item changed = item('Flow', FLOW_ID);
		changed.result = OrgAutomationDeactivation.RESULT_CHANGED;
		OrgAutomationDeactivation.Item failed = item('Flow', PKG_FLOW_ID);
		failed.result = OrgAutomationDeactivation.RESULT_FAILED;
		Assert.areEqual(
			'Done',
			OrgAutomationDeactivation.finalStatus(
				new List<OrgAutomationDeactivation.Item>{ changed },
				false
			)
		);
		Assert.areEqual(
			'Failed',
			OrgAutomationDeactivation.finalStatus(
				new List<OrgAutomationDeactivation.Item>{ failed },
				false
			)
		);
	}
}
