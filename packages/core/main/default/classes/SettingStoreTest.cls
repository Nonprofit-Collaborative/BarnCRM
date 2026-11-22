/**
 * The settings store (ADR-0238 settings as custom metadata, R-STV1 and R-STV2): value then default,
 * one deployment per save, read back in the same transaction, audited and applied by the
 * callback once the deployment succeeds, and a failure logged with Salesforce's reason.
 */
@IsTest(testFor='ApexClass:SettingStore, ApexClass:SettingValueDeployCallback')
private class SettingStoreTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static final Id JOB = FakeIds.ofPrefix('0Af', 3);

	private class TestContext extends Metadata.DeployCallbackContext {
		public override Id getCallbackJobId() {
			return JOB;
		}
	}

	/** Keeps what would be deployed, and never calls back: the deployment is still running. */
	private class CapturingDeployer implements SettingStore.Deployer {
		public Metadata.DeployContainer container;
		public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
			this.container = container;
			return JOB;
		}
	}

	private class RefusingDeployer implements SettingStore.Deployer {
		public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
			throw new CalloutException('not allowed');
		}
	}

	private static SettingStore.Change change(String name, String json) {
		SettingStore.Change change = new SettingStore.Change();
		change.name = name;
		change.settingName = 'BarnCRM_Settings__c.' + name + '__c';
		change.oldText = null;
		change.newText = json;
		change.json = json;
		return change;
	}

	@IsTest
	static void aSettingNothingSavedReadsItsShippedDefault() {
		System.runAs(TestUsers.admin()) {
			Assert.isFalse(SettingStore.has('Fuzzy_Match_Threshold'), 'nothing is saved yet');
			Assert.areEqual(90, SettingStore.value('Fuzzy_Match_Threshold'), 'the shipped default');
			Assert.areEqual(
				90,
				SettingsService.getSettings().Fuzzy_Match_Threshold__c.intValue(),
				'Core reads the default'
			);
		}
	}

	@IsTest
	static void aSavedValueWinsOverTheDefault() {
		System.runAs(TestUsers.admin()) {
			SettingsService.setForTest('Fuzzy_Match_Threshold__c', 85);

			Assert.areEqual(85, SettingStore.value('Fuzzy_Match_Threshold'), 'the saved value');
			Assert.areEqual(85, SettingsService.getSettings().Fuzzy_Match_Threshold__c.intValue(), 'Core reads it');
		}
	}

	@IsTest
	static void aValueThatIsNotJsonFallsBackToTheDefault() {
		System.runAs(TestUsers.admin()) {
			SettingStore.setForTest('Fuzzy_Match_Threshold', null);
			Assert.isNull(SettingStore.parse('not json'), 'not JSON reads as nothing');
			Assert.areEqual('Both', SettingStore.parse('"Both"'), 'a JSON text');
			Assert.areEqual(true, SettingStore.parse('true'), 'a JSON boolean');
			Assert.areEqual(90, SettingStore.value('Fuzzy_Match_Threshold'), 'blank reads as the default');
		}
	}

	@IsTest
	static void aSaveSendsOneDeploymentAndIsReadBackAtOnce() {
		System.runAs(TestUsers.admin()) {
			CapturingDeployer deployer = new CapturingDeployer();
			SettingStore.deployer = deployer;

			Id deploymentId = SettingStore.save(
				new List<SettingStore.Change>{
					change('Fuzzy_Match_Threshold', '85'),
					change('Job_Notifications', 'false')
				},
				true
			);

			Assert.areEqual(JOB, deploymentId, 'the deployment Id is returned');
			Assert.areEqual(2, deployer.container.getMetadata().size(), 'one deployment of both values');
			Metadata.CustomMetadata record = (Metadata.CustomMetadata) deployer.container.getMetadata()[0];
			Assert.isTrue(record.fullName.endsWith('Setting_Value.Fuzzy_Match_Threshold'), record.fullName);
			Assert.areEqual('85', record.values[0].value, 'the value as JSON');
			Assert.areEqual(85, SettingStore.value('Fuzzy_Match_Threshold'), 'read back in this transaction');
			Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'audited only once it succeeds');
		}
	}

	@IsTest
	static void aRefusedDeploymentSavesNothing() {
		System.runAs(TestUsers.admin()) {
			SettingStore.deployer = new RefusingDeployer();
			try {
				SettingStore.save(new List<SettingStore.Change>{ change('Fuzzy_Match_Threshold', '85') }, true);
				Assert.fail('a refused deployment is refused');
			} catch (SettingStore.SettingStoreException expected) {
				Assert.isTrue(expected.getMessage().contains('Apex'), 'names the Setup switch');
			}
			Assert.isFalse(SettingStore.has('Fuzzy_Match_Threshold'), 'nothing pending');
		}
	}

	@IsTest
	static void aSucceededDeploymentIsAuditedWithItsId() {
		System.runAs(TestUsers.admin()) {
			Metadata.DeployResult result = new Metadata.DeployResult();
			result.status = Metadata.DeployStatus.Succeeded;

			Test.startTest();
			new SettingValueDeployCallback(
					new List<SettingStore.Change>{ change('Fuzzy_Match_Threshold', '85') },
					true,
					UserInfo.getUserId()
				)
				.handleResult(result, new TestContext());
			Test.stopTest();

			Setting_Change__c row = [SELECT Setting_Name__c, New_Value__c, Deployment_Id__c FROM Setting_Change__c];
			Assert.areEqual('BarnCRM_Settings__c.Fuzzy_Match_Threshold__c', row.Setting_Name__c, 'named as before');
			Assert.areEqual('85', row.New_Value__c, 'the new value');
			Assert.areEqual(JOB, row.Deployment_Id__c, 'findable by the deployment');
			Assert.isTrue(CustomMetadataManagerSelector.hasSucceeded(JOB), 'the console sees it finished');
		}
	}

	@IsTest
	static void aFailedDeploymentIsLoggedWithTheReason() {
		System.runAs(TestUsers.admin()) {
			Metadata.DeployResult result = new Metadata.DeployResult();
			result.status = Metadata.DeployStatus.Failed;
			result.errorMessage = 'Deployments are not allowed';

			Test.startTest();
			new SettingValueDeployCallback(
					new List<SettingStore.Change>{ change('Fuzzy_Match_Threshold', '85') },
					true,
					UserInfo.getUserId()
				)
				.handleResult(result, new TestContext());
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'nothing audited');
			String message = CustomMetadataManagerSelector.failureMessage(JOB);
			Assert.isTrue(message.contains('Deployments are not allowed'), message);
		}
	}

	@IsTest
	static void aConsoleSaveIsAppliedThroughTheStoreInATest() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			SettingsService.saveValues(new Map<String, Object>{ 'Fuzzy_Match_Threshold__c' => 95 });
			Test.stopTest();

			Assert.areEqual(95, SettingsService.getSettings().Fuzzy_Match_Threshold__c.intValue(), 'saved');
			Assert.areEqual(95, ((Decimal) SettingsService.getValue('Fuzzy_Match_Threshold__c')).intValue(), 'stored');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Setting_Change__c
					WHERE Setting_Name__c = 'BarnCRM_Settings__c.Fuzzy_Match_Threshold__c'
				],
				'audited once'
			);
		}
	}

	@IsTest
	static void aLegacyValueIsReadUntilCarriedOver() {
		System.runAs(TestUsers.admin()) {
			insert new BarnCRM_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Fuzzy_Match_Threshold__c = 82);
			SettingsService.clearCaches();
			Assert.areEqual(
				82,
				SettingsService.getSettings().Fuzzy_Match_Threshold__c.intValue(),
				'legacy value before carry-over'
			);

			SettingStore.setForTest(SettingStore.CARRIED_OVER, true);
			SettingsService.clearCaches();
			Assert.areEqual(90, SettingsService.getSettings().Fuzzy_Match_Threshold__c.intValue(), 'the default after');
		}
	}

	@IsTest
	static void runStateIsKeptOnStateRows() {
		System.runAs(TestUsers.admin()) {
			Datetime ranAt = Datetime.newInstanceGmt(2026, 11, 21, 3, 0, 0);
			SettingsState.put(
				new Map<String, Object>{ 'Error_Digest_Last_Run__c' => ranAt, 'Match_Keys_Filled__c' => true }
			);
			SettingsState.clearCache();

			Assert.areEqual(ranAt, SettingsState.moment('Error_Digest_Last_Run__c'), 'the time read back');
			Assert.isTrue(SettingsState.flag('Match_Keys_Filled__c'), 'the marker read back');
			Assert.areEqual(2, [SELECT COUNT() FROM Nightly_Job__c WHERE Kind__c = 'State'], 'one row per key');
			Assert.isTrue(SettingsState.isStateKey('Setup_Steps_Completed__c'), 'a setup marker is state');
			Assert.isFalse(SettingsState.isStateKey('Fuzzy_Match_Threshold__c'), 'a setting is not');
		}
	}
}
