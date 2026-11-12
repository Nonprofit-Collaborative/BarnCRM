/**
 * Payments subscriptions (PAY-04, R-PAY6; ADR-NEXT payments subscriptions): a checkout with an
 * interval is a subscription only with the setting on; Stripe and PayPal renewals become new
 * Paid payments copied from the first, once each; failed charges, card updates and cancellations
 * change no payment and reach the listener once per run; Update Card opens the processor's own
 * page, and a completed Stripe setup session makes the new card the subscription's default.
 */
@IsTest(
	testFor='ApexClass:PaymentService, ApexClass:PaymentsApi, ApexClass:PaymentStripe, ApexClass:PaymentPayPal'
)
private class PaymentSubscriptionTest {
	private static final String LISTENER = 'PaymentSubscriptionTest.Listener';
	private static List<String> told = new List<String>();
	private static List<Map<String, Object>> news = new List<Map<String, Object>>();

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(PaymentsTestData.ADMIN);
	}

	/** A consumer's listener with both bulk forms: keeps what it is told. */
	public class Listener implements Callable {
		public Object call(String action, Map<String, Object> args) {
			if (action == 'paymentsChanged') {
				for (Object one : (List<Object>) args.get('payments')) {
					Map<String, Object> payment = (Map<String, Object>) one;
					told.add(payment.get('previousStatus') + '>' + payment.get('status'));
				}
			} else if (action == 'subscriptionsChanged') {
				for (Object one : (List<Object>) args.get('changes')) {
					news.add((Map<String, Object>) one);
				}
			}
			return true;
		}
	}

	private static void recurringOn() {
		Payments_Settings__c settings = Payments_Settings__c.getOrgDefaults();
		settings.Recurring_Payments__c = true;
		update settings;
	}

	private static Map<String, Object> checkout() {
		return new Map<String, Object>{
			'amount' => 20,
			'description' => 'Monthly gift',
			'successUrl' => 'https://example.org/thanks',
			'cancelUrl' => 'https://example.org/sorry',
			'interval' => 'month',
			'intervalCount' => 3
		};
	}

	/** The subscription's first payment, Pending, with the test listener. */
	private static Payment__c first(String processor, String subscriptionId) {
		Payment__c payment = PaymentsTestData.payment(processor, PaymentService.PENDING, 20);
		payment.Listener__c = LISTENER;
		payment.Source_Record_Id__c = '001000000000001AAA';
		payment.Subscription_Id__c = subscriptionId;
		update payment;
		return payment;
	}

	private static void stripe(String id, String type, Map<String, Object> obj) {
		PaymentsTestData.event(
			PaymentService.STRIPE,
			'stripe:' + id,
			PaymentsTestData.stripeEvent(id, type, obj),
			null
		);
	}

	private static Map<String, Object> invoice(String id, String ref, Integer cents) {
		return new Map<String, Object>{
			'id' => id,
			'customer' => 'cus_1',
			'currency' => 'usd',
			'amount_paid' => cents,
			// The newer API's shape: no payment intent, the subscription under parent.
			'parent' => new Map<String, Object>{
				'subscription_details' => new Map<String, Object>{
					'subscription' => 'sub_1',
					'metadata' => new Map<String, Object>{ 'barncrm_reference' => ref }
				}
			}
		};
	}

	private static List<Payment__c> payments() {
		return [
			SELECT Status__c, Amount__c, Processor_Payment_Id__c, Subscription_Id__c, Listener__c
			FROM Payment__c
			WITH SYSTEM_MODE
			ORDER BY CreatedDate ASC, Id ASC
		];
	}

	private static List<String> events() {
		List<String> found = new List<String>();
		for (Map<String, Object> change : news) {
			found.add(String.valueOf(change.get('event')));
		}
		return found;
	}

	@IsTest
	static void withTheSettingOffAnIntervalIsIgnored() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer('stripe.com', 200, '{"id":"cs_1","url":"https://checkout.stripe.com/c/1"}');
			PaymentsApi api = new PaymentsApi();

			Test.startTest();
			api.call('startCheckout', checkout());
			Test.stopTest();

			String sent = mock.last('stripe.com').getBody();
			Assert.isTrue(sent.contains('mode=payment'), 'One payment, as before: ' + sent);
			Assert.isFalse(sent.contains('recurring'), sent);
			Assert.isFalse(
				(Boolean) api.call('isReady', new Map<String, Object>{ 'recurring' => true }),
				'Not ready for recurring while off'
			);
		}
	}

	@IsTest
	static void withTheSettingOnAnIntervalStartsAStripeSubscription() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			recurringOn();
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer('stripe.com', 200, '{"id":"cs_1","url":"https://checkout.stripe.com/c/1"}');
			PaymentsApi api = new PaymentsApi();

			Test.startTest();
			api.call('startCheckout', checkout());
			Test.stopTest();

			String sent = mock.last('stripe.com').getBody();
			Assert.isTrue(
				(Boolean) api.call('isReady', new Map<String, Object>{ 'recurring' => true }),
				'Ready once on'
			);
			Assert.isTrue(sent.contains('mode=subscription'), sent);
			Assert.isTrue(sent.contains('%5Brecurring%5D%5Binterval%5D=month'), sent);
			Assert.isTrue(sent.contains('%5Brecurring%5D%5Binterval_count%5D=3'), sent);
			Assert.isTrue(sent.contains('subscription_data%5Bmetadata%5D'), sent);
			Assert.isFalse(
				sent.contains('payment_intent_data'),
				'Not allowed in subscription mode'
			);
		}
	}

	@IsTest
	static void aPayPalSubscriptionIsAProductAPlanAndAnApproveLink() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			recurringOn();
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer('oauth2/token', 200, '{"access_token":"tok"}')
				.answer('catalogs/products', 201, '{"id":"PROD-1"}')
				.answer('billing/plans', 201, '{"id":"P-1"}')
				.answer(
					'billing/subscriptions',
					201,
					'{"id":"I-1","links":[{"rel":"approve","href":"https://www.sandbox.paypal.com/webapps/billing/subscriptions?ba_token=BA-1"}]}'
				);

			Test.startTest();
			Payment__c payment = PaymentService.startCheckout(checkout());
			Test.stopTest();

			Assert.areEqual('I-1', payment.Subscription_Id__c, 'The subscription');
			Assert.areEqual('I-1', payment.Checkout_Id__c, 'Matched on its events too');
			Assert.isTrue(payment.Checkout_Url__c.contains('BA-1'), 'Its approve link');
			String plan = mock.last('billing/plans').getBody();
			Assert.isTrue(plan.contains('"interval_unit":"MONTH"'), plan);
			Assert.isTrue(plan.contains('"product_id":"PROD-1"'), plan);
			String subscription = mock.last('billing/subscriptions').getBody();
			Assert.isTrue(subscription.contains('"custom_id":"' + payment.Reference__c + '"'));
			Assert.isTrue(subscription.contains('"plan_id":"P-1"'), subscription);
		}
	}

	@IsTest
	static void stripeRenewalsFailuresAndCancellationReachTheListenerOnce() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			Payment__c payment = first(PaymentService.STRIPE, null);
			String ref = payment.Reference__c;
			stripe(
				'evt_1',
				'checkout.session.completed',
				new Map<String, Object>{
					'id' => payment.Checkout_Id__c,
					'client_reference_id' => ref,
					'payment_status' => 'paid',
					'mode' => 'subscription',
					'subscription' => 'sub_1',
					'customer' => 'cus_1'
				}
			);
			Map<String, Object> firstInvoice = invoice('in_1', ref, 2000);
			firstInvoice.put('payment_intent', 'pi_1');
			stripe('evt_2', 'invoice.paid', firstInvoice);
			stripe('evt_3', 'invoice.paid', invoice('in_2', ref, 2500));
			stripe('evt_4', 'invoice.payment_failed', invoice('in_3', ref, 0));
			stripe(
				'evt_5',
				'customer.subscription.deleted',
				new Map<String, Object>{
					'id' => 'sub_1',
					'customer' => 'cus_1',
					'metadata' => new Map<String, Object>{ 'barncrm_reference' => ref }
				}
			);
			stripe('evt_6', 'invoice.paid', invoice('in_2', ref, 2500));
			stripe('evt_7', 'invoice.paid', new Map<String, Object>{ 'id' => 'in_9' });

			Test.startTest();
			new PaymentEventProcessor.Run().execute(null);
			Test.stopTest();

			List<Payment__c> all = payments();
			Assert.areEqual(2, all.size(), 'The first payment and one renewal: ' + all);
			Assert.areEqual(PaymentService.PAID, all[0].Status__c);
			Assert.areEqual('sub_1', all[0].Subscription_Id__c, 'Gained its subscription');
			Assert.areEqual('pi_1', all[0].Processor_Payment_Id__c, 'Took the first charge');
			Assert.areEqual(PaymentService.PAID, all[1].Status__c, 'The renewal is Paid');
			Assert.areEqual(25.00, all[1].Amount__c, 'At the charged amount');
			Assert.areEqual('in_2', all[1].Processor_Payment_Id__c, 'The invoice stands in');
			Assert.areEqual(LISTENER, all[1].Listener__c, 'Copied from the first');
			Assert.areEqual(
				new List<String>{ 'Pending>Paid', 'Pending>Paid' },
				told,
				'Each payment told once'
			);
			Assert.areEqual(
				new List<String>{
					PaymentService.CHARGE_SUCCEEDED,
					PaymentService.CHARGE_SUCCEEDED,
					PaymentService.CHARGE_FAILED,
					PaymentService.SUBSCRIPTION_CANCELLED
				},
				events(),
				'Every change once, the resent invoice not again'
			);
			Assert.areEqual('cus_1', news[0].get('customerId'));
			Assert.areEqual('stripe:evt_2', news[0].get('eventKey'));
			Assert.areEqual('001000000000001AAA', news[0].get('sourceRecordId'));
			Assert.areEqual(
				'Ignored',
				[
					SELECT Status__c
					FROM Payment_Event__c
					WHERE Event_Key__c = 'stripe:evt_7'
					WITH SYSTEM_MODE
				]
				.Status__c,
				'An invoice with no subscription is not used'
			);
		}
	}

	@IsTest
	static void aCompletedSetupSessionMakesTheNewCardTheSubscriptionsDefault() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			first(PaymentService.STRIPE, 'sub_1');
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer(
					'setup_intents/seti_1',
					200,
					'{"id":"seti_1","payment_method":{"id":"pm_1","card":{"exp_month":12,"exp_year":2034}}}'
				)
				.answer('subscriptions/sub_1', 200, '{"id":"sub_1"}');
			stripe(
				'evt_8',
				'checkout.session.completed',
				new Map<String, Object>{
					'id' => 'cs_setup',
					'mode' => 'setup',
					'payment_status' => 'no_payment_required',
					'setup_intent' => 'seti_1',
					'customer' => 'cus_1',
					'metadata' => new Map<String, Object>{ 'barncrm_subscription' => 'sub_1' }
				}
			);

			Test.startTest();
			new PaymentEventProcessor.Run().execute(null);
			Test.stopTest();

			Assert.isTrue(
				mock.last('subscriptions/sub_1').getBody().contains('default_payment_method=pm_1'),
				'The new card is the default'
			);
			Assert.areEqual(new List<String>{ PaymentService.CARD_UPDATED }, events());
			Assert.areEqual(Date.newInstance(2034, 12, 31), news[0].get('cardExpires'));
			Assert.areEqual(PaymentService.PENDING, payments()[0].Status__c, 'No payment moved');
		}
	}

	@IsTest
	static void updateCardOpensTheProcessorsOwnPage() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer(
					'checkout/sessions',
					200,
					'{"id":"cs_s","url":"https://checkout.stripe.com/c/s"}'
				);
			PaymentsApi api = new PaymentsApi();
			Map<String, Object> args = new Map<String, Object>{
				'subscriptionId' => 'sub_1',
				'customerId' => 'cus_1',
				'returnUrl' => 'https://example.org/back'
			};

			Test.startTest();
			Map<String, Object> stripePage = (Map<String, Object>) api.call('updateCard', args);
			args.put('subscriptionId', 'I-1');
			Map<String, Object> payPalPage = (Map<String, Object>) api.call('updateCard', args);
			Test.stopTest();

			Assert.areEqual('https://checkout.stripe.com/c/s', stripePage.get('url'));
			String sent = mock.last('checkout/sessions').getBody();
			Assert.isTrue(sent.contains('mode=setup') && sent.contains('customer=cus_1'), sent);
			Assert.isTrue(sent.contains('barncrm_subscription%5D=sub_1'), sent);
			Assert.areEqual(PaymentPayPal.AUTOPAY_TEST, payPalPage.get('url'), 'PayPal sandbox');
			for (String missing : new List<String>{ 'customerId', 'returnUrl' }) {
				Map<String, Object> bad = args.clone();
				bad.put('subscriptionId', 'sub_1');
				bad.remove(missing);
				try {
					api.call('updateCard', bad);
					Assert.fail('Refused without ' + missing);
				} catch (PaymentsApi.PaymentException e) {
					Assert.isTrue(String.isNotBlank(e.getMessage()), missing);
				}
			}
		}
	}

	@IsTest
	static void payPalSalesRenewAndACancellationIsTold() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			Payment__c payment = first(PaymentService.PAYPAL, 'I-1');
			PaymentsTestData.processors()
				.answer('oauth2/token', 200, '{"access_token":"tok"}')
				.answer('verify-webhook-signature', 200, '{"verification_status":"SUCCESS"}');
			String headers = PaymentsTestData.payPalHeaders();
			for (Integer i = 1; i <= 2; i++) {
				PaymentsTestData.event(
					PaymentService.PAYPAL,
					null,
					PaymentsTestData.payPalEvent(
						'WH-' + i,
						'PAYMENT.SALE.COMPLETED',
						new Map<String, Object>{
							'id' => 'S-' + i,
							'billing_agreement_id' => 'I-1',
							'custom' => payment.Reference__c,
							'amount' => new Map<String, Object>{
								'total' => '20.00',
								'currency' => 'USD'
							}
						}
					),
					headers
				);
			}
			PaymentsTestData.event(
				PaymentService.PAYPAL,
				null,
				PaymentsTestData.payPalEvent(
					'WH-3',
					'BILLING.SUBSCRIPTION.CANCELLED',
					new Map<String, Object>{ 'id' => 'I-1', 'custom_id' => payment.Reference__c }
				),
				headers
			);

			Test.startTest();
			new PaymentEventProcessor.Run().execute(null);
			Test.stopTest();

			List<Payment__c> all = payments();
			Assert.areEqual(2, all.size(), 'The first sale and one renewal');
			Assert.areEqual('S-1', all[0].Processor_Payment_Id__c);
			Assert.areEqual('S-2', all[1].Processor_Payment_Id__c);
			Assert.areEqual(PaymentService.PAID, all[1].Status__c);
			Assert.areEqual(
				new List<String>{
					PaymentService.CHARGE_SUCCEEDED,
					PaymentService.CHARGE_SUCCEEDED,
					PaymentService.SUBSCRIPTION_CANCELLED
				},
				events()
			);
			Assert.areEqual('paypal:WH-3', news[2].get('eventKey'), 'Keyed once verified');
		}
	}

	@IsTest
	static void aRunOfRenewalsIsWrittenInOneInsert() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			Payment__c payment = first(PaymentService.STRIPE, 'sub_1');
			payment.Processor_Payment_Id__c = 'pi_first';
			payment.Status__c = PaymentService.PAID;
			update payment;
			for (Integer i = 0; i < 20; i++) {
				stripe(
					'evt_b' + i,
					'invoice.paid',
					invoice('in_b' + i, payment.Reference__c, 2000)
				);
			}

			Test.startTest();
			new PaymentEventProcessor.Run().execute(null);
			Integer dml = Limits.getDmlStatements();
			Test.stopTest();

			Assert.areEqual(21, payments().size(), 'Twenty renewals');
			Assert.isTrue(dml < 10, 'Not one write per renewal: ' + dml);
			Assert.areEqual(20, told.size(), 'Told once, together');
			Assert.areEqual(20, news.size());
		}
	}
}
