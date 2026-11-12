/**
 * An appeal's online donation page (G-34; ADR-0211 online donation pages, decisions 1 to 5;
 * R-AP5): only an active appeal with Donation Page on is published, with no gift or total; the
 * checkout is asked of Payments with the answer `amount`; the gift is right whichever comes
 * first, form processing or the payment report, and neither writes it twice.
 */
@IsTest(testFor='ApexClass:GivingDonationPage, ApexClass:GivingDonations')
private class GivingDonationsTest {
	private static final String FORM_KEY = 'a0B000000000001AAA';

	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.ensureDefaultFund();
		}
	}

	private static User admin() {
		return TestUsers.adminWith('Giving_Admin');
	}

	/** Stands in for BarnCRM Payments: one payment whose status the test sets. */
	private class FakePayments implements Callable {
		String status = 'Pending';
		Map<String, Object> asked;

		public Object call(String action, Map<String, Object> args) {
			switch on action {
				when 'isReady' {
					return true;
				}
				when 'startCheckout' {
					asked = args;
					return new Map<String, Object>{
						'paymentId' => 'pay-1',
						'checkoutUrl' => 'https://checkout.example.com/1'
					};
				}
				when else {
					return new Map<String, Object>{
						'paymentId' => 'pay-1',
						'status' => status,
						'amount' => 40.00,
						'processor' => 'Stripe',
						'paidAt' => Datetime.newInstance(2026, 11, 2, 12, 0, 0)
					};
				}
			}
		}
	}

	private static Appeal__c appeal(Boolean published) {
		Appeal__c record = GivingTestDataFactory.buildAppeal('Winter Coats');
		record.Donation_Page__c = published;
		record.Donation_Form_Key__c = FORM_KEY;
		record.Goal__c = 5000;
		insert as user record;
		return record;
	}

	private static FormSubmissionReceipt receipt(Id appealId, Id personId) {
		FormSubmissionReceipt given = new FormSubmissionReceipt();
		given.contextRecordId = appealId;
		given.personId = personId;
		given.answers = new Map<String, Object>{ 'amount' => 40, '_payment' => 'pay-1' };
		return given;
	}

	private static Contact donor() {
		Contact person = new Contact(FirstName = 'Dana', LastName = 'Zzdonor');
		insert as user person;
		return person;
	}

	private static Gift__c gift() {
		return [
			SELECT Status__c, Amount__c, Gift_Date__c, Appeal__c, Type__c
			FROM Gift__c
			WHERE Payment_Reference__c = 'pay-1'
			WITH USER_MODE
		];
	}

	@IsTest
	static void onlyAPublishedAppealHasAPageAndItShowsNoGifts() {
		System.runAs(admin()) {
			GivingDonations.paymentsForTest = new FakePayments();
			GivingDonationPage pages = new GivingDonationPage();
			Appeal__c open = appeal(true);
			Appeal__c hidden = appeal(false);

			Map<String, Object> page = pages.page(open.Id);

			Assert.areEqual('Winter Coats', page.get('title'));
			Assert.areEqual('Open', page.get('registration'), 'Payments is ready');
			Assert.areEqual(Id.valueOf(FORM_KEY), page.get('formId'));
			Assert.isFalse(JSON.serialize(page).contains('Gift'), 'No gift or total');
			Assert.isNull(pages.page(hidden.Id), 'Donation Page off');
			Assert.areEqual(Id.valueOf(FORM_KEY), pages.formFor(open.Id));
			Assert.isNull(pages.formFor(hidden.Id));
			Assert.isFalse(pages.signedClaim(open.Id));
			Assert.isTrue(pages.handles(Appeal__c.SObjectType));
			Assert.isNull(pages.listPage(), 'No public list');
		}
	}

	@IsTest
	static void withoutPaymentsThePageSaysGivingIsNotOpen() {
		System.runAs(admin()) {
			Map<String, Object> page = new GivingDonationPage().page(appeal(true).Id);

			Assert.areEqual('None', page.get('registration'), 'No Payments in this test');
			Assert.isNull(page.get('formId'));
			Assert.isNotNull(page.get('message'));
		}
	}

	@IsTest
	static void theCheckoutIsAskedForTheAnswerAmountWithThisClassListening() {
		System.runAs(admin()) {
			FakePayments payments = new FakePayments();
			GivingDonations.paymentsForTest = payments;
			Appeal__c open = appeal(true);

			Map<String, Object> started = new GivingDonationPage()
				.startCheckout(
					open.Id,
					new Map<String, Object>{
						'amount' => 40,
						'email' => 'dana@example.org',
						'firstName' => 'Dana'
					},
					'https://give.example.org/FormsPublic?record=' + open.Id
				);

			Assert.areEqual('https://checkout.example.com/1', started.get('checkoutUrl'));
			Assert.areEqual(40, payments.asked.get('amount'));
			Assert.areEqual('Winter Coats', payments.asked.get('description'));
			Assert.areEqual('Dana', payments.asked.get('payerName'));
			Assert.areEqual(GivingDonations.LISTENER, payments.asked.get('listener'));
			Assert.isTrue(
				String.valueOf(payments.asked.get('successUrl')).endsWith('payment=done')
			);
			Assert.isNull(
				new GivingDonationPage().startCheckout(appeal(false).Id, null, null),
				'An unpublished appeal takes no payment'
			);
		}
	}

	@IsTest
	static void processingFirstWritesAPendingGiftThatThePaymentSettles() {
		System.runAs(admin()) {
			FakePayments payments = new FakePayments();
			GivingDonations.paymentsForTest = payments;
			Appeal__c open = appeal(true);
			Contact person = donor();

			new GivingDonationPage().received(receipt(open.Id, person.Id));
			new GivingDonationPage().received(receipt(open.Id, person.Id));
			Gift__c pending = gift();
			new GivingDonations()
				.call(
					'paymentChanged',
					new Map<String, Object>{
						'paymentId' => 'pay-1',
						'status' => 'Paid',
						'paidAt' => Datetime.newInstance(2026, 11, 2, 12, 0, 0)
					}
				);
			Gift__c paid = gift();
			new GivingDonations()
				.call(
					'paymentChanged',
					new Map<String, Object>{ 'paymentId' => 'pay-1', 'status' => 'Refunded' }
				);

			Assert.areEqual('Pending', pending.Status__c, 'Written once, Pending');
			Assert.areEqual(open.Id, pending.Appeal__c);
			Assert.areEqual(40.00, pending.Amount__c);
			Assert.areEqual('Card', pending.Type__c);
			Assert.areEqual('Received', paid.Status__c);
			Assert.areEqual(Date.newInstance(2026, 11, 2), paid.Gift_Date__c, 'The paid date');
			Assert.areEqual('Refunded', gift().Status__c);
		}
	}

	@IsTest
	static void thePaymentFirstLeavesTheGiftToProcessingWithItsStatus() {
		System.runAs(admin()) {
			FakePayments payments = new FakePayments();
			payments.status = 'Paid';
			GivingDonations.paymentsForTest = payments;
			Appeal__c open = appeal(true);

			Object answered = new GivingDonations()
				.call(
					'paymentChanged',
					new Map<String, Object>{ 'paymentId' => 'pay-1', 'status' => 'Paid' }
				);
			Integer before = [SELECT COUNT() FROM Gift__c WITH USER_MODE];
			new GivingDonationPage().received(receipt(open.Id, donor().Id));

			Assert.isNull(answered);
			Assert.areEqual(0, before, 'No gift until processing');
			Assert.areEqual('Received', gift().Status__c, 'Written as Received');
		}
	}

	@IsTest
	static void aSubmissionWithNoPaymentOrNoDonorWritesNoGift() {
		System.runAs(admin()) {
			GivingDonations.paymentsForTest = new FakePayments();
			Appeal__c open = appeal(true);
			FormSubmissionReceipt noPayment = receipt(open.Id, donor().Id);
			noPayment.answers.remove('_payment');

			new GivingDonationPage().received(noPayment);
			new GivingDonationPage().received(receipt(open.Id, null));

			Assert.areEqual(0, [SELECT COUNT() FROM Gift__c WITH USER_MODE]);
		}
	}
}
