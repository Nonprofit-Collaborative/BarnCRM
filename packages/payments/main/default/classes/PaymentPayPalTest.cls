/**
 * PayPal's side of Payments (ADR-0201 `0201-payments-module.md`, decisions 2, 4 and 5): an Order
 * refused without an approve link, live addresses and whole-unit currencies, a webhook PayPal
 * will not confirm, every event type read, and the capture of an approved order. Events are read
 * in memory, so no write comes before a callout.
 */
@IsTest(testFor='ApexClass:PaymentPayPal')
private class PaymentPayPalTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(PaymentsTestData.ADMIN);
	}

	private static Payment__c draft(String currencyCode, Decimal amount) {
		return new Payment__c(
			Amount__c = amount,
			Currency_Code__c = currencyCode,
			Description__c = 'Gala ticket',
			Reference__c = 'ref-paypal-1'
		);
	}

	private static Payment_Event__c received(String id, String type, Map<String, Object> resource) {
		return new Payment_Event__c(
			Processor__c = PaymentService.PAYPAL,
			Status__c = 'Received',
			Payload__c = PaymentsTestData.payPalEvent(id, type, resource),
			Headers__c = PaymentsTestData.payPalHeaders()
		);
	}

	private static PaymentsTestData.Processors verifying() {
		return PaymentsTestData.processors()
			.answer('oauth2/token', 200, '{"access_token":"tok"}')
			.answer('verify-webhook-signature', 200, '{"verification_status":"SUCCESS"}');
	}

	private static Map<String, Object> resourceWithId(String id) {
		return new Map<String, Object>{ 'id' => id };
	}

	@IsTest
	static void anOrderWithNoApproveLinkIsRefusedAndLogged() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			PaymentsTestData.processors()
				.answer('oauth2/token', 200, '{"access_token":"tok"}')
				.answer('checkout/orders', 422, '{"name":"UNPROCESSABLE_ENTITY"}');
			Payment__c payment = draft('USD', 10);

			Test.startTest();
			try {
				PaymentPayPal.startCheckout(
					payment,
					'https://example.org/ok',
					'https://example.org/no'
				);
				Assert.fail('Refused');
			} catch (PaymentsApi.PaymentException e) {
				Assert.isTrue(String.isNotBlank(e.getMessage()), 'Said plainly');
			}
			Test.stopTest();

			Assert.isNull(payment.Checkout_Id__c, 'No order recorded');
			Assert.isTrue(
				[SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE] > 0,
				'PayPal answer logged'
			);
		}
	}

	@IsTest
	static void liveModeUsesTheLiveAddressAndWholeUnitCurrenciesHaveNoDecimals() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			Payments_Settings__c settings = Payments_Settings__c.getOrgDefaults();
			settings.Mode__c = PaymentService.LIVE;
			update settings;
			PaymentsTestData.Processors mock = PaymentsTestData.processors()
				.answer('oauth2/token', 200, '{"access_token":"tok"}')
				.answer(
					'checkout/orders',
					201,
					'{"id":"ORDERJ","links":[{"rel":"approve","href":"https://www.paypal.com/checkoutnow?token=ORDERJ"}]}'
				);
			Payment__c payment = draft('JPY', 1500);

			Test.startTest();
			PaymentPayPal.startCheckout(
				payment,
				'https://example.org/ok',
				'https://example.org/no'
			);
			Test.stopTest();

			Assert.areEqual('ORDERJ', payment.Checkout_Id__c, 'The order');
			HttpRequest order = mock.last('checkout/orders');
			Assert.isTrue(order.getEndpoint().startsWith(PaymentPayPal.LIVE_BASE), 'Live address');
			Assert.isTrue(order.getBody().contains('"value":"1500"'), order.getBody());
		}
	}

	@IsTest
	static void aWebhookPayPalWillNotConfirmIsRejected() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			PaymentsTestData.processors()
				.answer('oauth2/token', 200, '{"access_token":"tok"}')
				.answer('verify-webhook-signature', 200, '{"verification_status":"FAILURE"}');
			Map<String, Object> resource = resourceWithId('CAP1');
			Payment_Event__c unconfirmed = received('WH-U', 'PAYMENT.CAPTURE.COMPLETED', resource);
			Payment_Event__c noHeaders = received('WH-H', 'PAYMENT.CAPTURE.COMPLETED', resource);
			noHeaders.Headers__c = '{"paypal-auth-algo":"x"}';
			Payment_Event__c noBody = received('WH-B', 'PAYMENT.CAPTURE.COMPLETED', resource);
			noBody.Payload__c = null;

			Test.startTest();
			List<PaymentService.Outcome> outcomes = new List<PaymentService.Outcome>{
				PaymentPayPal.read(unconfirmed),
				PaymentPayPal.read(noHeaders),
				PaymentPayPal.read(noBody)
			};
			Test.stopTest();

			for (PaymentService.Outcome outcome : outcomes) {
				Assert.areEqual('Rejected', outcome.status, 'Not verified');
				Assert.isNull(outcome.change, 'Nothing to apply');
			}
		}
	}

	@IsTest
	static void withoutAWebhookIdEveryEventIsRejected() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			Payment_Keys__c keys = Payment_Keys__c.getOrgDefaults();
			keys.PayPal_Webhook_Id__c = null;
			update keys;
			verifying();

			Test.startTest();
			PaymentService.Outcome outcome = PaymentPayPal.read(
				received('WH-N', 'PAYMENT.CAPTURE.COMPLETED', resourceWithId('C'))
			);
			Test.stopTest();

			Assert.areEqual('Rejected', outcome.status, 'Nothing to check the event against');
		}
	}

	@IsTest
	static void captureEventsAreReadIntoChanges() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			verifying();

			Test.startTest();
			PaymentService.Outcome completed = PaymentPayPal.read(
				received('WH-1', 'PAYMENT.CAPTURE.COMPLETED', resourceWithId('CAP1'))
			);
			PaymentService.Outcome denied = PaymentPayPal.read(
				received('WH-2', 'PAYMENT.CAPTURE.DENIED', resourceWithId('CAP2'))
			);
			PaymentService.Outcome declined = PaymentPayPal.read(
				received('WH-3', 'PAYMENT.CAPTURE.DECLINED', resourceWithId('CAP3'))
			);
			PaymentService.Outcome reversed = PaymentPayPal.read(
				received('WH-4', 'PAYMENT.CAPTURE.REVERSED', resourceWithId('CAP4'))
			);
			PaymentService.Outcome ignored = PaymentPayPal.read(
				received('WH-5', 'BILLING.PLAN.CREATED', resourceWithId('X'))
			);
			Test.stopTest();

			Assert.areEqual(PaymentService.PAID, completed.change.status);
			Assert.areEqual('CAP1', completed.change.processorPaymentId);
			Assert.areEqual('paypal:WH-1', completed.event.Event_Key__c, 'Keyed to the event');
			Assert.areEqual(PaymentService.FAILED, denied.change.status);
			Assert.areEqual(PaymentService.FAILED, declined.change.status);
			Assert.isTrue(String.isNotBlank(denied.change.detail), 'Says it was declined');
			Assert.areEqual(PaymentService.REFUNDED, reversed.change.status);
			Assert.areEqual('CAP4', reversed.change.processorPaymentId);
			Assert.isNull(ignored.change, 'An event Payments does not use');
			Assert.isNull(ignored.status, 'Left to be marked processed');
		}
	}

	@IsTest
	static void refundEventsCarryTheTotalRefundedAndTheirCapture() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			verifying();
			Map<String, Object> withTotal = new Map<String, Object>{
				'id' => 'REF1',
				'amount' => new Map<String, Object>{ 'value' => '9.00' },
				'seller_payable_breakdown' => new Map<String, Object>{
					'total_refunded_amount' => new Map<String, Object>{ 'value' => '3.50' }
				},
				'links' => new List<Object>{
					new Map<String, Object>{
						'rel' => 'up',
						'href' => 'https://api-m.sandbox.paypal.com/v2/payments/captures/CAP9'
					}
				}
			};
			Map<String, Object> amountOnly = new Map<String, Object>{
				'id' => 'REF2',
				'amount' => new Map<String, Object>{ 'value' => '4.25' }
			};
			Map<String, Object> notANumber = new Map<String, Object>{
				'id' => 'REF3',
				'amount' => new Map<String, Object>{ 'value' => 'lots' }
			};

			Test.startTest();
			PaymentService.Outcome one = PaymentPayPal.read(
				received('WH-R1', 'PAYMENT.CAPTURE.REFUNDED', withTotal)
			);
			PaymentService.Outcome two = PaymentPayPal.read(
				received('WH-R2', 'PAYMENT.CAPTURE.REFUNDED', amountOnly)
			);
			PaymentService.Outcome three = PaymentPayPal.read(
				received('WH-R3', 'PAYMENT.CAPTURE.REFUNDED', notANumber)
			);
			Test.stopTest();

			Assert.areEqual(3.50, one.change.amountRefunded, 'The total refunded so far');
			Assert.areEqual('CAP9', one.change.processorPaymentId, 'The capture it refunds');
			Assert.areEqual(4.25, two.change.amountRefunded, 'The refund amount when no total');
			Assert.isNull(two.change.processorPaymentId, 'No up link');
			Assert.isNull(three.change.amountRefunded, 'An unreadable amount is not guessed');
		}
	}

	private static String capture(String status) {
		return '{"purchase_units":[{"payments":{"captures":[{"id":"CAPX","status":"' +
			status +
			'"}]}}]}';
	}

	private static PaymentService.Outcome approved(String letter) {
		return PaymentPayPal.read(
			received(
				'WH-' + letter,
				'CHECKOUT.ORDER.APPROVED',
				new Map<String, Object>{
					'id' => 'ORD' + letter,
					'purchase_units' => new List<Object>{
						new Map<String, Object>{ 'custom_id' => 'refORD' + letter }
					}
				}
			)
		);
	}

	@IsTest
	static void anApprovedOrderIsCapturedAndTheCaptureSetsTheStatus() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			verifying()
				.answer('ORDA/capture', 201, capture('COMPLETED'))
				.answer('ORDB/capture', 201, capture('DECLINED'))
				.answer('ORDC/capture', 201, capture('PENDING'))
				.answer('ORDD/capture', 422, '{"message":"ORDER_ALREADY_CAPTURED"}')
				.answer('ORDE/capture', 201, '{}');

			Test.startTest();
			PaymentService.Outcome paid = approved('A');
			PaymentService.Outcome failed = approved('B');
			PaymentService.Outcome pending = approved('C');
			PaymentService.Outcome already = approved('D');
			PaymentService.Outcome bare = approved('E');
			Test.stopTest();

			Assert.areEqual(PaymentService.PAID, paid.change.status);
			Assert.areEqual('CAPX', paid.change.processorPaymentId);
			Assert.areEqual('refORDA', paid.change.reference, 'From the purchase unit');
			Assert.areEqual('ORDA', paid.change.checkoutId);
			Assert.areEqual(PaymentService.FAILED, failed.change.status);
			Assert.isNull(pending.change.status, 'Left for the capture event');
			Assert.areEqual('ORDER_ALREADY_CAPTURED', already.change.detail, 'PayPal message kept');
			Assert.isNull(already.change.status, 'The capture event says which');
			Assert.isNull(bare.change.processorPaymentId, 'No captures in the answer');
		}
	}

	@IsTest
	static void anApprovedOrderWithNoPurchaseUnitHasNoReference() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			verifying().answer('ORDZ/capture', 201, '{}');

			Test.startTest();
			PaymentService.Outcome outcome = PaymentPayPal.read(
				received('WH-Z', 'CHECKOUT.ORDER.APPROVED', resourceWithId('ORDZ'))
			);
			Test.stopTest();

			Assert.isNull(outcome.change.reference, 'Nothing to match on');
			Assert.areEqual('ORDZ', outcome.change.checkoutId, 'Matched by the order');
		}
	}

	@IsTest
	static void aSignInPayPalRefusesStopsTheRead() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			PaymentsTestData.processors().answer('oauth2/token', 401, '{"error":"invalid_client"}');

			Test.startTest();
			try {
				PaymentPayPal.read(
					received('WH-S', 'PAYMENT.CAPTURE.COMPLETED', resourceWithId('C'))
				);
				Assert.fail('No token, no read');
			} catch (CalloutException e) {
				Assert.isTrue(e.getMessage().contains('401'), e.getMessage());
			}
			Test.stopTest();
		}
	}
}
