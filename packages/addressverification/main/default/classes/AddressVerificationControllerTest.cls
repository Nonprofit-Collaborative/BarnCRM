/**
 * Address Verification Setup, Health Check and the nightly step (ADR-0209 address verification
 * module, decisions 3, 5 and 7; R-AV4): only the last four characters of a key are shown; a blank
 * box keeps a saved key; clearing removes one provider's keys; someone who cannot manage settings
 * changes nothing; Health Check reports missing keys; the nightly step runs only once keys are in.
 */
@IsTest(
	testFor='ApexClass:AddressVerificationController, ApexClass:AddressVerificationHealthCheckExtension, ApexClass:AddressVerificationNightlyJobProvider'
)
private class AddressVerificationControllerTest {
	@TestSetup
	static void createTestUsers() {
		System.runAs(TestUsers.admin()) {
			AddressVerificationTestData.admin();
			TestUsers.standardUserWith('Zzav Staff', new List<String>{ 'BarnCRM_Staff' });
		}
	}

	private static Map<String, String> lastFour(AddressVerificationController.Setup setup) {
		Map<String, String> byName = new Map<String, String>();
		for (AddressVerificationController.KeyStatus key : setup.keys) {
			byName.put(key.name, key.lastFour);
		}
		return byName;
	}

	@IsTest
	static void savingShowsOnlyTheEndOfEachKeyAndKeepsBlankOnes() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationController.saveKeys(
				new Map<String, String>{
					'smartyAuthId' => 'id-abcd',
					'smartyAuthToken' => 'tok-wxyz'
				}
			);

			AddressVerificationController.Setup setup = AddressVerificationController.saveKeys(
				new Map<String, String>{ 'smartyAuthId' => '  ', 'googleApiKey' => 'AIza-9876' }
			);

			Map<String, String> ends = lastFour(setup);
			Assert.areEqual('abcd', ends.get('smartyAuthId'), 'A blank box keeps the saved key');
			Assert.areEqual('wxyz', ends.get('smartyAuthToken'), 'Only the last four characters');
			Assert.areEqual('9876', ends.get('googleApiKey'), 'Google saved');
			Assert.isTrue(setup.ready, 'Smarty, the default provider, is ready');
			Assert.isFalse(JSON.serialize(setup).contains('id-abcd'), 'No key is returned');
		}
	}

	@IsTest
	static void clearingRemovesOneProvidersKeys() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);

			Map<String, String> ends = lastFour(AddressVerificationController.clearKeys('Smarty'));

			Assert.isNull(ends.get('smartyAuthId'), 'Smarty cleared');
			Assert.isNotNull(ends.get('googleApiKey'), 'Google kept');
			try {
				AddressVerificationController.clearKeys('Other');
				Assert.fail('An unknown provider is refused');
			} catch (AuraHandledException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused with a message');
			}
		}
	}

	@IsTest
	static void someoneWhoCannotManageSettingsChangesNothing() {
		User staff = [SELECT Id FROM User WHERE LastName = 'Zzav Staff' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(staff) {
			try {
				AddressVerificationController.saveKeys(
					new Map<String, String>{ 'googleApiKey' => 'AIza-0000' }
				);
				Assert.fail('Refused');
			} catch (AuraHandledException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused with a message');
			}
		}
		Assert.isNull(
			Address_Verification_Keys__c.getOrgDefaults().Google_Api_Key__c,
			'Nothing saved'
		);
	}

	@IsTest
	static void healthCheckAndTheNightlyStepWaitForKeys() {
		System.runAs(AddressVerificationTestData.admin()) {
			List<HealthCheckService.Finding> before = new AddressVerificationHealthCheckExtension()
				.findings();
			NightlyStep stepBefore = new AddressVerificationNightlyJobProvider().nightlySteps()[0];
			String notStarted = AddressVerificationController.verifyWaiting();

			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);
			List<HealthCheckService.Finding> after = new AddressVerificationHealthCheckExtension()
				.findings();
			NightlyStep stepAfter = new AddressVerificationNightlyJobProvider().nightlySteps()[0];

			Assert.areEqual(1, before.size(), 'Keys missing');
			Assert.areEqual('address_verification_keys_missing', before[0].key, 'The finding');
			Assert.isTrue(after.isEmpty(), 'Nothing once the keys are in and nothing waits');
			Assert.isFalse(stepBefore.active, 'The step waits for keys');
			Assert.isTrue(stepAfter.active, 'Then runs');
			Assert.isTrue(stepAfter.switchDefault, 'Its switch ships on');
			Assert.areEqual(
				BarnHelp.text('AddressVerification', 'AddressVerification_Setup_NotStarted'),
				notStarted,
				'Verify Waiting Addresses says why nothing started'
			);
		}
	}

	@IsTest
	static void healthCheckSaysNothingToSomeoneWhoCannotManageSettingsOrWhileTheModuleIsOff() {
		User staff = [SELECT Id FROM User WHERE LastName = 'Zzav Staff' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(staff) {
			Assert.isTrue(
				new AddressVerificationHealthCheckExtension().findings().isEmpty(),
				'Staff cannot manage settings, so nothing is reported'
			);
		}
		System.runAs(AddressVerificationTestData.admin()) {
			ModuleManagerService.turnOff(AddressVerifier.MODULE);
			Assert.isFalse(AddressVerifier.isOn(), 'The module is off');
			Assert.isTrue(
				new AddressVerificationHealthCheckExtension().findings().isEmpty(),
				'Nothing is reported while the module is off'
			);
		}
	}

	@IsTest
	static void healthCheckCountsCurrentAddressesStillUnverifiedAfterThirtyDays() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);
			AddressVerificationTestData.addresses(2, 'United States');

			Assert.isTrue(
				new AddressVerificationHealthCheckExtension().findings().isEmpty(),
				'Addresses changed just now are not waiting yet'
			);
			// A test cannot age a record, so the wait is moved to put the cut-off tomorrow.
			AddressVerificationHealthCheckExtension.waitDays = -1;
			Assert.areEqual(
				2,
				AddressVerificationHealthCheckExtension.waitingCount(),
				'Both current, unverified addresses are now past the wait'
			);
			List<HealthCheckService.Finding> found = new AddressVerificationHealthCheckExtension()
				.findings();

			Assert.areEqual(1, found.size(), 'The waiting count is reported');
			Assert.areEqual('address_verification_waiting', found[0].key, 'The finding');
			Assert.areEqual(HealthCheckService.SEVERITY_INFO, found[0].severity, 'Info only');
		}
	}
}
