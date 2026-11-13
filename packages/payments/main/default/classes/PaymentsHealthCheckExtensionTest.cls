/**
 * Payments' Health Check (ADR-0201 payments module, decision 7): it reports keys not entered, a
 * Stripe key for the other mode, no Site, a guest user without the receiver set (and gives it),
 * processing not scheduled (and schedules it) and events waiting; it is quiet when Payments is
 * turned off.
 */
@IsTest(testFor='ApexClass:PaymentsHealthCheckExtension, ApexClass:PaymentSites')
private class PaymentsHealthCheckExtensionTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(PaymentsTestData.ADMIN);
	}

	private static Set<String> keys(List<HealthCheckService.Finding> findings) {
		// Read through JSON: the finding's fields are Core's and not namespace accessible.
		Set<String> found = new Set<String>();
		for (Object finding : (List<Object>) JSON.deserializeUntyped(JSON.serialize(findings))) {
			found.add(String.valueOf(((Map<String, Object>) finding).get('key')));
		}
		return found;
	}

	@IsTest
	static void missingSetupIsReportedAndFixed() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentSites.testSites = new List<PaymentSites.SiteInfo>();
			PaymentsHealthCheckExtension extension = new PaymentsHealthCheckExtension();
			Payment_Event__c waiting = PaymentsTestData.event(
				PaymentService.STRIPE,
				'stripe:evt_w',
				'{}',
				null
			);
			Test.setCreatedDate(waiting.Id, Datetime.now().addHours(-2));

			Set<String> found = keys(extension.findings());
			Assert.isTrue(found.contains('payments_keys_missing'), 'No keys: ' + found);
			Assert.isTrue(found.contains('payments_no_site'), 'No Site: ' + found);
			Assert.isTrue(
				found.contains(PaymentsHealthCheckExtension.FIX_SCHEDULE),
				'Not scheduled'
			);
			Assert.isTrue(found.contains('payments_waiting'), 'Waiting: ' + found);

			Test.startTest();
			String done = extension.runFix(
				PaymentsHealthCheckExtension.FIX_SCHEDULE,
				extension.fixScope(PaymentsHealthCheckExtension.FIX_SCHEDULE)
			);
			Test.stopTest();
			Assert.isNotNull(done, 'Says what it did');
			Assert.isTrue(PaymentEventProcessor.isScheduled(), 'Scheduled');
			PaymentsTestData.connect(PaymentService.STRIPE);
			Assert.isFalse(
				keys(extension.findings()).contains('payments_keys_missing'),
				'Connected'
			);
		}
	}

	@IsTest
	static void aStripeKeyForTheOtherModeIsReported() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			Assert.isFalse(
				PaymentsHealthCheckExtension.stripeKeyMismatch(),
				'A test key in Test mode'
			);
			Payments_Settings__c live = Payments_Settings__c.getOrgDefaults();
			live.Mode__c = PaymentService.LIVE;
			update live;
			Assert.isTrue(
				PaymentsHealthCheckExtension.stripeKeyMismatch(),
				'A test key in Live mode'
			);
			Assert.isTrue(
				keys(new PaymentsHealthCheckExtension().findings())
					.contains('payments_mode_mismatch')
			);
		}
	}

	@IsTest
	static void aGuestWithoutAccessIsGivenIt() {
		System.runAs(PaymentsTestData.admin()) {
			User guest = TestUsers.standardUser('Zzpay Guest');
			PaymentSites.SiteInfo site = new PaymentSites.SiteInfo();
			site.name = 'Zzpay Site';
			site.guestUserId = guest.Id;
			site.url = 'https://zzpay.example.org';
			PaymentSites.testSites = new List<PaymentSites.SiteInfo>{ site };
			PaymentsHealthCheckExtension extension = new PaymentsHealthCheckExtension();

			Assert.isTrue(
				keys(extension.findings()).contains(PaymentsHealthCheckExtension.FIX_GUEST),
				'Reported'
			);
			Assert.areEqual(
				new List<String>{ 'Zzpay Site' },
				extension.fixScope(PaymentsHealthCheckExtension.FIX_GUEST),
				'Names the Site'
			);
			extension.runFix(
				PaymentsHealthCheckExtension.FIX_GUEST,
				new List<String>{ 'Zzpay Site' }
			);
			Assert.isFalse(
				keys(extension.findings()).contains(PaymentsHealthCheckExtension.FIX_GUEST),
				'Given'
			);
			Assert.isNotNull(
				extension.fixLabel(PaymentsHealthCheckExtension.FIX_GUEST),
				'Labelled'
			);
			Assert.isNull(extension.fixLabel('other'), 'Not its key');
			Assert.isNull(extension.runFix('other', null), 'Not its key');
		}
	}

	@IsTest
	static void quietWhenTurnedOffAndTheOrgsSitesAreRead() {
		System.runAs(PaymentsTestData.admin()) {
			BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
			settings.Modules_Turned_Off__c = 'Payments';
			TestDataFactory.saveSettings(settings);
			Assert.isTrue(new PaymentsHealthCheckExtension().findings().isEmpty(), 'Turned off');

			Integer expected = [
				SELECT COUNT()
				FROM Site
				WHERE Status = 'Active' AND SiteType = 'Visualforce'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(
				Math.min(expected, 50),
				PaymentSites.active().size(),
				'Every active Site'
			);
			Assert.isTrue(PaymentSites.guestUserIds().size() <= expected, 'Their guests');
		}
	}
}
