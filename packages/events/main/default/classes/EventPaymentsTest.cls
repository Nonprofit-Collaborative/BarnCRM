/**
 * Dana's gala takes payment online (EV-20, R-ERG5 to R-ERG7): a form registration that owes money
 * waits with its seat held, the job starts the checkout and emails the link, and what the
 * processor reports confirms, refunds or cancels it. Payments is a stand-in here, as it may not
 * be installed beside Events.
 */
@IsTest(
	testFor='ApexClass:EventPayments, ApexClass:EventPaymentListener, ApexClass:EventCheckoutJob, ApexClass:EventTemplateMail'
)
private class EventPaymentsTest {
	private static final String LINK = 'https://checkout.stripe.com/c/pay/cs_test_1';

	/** BarnCRM Payments' seam as a test sees it. */
	private class FakePayments implements Callable {
		Boolean ready = true;
		String refuseWith;
		List<Map<String, Object>> started = new List<Map<String, Object>>();

		public Object call(String action, Map<String, Object> args) {
			if (action == 'isReady') {
				return ready;
			}
			if (refuseWith != null) {
				throw new IllegalArgumentException(refuseWith);
			}
			started.add(args);
			return new Map<String, Object>{
				'paymentId' => UserInfo.getOrganizationId(),
				'checkoutUrl' => LINK,
				'status' => 'Pending'
			};
		}
	}

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static FakePayments online(Boolean turnedOn) {
		OrgSettingsSystemWriter.save(
			Events_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Events_Settings__c.Online_Payments__c => turnedOn
			}
		);
		SettingsService.clearCaches();
		FakePayments fake = new FakePayments();
		EventPayments.apiForTest = fake;
		return fake;
	}

	private static Id register(String source, Decimal price) {
		Datetime start = Datetime.now().addDays(30);
		Event__c event = new Event__c(
			Name = 'Spring Gala',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(4)
		);
		insert as user event;
		insert as user new Ticket_Type__c(
			Event__c = event.Id,
			Name = 'General',
			Price__c = price,
			Active__c = true
		);
		Contact jane = TestDataFactory.person(
			new Contact(FirstName = 'Jane', LastName = 'Payer', Email = 'jane@example.org')
		);
		// An org's duplicate rule must not stop a test person sharing an email.
		Database.DMLOptions options = new Database.DMLOptions();
		options.DuplicateRuleHeader.allowSave = true;
		Database.insert(jane, options, AccessLevel.USER_MODE);
		EventRegistrationService.Request request = new EventRegistrationService.Request();
		request.eventId = event.Id;
		request.registrant = new EventPersonMatcher.PersonInput();
		request.registrant.contactId = jane.Id;
		request.source = source;
		return EventRegistrationService.register(request).registrationId;
	}

	private static Event_Registration__c reload(Id registrationId) {
		return [
			SELECT
				Status__c,
				Payment_Status__c,
				Payment_Key__c,
				Payment_Link__c,
				Amount_Paid__c,
				(SELECT Status__c FROM Attendees__r)
			FROM Event_Registration__c
			WHERE Id = :registrationId
		];
	}

	private static Map<String, Object> report(Id registrationId, String status, Decimal refunded) {
		return new Map<String, Object>{
			'paymentId' => UserInfo.getOrganizationId(),
			'sourceRecordId' => registrationId,
			'status' => status,
			'amount' => 25.00,
			'amountRefunded' => refunded
		};
	}

	private static void makeTemplate() {
		System.runAs(new User(Id = UserInfo.getUserId())) {
			insert new EmailTemplate(
				Name = 'Payment link',
				DeveloperName = EventsSettings.paymentLinkTemplate(),
				TemplateType = 'text',
				FolderId = UserInfo.getUserId(),
				IsActive = true,
				Subject = 'Pay',
				Body = 'Pay here'
			);
		}
	}

	@IsTest
	static void aFormRegistrationThatOwesMoneyWaitsWithItsSeatHeld() {
		System.runAs(staff()) {
			online(true);
			Test.startTest();
			Id waiting = register(EventRegistrationService.SOURCE_FORM, 25);
			Test.stopTest();

			Event_Registration__c after = reload(waiting);
			Assert.areEqual('Pending Payment', after.Status__c, 'Waits for payment');
			Assert.areEqual(EventPayments.UNPAID, after.Payment_Status__c, 'Unpaid');
			Assert.areEqual('Registered', after.Attendees__r[0].Status__c, 'The seat is held');
			Assert.isTrue(EventPayments.checkoutsQueued, 'The checkout job is queued');
		}
	}

	@IsTest
	static void staffFreeAndSettingOffRegistrationsAreConfirmedAtOnce() {
		System.runAs(staff()) {
			FakePayments fake = online(false);
			Id settingOff = register(EventRegistrationService.SOURCE_FORM, 25);
			online(true);
			Id byStaff = register(EventRegistrationService.SOURCE_STAFF, 25);
			Id free = register(EventRegistrationService.SOURCE_FORM, 0);
			fake = online(true);
			fake.ready = false;
			Id notReady = register(EventRegistrationService.SOURCE_FORM, 25);

			for (Id registrationId : new List<Id>{ settingOff, byStaff, free, notReady }) {
				Event_Registration__c after = reload(registrationId);
				Assert.areEqual('Registered', after.Status__c, 'Confirmed at once');
				Assert.isNull(after.Payment_Status__c, 'No online payment asked for');
			}
		}
	}

	@IsTest
	static void theJobStartsTheCheckoutAndEmailsTheLink() {
		makeTemplate();
		RecordingEmailSender sender = new RecordingEmailSender();
		EventPayments.emailSender = sender;
		System.runAs(staff()) {
			FakePayments fake = online(true);
			Id waiting = register(EventRegistrationService.SOURCE_FORM, 25);

			Test.startTest();
			new EventCheckoutJob().execute(null);
			Test.stopTest();

			Event_Registration__c after = reload(waiting);
			Assert.areEqual(EventPayments.LINK_SENT, after.Payment_Status__c, 'Link sent');
			Assert.areEqual(LINK, after.Payment_Link__c, 'The checkout address is kept');
			Assert.areEqual(
				UserInfo.getOrganizationId(),
				Id.valueOf(after.Payment_Key__c),
				'The payment is the current one'
			);
			Assert.areEqual('Pending Payment', after.Status__c, 'Still waits');
			Assert.areEqual(1, fake.started.size(), 'One checkout');
			Assert.areEqual(25, (Decimal) fake.started[0].get('amount'), 'The amount owed');
			Assert.areEqual(EventPayments.LISTENER, fake.started[0].get('listener'), 'Listener');
			Assert.areEqual(waiting, fake.started[0].get('sourceRecordId'), 'Source');
			Assert.isTrue(
				String.valueOf(fake.started[0].get('successUrl')).startsWith('https://'),
				'A secure return address'
			);
			Assert.areEqual(1, sender.received.size(), 'The link is emailed');
		}
	}

	@IsTest
	static void aRefusedCheckoutMarksThePaymentFailedAndStopsThere() {
		System.runAs(staff()) {
			FakePayments fake = online(true);
			Id waiting = register(EventRegistrationService.SOURCE_FORM, 25);
			fake.refuseWith = 'The Stripe key was refused.';

			Test.startTest();
			new EventCheckoutJob().execute(null);
			Test.stopTest();

			Assert.areEqual(EventPayments.FAILED, reload(waiting).Payment_Status__c, 'Failed');
		}
	}

	@IsTest
	static void aFailedMarkIsReportedSoTheJobDoesNotChainOnIt() {
		System.runAs(staff()) {
			online(true);
			Id waiting = register(EventRegistrationService.SOURCE_FORM, 25);
			Assert.isTrue(EventCheckoutJob.markFailed(waiting), 'A saved mark is reported');
			Assert.areEqual(EventPayments.FAILED, reload(waiting).Payment_Status__c, 'Failed');
			Id gone = Id.valueOf(
				Event_Registration__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
					.getKeyPrefix() + '000000000001'
			);
			Assert.isFalse(
				EventCheckoutJob.markFailed(gone),
				'A mark that did not save is reported'
			);
		}
	}

	@IsTest
	static void theMorningRunQueuesCheckoutsOnlyWhileOnlinePaymentsAreOn() {
		System.runAs(staff()) {
			online(false);
			new EventEmailScheduler().execute(null);
			Assert.isFalse(EventPayments.checkoutsQueued, 'Nothing queued while payments are off');
			online(true);
			new EventEmailScheduler().execute(null);
			Assert.isTrue(EventPayments.checkoutsQueued, 'Unpaid registrations are swept up');
		}
	}

	@IsTest
	static void thePaymentConfirmsThenRefundsCancel() {
		System.runAs(staff()) {
			online(true);
			Id waiting = register(EventRegistrationService.SOURCE_FORM, 25);
			update as system new Event_Registration__c(
				Id = waiting,
				Payment_Key__c = UserInfo.getOrganizationId()
			);
			Callable listener = new EventPaymentListener();

			Test.startTest();
			listener.call('paymentChanged', report(waiting, 'Paid', 0));
			listener.call('paymentChanged', report(waiting, 'Paid', 0));
			Event_Registration__c paid = reload(waiting);
			listener.call('paymentChanged', report(waiting, 'Paid', 10));
			Event_Registration__c partly = reload(waiting);
			listener.call('paymentChanged', report(waiting, 'Refunded', 25));
			Test.stopTest();

			Assert.areEqual('Registered', paid.Status__c, 'Confirmed on payment');
			Assert.areEqual(EventPayments.PAID, paid.Payment_Status__c, 'Paid');
			Assert.areEqual(25, paid.Amount_Paid__c, 'Amount paid');
			Assert.areEqual(EventPayments.PARTLY_REFUNDED, partly.Payment_Status__c, 'Partly');
			Assert.areEqual(15, partly.Amount_Paid__c, 'Less the refund');
			Event_Registration__c refunded = reload(waiting);
			Assert.areEqual('Cancelled', refunded.Status__c, 'A full refund cancels');
			Assert.areEqual(0, refunded.Amount_Paid__c, 'Nothing kept');
			Assert.areEqual('Cancelled', refunded.Attendees__r[0].Status__c, 'Seat freed');
		}
	}

	@IsTest
	static void anAbandonedCheckoutCancelsOnlyARegistrationThatWaits() {
		System.runAs(staff()) {
			online(true);
			Id waiting = register(EventRegistrationService.SOURCE_FORM, 25);
			Id byStaff = register(EventRegistrationService.SOURCE_STAFF, 25);
			Id stale = register(EventRegistrationService.SOURCE_FORM, 25);
			update as system new List<Event_Registration__c>{
				new Event_Registration__c(
					Id = waiting,
					Payment_Key__c = UserInfo.getOrganizationId()
				),
				new Event_Registration__c(
					Id = byStaff,
					Payment_Key__c = UserInfo.getOrganizationId()
				),
				new Event_Registration__c(Id = stale, Payment_Key__c = UserInfo.getUserId())
			};
			Callable listener = new EventPaymentListener();

			Test.startTest();
			listener.call('paymentChanged', report(waiting, 'Cancelled', 0));
			listener.call('paymentChanged', report(byStaff, 'Cancelled', 0));
			listener.call('paymentChanged', report(stale, 'Paid', 0));
			listener.call('somethingElse', report(stale, 'Paid', 0));
			Test.stopTest();

			Event_Registration__c abandoned = reload(waiting);
			Assert.areEqual('Cancelled', abandoned.Status__c, 'Cancelled');
			Assert.areEqual('Cancelled', abandoned.Attendees__r[0].Status__c, 'Seat freed');
			Event_Registration__c kept = reload(byStaff);
			Assert.areEqual('Registered', kept.Status__c, 'A staff registration stays');
			Assert.areEqual(EventPayments.CANCELLED, kept.Payment_Status__c, 'Recorded');
			Assert.areEqual(
				'Pending Payment',
				reload(stale).Status__c,
				'A report about an older payment changes nothing'
			);
		}
	}

	@IsTest
	static void staffSendALinkOnlyForWhatIsOwed() {
		makeTemplate();
		EventPayments.emailSender = new RecordingEmailSender();
		System.runAs(staff()) {
			online(true);
			Id byStaff = register(EventRegistrationService.SOURCE_STAFF, 25);
			Id free = register(EventRegistrationService.SOURCE_STAFF, 0);

			Test.startTest();
			String sent = EventRegistrationsController.sendPaymentLink(byStaff);
			Boolean refused = false;
			try {
				EventRegistrationsController.sendPaymentLink(free);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Events', 'Events_Payment_LinkSent'), sent, 'Sent');
			Assert.isTrue(refused, 'Nothing owed is refused');
			Event_Registration__c after = reload(byStaff);
			Assert.areEqual('Registered', after.Status__c, 'Not held for payment');
			Assert.areEqual(EventPayments.LINK_SENT, after.Payment_Status__c, 'Link sent');
		}
	}

	@IsTest
	static void thePortalResendsOnlyThePersonsOwnLink() {
		makeTemplate();
		EventPayments.emailSender = new RecordingEmailSender();
		System.runAs(staff()) {
			online(true);
			Id waiting = register(EventRegistrationService.SOURCE_FORM, 25);
			Event_Registration__c registration = [
				SELECT Contact__c
				FROM Event_Registration__c
				WHERE Id = :waiting
			];
			PortalActionExtension portal = new EventsPortalExtension();

			Test.startTest();
			String none = portal.run(
				EventsPortalExtension.SEND_LINK,
				registration.Contact__c,
				waiting
			);
			update as system new Event_Registration__c(Id = waiting, Payment_Link__c = LINK);
			String sent = portal.run(
				EventsPortalExtension.SEND_LINK,
				registration.Contact__c,
				waiting
			);
			Boolean refused = false;
			try {
				portal.run(EventsPortalExtension.SEND_LINK, UserInfo.getUserId(), waiting);
			} catch (QueryException e) {
				refused = true;
			}
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Events', 'Events_Portal_NoPaymentLink'),
				none,
				'No link'
			);
			Assert.areEqual(BarnHelp.text('Events', 'Events_Portal_PaymentLinkSent'), sent, 'Sent');
			Assert.isTrue(refused, 'Another person is refused');
		}
	}

	@IsTest
	static void healthCheckWarnsWhenPaymentsAreNotReady() {
		System.runAs(staff()) {
			FakePayments fake = online(true);
			fake.ready = false;

			Test.startTest();
			String found = JSON.serialize(new EventsHealthCheckExtension().findings());
			Test.stopTest();

			Assert.isTrue(found.contains(EventsHealthCheckExtension.PAYMENTS_NOT_READY), found);
		}
	}
}
