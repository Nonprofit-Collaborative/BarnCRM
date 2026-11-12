/**
 * Maria's client pays an invoice online (PM-10, R-PM22): Send Payment Link starts a checkout for
 * the balance through BarnCRM Payments by name and emails it, and what the processor reports
 * marks the invoice Paid, sets it back to Sent on a refund, or changes nothing. Payments is a
 * stand-in here, as it may not be installed beside Projects; the listener is called directly.
 */
@IsTest(
	testFor='ApexClass:ProjectInvoicePayments, ApexClass:ProjectInvoicePaymentListener, ApexClass:ProjectsSettings'
)
private class ProjectInvoicePaymentsTest {
	private static final String LINK = 'https://checkout.stripe.com/c/pay/cs_test_1';

	/** BarnCRM Payments' seam as a test sees it. */
	private class FakePayments implements Callable {
		String refuseWith;
		List<Map<String, Object>> started = new List<Map<String, Object>>();

		public Object call(String action, Map<String, Object> args) {
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
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static FakePayments online(Boolean turnedOn) {
		OrgSettingsSystemWriter.save(
			Projects_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Projects_Settings__c.Billing_Enabled__c => true,
				Projects_Settings__c.Online_Payments_Enabled__c => turnedOn
			}
		);
		SettingsService.clearCaches();
		FakePayments fake = new FakePayments();
		ProjectInvoicePayments.apiForTest = fake;
		ProjectInvoicePayments.emailSender = new RecordingEmailSender();
		return fake;
	}

	/** A Sent invoice of 300 billed to a contact with an email. */
	private static Project_Invoice__c sentInvoice() {
		Contact payer = new Contact(
			FirstName = 'Pat',
			LastName = 'Client',
			Email = 'pat@example.org'
		);
		Database.DMLOptions options = new Database.DMLOptions();
		options.DuplicateRuleHeader.allowSave = true;
		Database.insert(payer, options, AccessLevel.USER_MODE);
		Project__c project = ProjectsTestData.project('Active', 10);
		insert new Time_Entry__c(
			Project__c = project.Id,
			User__c = UserInfo.getUserId(),
			Date__c = Date.today(),
			Hours__c = 3,
			Billable__c = true
		);
		Id invoiceId = ProjectBilling.build(project.Id, Date.today(), Date.today());
		update new Project_Invoice__c(Id = invoiceId, Contact__c = payer.Id);
		ProjectBilling.send(invoiceId);
		return reload(invoiceId);
	}

	private static Project_Invoice__c reload(Id invoiceId) {
		return [
			SELECT
				Id,
				Status__c,
				Total__c,
				Amount_Paid__c,
				Paid_Date__c,
				Payment_Key__c,
				Payment_Link__c
			FROM Project_Invoice__c
			WHERE Id = :invoiceId
		];
	}

	private static Map<String, Object> report(
		Id invoiceId,
		String status,
		Decimal amount,
		Decimal refunded
	) {
		return new Map<String, Object>{
			'paymentId' => UserInfo.getOrganizationId(),
			'sourceRecordId' => invoiceId,
			'status' => status,
			'amount' => amount,
			'amountRefunded' => refunded,
			'paidAt' => Datetime.newInstance(2026, 11, 3, 12, 0, 0)
		};
	}

	@IsTest
	static void sendPaymentLinkStartsACheckoutForTheBalanceAndEmailsIt() {
		System.runAs(ProjectsTestData.admin()) {
			FakePayments fake = online(true);
			Project_Invoice__c invoice = sentInvoice();

			Test.startTest();
			String message = ProjectBillingController.sendPaymentLink(invoice.Id);
			Test.stopTest();

			Assert.areEqual(1, fake.started.size(), 'One checkout');
			Map<String, Object> args = fake.started[0];
			Assert.areEqual(300, (Decimal) args.get('amount'), 'The balance due');
			Assert.areEqual('ProjectInvoicePaymentListener', args.get('listener'), 'Told by name');
			Assert.areEqual(invoice.Id, args.get('sourceRecordId'), 'For the invoice');
			Assert.areEqual(
				Url.getOrgDomainUrl().toExternalForm(),
				args.get('successUrl'),
				'Returns to My Domain by default'
			);
			Project_Invoice__c after = reload(invoice.Id);
			Assert.areEqual(UserInfo.getOrganizationId(), after.Payment_Key__c, 'Key stored');
			Assert.areEqual(LINK, after.Payment_Link__c, 'Link stored');
			Assert.isTrue(message.contains('pat@example.org'), 'Emailed to the contact');
			RecordingEmailSender sender = (RecordingEmailSender) ProjectInvoicePayments.emailSender;
			Assert.isTrue(
				sender.received[0].getPlainTextBody().contains(LINK),
				'The link is in it'
			);
		}
	}

