/**
 * Payments at volume (R-PAY3, R-PAY5, R-PEV4): a listener with the bulk form is told once per
 * run with every payment of its own, a listener without it one payment at a time; abandoned
 * checkouts are cancelled in their own job; a run stops reading at its callout-time budget and
 * leaves a transport failure Received; a PayPal refund names its capture.
 */
@IsTest(
	testFor='ApexClass:PaymentService, ApexClass:PaymentEventProcessor, ApexClass:PaymentPayPal, ApexClass:PaymentsApi'
)
private class PaymentBulkTest {
	private static final String BULK_LISTENER = 'PaymentBulkTest.BulkListener';
	private static final String SINGLE_LISTENER = 'PaymentBulkTest.SingleListener';
	private static List<Integer> bulkCalls = new List<Integer>();
	private static List<String> singleCalls = new List<String>();

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(PaymentsTestData.ADMIN);
	}

	/** A listener with the bulk form: one SOQL per call, whatever the count. */
	public class BulkListener implements Callable {
		public Object call(String action, Map<String, Object> args) {
			if (action != 'paymentsChanged') {
				throw new IllegalArgumentException('told one at a time');
			}
			List<Object> payments = (List<Object>) args.get('payments');
			Set<Id> ids = new Set<Id>();
			for (Object one : payments) {
				ids.add((Id) ((Map<String, Object>) one).get('paymentId'));
			}
			Assert.areEqual(
				ids.size(),
				[SELECT COUNT() FROM Payment__c WHERE Id IN :ids WITH SYSTEM_MODE]
			);
			bulkCalls.add(payments.size());
			return true;
		}
	}

	/** A listener with only the one-payment form, as Events and Memberships have. */
	public class SingleListener implements Callable {
		public Object call(String action, Map<String, Object> args) {
			if (action == 'paymentChanged') {
				singleCalls.add(String.valueOf(args.get('status')));
			}
			return null;
		}
	}

	/** A processor that cannot be reached. */
	private class Unreachable implements HttpCalloutMock {
		public HttpResponse respond(HttpRequest request) {
			throw new CalloutException('Read timed out');
		}
	}

	private static List<Payment__c> pending(Integer count, String listener) {
		List<Payment__c> made = new List<Payment__c>();
		for (Integer i = 0; i < count; i++) {
			made.add(
				new Payment__c(
					Processor__c = PaymentService.STRIPE,
					Mode__c = PaymentService.TEST,
					Status__c = PaymentService.PENDING,
					Amount__c = 10,
					Amount_Refunded__c = 0,
					Currency_Code__c = 'USD',
					Description__c = 'Gala ticket',
					Reference__c = 'bulkref' + listener.length() + '-' + i,
					Listener__c = listener
				)
			);
		}
		insert made;
		return made;
	}

	@IsTest
	static void abandonedCheckoutsReachEachListenerOnceOrOneAtATime() {
		System.runAs(PaymentsTestData.admin()) {
			List<Payment__c> stale = pending(26, BULK_LISTENER);
			stale.addAll(pending(4, SINGLE_LISTENER));
			for (Payment__c payment : stale) {
				Test.setCreatedDate(payment.Id, Datetime.now().addDays(-3));
			}

			Test.startTest();
			new PaymentEventProcessor().execute(null);
			Test.stopTest();

			Assert.areEqual(new List<Integer>{ 26 }, bulkCalls, 'One bulk call with all 26');
			Assert.areEqual(4, singleCalls.size(), 'The other listener one payment at a time');
			Assert.areEqual(
				30,
				[
					SELECT COUNT()
					FROM Payment__c
					WHERE Status__c = :PaymentService.CANCELLED
					WITH SYSTEM_MODE
				],
				'R-PAY3, in the Abandon job'
			);
		}
	}

	@IsTest
	static void aRunTellsTheBulkListenerOnceAndLeavesTheRestReceived() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.STRIPE);
			List<Payment__c> payments = pending(25, BULK_LISTENER);
			List<Payment_Event__c> events = new List<Payment_Event__c>();
			for (Integer i = 0; i < payments.size(); i++) {
				events.add(
					new Payment_Event__c(
						Processor__c = PaymentService.STRIPE,
						Status__c = 'Received',
						Event_Key__c = 'stripe:evt_bulk' + i,
						Payload__c = PaymentsTestData.stripeEvent(
							'evt_bulk' + i,
							'checkout.session.completed',
							new Map<String, Object>{
								'client_reference_id' => payments[i].Reference__c,
								'payment_intent' => 'pi_bulk' + i,
								'payment_status' => 'paid'
							}
						)
					)
				);
			}
			insert events;

			Test.startTest();
			new PaymentEventProcessor.Run().execute(null);
			Test.stopTest();

			Assert.areEqual(
				new List<Integer>{ PaymentEventProcessor.PER_RUN },
				bulkCalls,
				'One call for the run'
			);
			Assert.areEqual(
				PaymentEventProcessor.PER_RUN,
				[
					SELECT COUNT()
					FROM Payment__c
					WHERE Status__c = :PaymentService.PAID
					WITH SYSTEM_MODE
				]
			);
			Assert.areEqual(
				25 - PaymentEventProcessor.PER_RUN,
				PaymentEventProcessor.waiting(50).size(),
				'The rest wait for the next run, none marked'
			);
		}
	}

	@IsTest
	static void aRunStopsAtItsCalloutBudgetAndRetriesTransportFailures() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			for (Integer i = 0; i < 3; i++) {
				PaymentsTestData.event(
					PaymentService.PAYPAL,
					null,
					PaymentsTestData.payPalEvent(
						'WH-T' + i,
						'PAYMENT.CAPTURE.COMPLETED',
						new Map<String, Object>{ 'id' => 'CAPT' + i }
					),
					PaymentsTestData.payPalHeaders()
				);
			}
			Test.setMock(HttpCalloutMock.class, new Unreachable());
			PaymentEventProcessor.calloutBudgetMs = -1;

			Test.startTest();
			new PaymentEventProcessor.Run().execute(null);
			Test.stopTest();

			Assert.areEqual(
				3,
				PaymentEventProcessor.waiting(10).size(),
				'One read, failed in transport, two not reached: all still Received'
			);
			Assert.areEqual(1, [SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE], 'One logged');
		}
	}

	@IsTest
	static void aPayPalRefundNamesItsCaptureAndRecentPaymentsAreCounted() {
		System.runAs(PaymentsTestData.admin()) {
			PaymentsTestData.connect(PaymentService.PAYPAL);
			Map<String, Object> refund = new Map<String, Object>{
				'id' => 'REF1',
				'links' => new List<Object>{
					new Map<String, Object>{
						'rel' => 'self',
						'href' => 'https://api-m.paypal.com/v2/payments/refunds/REF1'
					},
					new Map<String, Object>{
						'rel' => 'up',
						'href' => 'https://api-m.paypal.com/v2/payments/captures/CAP7'
					}
				}
			};
			Payment__c payment = pending(1, SINGLE_LISTENER)[0];
			update new Payment__c(Id = payment.Id, Source_Record_Id__c = '001000000000009AAA');

			Assert.areEqual('CAP7', PaymentPayPal.refundedCapture(refund), 'From the up link');
			Assert.isNull(PaymentPayPal.refundedCapture(new Map<String, Object>()), 'None');
			PaymentsApi api = new PaymentsApi();
			Assert.areEqual(
				1,
				api.call(
					'countRecent',
					new Map<String, Object>{ 'sourceRecordId' => '001000000000009AAA' }
				)
			);
			Assert.areEqual(
				0,
				api.call(
					'countRecent',
					new Map<String, Object>{
						'sourceRecordId' => '001000000000009AAA',
						'minutes' => 10,
						'status' => PaymentService.PAID
					}
				)
			);
		}
	}
}
