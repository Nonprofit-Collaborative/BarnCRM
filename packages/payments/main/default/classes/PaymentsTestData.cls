/**
 * Payments test data: the admin, test keys, a processor stand-in that answers by address and
 * keeps each request, payments and events, and a Stripe signature made the way Stripe makes it.
 */
@IsTest
public class PaymentsTestData {
	public static final String ADMIN = 'Payments_Admin';
	public static final String STRIPE_SECRET = 'whsec_barn_test_secret';

	public static User admin() {
		return TestUsers.adminWith(ADMIN);
	}

	/** Every key entered, in Test mode, with the processor given. */
	public static void connect(String processor) {
		Payments_Settings__c settings = Payments_Settings__c.getOrgDefaults();
		settings.SetupOwnerId = UserInfo.getOrganizationId();
		settings.Processor__c = processor;
		settings.Mode__c = PaymentService.TEST;
		settings.Currency__c = 'USD';
		upsert settings;
		Payment_Keys__c keys = Payment_Keys__c.getOrgDefaults();
		keys.SetupOwnerId = UserInfo.getOrganizationId();
		keys.Stripe_Secret_Key__c = 'sk_test_barn';
		keys.Stripe_Webhook_Secret__c = STRIPE_SECRET;
		keys.PayPal_Client_Id__c = 'client';
		keys.PayPal_Client_Secret__c = 'secret';
		keys.PayPal_Webhook_Id__c = 'WH-1';
		upsert keys;
	}

	/** Answers each request by the first address part it contains; keeps every request. */
	public class Processors implements HttpCalloutMock {
		public Map<String, String> bodies = new Map<String, String>();
		public Map<String, Integer> codes = new Map<String, Integer>();
		public List<HttpRequest> requests = new List<HttpRequest>();

		public Processors answer(String addressPart, Integer code, String body) {
			bodies.put(addressPart, body);
			codes.put(addressPart, code);
			return this;
		}

		public HttpResponse respond(HttpRequest request) {
			requests.add(request);
			HttpResponse response = new HttpResponse();
			response.setStatusCode(404);
			response.setBody('{}');
			for (String part : bodies.keySet()) {
				if (request.getEndpoint().contains(part)) {
					response.setStatusCode(codes.get(part));
					response.setBody(bodies.get(part));
					break;
				}
			}
			return response;
		}

		public HttpRequest last(String addressPart) {
			HttpRequest found;
			for (HttpRequest request : requests) {
				if (request.getEndpoint().contains(addressPart)) {
					found = request;
				}
			}
			return found;
		}
	}

	public static Processors processors() {
		Processors mock = new Processors();
		Test.setMock(HttpCalloutMock.class, mock);
		return mock;
	}

	public static Payment__c payment(String processor, String status, Decimal amount) {
		Payment__c payment = new Payment__c(
			Processor__c = processor,
			Mode__c = PaymentService.TEST,
			Status__c = status,
			Amount__c = amount,
			Amount_Refunded__c = 0,
			Currency_Code__c = 'USD',
			Description__c = 'Gala ticket',
			Reference__c = 'ref' + String.valueOf(Crypto.getRandomInteger()).remove('-'),
			Checkout_Id__c = 'cs_' + String.valueOf(Crypto.getRandomInteger()).remove('-')
		);
		insert payment;
		return payment;
	}

	public static Payment_Event__c event(
		String processor,
		String key,
		String payload,
		String headers
	) {
		Payment_Event__c event = new Payment_Event__c(
			Processor__c = processor,
			Status__c = 'Received',
			Event_Key__c = key,
			Payload__c = payload,
			Headers__c = headers
		);
		insert event;
		return event;
	}

	/** A Stripe event body. */
	public static String stripeEvent(String id, String type, Map<String, Object> obj) {
		return JSON.serialize(
			new Map<String, Object>{
				'id' => id,
				'type' => type,
				'created' => 1800000000,
				'data' => new Map<String, Object>{ 'object' => obj }
			}
		);
	}

	/** A PayPal event body. */
	public static String payPalEvent(String id, String type, Map<String, Object> resource) {
		return JSON.serialize(
			new Map<String, Object>{ 'id' => id, 'event_type' => type, 'resource' => resource }
		);
	}

	public static String payPalHeaders() {
		Map<String, String> headers = new Map<String, String>();
		for (String name : PaymentPayPal.HEADERS) {
			headers.put(name, 'value-' + name);
		}
		return JSON.serialize(headers);
	}

	/** The Stripe-Signature header for this body at this time. */
	public static String stripeSignature(String body, Long seconds) {
		return 't=' +
			seconds +
			',v1=' +
			EncodingUtil.convertToHex(
				Crypto.generateMac(
					'hmacSHA256',
					Blob.valueOf(seconds + '.' + body),
					Blob.valueOf(STRIPE_SECRET)
				)
			);
	}

	public static Payment__c reread(Id paymentId) {
		return [
			SELECT Status__c, Amount_Refunded__c, Paid_At__c, Processor_Payment_Id__c, Detail__c
			FROM Payment__c
			WHERE Id = :paymentId
			WITH SYSTEM_MODE
		];
	}

	public static Payment_Event__c rereadEvent(Id eventId) {
		return [
			SELECT Status__c, Message__c, Payment__c, Event_Key__c
			FROM Payment_Event__c
			WHERE Id = :eventId
			WITH SYSTEM_MODE
		];
	}
}
