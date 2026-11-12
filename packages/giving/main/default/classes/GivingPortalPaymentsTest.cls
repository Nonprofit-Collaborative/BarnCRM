/**
 * The donor portal's Pay Online (PAY-03; ADR-NEXT donor portal payments, decisions 2 to 4): only
 * the person's own active commitment with something due queues a checkout; the job asks Payments
 * for the next payment's amount with Giving listening and emails the link; the Paid report writes
 * one Received gift on the commitment, and a second report writes nothing more.
 */
@IsTest(testFor='ApexClass:GivingPortalPayments, ApexClass:GivingDonations')
private class GivingPortalPaymentsTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.ensureDefaultFund();
		}
	}

	private static User admin() {
		return TestUsers.adminWith('Giving_Admin');
	}

	/** Stands in for BarnCRM Payments. */
	private class FakePayments implements Callable {
		Map<String, Object> asked;

		public Object call(String action, Map<String, Object> args) {
			if (action == 'isReady') {
				return true;
			}
			asked = args;
			return new Map<String, Object>{
				'paymentId' => 'pay-9',
				'checkoutUrl' => 'https://checkout.example.com/9'
			};
		}
	}

	private static Contact donor(String email) {
		Contact person = new Contact(FirstName = 'Pat', LastName = 'Zzpledge', Email = email);
		insert as user person;
		return person;
	}

	private static Commitment__c pledge(Id donorId) {
		Commitment__c record = new Commitment__c(
			Type__c = 'Pledge',
			Status__c = 'Active',
			Donor_Contact__c = donorId,
			Amount__c = 100,
			Frequency__c = 'Monthly',
			Start_Date__c = Date.today(),
			End_Date__c = Date.today().addMonths(3).addDays(-1),
			Expected_Total__c = 300,
			Installments_Planned__c = 3
		);
		insert as user record;
		return record;
	}

	@IsTest
	static void payOnlineEmailsALinkForTheNextPaymentDue() {
		System.runAs(admin()) {
			FakePayments payments = new FakePayments();
			GivingDonations.paymentsForTest = payments;
			RecordingEmailSender sender = new RecordingEmailSender();
			GivingPortalPayments.emailSender = sender;
			Contact person = donor('pat.zzpledge@example.org');
			Commitment__c record = pledge(person.Id);

			Test.startTest();
			String message = new GivingPortalPayments()
				.run(GivingPortalPayments.PAY_ONLINE, person.Id, record.Id);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Giving', 'Giving_PayOnline_Sent'), message);
			Assert.areEqual(100, (Decimal) payments.asked.get('amount'), 'The first payment');
			Assert.areEqual(record.Id, payments.asked.get('sourceRecordId'));
			Assert.areEqual(GivingDonations.LISTENER, payments.asked.get('listener'));
			Assert.areEqual(1, sender.received.size(), 'One email');
			Assert.isTrue(
				sender.received[0].getPlainTextBody().contains('https://checkout.example.com/9'),
				'With the checkout link'
			);
			Assert.isTrue(
				new GivingPortalPayments().actionNames().contains(GivingPortalPayments.PAY_ONLINE)
			);
		}
	}

	@IsTest
	static void someoneElsesOrAnInactiveOrEmaillessCommitmentIsRefused() {
		System.runAs(admin()) {
			GivingDonations.paymentsForTest = new FakePayments();
			Contact person = donor('pat.zzpledge@example.org');
			Contact other = donor(null);
			Commitment__c record = pledge(person.Id);
			Commitment__c noEmail = pledge(other.Id);
			List<String> refused = new List<String>();
			List<List<Id>> attempts = new List<List<Id>>{
				new List<Id>{ other.Id, record.Id },
				new List<Id>{ other.Id, noEmail.Id }
			};
			for (List<Id> attempt : attempts) {
				try {
					new GivingPortalPayments()
						.run(GivingPortalPayments.PAY_ONLINE, attempt[0], attempt[1]);
				} catch (GivingPortalPayments.PortalPaymentException expected) {
					refused.add(expected.getMessage());
				}
			}

			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Giving', 'Giving_PayOnline_NotFound'),
					BarnHelp.text('Giving', 'Giving_PayOnline_NoEmail')
				},
				refused
			);
			Assert.areEqual(0, Limits.getQueueableJobs(), 'Nothing queued');
		}
	}

	@IsTest
	static void thePaidReportWritesOneReceivedGiftOnTheCommitment() {
		System.runAs(admin()) {
			Contact person = donor('pat.zzpledge@example.org');
			Commitment__c record = pledge(person.Id);
			Map<String, Object> paid = new Map<String, Object>{
				'paymentId' => 'pay-9',
				'status' => 'Paid',
				'sourceRecordId' => record.Id,
				'personId' => person.Id,
				'amount' => 100.00,
				'processor' => 'PayPal',
				'paidAt' => Datetime.newInstance(2026, 11, 3, 12, 0, 0)
			};

			new GivingDonations().call('paymentChanged', paid);
			new GivingDonations().call('paymentChanged', paid);

			List<Gift__c> gifts = [
				SELECT Status__c, Amount__c, Commitment__c, Donor_Contact__c, Type__c, Gift_Date__c
				FROM Gift__c
				WHERE Payment_Reference__c = 'pay-9'
				WITH USER_MODE
			];
			Assert.areEqual(1, gifts.size(), 'Written once');
			Assert.areEqual('Received', gifts[0].Status__c);
			Assert.areEqual(record.Id, gifts[0].Commitment__c);
			Assert.areEqual(person.Id, gifts[0].Donor_Contact__c);
			Assert.areEqual('Other', gifts[0].Type__c, 'PayPal');
			Assert.areEqual(Date.newInstance(2026, 11, 3), gifts[0].Gift_Date__c);
		}
	}
}
