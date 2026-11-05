/**
 * DataDictionaryController: the Data Dictionary section lists an object's fields from describe
 * (plan Section 6.1.1 item 13, D-154). Tests run as Maria, a Standard User holding only BarnCRM
 * Admin, so what comes back is what that permission set lets her see.
 */
@IsTest(testFor='ApexClass:DataDictionaryController')
private class DataDictionaryControllerTest {
	private static final String DISMISSAL = Duplicate_Dismissal__c.SObjectType.getDescribe(
			SObjectDescribeOptions.DEFERRED
		)
		.getName();
	private static final String PAIR_KEY = Duplicate_Dismissal__c.Pair_Key__c.getDescribe()
		.getName();
	private static final String IS_ORGANIZATION = Account.Is_Organization__c.getDescribe()
		.getName();
	private static final String ROW_STATUS = Import_Row__c.Status__c.getDescribe().getName();

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static User maria() {
		return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
	}

	private static Map<String, DataDictionaryController.FieldRow> byName(
		DataDictionaryController.ObjectDictionary dictionary
	) {
		Map<String, DataDictionaryController.FieldRow> found = new Map<String, DataDictionaryController.FieldRow>();
		for (DataDictionaryController.FieldRow row : dictionary.fields) {
			found.put(row.fieldName, row);
		}
		return found;
	}

	private static String refusalOf(String objectName) {
		try {
			DataDictionaryController.describeObject(objectName);
		} catch (AuraHandledException caught) {
			return caught.getMessage();
		}
		return null;
	}

	@IsTest
	static void aFieldIsDescribedWithItsRulesAndHelpText() {
		System.runAs(TestUsers.admin()) {
			DataDictionaryController.ObjectDictionary dictionary;
			System.runAs(maria()) {
				dictionary = DataDictionaryController.describeObject(DISMISSAL);
			}

			Assert.areEqual(DISMISSAL, dictionary.objectName, 'The object API name.');
			Assert.isTrue(dictionary.isCustom, 'Duplicate Dismissal is a custom object.');
			DataDictionaryController.FieldRow key = byName(dictionary).get(PAIR_KEY);
			Assert.isNotNull(key, 'Pair Key is listed.');
			Assert.areEqual('Pair Key', key.fieldLabel, 'Label.');
			Assert.areEqual('string', key.dataType, 'Type.');
			Assert.areEqual(40, key.length, 'Length.');
			Assert.isTrue(key.required, 'Required.');
			Assert.isTrue(key.isUnique, 'Unique.');
			Assert.isTrue(key.externalId, 'External ID.');
			Assert.isTrue(key.isCustom, 'Custom.');
			Assert.areEqual(
				'The two records that are not duplicates of each other.',
				key.helpText,
				'Help text.'
			);
			Assert.isNull(key.formula, 'Not a formula.');
			Assert.isNull(key.picklistValues, 'Not a picklist.');
		}
	}

	@IsTest
	static void aFormulaPicklistAndLookupShowTheirDetail() {
		System.runAs(TestUsers.admin()) {
			DataDictionaryController.ObjectDictionary account;
			DataDictionaryController.ObjectDictionary rows;
			System.runAs(maria()) {
				account = DataDictionaryController.describeObject('Account');
				rows = DataDictionaryController.describeObject(
					Import_Row__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
				);
			}

			Assert.isFalse(account.isCustom, 'Account is a standard object.');
			DataDictionaryController.FieldRow formula = byName(account).get(IS_ORGANIZATION);
			Assert.isFalse(String.isBlank(formula.formula), 'The formula text is shown.');
			DataDictionaryController.FieldRow status = byName(rows).get(ROW_STATUS);
			String first = Import_Row__c.Status__c.getDescribe().getPicklistValues()[0].getValue();
			Assert.isTrue(
				status.picklistValues.startsWith(first),
				'Active picklist values are listed in order.'
			);
			DataDictionaryController.FieldRow parent = byName(account).get('ParentId');
			Assert.areEqual('Account', parent.relatedTo, 'A lookup names what it points to.');
		}
	}

