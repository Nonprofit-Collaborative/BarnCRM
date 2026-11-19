/**
 * The webhook receiver (ADR-0201 payments module, decisions 4 and 5; R-PEV1 to R-PEV3): a Stripe
 * event is stored once, by its id, for the processing job to fetch back from Stripe, with no
 * callout and no secret; a PayPal event is stored with its transmission headers for verification
 * later; a post to an unconnected processor, or one that cannot be an event, is refused.
 */
@IsTest(testFor='ApexClass:PaymentWebhookRest')
private class PaymentWebhookRestTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(PaymentsTestData.ADMIN);
	}

	private static RestRequest request(String processor, String body, Map<String, String> headers) {
		RestRequest request = bare(processor, body, headers);
		request.params.put('token', PaymentService.webhookToken(false));
		return request;
	}

	private static RestRequest bare(String processor, String body, Map<String, String> headers) {
		RestRequest request = new RestRequest();
		request.requestURI = '/barncrm/payments/v1/' + processor;
		request.httpMethod = 'POST';
		request.requestBody = body == null ? null : Blob.valueOf(body);
		for (String name : headers.keySet()) {
			request.addHeader(name, headers.get(name));
		}
		return request;
	}

	private static Integer stripe(String body) {
		return PaymentWebhookRest.store(request('stripe', body, new Map<String, String>()));
	}

	private static Integer storedEvents() {
		return [SELECT COUNT() FROM Payment_Event__c WITH SYSTEM_MODE];
	}

	@IsTest
	static void aStripeEventIsStoredOnceWithNoCallout() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			PaymentsTestData.Processors mock = PaymentsTestData.processors();
			String body = PaymentsTestData.stripeEvent(
				'evt_9',
				'checkout.session.completed',
				new Map<String, Object>()
			);

			Assert.areEqual(200, stripe(body), 'Stored');
			Assert.areEqual(200, stripe(body), 'A resend is answered as received');

			List<Payment_Event__c> stored = [
				SELECT Event_Key__c, Event_Type__c, Status__c
				FROM Payment_Event__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, stored.size(), 'Once');
			Assert.areEqual('stripe:evt_9', stored[0].Event_Key__c, 'Keyed');
			Assert.areEqual('checkout.session.completed', stored[0].Event_Type__c, 'Its type');
			Assert.areEqual('Received', stored[0].Status__c, 'Waits for processing');
			Assert.isTrue(mock.requests.isEmpty(), 'The guest makes no callout');
		}
	}

	@IsTest
	static void postsThatCannotBeAStripeEventAreRefused() {
		System.runAs(PaymentsTestData.admin()) {
			String body = PaymentsTestData.stripeEvent(
				'evt_8',
				'charge.refunded',
				new Map<String, Object>()
			);
			Assert.areEqual(400, stripe(body), 'Refused while Stripe is not connected');
			PaymentsTestData.connect(PaymentService.STRIPE);

			Assert.areEqual(400, stripe('{"type":"charge.refunded"}'), 'No event id');
			Assert.areEqual(
				400,
				stripe('{"id":"ch_1","type":"charge.refunded"}'),
				'Not an event id'
			);
			Assert.areEqual(400, stripe('not json'), 'Not an event');
			Assert.areEqual(
				200,
				stripe(PaymentsTestData.stripeEvent('evt_7', 'customer.created', null)),
				'A type the job does not act on is acknowledged, so Stripe stops sending it'
			);
			Assert.areEqual(
				404,
				PaymentWebhookRest.store(request('square', body, new Map<String, String>())),
				'Not a processor'
			);
			Assert.areEqual(0, storedEvents(), 'Nothing stored');
		}
	}

	@IsTest
	static void aPayPalEventIsKeptWithItsHeaders() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			String body = PaymentsTestData.payPalEvent(
				'WH-7',
				'PAYMENT.CAPTURE.COMPLETED',
				new Map<String, Object>()
			);
			Map<String, String> headers = (Map<String, String>) JSON.deserialize(
				PaymentsTestData.payPalHeaders(),
				Map<String, String>.class
			);
			Map<String, String> partial = headers.clone();
			partial.remove('paypal-transmission-sig');

			Assert.areEqual(
				400,
				PaymentWebhookRest.store(request('paypal', body, partial)),
				'Unsigned'
			);
			Assert.areEqual(
				200,
				PaymentWebhookRest.store(request('paypal', body, headers)),
				'Kept'
			);

			Payment_Event__c stored = [
				SELECT Event_Key__c, Event_Id__c, Headers__c, Processor__c
				FROM Payment_Event__c
				WITH SYSTEM_MODE
			];
			Assert.isNull(stored.Event_Key__c, 'Keyed only once PayPal verifies it');
			Assert.areEqual('WH-7', stored.Event_Id__c, 'Its id');
			Assert.isTrue(
				stored.Headers__c.contains('paypal-transmission-sig'),
				'Headers kept to verify'
			);
		}
	}

	private static Map<String, String> payPalHeaders() {
		return (Map<String, String>) JSON.deserialize(
			PaymentsTestData.payPalHeaders(),
			Map<String, String>.class
		);
	}

	private static Integer payPal(String body) {
		return PaymentWebhookRest.store(request('paypal', body, payPalHeaders()));
	}

	@IsTest
	static void nothingIsStoredForPayPalUntilItIsConnected() {
		System.runAs(PaymentsTestData.admin()) {
			String body = PaymentsTestData.payPalEvent(
				'WH-6',
				'PAYMENT.CAPTURE.COMPLETED',
				new Map<String, Object>()
			);

			Assert.areEqual(400, payPal(body), 'Refused while PayPal is not set up');
			Assert.areEqual(0, storedEvents(), 'Nothing stored');
		}
	}

	@IsTest
	static void aPayPalPostThatCannotBeAnEventItActsOnIsNotStored() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);

			Assert.areEqual(
				200,
				payPal(
					PaymentsTestData.payPalEvent(
						'WH-5',
						'CUSTOMER.DISPUTE.CREATED',
						new Map<String, Object>()
					)
				),
				'A type the job does not act on is acknowledged, so PayPal stops sending it'
			);
			Assert.areEqual(
				400,
				payPal('{"id":"WH-4","event_type":"PAYMENT.CAPTURE.COMPLETED"}'),
				'No resource'
			);
			Assert.areEqual(400, payPal('not json'), 'Not an event');
			Assert.areEqual(0, storedEvents(), 'Nothing stored');
		}
	}

	@IsTest
	static void aPostWithoutTheSavedTokenIsRefusedAndStoresNothing() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			String token = PaymentService.webhookToken(false);
			Assert.isTrue(token.length() >= 32, 'A long random token');
			String body = PaymentsTestData.stripeEvent(
				'evt_5',
				'checkout.session.completed',
				new Map<String, Object>()
			);

			RestRequest none = bare('stripe', body, new Map<String, String>());
			Assert.areEqual(404, PaymentWebhookRest.store(none), 'No token');
			RestRequest wrong = bare('stripe', body, new Map<String, String>());
			wrong.params.put('token', token.left(token.length() - 1) + 'x');
			Assert.areEqual(404, PaymentWebhookRest.store(wrong), 'Another token');
			RestRequest shorter = bare('stripe', body, new Map<String, String>());
			shorter.params.put('token', token.left(10));
			Assert.areEqual(404, PaymentWebhookRest.store(shorter), 'A prefix of the token');
			Assert.areEqual(0, storedEvents(), 'Nothing stored');

			RestRequest right = bare('stripe', body, new Map<String, String>());
			right.params.put('token', token);
			Assert.areEqual(200, PaymentWebhookRest.store(right), 'The saved token is accepted');
			Assert.areEqual(1, storedEvents(), 'Stored');

			String replaced = PaymentService.webhookToken(true);
			Assert.areNotEqual(token, replaced, 'Regenerated');
			Assert.areEqual(404, PaymentWebhookRest.store(right), 'The old token stops working');
		}
	}

	@IsTest
	static void theHourlyCapIsCountedPerProcessor() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			List<Payment_Event__c> flood = new List<Payment_Event__c>();
			for (Integer i = 0; i < PaymentWebhookRest.HOURLY_LIMIT; i++) {
				flood.add(
					new Payment_Event__c(
						Processor__c = PaymentService.PAYPAL,
						Status__c = 'Received',
						Event_Id__c = 'WH-F' + i
					)
				);
			}
			Database.insert(flood, AccessLevel.SYSTEM_MODE);
			String stripeBody = PaymentsTestData.stripeEvent(
				'evt_7',
				'charge.refunded',
				new Map<String, Object>()
			);

			Assert.areEqual(
				429,
				payPal(
					PaymentsTestData.payPalEvent(
						'WH-3',
						'PAYMENT.CAPTURE.COMPLETED',
						new Map<String, Object>()
					)
				),
				'PayPal is at its cap'
			);
			String second = PaymentsTestData.payPalEvent(
				'WH-2',
				'PAYMENT.CAPTURE.COMPLETED',
				new Map<String, Object>()
			);
			Assert.areEqual(429, payPal(second), 'Still at its cap');
			// The Warning travels as an Error Log event, written when the event is delivered.
			Test.getEventBus().deliver();
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'PaymentWebhookRest' AND Severity__c = 'Warning'
					WITH SYSTEM_MODE
				],
				'One Warning for the hour, not one per refused post'
			);
			Assert.isNotNull(
				PaymentService.settings().Webhook_Cap_Hit_At__c,
				'Health Check can see the cap was hit'
			);
			Assert.areEqual(
				200,
				stripe(stripeBody),
				'Stripe events still arrive while PayPal posts fill PayPal\'s cap'
			);
		}
	}

	@IsTest
	static void theEndpointAnswersWithAnEmptyBody() {
		System.runAs(PaymentsTestData.admin()) {
			RestContext.request = request('stripe', '{}', new Map<String, String>());
			RestContext.response = new RestResponse();

			PaymentWebhookRest.receive();

			Assert.areEqual(400, RestContext.response.statusCode, 'Refused');
			Assert.areEqual(
				'{}',
				RestContext.response.responseBody.toString(),
				'Says nothing more'
			);
		}
	}
}
