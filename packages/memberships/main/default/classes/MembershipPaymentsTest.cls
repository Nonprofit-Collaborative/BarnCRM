/**
 * Dues paid online (PAY-02; canonical model R-MEM7): a payment link is asked of Payments by name,
 * stored on the term and emailed; a payment renews or activates the term once; a refund cancels
 * it; the portal's Pay Dues works only on the person's own term. Payments is a test double.
 */
@IsTest(
	testFor='ApexClass:MembershipPayments, ApexClass:MembershipPaymentListener, ApexClass:MembershipsPortalExtension'
)
private class MembershipPaymentsTest {
	private static final String ADMIN = 'Memberships_Admin';
	private static final String LINK = 'https://checkout.example.org/pay/1';

	/** Payments: ready or not, recording each checkout asked for. */
	private class FakePayments implements Callable {
		Boolean ready;
		List<Map<String, Object>> checkouts = new List<Map<String, Object>>();
		FakePayments(Boolean ready) {
			this.ready = ready;
		}
		public Object call(String action, Map<String, Object> args) {
			if (action == 'isReady') {
				return ready;
			}
			checkouts.add(args);
			return new Map<String, Object>{ 'checkoutUrl' => LINK };
		}
	}

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN);
	}

	private static Membership_Term__c term(String status, String email) {
		Membership_Level__c level = new Membership_Level__c(
			Name = 'Individual',
			Dues__c = 50,
			Term_Months__c = 12
		);
		insert as user level;
		Contact member = new Contact(LastName = 'Zzmem Payer', Email = email);
		insert as user member;
		Membership_Term__c term = new Membership_Term__c(
			Level__c = level.Id,
			Contact__c = member.Id,
			Status__c = status,
			Start_Date__c = status == 'Pending' ? null : Date.today().addMonths(-11)
		);
		insert as user term;
		return [
			SELECT Id, Contact__c, Status__c
			FROM Membership_Term__c
			WHERE Id = :term.Id
			WITH USER_MODE
		];
	}

	private static String refusal(Id termId) {
		try {
			MembershipPayments.request(termId);
			return null;
		} catch (MembershipService.MembershipException e) {
			return e.getMessage();
		}
	}

	@IsTest
	static void aLinkIsAskedOfPaymentsStoredAndEmailed() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			FakePayments payments = new FakePayments(true);
			MembershipPayments.apiOverride = payments;
			RecordingEmailSender sender = new RecordingEmailSender();
			MembershipPayments.emailSender = sender;
			Membership_Term__c current = term('Current', 'payer@example.org');
			Test.startTest();
			MembershipPayments.request(current.Id);
			Test.stopTest();
			Assert.areEqual(1, payments.checkouts.size(), 'one checkout');
			Map<String, Object> asked = payments.checkouts[0];
			Assert.areEqual(50, (Decimal) asked.get('amount'), 'the level dues');
			Assert.areEqual(MembershipPayments.LISTENER, asked.get('listener'), 'told back to us');
			Assert.areEqual(current.Id, asked.get('sourceRecordId'), 'for this term');
			Assert.areEqual(
				LINK,
				[SELECT Pay_Link__c FROM Membership_Term__c WHERE Id = :current.Id WITH USER_MODE]
				.Pay_Link__c,
				'the link is on the term'
			);
			Assert.areEqual(1, sender.received.size(), 'emailed to the member');
			Assert.isNotNull(MembershipPayments.returnUrl(), 'the payer returns somewhere');
		}
	}

	@IsTest
	static void aLinkIsRefusedWithTheReason() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipPayments.apiOverride = new FakePayments(false);
			Membership_Term__c noEmail = term('Current', null);
			Assert.areEqual(
				BarnHelp.text('Memberships', 'Memberships_Error_PaymentsNotReady'),
				refusal(noEmail.Id),
				'Payments not ready'
			);
			MembershipPayments.apiOverride = new FakePayments(true);
			Assert.areEqual(
				BarnHelp.text('Memberships', 'Memberships_Error_NoEmail'),
				refusal(noEmail.Id),
				'no email'
			);
			Assert.areEqual(
				BarnHelp.text('Memberships', 'Memberships_Error_NotFound'),
				refusal(
					Id.valueOf(
						Membership_Term__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
							.getKeyPrefix() + '000000000001'
					)
				),
				'no term'
			);
		}
	}

	/** Payments that is ready but fails to start a checkout, or fails even to say if it is ready. */
	private class FailingPayments implements Callable {
		Boolean failReadiness;
		FailingPayments(Boolean failReadiness) {
			this.failReadiness = failReadiness;
		}
		public Object call(String action, Map<String, Object> args) {
			if (action == 'isReady' && !failReadiness) {
				return true;
			}
			throw new IllegalArgumentException('Payments is down');
		}
	}

	@IsTest
	static void paymentsIsNotReadyWhenItIsAbsentOrCannotSay() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipPayments.apiOverride = new FailingPayments(true);
			Assert.isFalse(MembershipPayments.ready(), 'It could not answer');
			MembershipPayments.apiOverride = null;
			Assert.isFalse(MembershipPayments.ready(), 'Nothing is connected in a new org');
		}
	}

	@IsTest
	static void aTermThatCannotPayOrOwesNothingIsRefused() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipPayments.apiOverride = new FakePayments(true);
			Assert.areEqual(
				BarnHelp.text('Memberships', 'Memberships_Error_CannotRenew'),
				refusal(term('Renewed', 'renewed.payer@example.org').Id),
				'A renewed term is done'
			);
			Assert.areEqual(
				BarnHelp.text('Memberships', 'Memberships_Error_CannotRenew'),
				refusal(term('Cancelled', 'cancelled.payer@example.org').Id),
				'A cancelled term is done'
			);
			Membership_Term__c free = term('Current', 'free.payer@example.org');
			Membership_Level__c level = [
				SELECT Id
				FROM Membership_Level__c
				WHERE Id IN (SELECT Level__c FROM Membership_Term__c WHERE Id = :free.Id)
				WITH USER_MODE
			];
			update as user new Membership_Level__c(Id = level.Id, Dues__c = 0);
			Assert.areEqual(
				BarnHelp.text('Memberships', 'Memberships_Error_NoDues'),
				refusal(free.Id),
				'A level with no dues has nothing to pay'
			);
		}
	}

	@IsTest
	static void aPendingTermPaysItsOwnDuesNotTheLevels() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			FakePayments payments = new FakePayments(true);
			MembershipPayments.apiOverride = payments;
			MembershipPayments.emailSender = new RecordingEmailSender();
			Membership_Term__c pending = term('Pending', 'payer@example.org');
			update as user new Membership_Term__c(Id = pending.Id, Dues__c = 75);

			Test.startTest();
			MembershipPayments.request(pending.Id);
			Test.stopTest();

			Assert.areEqual(1, payments.checkouts.size(), 'one checkout');
			Assert.areEqual(75, (Decimal) payments.checkouts[0].get('amount'), 'its own dues');
		}
	}

	@IsTest
	static void aCheckoutPaymentsCannotStartLeavesNoLinkAndSendsNothing() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipPayments.apiOverride = new FailingPayments(false);
			RecordingEmailSender sender = new RecordingEmailSender();
			MembershipPayments.emailSender = sender;
			Membership_Term__c current = term('Current', 'payer@example.org');

			Test.startTest();
			MembershipPayments.request(current.Id);
			Test.stopTest();

			Assert.isNull(
				[SELECT Pay_Link__c FROM Membership_Term__c WHERE Id = :current.Id WITH USER_MODE]
				.Pay_Link__c,
				'No link was stored'
			);
			Assert.isTrue(sender.received.isEmpty(), 'Nothing was emailed');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'MembershipPayments'
					WITH SYSTEM_MODE
				],
				'The failure is logged against the term'
			);
		}
	}

	@IsTest
	static void aLinkJobForATermThatIsGoneLogsAWarning() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipPayments.apiOverride = new FakePayments(true);
			RecordingEmailSender sender = new RecordingEmailSender();
			MembershipPayments.emailSender = sender;
			Id gone = Id.valueOf(
				Membership_Term__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
					.getKeyPrefix() + '000000000002'
			);

			Test.startTest();
			new MembershipPayments(gone).execute(null);
			Test.stopTest();

			Assert.isTrue(sender.received.isEmpty(), 'Nothing was emailed');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'MembershipPayments' AND Severity__c = 'Warning'
					WITH SYSTEM_MODE
				],
				'The link was not sent, and the log says so'
			);
		}
	}

	@IsTest
	static void aPaymentRenewsOnceAndARefundCancels() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Membership_Term__c current = term('Current', 'payer@example.org');
			Map<String, Object> payment = new Map<String, Object>{
				'paymentId' => 'pay-1',
				'sourceRecordId' => String.valueOf(current.Id),
				'status' => 'Paid',
				'amount' => 50,
				'paidAt' => Datetime.now()
			};
			MembershipPaymentListener listener = new MembershipPaymentListener();
			listener.call('paymentChanged', payment);
			listener.call('paymentChanged', payment);
			List<Membership_Term__c> paid = [
				SELECT Id, Status__c, Source__c
				FROM Membership_Term__c
				WHERE Payment_Id__c = 'pay-1'
				WITH USER_MODE
			];
			Assert.areEqual(1, paid.size(), 'renewed once');
			Assert.areEqual('Online Payment', paid[0].Source__c, 'paid online');
			payment.put('status', 'Refunded');
			listener.call('paymentChanged', payment);
			Assert.areEqual(
				'Cancelled',
				[SELECT Status__c FROM Membership_Term__c WHERE Id = :paid[0].Id WITH USER_MODE]
				.Status__c,
				'a refund cancels the term it paid'
			);
			Assert.isNull(listener.call('somethingElse', payment), 'other calls are ignored');
		}
	}

	@IsTest
	static void aPaymentActivatesAPendingTerm() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Membership_Term__c pending = term('Pending', 'payer@example.org');
			new MembershipPaymentListener()
				.call(
					'paymentChanged',
					new Map<String, Object>{
						'paymentId' => 'pay-2',
						'sourceRecordId' => String.valueOf(pending.Id),
						'status' => 'Paid',
						'amount' => 50,
						'paidAt' => Datetime.newInstance(2026, 4, 1, 12, 0, 0)
					}
				);
			Membership_Term__c after = [
				SELECT Status__c, Start_Date__c, End_Date__c, Payment_Id__c
				FROM Membership_Term__c
				WHERE Id = :pending.Id
				WITH USER_MODE
			];
			Assert.areEqual('Current', after.Status__c, 'the pending term is now current');
			Assert.areEqual(Date.newInstance(2026, 4, 1), after.Start_Date__c, 'from the payment');
			Assert.areEqual(Date.newInstance(2027, 3, 31), after.End_Date__c, 'for a year');
			Assert.areEqual('pay-2', after.Payment_Id__c, 'linked to the payment');
		}
	}

	@IsTest
	static void thePortalPaysOnlyThePersonsOwnTerm() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipPayments.apiOverride = new FakePayments(true);
			Membership_Term__c current = term('Current', 'payer@example.org');
			MembershipsPortalExtension portal = new MembershipsPortalExtension();
			Assert.isTrue(
				portal.actionNames().contains(MembershipsPortalExtension.PAY_DUES),
				'offers Pay Dues'
			);
			Test.startTest();
			Assert.areEqual(
				BarnHelp.text('Memberships', 'Memberships_Portal_LinkSent'),
				portal.run(MembershipsPortalExtension.PAY_DUES, current.Contact__c, current.Id),
				'the link is on its way'
			);
			Test.stopTest();
			Contact stranger = new Contact(LastName = 'Zzmem Stranger');
			insert as user stranger;
			try {
				portal.run(MembershipsPortalExtension.PAY_DUES, stranger.Id, current.Id);
				Assert.fail('paid someone else\'s term');
			} catch (MembershipService.MembershipException e) {
				Assert.areEqual(
					BarnHelp.text('Memberships', 'Memberships_Error_NotFound'),
					e.getMessage(),
					'not theirs'
				);
			}
		}
	}
}
