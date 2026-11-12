/**
 * The webhook receiver (ADR-0201 payments module, decisions 4 and 5; R-PEV1, R-PEV3): a Stripe
 * event is stored only with a good, recent signature and only once; a PayPal event is stored
 * with its transmission headers for verification later; anything else is refused.
 */
@IsTest(testFor='ApexClass:PaymentWebhookRest')
private class PaymentWebhookRestTest {
	private static final Long NOW = 1800000000L;

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(PaymentsTestData.ADMIN);
	}

	private static RestRequest request(String processor, String body, Map<String, String> headers) {
		RestRequest request = new RestRequest();
		request.requestURI = '/barncrm/payments/v1/' + processor;
		request.httpMethod = 'POST';
		request.requestBody = body == null ? null : Blob.valueOf(body);
		for (String name : headers.keySet()) {
			request.addHeader(name, headers.get(name));
		}
		return request;
	}

	private static Integer stripe(String body, String signature) {
		return PaymentWebhookRest.store(
			request('stripe', body, new Map<String, String>{ 'Stripe-Signature' => signature }),
			NOW
		);
	}

	private static Integer storedEvents() {
		return [SELECT COUNT() FROM Payment_Event__c WITH SYSTEM_MODE];
	}

	@IsTest
	static void aSignedStripeEventIsStoredOnce() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			String body = PaymentsTestData.stripeEvent(
				'evt_9',
				'checkout.session.completed',
				new Map<String, Object>()
			);
			String signature = PaymentsTestData.stripeSignature(body, NOW - 30);

			Assert.areEqual(200, stripe(body, signature), 'Stored');
			Assert.areEqual(200, stripe(body, signature), 'A resend is answered as received');

			List<Payment_Event__c> stored = [
				SELECT Event_Key__c, Event_Type__c, Status__c
				FROM Payment_Event__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, stored.size(), 'Once');
			Assert.areEqual('stripe:evt_9', stored[0].Event_Key__c, 'Keyed');
			Assert.areEqual('checkout.session.completed', stored[0].Event_Type__c, 'Its type');
			Assert.areEqual('Received', stored[0].Status__c, 'Waits for processing');
		}
	}

	@IsTest
	static void badSignaturesOldEventsAndOtherPathsAreRefused() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			String body = PaymentsTestData.stripeEvent(
				'evt_8',
				'charge.refunded',
				new Map<String, Object>()
			);

			Assert.areEqual(
				400,
				stripe(body, PaymentsTestData.stripeSignature(body + ' ', NOW)),
				'Changed body'
			);
			Assert.areEqual(
				400,
				stripe(body, PaymentsTestData.stripeSignature(body, NOW - 301)),
				'Too old'
			);
			Assert.areEqual(400, stripe(body, 't=abc,v1=00'), 'Not a time');
			Assert.areEqual(400, stripe(body, null), 'No signature');
			Assert.areEqual(400, stripe('{"type":"x"}', 't=1,v1=0'), 'No event id');
			Assert.areEqual(
				404,
				PaymentWebhookRest.store(request('square', body, new Map<String, String>()), NOW),
				'Not a processor'
			);
			Assert.areEqual(0, storedEvents(), 'Nothing stored');
			Assert.isFalse(PaymentStripe.sameText('abc', 'abd'), 'Compared in full');
		}
	}

	@IsTest
	static void aPayPalEventIsKeptWithItsHeaders() {
		System.runAs(PaymentsTestData.admin()) {
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
				PaymentWebhookRest.store(request('paypal', body, partial), NOW),
				'Unsigned'
			);
			Assert.areEqual(
				200,
				PaymentWebhookRest.store(request('paypal', body, headers), NOW),
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