	@IsTest
	static void aManyFieldObjectListsEveryVisibleFieldOnceInLabelOrder() {
		System.runAs(TestUsers.admin()) {
			DataDictionaryController.ObjectDictionary account;
			System.runAs(maria()) {
				account = DataDictionaryController.describeObject('Account');
			}

			Assert.isTrue(account.fields.size() > 40, 'Account has dozens of fields.');
			Set<String> names = new Set<String>();
			// The controller's rule: lower-case label, then API name, as List.sort orders them.
			List<String> keys = new List<String>();
			for (DataDictionaryController.FieldRow row : account.fields) {
				Assert.isTrue(names.add(row.fieldName), 'Each field once: ' + row.fieldName);
				keys.add(row.fieldLabel.toLowerCase() + '\u0000' + row.fieldName);
			}
			List<String> sorted = new List<String>(keys);
			sorted.sort();
			Assert.areEqual(sorted, keys, 'Sorted by label, then API name.');
		}
	}

	@IsTest
	static void aFieldThePersonCannotSeeIsNotListed() {
		System.runAs(TestUsers.admin()) {
			DataDictionaryController.ObjectDictionary dictionary;
			System.runAs(maria()) {
				dictionary = DataDictionaryController.describeObject(DISMISSAL);
				for (
					Schema.SObjectField token : Duplicate_Dismissal__c.SObjectType.getDescribe(
							SObjectDescribeOptions.DEFERRED
						)
						.fields.getMap()
						.values()
				) {
					Schema.DescribeFieldResult field = token.getDescribe();
					Assert.areEqual(
						field.isAccessible(),
						byName(dictionary).containsKey(field.getName()),
						'Listed only when readable: ' + field.getName()
					);
				}
			}
		}
	}

	@IsTest
	static void thePickerMarksBarnCrmObjectsAndTheCommonStandardOnes() {
		System.runAs(TestUsers.admin()) {
			List<DataDictionaryController.Option> options;
			System.runAs(maria()) {
				options = DataDictionaryController.listObjects();
			}

			Map<String, DataDictionaryController.Option> byValue = new Map<String, DataDictionaryController.Option>();
			for (DataDictionaryController.Option option : options) {
				byValue.put(option.value, option);
				Assert.areEqual(option.label.trim(), option.label, 'Labels are trimmed (QA-F6).');
			}
			Assert.isTrue(byValue.get('Account').isDefault, 'Account is chosen to start.');
			Assert.isTrue(byValue.get('Contact').isDefault, 'Contact is chosen to start.');
			Assert.isTrue(byValue.get(DISMISSAL).isDefault, 'A BarnCRM object is chosen to start.');
			Assert.isFalse(
				byValue.containsKey(
					Field_Utilization_Snapshot__c.SObjectType.getDescribe(
							SObjectDescribeOptions.DEFERRED
						)
						.getName()
				),
				'The snapshot table is not documented.'
			);
		}
	}

