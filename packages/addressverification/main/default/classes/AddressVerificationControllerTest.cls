/**
 * Address Verification Setup, Health Check and the nightly step (ADR-0209 address verification
 * module, decisions 3, 5 and 7, as amended by ADR-NEXT
 * `NEXT-provider-secrets-named-credentials.md`; R-AV4): the page names where each key goes and
 * never holds one; Check Connection looks one address up through the Named Credential and records
 * the provider as connected only when it answered; a first save keeps the shipped choices;
 * Disconnect forgets one provider; someone who cannot manage settings changes nothing; Health
 * Check reports a provider not connected; the nightly step runs only once it is.
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

	private static Map<String, AddressVerificationController.Credential> byProvider(
		AddressVerificationController.Setup setup
	) {
		Map<String, AddressVerificationController.Credential> found = new Map<String, AddressVerificationController.Credential>();
		for (AddressVerificationController.Credential credential : setup.credentials) {
			found.put(credential.provider, credential);
		}
		return found;
	}

	@IsTest
	static void theSetupPageNamesWhereEachKeyGoes() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationController.Setup setup = AddressVerificationController.getSetup();

			Map<String, AddressVerificationController.Credential> found = byProvider(setup);
			Assert.areEqual(2, found.size(), 'Both providers');
			Assert.areEqual(
				NamespaceUtil.qualify('Barn_Smarty'),
				found.get(AddressVerifier.SMARTY).externalCredential,
				'Qualified for this org'
			);
			Assert.areEqual('AuthId, AuthToken', found.get(AddressVerifier.SMARTY).parameters);
			Assert.areEqual('ApiKey', found.get(AddressVerifier.GOOGLE).parameters);
			Assert.isFalse(found.get(AddressVerifier.SMARTY).connected, 'Not yet');
			Assert.isFalse(setup.ready, 'Nothing is looked up yet');
		}
	}

	@IsTest
	static void aSuccessfulCheckConnectsAndKeepsTheShippedChoices() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.Provider smarty = new AddressVerificationTestData.Provider(
				200,
				AddressVerificationTestData.SMARTY_FOUND
			);
			Test.setMock(HttpCalloutMock.class, smarty);

			Test.startTest();
			String said = AddressVerificationController.checkConnection(AddressVerifier.SMARTY);
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text(
					'AddressVerification',
					'AddressVerification_Setup_Connected',
					new List<Object>{ AddressVerifier.SMARTY }
				),
				said
			);
			Assert.isTrue(
				smarty.requests[0]
					.getEndpoint()
					.startsWith('callout:' + AddressVerifier.credential(AddressVerifier.SMARTY)),
				'Through the Named Credential'
			);
			Assert.isTrue(AddressVerifier.isReady(), 'Smarty, the default provider, is ready');
			Address_Verification_Settings__c stored = Address_Verification_Settings__c.getOrgDefaults();
			Assert.areEqual(AddressVerifier.SMARTY, stored.Connected_Provider__c, 'Recorded');
			Assert.isTrue(stored.Verify_On_Save__c, 'The first save keeps Verify On Save on');
			Assert.areEqual(200, stored.Nightly_Limit__c, 'And the shipped limit');
		}
	}

	@IsTest
	static void aFailedCheckSaysWhyAndDoesNotConnect() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.GOOGLE, false);
			Test.setMock(
				HttpCalloutMock.class,
				new AddressVerificationTestData.Provider(403, '{"error":{"status":"DENIED"}}')
			);

			Test.startTest();
			String said = AddressVerificationController.checkConnection(AddressVerifier.GOOGLE);
			Test.stopTest();

			Assert.isTrue(said.contains('403'), said);
			Assert.isFalse(AddressVerifier.isReady(), 'No longer used');
			Assert.isNull(Address_Verification_Settings__c.getOrgDefaults().Connected_Provider__c);
		}
	}

	@IsTest
	static void disconnectingForgetsOneProvider() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);

			AddressVerificationController.Setup kept = AddressVerificationController.clearKeys(
				'Google'
			);
			Assert.isTrue(byProvider(kept).get(AddressVerifier.SMARTY).connected, 'Smarty kept');
			AddressVerificationController.Setup cleared = AddressVerificationController.clearKeys(
				'Smarty'
			);
			Assert.isFalse(byProvider(cleared).get(AddressVerifier.SMARTY).connected, 'Forgotten');
			Assert.isFalse(cleared.ready, 'Nothing is looked up');
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
				AddressVerificationController.checkConnection(AddressVerifier.GOOGLE);
				Assert.fail('Refused');
			} catch (AuraHandledException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused with a message');
			}
		}
		Assert.isNull(
			Address_Verification_Settings__c.getOrgDefaults().Connected_Provider__c,
			'Nothing saved'
		);
	}

	@IsTest
	static void healthCheckAndTheNightlyStepWaitForAConnection() {
		System.runAs(AddressVerificationTestData.admin()) {
			List<HealthCheckService.Finding> before = new AddressVerificationHealthCheckExtension()
				.findings();
			NightlyStep stepBefore = new AddressVerificationNightlyJobProvider().nightlySteps()[0];
			String notStarted = AddressVerificationController.verifyWaiting();

			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);
			List<HealthCheckService.Finding> after = new AddressVerificationHealthCheckExtension()
				.findings();
			NightlyStep stepAfter = new AddressVerificationNightlyJobProvider().nightlySteps()[0];

			Assert.areEqual(1, before.size(), 'Not connected');
			Assert.areEqual('address_verification_keys_missing', before[0].key, 'The finding');
			Assert.isTrue(after.isEmpty(), 'Nothing once connected and nothing waits');
			Assert.isFalse(stepBefore.active, 'The step waits for a connection');
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
