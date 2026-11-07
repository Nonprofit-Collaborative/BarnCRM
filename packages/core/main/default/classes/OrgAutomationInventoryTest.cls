/**
 * The Automation tab's inventory (C-60, D-184): BarnCRM's switches, flows and triggers in one
 * list, with owner and whether Pause All covers each. Read as Maria, who holds only BarnCRM
 * Admin, so what comes back is what that permission set lets her see.
 */
@IsTest(testFor='ApexClass:OrgAutomationInventory, ApexClass:OrgAutomationController')
private class OrgAutomationInventoryTest {
	private static final String NAMING = 'Household_Naming';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static User maria() {
		return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
	}

	private static Map<String, OrgAutomationInventory.Row> byKey(
		OrgAutomationInventory.Result result
	) {
		Map<String, OrgAutomationInventory.Row> found = new Map<String, OrgAutomationInventory.Row>();
		for (OrgAutomationInventory.Row row : result.rows) {
			found.put(row.key, row);
		}
		return found;
	}

	@IsTest
	static void barnCrmSwitchesTriggersAndTemplatesAreListedAndCovered() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => false });
			OrgAutomationInventory.Result result;
			System.runAs(maria()) {
				result = OrgAutomationController.getInventory();
			}
			Map<String, OrgAutomationInventory.Row> rows = byKey(result);

			OrgAutomationInventory.Row naming = rows.get('BarnCRM|' + NAMING);
			Assert.isNotNull(naming, 'A BarnCRM switch is listed.');
			Assert.areEqual(OrgAutomationInventory.STATUS_OFF, naming.status, 'Its switch is off.');
			Assert.areEqual(OrgAutomationInventory.OWNER_BARN, naming.owner);
			Assert.areEqual(OrgAutomationInventory.COVERED_YES, naming.covered);

			OrgAutomationInventory.Row contactTrigger = rows.get('ApexTrigger|ContactTrigger');
			Assert.isNotNull(contactTrigger, 'A BarnCRM trigger is listed.');
			Assert.areEqual(OrgAutomationInventory.OWNER_BARN, contactTrigger.owner);
			Assert.areEqual(OrgAutomationInventory.COVERED_YES, contactTrigger.covered);
			Assert.areEqual('Contact', contactTrigger.objectName);
			Assert.isFalse(contactTrigger.canDeactivate, 'A trigger is never deactivated here.');

			OrgAutomationInventory.Row errors = rows.get('ApexTrigger|ErrorLogEventTrigger');
			Assert.areEqual(OrgAutomationInventory.OWNER_BARN, errors.owner);
			Assert.areEqual(
				OrgAutomationInventory.COVERED_NO,
				errors.covered,
				'Recording errors is never paused (R-A3).'
			);

			OrgAutomationInventory.Row template = rows.get('Flow|Template_Account_Address_Capture');
			Assert.isNotNull(template, 'A BarnCRM flow template is listed.');
			Assert.areEqual(OrgAutomationInventory.OWNER_BARN, template.owner);
			Assert.areEqual(OrgAutomationInventory.COVERED_YES, template.covered);
			Assert.isFalse(template.canDeactivate, 'BarnCRM items are never offered.');
			Assert.isTrue(result.unreadable.isEmpty(), 'Every part was read.');
		}
	}

	@IsTest
	static void anAlwaysRunsSwitchIsNotCovered() {
		System.runAs(TestUsers.admin()) {
			insert new Automation_Setting__c(
				Name = 'Receipt lock',
				Automation_Name__c = 'Receipt_Lock_Test',
				Enabled__c = true,
				Always_Runs__c = true,
				Is_Package_Default__c = true
			);
			OrgAutomationInventory.Row row;
			System.runAs(maria()) {
				row = byKey(OrgAutomationInventory.build()).get('BarnCRM|Receipt_Lock_Test');
			}
			Assert.areEqual(OrgAutomationInventory.STATUS_ALWAYS, row.status);
			Assert.areEqual(OrgAutomationInventory.COVERED_NO, row.covered);
		}
	}

	@IsTest
	static void anOrgFlowIsNotCheckedAndCanBeDeactivatedWhileActive() {
		// runs-as: deploying user (rows built in memory; no record or permission is read)
		Map<String, Object> values = new Map<String, Object>{
			'DurableId' => '300000000000001AAA',
			'ApiName' => 'My_Gift_Flow',
			'Label' => 'My Gift Flow',
			'IsActive' => true,
			'ProcessType' => 'AutoLaunchedFlow',
			'TriggerType' => 'RecordAfterSave',
			'TriggerObjectOrEventId' => 'Account'
		};
		SObject row = (SObject) JSON.deserialize(JSON.serialize(values), FlowDefinitionView.class);
		OrgAutomationInventory.Row own = OrgAutomationInventory.flowRow(row);
		Assert.areEqual(OrgAutomationInventory.OWNER_ORG, own.owner);
		Assert.areEqual(OrgAutomationInventory.COVERED_UNKNOWN, own.covered);
		Assert.areEqual('After save', own.detail);
		Assert.isTrue(own.canDeactivate);

		values.put('NamespacePrefix', 'otherpkg');
		values.put('ProcessType', 'Workflow');
		OrgAutomationInventory.Row managed = OrgAutomationInventory.flowRow(
			(SObject) JSON.deserialize(JSON.serialize(values), FlowDefinitionView.class)
		);
		Assert.areEqual('otherpkg', managed.owner, 'A managed flow is owned by its namespace.');
		Assert.areEqual(OrgAutomationInventory.KIND_PROCESS, managed.kind);
		Assert.areEqual(OrgAutomationInventory.COVERED_NO, managed.covered);
		Assert.isFalse(managed.canDeactivate, 'A managed package item is never offered.');
	}

	@IsTest
	static void anOrgTriggerIsCoveredOnlyWhenItAsksTheSetting() {
		// runs-as: deploying user (rows built in memory; no record or permission is read)
		Map<String, Object> values = new Map<String, Object>{
			'Name' => 'GiftTriggerOwn',
			'Status' => 'Active',
			'TableEnumOrId' => 'Account',
			'Body' => 'trigger GiftTriggerOwn on Account (before insert) { }',
			'UsageBeforeInsert' => true
		};
		OrgAutomationInventory.Row plain = OrgAutomationInventory.triggerRow(
			(SObject) JSON.deserialize(JSON.serialize(values), ApexTrigger.class)
		);
		Assert.areEqual(OrgAutomationInventory.OWNER_ORG, plain.owner);
		Assert.areEqual(OrgAutomationInventory.COVERED_NO, plain.covered);
		Assert.areEqual('before insert', plain.detail);

		values.put(
			'Body',
			'trigger GiftTriggerOwn on Account (before insert) { if (BarnCRM_Automation_Control__c.getInstance().Pause_All__c) return; }'
		);
		OrgAutomationInventory.Row checks = OrgAutomationInventory.triggerRow(
			(SObject) JSON.deserialize(JSON.serialize(values), ApexTrigger.class)
		);
		Assert.areEqual(OrgAutomationInventory.OWNER_ORG, checks.owner);
		Assert.areEqual(OrgAutomationInventory.COVERED_YES, checks.covered);
	}

	@IsTest
	static void aPartThatCannotBeReadIsNamedAndTheRestStillLists() {
		System.runAs(TestUsers.admin()) {
			OrgAutomationInventory.Result result;
			System.runAs(maria()) {
				OrgAutomationInventory.failPart = 'Flows';
				result = OrgAutomationInventory.build();
			}
			Assert.areEqual(new List<String>{ 'Flows' }, result.unreadable);
			Assert.isNotNull(byKey(result).get('ApexTrigger|ContactTrigger'));
		}
	}

	@IsTest
	static void theInventoryNeedsTheSettingsPermission() {
		System.runAs(TestUsers.admin()) {
			User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
			String refused;
			System.runAs(david) {
				try {
					OrgAutomationController.getInventory();
				} catch (AuraHandledException caught) {
					refused = caught.getMessage();
				}
			}
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_AutomationInventory_NoPermission'),
				refused
			);
		}
	}
}
