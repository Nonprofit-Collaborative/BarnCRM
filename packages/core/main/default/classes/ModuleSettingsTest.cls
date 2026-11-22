/**
 * A module's settings in the store (ADR-0238 settings as custom metadata, phase 2): typed reads
 * by name answer the saved value, else the legacy value before carry-over, else the default;
 * saves through SettingsService are validated, audited and deployed once; run state uses
 * prefixed keys and a run lock; carry-over covers every registered module.
 *
 * The module here is a stand-in (registry and definitions set in memory): Core ships none, and
 * its settings group names no object, as after the legacy objects are removed.
 */
@IsTest(testFor='ApexClass:ModuleSettings')
private class ModuleSettingsTest {
	private static final String GROUP_NAME = 'Test_Module_Settings__c';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Setting_Definition__mdt row(String name, String key, String dataType, String defaultValue) {
		return new Setting_Definition__mdt(
			DeveloperName = name,
			MasterLabel = name.replace('_', ' '),
			Settings_Object__c = GROUP_NAME,
			Setting_Key__c = key,
			Data_Type__c = dataType,
			Default_Value__c = defaultValue,
			Section__c = SettingSections.GENERAL,
			Module__c = 'Test'
		);
	}

	private static void registerModule() {
		Setting_Definition__mdt days = row('Test_Days', 'Days__c', 'Number', '7');
		days.Min_Value__c = 1;
		days.Max_Value__c = 30;
		Setting_Definition__mdt mode = row('Test_Mode', 'Mode__c', 'Picklist', '"Fast"');
		mode.Picklist_Values__c = 'Fast:Fast;Slow:Slow';
		SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
			row('Test_Flag', 'Flag__c', 'Checkbox', 'true'),
			days,
			mode,
			row('Test_Start', 'Start__c', 'Text', '"2026-01-15"'),
			row('Test_Moment', 'Moment__c', 'DateTime', null),
			row('Test_Hidden', 'Hidden__c', 'Hidden', null)
		};
		ModuleSettings.stubbedModules = new List<Setting_Module__mdt>{
			new Setting_Module__mdt(
				DeveloperName = 'TestMod',
				Settings_Object__c = GROUP_NAME,
				Key_Prefix__c = 'TestMod'
			)
		};
		SettingsService.clearCaches();
	}

	@IsTest
	static void anUnsavedSettingReadsItsDefaultInItsType() {
		System.runAs(TestUsers.admin()) {
			registerModule();
			Assert.isTrue(ModuleSettings.isStoreObject(GROUP_NAME));
			Assert.isFalse(
				ModuleSettings.isStoreObject(SettingsService.CORE_SETTINGS_OBJECT),
				'Core is never a module.'
			);
			Assert.isTrue(ModuleSettings.flag('Test_Flag'));
			Assert.areEqual(7, ModuleSettings.number('Test_Days').intValue());
			Assert.areEqual(7, ModuleSettings.integerValue('Test_Days'));
			Assert.areEqual('Fast', ModuleSettings.text('Test_Mode'));
			Assert.areEqual(Date.newInstance(2026, 1, 15), ModuleSettings.dateValue('Test_Start'));
			Assert.isNull(ModuleSettings.datetimeValue('Test_Moment'), 'No default, nothing saved.');
			Assert.isNull(ModuleSettings.text('No_Such_Setting'), 'An unknown name reads as unset.');
			Assert.isFalse(ModuleSettings.flag('No_Such_Setting'));
			Assert.areEqual('TestMod', ModuleSettings.moduleByPrefix('testmod').DeveloperName);
		}
	}

	@IsTest
	static void aSavedValueWinsAndANumberOutsideItsRangeReadsTheDefault() {
		System.runAs(TestUsers.admin()) {
			registerModule();
			Datetime moment = Datetime.newInstanceGmt(2026, 3, 4, 5, 6, 7);
			ModuleSettings.setForTest('Test_Flag', false);
			ModuleSettings.setForTest('Test_Moment', moment);
			ModuleSettings.setForTest('Test_Days', 99);
			Assert.isFalse(ModuleSettings.flag('Test_Flag'));
			Assert.areEqual(moment, ModuleSettings.datetimeValue('Test_Moment'));
			Assert.areEqual(7, ModuleSettings.number('Test_Days').intValue(), 'Outside 1 to 30: the default.');
		}
	}

	@IsTest
	static void settingsServiceReadsAStoreModuleByGroupAndKey() {
		System.runAs(TestUsers.admin()) {
			registerModule();
			ModuleSettings.setForTest('Test_Days', 12);
			Assert.isTrue(SettingsService.hasKey(GROUP_NAME, 'Days__c'));
			Assert.isFalse(SettingsService.hasKey(GROUP_NAME, 'Nope__c'));
			Assert.areEqual(12, SettingsService.number(GROUP_NAME, 'Days__c').intValue());
			Assert.isTrue(SettingsService.flag(GROUP_NAME, 'Flag__c'));
			Assert.areEqual('Fast', SettingsService.text(GROUP_NAME, 'Mode__c'));
			Assert.areEqual(12, SettingsService.getValue(GROUP_NAME, 'Days__c'));
			Assert.isNull(SettingsService.getValue(GROUP_NAME, 'Mode__c'), 'Nothing saved for it.');
			Assert.areEqual('Fast', SettingsService.getEffectiveValue(GROUP_NAME, 'Mode__c', 'Picklist'));
			Assert.areEqual(true, SettingsService.getEffectiveValue(GROUP_NAME, 'Flag__c', 'Checkbox'));
			try {
				SettingsService.getValue(GROUP_NAME, 'Nope__c');
				Assert.fail('An unknown key is refused.');
			} catch (SettingsService.SettingsException expected) {
				Assert.isNotNull(expected.getMessage());
			}
		}
	}

	@IsTest
	static void aSaveIsValidatedAuditedAndReadBack() {
		System.runAs(TestUsers.admin()) {
			registerModule();
			Test.startTest();
			ModuleSettings.save(
				new Map<String, Object>{ 'Test_Days' => '14', 'Test_Mode' => 'Slow', 'Test_Flag' => true }
			);
			Test.stopTest();

			Assert.areEqual(14, ModuleSettings.integerValue('Test_Days'));
			Assert.areEqual('Slow', ModuleSettings.text('Test_Mode'));
			Assert.isTrue(SettingStore.has('Test_Flag'), 'Keeping a shown default saves it.');
			String auditName = GROUP_NAME + '.Days__c';
			List<Setting_Change__c> audit = [
				SELECT Setting_Name__c, New_Value__c
				FROM Setting_Change__c
				WHERE Setting_Name__c = :auditName
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, audit.size(), 'Audited as Group.Key once the deployment succeeds.');
			Assert.areEqual('14', audit[0].New_Value__c);
		}
	}

	@IsTest
	static void aSaveIsRefusedWithTheSettingNamed() {
		System.runAs(TestUsers.admin()) {
			registerModule();
			for (
				Map<String, Object> values : new List<Map<String, Object>>{
					new Map<String, Object>{ 'Test_Days' => 'many' },
					new Map<String, Object>{ 'Test_Days' => 45 },
					new Map<String, Object>{ 'Test_Mode' => 'Sideways' },
					new Map<String, Object>{ 'Test_Moment' => 'not a time' },
					new Map<String, Object>{ 'Test_Hidden' => 'x' },
					new Map<String, Object>{ 'No_Such_Setting' => 'x' }
				}
			) {
				try {
					ModuleSettings.save(values);
					Assert.fail('Refused: ' + values);
				} catch (SettingsService.SettingsException expected) {
					Assert.isNotNull(expected.getMessage());
				}
			}
			Assert.isFalse(SettingStore.has('Test_Days') || SettingStore.has('Test_Mode'), 'Nothing was saved.');

			ModuleSettings.saveSystem(new Map<String, Object>{ 'Test_Hidden' => 'kept' });
			Assert.areEqual('kept', ModuleSettings.text('Test_Hidden'), 'A module writes its Hidden rows.');
		}
	}

	@IsTest
	static void collectedSavesGoOutAsOneDeployment() {
		System.runAs(TestUsers.admin()) {
			registerModule();
			SettingsService.collectSaves();
			SettingsService.saveValues(GROUP_NAME, new Map<String, Object>{ 'Days__c' => 20 });
			Assert.isFalse(SettingStore.has('Test_Days'), 'Held back until sent.');
			SettingsService.sendCollected();
			Assert.areEqual(20, ModuleSettings.integerValue('Test_Days'));
			Assert.isNull(SettingsService.sendCollected(), 'Nothing left to send.');
		}
	}

	@IsTest
	static void moduleStateUsesPrefixedKeysAndARunLock() {
		System.runAs(TestUsers.admin()) {
			registerModule();
			String key = SettingsState.moduleKey('TestMod', 'Last_Run_Started__c');
			Assert.areEqual('TestMod.Last_Run_Started__c', key);
			Assert.isNull(SettingsState.lockOrCreate(key), 'Created empty the first time.');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Nightly_Job__c WHERE Name = :key AND Kind__c = 'State' WITH SYSTEM_MODE]
			);
			SettingsState.put(new Map<String, Object>{ key => 42 });
			SettingsState.clearCache();
			Assert.areEqual(42, SettingsState.lockOrCreate(key), 'The locked row is read, not made again.');
			Assert.areEqual(42, SettingsState.number(key).intValue());
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Nightly_Job__c WHERE Name = :key AND Kind__c = 'State' WITH SYSTEM_MODE]
			);
		}
	}

	/**
	 * A registered module whose legacy custom setting the org saved: read until carry-over, then
	 * carried with the Core values. Automation Control stands in for the module's object, the one
	 * Core hierarchy setting a test can name as if it were another package's.
	 */
	@IsTest
	static void aModulesLegacyValuesAreReadThenCarriedOver() {
		System.runAs(TestUsers.admin()) {
			Datetime pausedUntil = Datetime.newInstanceGmt(2030, 1, 2, 3, 4, 5);
			String standIn = 'BarnCRM_Automation_Control__c';
			SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
				new Setting_Definition__mdt(
					DeveloperName = 'Test_Pause_All',
					MasterLabel = 'Test pause all',
					Settings_Object__c = standIn,
					Setting_Key__c = 'Pause_All__c',
					Data_Type__c = 'Checkbox',
					Default_Value__c = 'false'
				)
			};
			ModuleSettings.stubbedModules = new List<Setting_Module__mdt>{
				new Setting_Module__mdt(
					DeveloperName = 'TestMod',
					Settings_Object__c = standIn,
					Key_Prefix__c = 'TestMod',
					State_Fields__c = 'Paused_Until__c, Not_A_Field__c'
				)
			};
			SettingsService.clearCaches();
			BarnCRM_Settings__c core = SettingsService.firstSaveRecord();
			insert as system core;
			insert as system new BarnCRM_Automation_Control__c(
				SetupOwnerId = UserInfo.getOrganizationId(),
				Pause_All__c = true,
				Paused_Until__c = pausedUntil
			);
			String stateKey = SettingsState.moduleKey('TestMod', 'Paused_Until__c');

			Assert.isTrue(ModuleSettings.flag('Test_Pause_All'), 'The legacy value, before carry-over.');
			Assert.areEqual(pausedUntil, SettingsState.moment(stateKey), 'Legacy state, before carry-over.');
			Assert.isTrue(SettingsCarryOver.isNeeded());

			Test.startTest();
			SettingsCarryOver.Result result = SettingsCarryOver.run();
			Test.stopTest();

			Assert.isTrue(SettingStore.isCarriedOver());
			Assert.isTrue(SettingStore.has('Test_Pause_All'), 'The module value joined the deployment.');
			Assert.areEqual(true, SettingStore.value('Test_Pause_All'));
			Assert.isTrue(result.settingCount >= 1);
			SettingsState.clearCache();
			Assert.areEqual(pausedUntil, SettingsState.moment(stateKey), 'The state field has its row.');
			Assert.isNull(ModuleSettings.legacyValue(standIn, 'Pause_All__c'), 'Not read after carry-over.');
			String auditName = standIn + '.Pause_All__c';
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Setting_Change__c WHERE Setting_Name__c = :auditName WITH SYSTEM_MODE],
				'Audited as Object.Field.'
			);
		}
	}
}
