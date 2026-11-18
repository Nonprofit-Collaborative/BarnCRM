/**
 * Payments Setup (ADR-0201 payments module, decision 7, as amended by ADR-NEXT
 * `NEXT-provider-secrets-named-credentials.md`): it shows each Site's receiver addresses, where
 * each processor's secrets go in Setup and whether it is connected, and the PayPal webhook id by
 * its last four characters; Check Connection calls the processor through its Named Credential and
 * records the answer; Disconnect forgets one processor; someone who cannot manage settings cannot
 * change anything.
 */
@IsTest(testFor='ApexClass:PaymentsSetupController')
private class PaymentsSetupControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(PaymentsTestData.ADMIN);
	}

	private static Map<String, PaymentsSetupController.Credential> byProcessor(
		PaymentsSetupController.Setup setup
	) {
		Map<String, PaymentsSetupController.Credential> found = new Map<String, PaymentsSetupController.Credential>();
		for (PaymentsSetupController.Credential credential : setup.credentials) {
			found.put(credential.processor, credential);
		}
		return found;
	}

	@IsTest
	static void showsAddressesConnectionsAndWhereEachSecretGoes() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentSites.SiteInfo site = new PaymentSites.SiteInfo();
			site.name = 'Zzpay Site';
			site.url = 'https://zzpay.example.org';
			PaymentSites.SiteInfo noAddress = new PaymentSites.SiteInfo();
			noAddress.name = 'Not Published';
			PaymentSites.testSites = new List<PaymentSites.SiteInfo>{ site, noAddress };
			PaymentsTestData.connect(PaymentService.STRIPE);

			PaymentsSetupController.Setup setup = PaymentsSetupController.getSetup();

			Assert.areEqual(1, setup.receivers.size(), 'Only Sites with an address');
			Assert.areEqual(
				'https://zzpay.example.org/services/apexrest/barncrm/payments/v1/stripe',
				setup.receivers[0].stripeUrl,
				'The Stripe address'
			);
			Assert.isTrue(
				setup.receivers[0].payPalUrl.endsWith('/v1/paypal'),
				'The PayPal address'
			);
			Map<String, PaymentsSetupController.Credential> found = byProcessor(setup);
			Assert.isTrue(found.get(PaymentService.STRIPE).connected, 'Stripe connected');
			Assert.areEqual(
				NamespaceUtil.qualify('Barn_Stripe'),
				found.get(PaymentService.STRIPE).externalCredential,
				'The External Credential, qualified for this org'
			);
			Assert.areEqual('SecretKey', found.get(PaymentService.STRIPE).parameters);
			Assert.areEqual('Barn_PayPal_App', found.get(PaymentService.PAYPAL).principal);
			Assert.isTrue(
				found.get(PaymentService.PAYPAL).namedCredentials.contains('Barn_PayPal_Sandbox'),
				'Both PayPal Named Credentials'
			);
			Assert.areEqual(1, setup.keys.size(), 'Only the webhook id is typed here');
			Assert.areEqual('WH-1', setup.keys[0].lastFour, 'Its last four');
			Assert.isTrue(setup.canManage, 'An admin may change them');
			Assert.areEqual(PaymentService.TEST, setup.mode, 'The mode');
		}
	}

	@IsTest
	static void savingKeepsABlankWebhookIdAndDisconnectingForgetsOneProcessor() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);

			PaymentsSetupController.Setup kept = PaymentsSetupController.saveKeys(
				new Map<String, String>{ 'payPalWebhookId' => '', 'notAKey' => 'ignored' }
			);
			Assert.areEqual('WH-1', kept.keys[0].lastFour, 'Blank keeps the old');
			PaymentsSetupController.Setup saved = PaymentsSetupController.saveKeys(
				new Map<String, String>{ 'payPalWebhookId' => '  WH-98765  ' }
			);
			Assert.areEqual('8765', saved.keys[0].lastFour, 'Saved, trimmed');
			Assert.areEqual(
				'WH-98765',
				Payments_Settings__c.getOrgDefaults().PayPal_Webhook_Id__c,
				'Stored'
			);

			PaymentsSetupController.Setup cleared = PaymentsSetupController.clearKeys(
				PaymentService.PAYPAL
			);
			Assert.isFalse(byProcessor(cleared).get(PaymentService.PAYPAL).connected);
			Assert.isNull(cleared.keys[0].lastFour, 'The webhook id too');
			Assert.isTrue(byProcessor(cleared).get(PaymentService.STRIPE).connected, 'Kept');
			Assert.isFalse(PaymentService.isReady(PaymentService.PAYPAL), 'Not used until checked');
			try {
				PaymentsSetupController.clearKeys('Square');
				Assert.fail('Not a processor');
			} catch (AuraHandledException e) {
				Assert.isNotNull(e.getMessage(), 'Refused');
			}
		}
	}

	@IsTest
	static void checkConnectionRecordsWhatStripeSaid() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer('balance', 200, '{"object":"balance","livemode":false}');

			Test.startTest();
			PaymentsSetupController.Setup connected = PaymentsSetupController.checkConnection(
				PaymentService.STRIPE
			);
			Test.stopTest();

			Assert.isTrue(connected.checkOk, 'Stripe answered');
			Assert.areEqual(
				BarnHelp.text(
					'Payments',
					'Payments_Setup_Connected',
					new List<Object>{ 'Stripe', PaymentService.TEST }
				),
				connected.checkMessage
			);
			Assert.areEqual(
				'Bearer {!$Credential.' + PaymentStripe.CREDENTIAL + '.SecretKey}',
				mock.last('balance').getHeader('Authorization'),
				'Through the Named Credential'
			);
			Assert.isTrue(PaymentService.isReady(PaymentService.STRIPE), 'Ready');
		}
	}

	@IsTest
	static void aFailedCheckStopsTheProcessorBeingUsed() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			PaymentsTestData.processors()
				.answer('balance', 401, '{"error":{"message":"Invalid API Key"}}');

			Test.startTest();
			PaymentsSetupController.Setup refused = PaymentsSetupController.checkConnection(
				PaymentService.STRIPE
			);
			Test.stopTest();

			Assert.isFalse(refused.checkOk, 'A bad key');
			Assert.isTrue(refused.checkMessage.contains('401'), refused.checkMessage);
			Assert.isFalse(
				PaymentService.isReady(PaymentService.STRIPE),
				'Not used until a check succeeds'
			);
		}
	}

	@IsTest
	static void checkConnectionSaysWhenTheStripeKeyIsForTheOtherMode() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			PaymentsTestData.processors()
				.answer('balance', 200, '{"object":"balance","livemode":true}');

			Test.startTest();
			PaymentsSetupController.Setup checked = PaymentsSetupController.checkConnection(
				PaymentService.STRIPE
			);
			Test.stopTest();

			Assert.isTrue(checked.checkOk, 'Connected');
			Assert.areEqual(
				BarnHelp.text(
					'Payments',
					'Payments_Health_ModeMismatchDetail',
					new List<Object>{ PaymentService.TEST }
				),
				checked.checkMessage,
				'A live key in Test mode'
			);
		}
	}

	@IsTest
	static void checkConnectionSignsInToPayPal() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer('oauth2/token', 200, '{"access_token":"tok"}');

			Test.startTest();
			PaymentsSetupController.Setup checked = PaymentsSetupController.checkConnection(
				PaymentService.PAYPAL
			);
			Test.stopTest();

			Assert.isTrue(checked.checkOk, 'Signed in');
			Assert.isTrue(byProcessor(checked).get(PaymentService.PAYPAL).connected);
			Assert.isTrue(
				mock.last('oauth2/token').getEndpoint().startsWith(PaymentPayPal.TEST_BASE),
				'The sandbox Named Credential in Test mode'
			);
		}
	}

	@IsTest
	static void aRefusedPayPalSignInIsNotConnected() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			PaymentsTestData.processors().answer('oauth2/token', 401, '{"error":"invalid_client"}');

			Test.startTest();
			PaymentsSetupController.Setup refused = PaymentsSetupController.checkConnection(
				PaymentService.PAYPAL
			);
			Test.stopTest();

			Assert.isFalse(refused.checkOk, 'Refused');
			Assert.isFalse(byProcessor(refused).get(PaymentService.PAYPAL).connected);
			Assert.isFalse(PaymentService.isReady(PaymentService.PAYPAL), 'Not used');
		}
	}

	@IsTest
	static void processingIsShownUnscheduledUntilTheAdminSchedulesIt() {
		System.runAs(PaymentsTestData.admin()) {
			Assert.isFalse(PaymentsSetupController.getSetup().scheduled, 'Never automatic');

			Test.startTest();
			PaymentsSetupController.Setup after = PaymentsSetupController.scheduleProcessing();
			Test.stopTest();

			Assert.isTrue(after.scheduled, 'Scheduled by the click');
			Assert.isTrue(PaymentEventProcessor.isScheduled(), 'The four jobs');
		}
	}

	@IsTest
	static void someoneWhoCannotManageSettingsCannotChangeAnything() {
		User staff = TestUsers.standardUserWith(
			'Zzpay Staff',
			new List<String>{ 'Payments_Staff' }
		);
		System.runAs(staff) {
			try {
				PaymentsSetupController.saveKeys(
					new Map<String, String>{ 'payPalWebhookId' => 'WH-X' }
				);
				Assert.fail('Refused');
			} catch (AuraHandledException e) {
				Assert.isNotNull(e.getMessage(), 'Says why');
			}
			try {
				PaymentsSetupController.checkConnection(PaymentService.STRIPE);
				Assert.fail('Refused');
			} catch (AuraHandledException e) {
				Assert.isNotNull(e.getMessage(), 'Says why');
			}
		}
		System.runAs(PaymentsTestData.admin()) {
			Assert.isNull(
				Payments_Settings__c.getOrgDefaults().PayPal_Webhook_Id__c,
				'Nothing saved'
			);
		}
	}
}
