/**
 * The one-time carry-over of the legacy settings (ADR-0238 settings as custom metadata,
 * decision 9; canonical model R-STV1): changed values become Setting Value records with the
 * marker in one deployment, run state and seen versions become rows, a pause still running
 * moves to Automation Control, and a second run changes nothing.
 */
@IsTest(testFor='ApexClass:SettingsCarryOver')
private class SettingsCarryOverTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static void storeLegacy(BarnCRM_Settings__c values) {
		values.SetupOwnerId = UserInfo.getOrganizationId();
		insert as system values;
	}

	/** Counts the records written in the transaction when the deployment starts. */
	private class DmlCountingDeployer implements SettingStore.Deployer {
		Integer dmlBeforeDeploy;

		public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
			dmlBeforeDeploy = Limits.getDmlStatements();
			return null;
		}
	}

	@IsTest
	static void theDeploymentStartsBeforeAnyRecordIsWritten() {
		System.runAs(TestUsers.admin()) {
			storeLegacy(
				new BarnCRM_Settings__c(
					Fuzzy_Match_Threshold__c = 80,
					Error_Digest_Last_Run__c = Datetime.newInstanceGmt(2026, 10, 1, 2, 0, 0),
					Automation_Paused_Until__c = Datetime.now().addHours(3)
				)
			);
			insert as system new Whats_New_Seen__c(SetupOwnerId = UserInfo.getUserId(), Last_Seen_Version__c = '0.9');
			DmlCountingDeployer counting = new DmlCountingDeployer();
			SettingStore.deployer = counting;

			Test.startTest();
			SettingsCarryOver.Result result = SettingsCarryOver.run();
			Assert.areEqual(
				0,
				counting.dmlBeforeDeploy,
				'A record written before the deployment makes Salesforce refuse it (mixed DML).'
			);
			Test.stopTest();

			Assert.areEqual(1, result.stateCount);
			Assert.areEqual(1, result.seenCount);
			SettingsState.clearCache();
			Assert.isNotNull(SettingsState.moment('Error_Digest_Last_Run__c'), 'The queued job wrote the state row.');
			Assert.areEqual('0.9', WhatsNewSeenWriter.lastSeen(), 'The queued job wrote the seen row.');
			Assert.isNotNull(
				BarnCRM_Automation_Control__c.getOrgDefaults().Paused_Until__c,
				'The queued job moved the running pause.'
			);
		}
	}

	@IsTest
	static void anOrgWithNothingStoredHasNothingToCarryOver() {
		System.runAs(TestUsers.admin()) {
			Assert.isFalse(SettingsCarryOver.isNeeded(), 'No legacy record, nothing to offer.');
			Assert.isFalse(SettingsController.getCarryOverNeeded(), 'The console offers nothing.');
		}
	}

	@IsTest
	static void changedValuesStateSeenAndPauseAreCarriedOverOnce() {
		System.runAs(TestUsers.admin()) {
			Datetime lastRun = Datetime.newInstanceGmt(2026, 10, 1, 2, 0, 0);
			Datetime pausedUntil = Datetime.now().addHours(3);
			storeLegacy(
				new BarnCRM_Settings__c(
					Fuzzy_Match_Threshold__c = 80,
					Error_Digest_Last_Run__c = lastRun,
					Automation_Paused_Until__c = pausedUntil
				)
			);
			insert as system new Whats_New_Seen__c(SetupOwnerId = UserInfo.getUserId(), Last_Seen_Version__c = '0.9');
			Assert.isTrue(SettingsController.getCarryOverNeeded(), 'Offered before the carry-over.');
			Assert.areEqual(80, SettingsService.getSettings().Fuzzy_Match_Threshold__c.intValue(), 'Legacy read.');

			Test.startTest();
			SettingsCarryOver.Result result = SettingsController.carryOverSettings();
			Test.stopTest();

			Assert.isTrue(SettingStore.isCarriedOver(), 'The marker is deployed with the values.');
			Assert.isTrue(SettingStore.has('Fuzzy_Match_Threshold'), 'A changed value is carried.');
			Assert.areEqual(80, SettingStore.value('Fuzzy_Match_Threshold'));
			Assert.isFalse(
				SettingStore.has('Household_Name_Pattern'),
				'A value equal to its default is left to the default.'
			);
			Assert.areEqual(1, result.stateCount, 'The digest run is the one state value stored.');
			Assert.areEqual(1, result.seenCount);
			Assert.isTrue(result.tooLong.isEmpty());

			SettingsState.clearCache();
			Assert.areEqual(lastRun, SettingsState.moment('Error_Digest_Last_Run__c'), 'State row written.');
			Assert.areEqual('0.9', WhatsNewSeenWriter.lastSeen(), 'Seen row written.');
			Assert.areEqual(
				pausedUntil,
				BarnCRM_Automation_Control__c.getOrgDefaults().Paused_Until__c,
				'The running pause moved.'
			);
			Assert.isTrue(
				[
					SELECT COUNT()
					FROM Setting_Change__c
					WHERE Setting_Name__c = 'BarnCRM_Settings__c.Fuzzy_Match_Threshold__c'
					WITH SYSTEM_MODE
				] > 0,
				'Each carried value is in Recent Changes.'
			);

			Assert.isFalse(SettingsCarryOver.isNeeded(), 'Not offered again.');
			SettingsCarryOver.Result again = SettingsCarryOver.run();
			Assert.isNull(again.deploymentId, 'A second run deploys nothing.');
			Assert.areEqual(0, again.settingCount);
		}
	}

	@IsTest
	static void valuesCompareAsValues() {
		System.runAs(TestUsers.admin()) {
			Assert.isTrue(SettingsCarryOver.sameValue(7.00, 7), '7.00 is the default 7.');
			Assert.isFalse(SettingsCarryOver.sameValue(8, 7));
			Assert.isTrue(SettingsCarryOver.sameValue(false, null), 'An unchecked box with no default.');
			Assert.isFalse(SettingsCarryOver.sameValue(true, null));
			Assert.isTrue(SettingsCarryOver.sameValue('Standalone', 'Standalone'));
			Assert.isFalse(SettingsCarryOver.sameValue('standalone', 'Standalone'), 'Text compares exactly.');
		}
	}

	@IsTest
	static void someoneWithoutTheSettingsPermissionCannotCarryOver() {
		System.runAs(TestUsers.admin()) {
			User reader = TestDataFactory.createUser('CarryReader', new List<String>{ 'BarnCRM_Read_Only' });
			System.runAs(reader) {
				Assert.isFalse(SettingsController.getCarryOverNeeded());
				try {
					SettingsController.carryOverSettings();
					Assert.fail('Refused without Manage BarnCRM Settings.');
				} catch (AuraHandledException expected) {
					Assert.isNotNull(expected.getMessage());
				}
			}
		}
	}
}
