/**
 * Payments' status flow (canonical model 29PAY1, R-PAY1 to R-PAY3; ADR-0201 payments module,
 * decisions 2, 3, 5, 6 and 8): a checkout starts at Stripe or PayPal through the seam, processor
 * events move payments once each, refunds and failures are recorded, abandoned checkouts are
 * cancelled, and each change reaches its listener, whose failure is rolled back on its own.
 */
@IsTest(
	testFor='ApexClass:PaymentService, ApexClass:PaymentsApi, ApexClass:PaymentStripe, ApexClass:PaymentPayPal, ApexClass:PaymentEventProcessor'
)
private class PaymentServiceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(PaymentsTestData.ADMIN);
	}

	/** A consumer's listener: keeps what it is told. */
	public class Listener implements Callable {
		public Object call(String action, Map<String, Object> args) {
			told.add(action + ':' + args.get('previousStatus') + '>' + args.get('status'));
			return null;
		}
	}

	/** A consumer's listener that writes, then fails. */
	public class FailingListener implements Callable {
		public Object call(String action, Map<String, Object> args) {
			insert new Contact(LastName = 'Zzpay Listener');
			throw new System.IllegalArgumentException('consumer failed');
		}
	}

	private static List<String> told = new List<String>();

	private static Map<String, Object> checkout(Object amount) {
		return new Map<String, Object>{
			'amount' => amount,
			'description' => 'Gala ticket',
			'successUrl' => 'https://example.org/thanks',
			'cancelUrl' => 'https://example.org/sorry',
			'payerEmail' => 'pat@example.org',
			'sourceRecordId' => '001000000000001AAA',
			'listener' => 'PaymentServiceTest.Listener'
		};
	}

	private static void runOnce() {
		new PaymentEventProcessor.Run().execute(null);
	}

	@IsTest
	static void aStripeCheckoutStartsThroughTheSeam() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer(
					'stripe.com',
					200,
					'{"id":"cs_test_1","url":"https://checkout.stripe.com/c/pay/cs_test_1"}'
				);
			Callable api = (Callable) NamespaceUtil.build('PaymentsApi', Callable.class, 'test');

			Test.startTest();
			Map<String, Object> started = (Map<String, Object>) api.call(
				'startCheckout',
				checkout(25)
			);
			Test.stopTest();

			Assert.areEqual(
				'https://checkout.stripe.com/c/pay/cs_test_1',
				started.get('checkoutUrl')
			);
			Assert.areEqual(PaymentService.PENDING, started.get('status'), 'Starts Pending');
			HttpRequest sent = mock.last('stripe.com');
			Assert.isTrue(
				sent.getBody().contains('unit_amount%5D=2500'),
				'In cents: ' + sent.getBody()
			);
			Assert.areEqual(
				started.get('reference'),
				sent.getHeader('Idempotency-Key'),
				'Sent once only'
			);
			Map<String, Object> payment = (Map<String, Object>) api.call(
				'getPayment',
				new Map<String, Object>{ 'paymentId' => started.get('paymentId') }
			);
			Assert.areEqual(25.00, payment.get('amount'), 'Recorded');
			Assert.areEqual('001000000000001AAA', payment.get('sourceRecordId'), 'For its record');
			Assert.areEqual(PaymentService.TEST, payment.get('mode'), 'In test mode');
			Assert.isTrue((Boolean) api.call('isReady', null), 'Connected');
		}
	}

	@IsTest
	static void aPayPalCheckoutStartsWithAnApproveLink() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer('oauth2/token', 200, '{"access_token":"tok"}')
				.answer(
					'/v2/checkout/orders',
					201,
					'{"id":"ORDER1","links":[{"rel":"self","href":"https://x"},{"rel":"payer-action","href":"https://www.sandbox.paypal.com/checkoutnow?token=ORDER1"}]}'
				);

			Test.startTest();
			Payment__c payment = PaymentService.startCheckout(checkout(10.5));
			Test.stopTest();

			Assert.areEqual('ORDER1', payment.Checkout_Id__c, 'The order');
			Assert.isTrue(payment.Checkout_Url__c.contains('token=ORDER1'), 'Its approve link');
			HttpRequest order = mock.last('/v2/checkout/orders');
			Assert.isTrue(
				order.getEndpoint().startsWith(PaymentPayPal.TEST_BASE),
				'The sandbox in Test mode'
			);
			Assert.isTrue(order.getBody().contains('"value":"10.50"'), order.getBody());
			Assert.areEqual('Bearer tok', order.getHeader('Authorization'), 'Signed in');
		}
	}

	@IsTest
	static void badRequestsAndProcessorErrorsAreRefusedPlainly() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsApi api = new PaymentsApi();
			Map<String, Object> notReady = checkout(5);
			assertRefused(api, notReady, 'not connected');
			PaymentsTestData.connect(PaymentService.STRIPE);
			assertRefused(api, checkout(0), 'zero');
			Map<String, Object> plain = checkout(5);
			plain.put('successUrl', 'http://example.org');
			assertRefused(api, plain, 'not https');
			Map<String, Object> noWords = checkout(5);
			noWords.put('description', ' ');
			assertRefused(api, noWords, 'no description');
			Map<String, Object> badCurrency = checkout(5);
			badCurrency.put('currency', 'dollars');
			assertRefused(api, badCurrency, 'bad currency');
			PaymentsTestData.processors()
				.answer('stripe.com', 400, '{"error":{"message":"No such price"}}');
			assertRefused(api, checkout(5), 'processor error');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Payment__c WITH SYSTEM_MODE],
				'Nothing recorded'
			);
			try {
				api.call('refund', null);
				Assert.fail('Unknown action');
			} catch (PaymentsApi.PaymentException e) {
				Assert.isTrue(e.getMessage().contains('refund'), e.getMessage());
			}
		}
	}

	private static void assertRefused(PaymentsApi api, Map<String, Object> args, String why) {
		try {
			api.call('startCheckout', args);
			Assert.fail('Refused: ' + why);
		} catch (PaymentsApi.PaymentException e) {
			Assert.isTrue(String.isNotBlank(e.getMessage()), why);
		}
	}

	@IsTest
	static void stripeEventsMovePaymentsAndRefundsAreRecorded() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			Payment__c payment = PaymentsTestData.payment(
				PaymentService.STRIPE,
				PaymentService.PENDING,
				25
			);
			update new Payment__c(Id = payment.Id, Listener__c = 'PaymentServiceTest.Listener');
			Payment_Event__c paid = PaymentsTestData.event(
				PaymentService.STRIPE,
				'stripe:evt_1',
				PaymentsTestData.stripeEvent(
					'evt_1',
					'checkout.session.completed',
					new Map<String, Object>{
						'id' => payment.Checkout_Id__c,
						'client_reference_id' => payment.Reference__c,
						'payment_intent' => 'pi_1',
						'payment_status' => 'paid'
					}
				),
				null
			);
			Payment_Event__c partial = PaymentsTestData.event(
				PaymentService.STRIPE,
				'stripe:evt_2',
				PaymentsTestData.stripeEvent(
					'evt_2',
					'charge.refunded',
					new Map<String, Object>{
						'payment_intent' => 'pi_1',
						'amount_refunded' => 1000,
						'currency' => 'usd'
					}
				),
				null
			);
			Payment_Event__c other = PaymentsTestData.event(
				PaymentService.STRIPE,
				'stripe:evt_3',
				PaymentsTestData.stripeEvent(
					'evt_3',
					'customer.created',
					new Map<String, Object>()
				),
				null
			);

			Test.startTest();
			runOnce();
			Payment__c afterPartial = PaymentsTestData.reread(payment.Id);
			PaymentsTestData.event(
				PaymentService.STRIPE,
				'stripe:evt_4',
				PaymentsTestData.stripeEvent(
					'evt_4',
					'charge.refunded',
					new Map<String, Object>{
						'payment_intent' => 'pi_1',
						'amount_refunded' => 2500,
						'currency' => 'usd'
					}
				),
				null
			);
			runOnce();
			Test.stopTest();

			Assert.areEqual(
				PaymentService.PAID,
				afterPartial.Status__c,
				'A partial refund keeps Paid (R-PAY2)'
			);
			Assert.areEqual(10.00, afterPartial.Amount_Refunded__c, 'The amount refunded');
			Assert.isNotNull(afterPartial.Paid_At__c, 'When paid');
			Assert.areEqual('pi_1', afterPartial.Processor_Payment_Id__c, 'The processor payment');
			Payment__c refunded = PaymentsTestData.reread(payment.Id);
			Assert.areEqual(PaymentService.REFUNDED, refunded.Status__c, 'A full refund');
			Assert.areEqual('Applied', PaymentsTestData.rereadEvent(paid.Id).Status__c, 'Applied');
			Assert.areEqual(
				payment.Id,
				PaymentsTestData.rereadEvent(partial.Id).Payment__c,
				'Linked'
			);
			Assert.areEqual(
				'Ignored',
				PaymentsTestData.rereadEvent(other.Id).Status__c,
				'Not used'
			);
			Assert.areEqual(
				new List<String>{ 'paymentChanged:Pending>Paid', 'paymentChanged:Paid>Refunded' },
				told,
				'The listener is told of each move'
			);
		}
	}

	@IsTest
	static void failuresAndRefusedMovesAreRecordedAndAFailingListenerIsRolledBack() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			Payment__c payment = PaymentsTestData.payment(
				PaymentService.STRIPE,
				PaymentService.PENDING,
				25
			);
			update new Payment__c(
				Id = payment.Id,
				Processor_Payment_Id__c = 'pi_9',
				Listener__c = 'PaymentServiceTest.FailingListener'
			);
			Payment__c done = PaymentsTestData.payment(
				PaymentService.STRIPE,
				PaymentService.REFUNDED,
				5
			);
			PaymentsTestData.event(
				PaymentService.STRIPE,
				'stripe:evt_f',
				PaymentsTestData.stripeEvent(
					'evt_f',
					'payment_intent.payment_failed',
					new Map<String, Object>{
						'id' => 'pi_9',
						'last_payment_error' => new Map<String, Object>{
							'message' => 'Card declined'
						}
					}
				),
				null
			);
			Payment_Event__c late = PaymentsTestData.event(
				PaymentService.STRIPE,
				'stripe:evt_l',
				PaymentsTestData.stripeEvent(
					'evt_l',
					'checkout.session.completed',
					new Map<String, Object>{
						'client_reference_id' => done.Reference__c,
						'payment_status' => 'paid'
					}
				),
				null
			);

			Test.startTest();
			runOnce();
			Test.stopTest();

			Payment__c failed = PaymentsTestData.reread(payment.Id);
			Assert.areEqual(PaymentService.FAILED, failed.Status__c, 'Failed is recorded');
			Assert.areEqual('Card declined', failed.Detail__c, 'With the reason');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Contact WHERE LastName = 'Zzpay Listener' WITH SYSTEM_MODE],
				'Rolled back'
			);
			Assert.isTrue(
				[SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE] > 0,
				'The listener failure is logged'
			);
			Assert.areEqual(
				PaymentService.REFUNDED,
				PaymentsTestData.reread(done.Id).Status__c,
				'R-PAY1'
			);
			Payment_Event__c refused = PaymentsTestData.rereadEvent(late.Id);
			Assert.areEqual('Ignored', refused.Status__c, 'Refunded never goes back to Paid');
			Assert.isTrue(refused.Message__c.contains('Refunded'), refused.Message__c);
		}
	}

	@IsTest
	static void payPalEventsAreVerifiedCapturedAndUsedOnce() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			Payment__c payment = PaymentsTestData.payment(
				PaymentService.PAYPAL,
				PaymentService.PENDING,
				40
			);
			Map<String, Object> order = new Map<String, Object>{
				'id' => payment.Checkout_Id__c,
				'purchase_units' => new List<Object>{
					new Map<String, Object>{ 'custom_id' => payment.Reference__c }
				}
			};
			String approved = PaymentsTestData.payPalEvent(
				'WH-A',
				'CHECKOUT.ORDER.APPROVED',
				order
			);
			Payment_Event__c first = PaymentsTestData.event(
				PaymentService.PAYPAL,
				null,
				approved,
				PaymentsTestData.payPalHeaders()
			);
			Payment_Event__c again = PaymentsTestData.event(
				PaymentService.PAYPAL,
				null,
				approved,
				PaymentsTestData.payPalHeaders()
			);
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer('oauth2/token', 200, '{"access_token":"tok"}')
				.answer('verify-webhook-signature', 200, '{"verification_status":"SUCCESS"}')
				.answer(
					'/capture',
					201,
					'{"purchase_units":[{"payments":{"captures":[{"id":"CAP1","status":"COMPLETED"}]}}]}'
				);

			Test.startTest();
			runOnce();
			Test.stopTest();

			Payment__c paid = PaymentsTestData.reread(payment.Id);
			Assert.areEqual(PaymentService.PAID, paid.Status__c, 'Captured and paid');
			Assert.areEqual('CAP1', paid.Processor_Payment_Id__c, 'The capture');
			Assert.areEqual(
				'paypal:WH-A',
				PaymentsTestData.rereadEvent(first.Id).Event_Key__c,
				'Keyed once verified'
			);
			Payment_Event__c duplicate = PaymentsTestData.rereadEvent(again.Id);
			Assert.areEqual('Ignored', duplicate.Status__c, 'The resend is not applied twice');
			Assert.isNull(duplicate.Event_Key__c, 'Its key stays with the first');
			Assert.isTrue(
				mock.last('verify-webhook-signature').getBody().contains('"webhook_id":"WH-1"'),
				'Verified against this webhook'
			);
		}
	}

	@IsTest
	static void anUnverifiedPayPalEventIsRejected() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			Payment__c payment = PaymentsTestData.payment(
				PaymentService.PAYPAL,
				PaymentService.PENDING,
				40
			);
			Payment_Event__c forged = PaymentsTestData.event(
				PaymentService.PAYPAL,
				null,
				PaymentsTestData.payPalEvent(
					'WH-F',
					'PAYMENT.CAPTURE.REVERSED',
					new Map<String, Object>{ 'id' => 'CAP9', 'custom_id' => payment.Reference__c }
				),
				PaymentsTestData.payPalHeaders()
			);
			PaymentsTestData.processors()
				.answer('oauth2/token', 200, '{"access_token":"tok"}')
				.answer('verify-webhook-signature', 200, '{"verification_status":"FAILURE"}');

			Test.startTest();
			runOnce();
			Test.stopTest();

			Assert.areEqual(
				'Rejected',
				PaymentsTestData.rereadEvent(forged.Id).Status__c,
				'Rejected'
			);
			Assert.areEqual(
				PaymentService.PENDING,
				PaymentsTestData.reread(payment.Id).Status__c,
				'Untouched'
			);
		}
	}

	@IsTest
	static void abandonedCheckoutsAreCancelledAndProcessingIsScheduled() {
		System.runAs(PaymentsTestData.admin()) {
			Payment__c stale = PaymentsTestData.payment(
				PaymentService.STRIPE,
				PaymentService.PENDING,
				5
			);
			Payment__c fresh = PaymentsTestData.payment(
				PaymentService.STRIPE,
				PaymentService.PENDING,
				5
			);
			Test.setCreatedDate(stale.Id, Datetime.now().addDays(-3));

			Test.startTest();
			PaymentEventProcessor.schedule();
			new PaymentEventProcessor().execute(null);
			Test.stopTest();

			Assert.areEqual(
				PaymentService.CANCELLED,
				PaymentsTestData.reread(stale.Id).Status__c,
				'R-PAY3'
			);
			Assert.areEqual(
				PaymentService.PENDING,
				PaymentsTestData.reread(fresh.Id).Status__c,
				'Still in time'
			);
			Assert.isTrue(PaymentEventProcessor.isScheduled(), 'Four jobs');
			Assert.areEqual(
				4,
				[
					SELECT COUNT()
					FROM CronTrigger
					WHERE CronJobDetail.Name LIKE :PaymentEventProcessor.JOB_NAME + '%'
					WITH SYSTEM_MODE
				],
				'Every 15 minutes'
			);
		}
	}

	@IsTest
	static void amountsConvertToAndFromMinorUnits() {
		// runs-as: deploying user (pure arithmetic, no DML or SOQL)
		Assert.areEqual(1050L, PaymentService.minorUnits(10.5, 'USD'), 'Cents');
		Assert.areEqual(500L, PaymentService.minorUnits(500, 'JPY'), 'No minor unit');
		Assert.areEqual(10.50, PaymentService.fromMinorUnits(1050, 'usd'), 'Back');
		Assert.areEqual(500, PaymentService.fromMinorUnits(500, 'jpy'), 'Back, whole');
		Assert.isNull(PaymentService.fromMinorUnits('x', 'usd'), 'Not a number');
		Assert.isTrue(
			PaymentService.canMove(PaymentService.FAILED, PaymentService.PAID),
			'A retry succeeds'
		);
		Assert.isFalse(
			PaymentService.canMove(PaymentService.CANCELLED, PaymentService.FAILED),
			'Not back'
		);
	}
}