	@IsTest
	static void someoneWithoutThePermissionIsRefused() {
		System.runAs(TestUsers.admin()) {
			User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
			String refusal;
			String listRefusal;
			System.runAs(david) {
				refusal = refusalOf(DISMISSAL);
				try {
					DataDictionaryController.listObjects();
				} catch (AuraHandledException caught) {
					listRefusal = caught.getMessage();
				}
			}

			Assert.areEqual(
				BarnHelp.text('Core', 'Core_DataDictionary_PermissionRequired'),
				refusal,
				'Refused.'
			);
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_DataDictionary_PermissionRequired'),
				listRefusal,
				'The list is refused too.'
			);
		}
	}

	private static Map<String, DataDictionaryController.AutomationRow> automationByKey(
		DataDictionaryController.AutomationInventory inventory
	) {
		Map<String, DataDictionaryController.AutomationRow> found = new Map<String, DataDictionaryController.AutomationRow>();
		for (DataDictionaryController.AutomationRow row : inventory.rows) {
			found.put(row.automationType + '|' + row.apiName, row);
		}
		return found;
	}

	@IsTest
	static void anObjectListsItsApexTriggers() {
		System.runAs(TestUsers.admin()) {
			DataDictionaryController.AutomationInventory inventory;
			System.runAs(maria()) {
				inventory = DataDictionaryController.getAutomation('Account');
			}

			Assert.areEqual('Account', inventory.objectName, 'The object API name.');
			Assert.isFalse(inventory.triggersFailed, 'Triggers are readable.');
			Assert.isFalse(inventory.flowsFailed, 'Flows are readable.');
			DataDictionaryController.AutomationRow accountTrigger = automationByKey(inventory)
				.get('ApexTrigger|AccountTrigger');
			Assert.isNotNull(accountTrigger, 'Core\'s Account trigger is listed.');
			Assert.areEqual('Active', accountTrigger.status, 'It is active.');
			Assert.isTrue(
				accountTrigger.detail.contains('before insert'),
				'With the events it runs on.'
			);
			Assert.isNotNull(accountTrigger.apiVersion, 'And its API version.');
		}
	}

	@IsTest
	static void aCustomObjectListsItsTriggersAndItsFlowsByTheObjectId() {
		System.runAs(TestUsers.admin()) {
			DataDictionaryController.AutomationInventory inventory;
			System.runAs(maria()) {
				inventory = DataDictionaryController.getAutomation(
					Affiliation__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
						.getName()
				);
			}

			Map<String, DataDictionaryController.AutomationRow> found = automationByKey(inventory);
			Assert.isNotNull(found.get('ApexTrigger|AffiliationTrigger'), 'Its trigger is listed.');
			DataDictionaryController.AutomationRow flow = found.get(
				'Flow|Template_Affiliation_Primary'
			);
			Assert.isNotNull(flow, 'A flow that a record of the object triggers is listed.');
			Assert.areEqual('After save', flow.detail, 'With the point in the save it runs at.');
			Assert.areEqual(
				'Inactive',
				flow.status,
				'A template flow ships inactive until an admin turns it on.'
			);
			Assert.isNull(
				found.get('Flow|Template_Account_Address_Capture'),
				'Another object\'s flow is not listed.'
			);
		}
	}

	@IsTest
	static void aPartThatCannotBeReadIsReportedAndTheOtherPartStillLists() {
		System.runAs(TestUsers.admin()) {
			DataDictionaryController.AutomationInventory inventory;
			System.runAs(maria()) {
				AutomationInventoryService.failType = AutomationInventoryService.TYPE_FLOW;
				inventory = DataDictionaryController.getAutomation('Account');
			}

			Assert.isTrue(inventory.flowsFailed, 'The flows could not be read, and it says so.');
			Assert.isFalse(inventory.triggersFailed, 'The triggers were.');
			Assert.isNotNull(
				automationByKey(inventory).get('ApexTrigger|AccountTrigger'),
				'The triggers are still listed.'
			);
		}
	}

	@IsTest
	static void theInventoryNeedsTheSettingsPermissionAndAKnownObject() {
		System.runAs(TestUsers.admin()) {
			String unknown;
			System.runAs(maria()) {
				try {
					DataDictionaryController.getAutomation('Nothing_Here__c');
				} catch (AuraHandledException caught) {
					unknown = caught.getMessage();
				}
			}
			Assert.areEqual(
				String.format(
					BarnHelp.text('Core', 'Core_DataDictionary_UnknownObject'),
					new List<Object>{ 'Nothing_Here__c' }
				),
				unknown,
				'An unknown object is refused by name.'
			);

			User plain = TestDataFactory.createUser('Plain', new List<String>{ 'BarnCRM_Staff' });
			String refusal;
			System.runAs(plain) {
				try {
					DataDictionaryController.getAutomation('Account');
				} catch (AuraHandledException caught) {
					refusal = caught.getMessage();
				}
			}
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_DataDictionary_PermissionRequired'),
				refusal,
				'Manage BarnCRM Settings is required.'
			);
		}
	}

	@IsTest
	static void anUnknownOrBlankObjectIsRefusedByName() {
		System.runAs(TestUsers.admin()) {
			String unknown;
			String blank;
			System.runAs(maria()) {
				unknown = refusalOf('Nothing_Here__c');
				blank = refusalOf(' ');
			}

			Assert.areEqual(
				String.format(
					BarnHelp.text('Core', 'Core_DataDictionary_UnknownObject'),
					new List<Object>{ 'Nothing_Here__c' }
				),
				unknown,
				'The name is in the message.'
			);
			Assert.isNotNull(blank, 'A blank name is refused.');
		}
	}
}