	@IsTest
	static void reportsMarkPaidRefundBackToSentAndIgnoreOthers() {
		System.runAs(ProjectsTestData.admin()) {
			online(true);
			Project_Invoice__c invoice = sentInvoice();
			ProjectInvoicePayments.sendLink(invoice.Id);
			ProjectInvoicePaymentListener listener = new ProjectInvoicePaymentListener();

			Test.startTest();
			listener.call('paymentChanged', report(invoice.Id, 'Failed', 300, 0));
			Project_Invoice__c failed = reload(invoice.Id);
			Object handled = listener.call(
				'paymentsChanged',
				new Map<String, Object>{
					'payments' => new List<Map<String, Object>>{
						report(invoice.Id, 'Paid', 300, 0)
					}
				}
			);
			Project_Invoice__c paid = reload(invoice.Id);
			listener.call('paymentChanged', report(invoice.Id, 'Paid', 300, 0));
			Project_Invoice__c twice = reload(invoice.Id);
			listener.call('paymentChanged', report(invoice.Id, 'Paid', 300, 100));
			Project_Invoice__c partly = reload(invoice.Id);
			Test.stopTest();

			Assert.areEqual('Sent', failed.Status__c, 'Failed changes nothing');
			Assert.isTrue(handled == true, 'The bulk call is handled');
			Assert.areEqual('Paid', paid.Status__c, 'Paid in full');
			Assert.areEqual(300, paid.Amount_Paid__c, 'Amount Paid');
			Assert.areEqual(Date.newInstance(2026, 11, 3), paid.Paid_Date__c, 'The payment date');
			Assert.areEqual(300, twice.Amount_Paid__c, 'The same report twice adds nothing');
			Assert.areEqual('Sent', partly.Status__c, 'A refund sets it back to Sent');
			Assert.areEqual(200, partly.Amount_Paid__c, 'Less the refund');
			Assert.isNull(partly.Paid_Date__c, 'No longer paid');
		}
	}

	@IsTest
	static void anOlderPaymentOrAVoidInvoiceIsNeverChanged() {
		System.runAs(ProjectsTestData.admin()) {
			online(true);
			Project_Invoice__c invoice = sentInvoice();
			ProjectInvoicePayments.sendLink(invoice.Id);
			Map<String, Object> older = report(invoice.Id, 'Paid', 300, 0);
			older.put('paymentId', UserInfo.getUserId());

			Test.startTest();
			ProjectInvoicePayments.apply(new List<Map<String, Object>>{ older });
			Project_Invoice__c afterOlder = reload(invoice.Id);
			ProjectBilling.voidInvoice(invoice.Id);
			ProjectInvoicePayments.apply(
				new List<Map<String, Object>>{ report(invoice.Id, 'Paid', 300, 0) }
			);
			Test.stopTest();

			Assert.areEqual('Sent', afterOlder.Status__c, 'Not the current key');
			Assert.areEqual('Void', reload(invoice.Id).Status__c, 'Void is never changed');
		}
	}

	@IsTest
	static void noLinkWhenOffWithoutPaymentsOrWhenRefused() {
		System.runAs(ProjectsTestData.admin()) {
			FakePayments fake = online(false);
			Project_Invoice__c invoice = sentInvoice();
			Assert.isFalse(
				(Boolean) ProjectBillingController.getInvoiceActions(invoice.Id).get('online'),
				'Hidden when the setting is off'
			);
			Test.startTest();
			try {
				ProjectInvoicePayments.sendLink(invoice.Id);
				Assert.fail('Off');
			} catch (Projects.ProjectsException expected) {
				Assert.isTrue(expected.getMessage().contains('Payments'), 'Says how');
			}
			online(true).refuseWith = 'Enter your Stripe keys first.';
			try {
				ProjectInvoicePayments.sendLink(invoice.Id);
				Assert.fail('Refused by Payments');
			} catch (Projects.ProjectsException expected) {
				Assert.areEqual('Enter your Stripe keys first.', expected.getMessage(), 'As said');
			}
			Test.stopTest();
			Assert.isTrue(fake.started.isEmpty(), 'No checkout while off');
			Assert.isNull(reload(invoice.Id).Payment_Key__c, 'Nothing stored');
		}
	}
}
