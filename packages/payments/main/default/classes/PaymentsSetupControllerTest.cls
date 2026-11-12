/**
 * Payments Setup (ADR-0201 payments module, decision 7): it shows each Site's receiver
 * addresses and only the last four characters of each key; saving keeps keys left blank;
 * clearing removes one processor's keys; someone who cannot manage settings cannot change them.
 */
@IsTest(testFor='ApexClass:PaymentsSetupController')
private class PaymentsSetupControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(PaymentsTestData.ADMIN);
	}

	private static Map<String, String> lastFour(PaymentsSetupController.Setup setup) {
		Map<String, String> byName = new Map<String, String>();
		for (PaymentsSetupController.KeyStatus key : setup.keys) {
			byName.put(key.name, key.lastFour);
		}
		return byName;
	}

	@IsTest
	static void showsAddressesAndOnlyTheEndOfEachKey() {
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
			Assert.areEqual('barn', lastFour(setup).get('stripeSecretKey'), 'The last four only');
			Assert.isFalse(JSON.serialize(setup).contains('sk_test_barn'), 'Never the key');
			Assert.areEqual(5, setup.keys.size(), 'Every key');
			Assert.isTrue(setup.canManage, 'An admin may change them');
			Assert.areEqual(PaymentService.TEST, setup.mode, 'The mode');
		}
	}

	@IsTest
	static void savingKeepsBlankKeysAndClearingRemovesOneProcessor() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);

			PaymentsSetupController.Setup saved = PaymentsSetupController.saveKeys(
				new Map<String, String>{
					'stripeSecretKey' => '  sk_live_9876  ',
					'stripeWebhookSecret' => '',
					'notAKey' => 'ignored'
				}
			);
			Assert.areEqual('9876', lastFour(saved).get('stripeSecretKey'), 'Saved, trimmed');
			Assert.areEqual(
				'cret',
				lastFour(saved).get('stripeWebhookSecret'),
				'Blank keeps the old'
			);
			Assert.areEqual(
				'sk_live_9876',
				Payment_Keys__c.getOrgDefaults().Stripe_Secret_Key__c,
				'Stored'
			);

			PaymentsSetupController.Setup cleared = PaymentsSetupController.clearKeys(
				PaymentService.PAYPAL
			);
			Assert.isNull(lastFour(cleared).get('payPalClientId'), 'PayPal cleared');
			Assert.isNull(lastFour(cleared).get('payPalWebhookId'), 'Every PayPal key');
			Assert.areEqual('9876', lastFour(cleared).get('stripeSecretKey'), 'Stripe kept');
			try {
				PaymentsSetupController.clearKeys('Square');
				Assert.fail('Not a processor');
			} catch (AuraHandledException e) {
				Assert.isNotNull(e.getMessage(), 'Refused');
			}
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
	static void someoneWhoCannotManageSettingsCannotChangeKeys() {
		User staff = TestUsers.standardUserWith(
			'Zzpay Staff',
			new List<String>{ 'Payments_Staff' }
		);
		System.runAs(staff) {
			try {
				PaymentsSetupController.saveKeys(
					new Map<String, String>{ 'stripeSecretKey' => 'sk_test_x' }
				);
				Assert.fail('Refused');
			} catch (AuraHandledException e) {
				Assert.isNotNull(e.getMessage(), 'Says why');
			}
		}
		System.runAs(PaymentsTestData.admin()) {
			Assert.isNull(Payment_Keys__c.getOrgDefaults().Stripe_Secret_Key__c, 'Nothing saved');
		}
	}
}
