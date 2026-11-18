/**
 * Payments test data: the admin, both processors connected, a processor stand-in that answers by
 * address and keeps each request (and, like Stripe, answers `GET /v1/events/{id}` with the stored
 * event of that id), payments and events.
 */
@IsTest
public class PaymentsTestData {
	public static final String ADMIN = 'Payments_Admin';

	public static User admin() {
		return TestUsers.adminWith(ADMIN);
	}

	/**
	 * Both processors connected (as Check Connection leaves them), in Test mode, with the
	 * processor given, and a processor stand-in in place for any event fetch.
	 */
	public static void connect(String processor) {
		Payments_Settings__c settings = Payments_Settings__c.getOrgDefaults();
		settings.SetupOwnerId = UserInfo.getOrganizationId();
		settings.Processor__c = processor;
		settings.Mode__c = PaymentService.TEST;
		settings.Currency__c = 'USD';
		settings.Stripe_Connected__c = true;
		settings.PayPal_Connected__c = true;
		settings.PayPal_Webhook_Id__c = 'WH-1';
		upsert settings;
		processors();
	}

	/**
	 * Answers each request by the first address part it contains; keeps every request. A Stripe
	 * event fetch no part matches is answered as Stripe would: the stored event with that id, or
	 * 404 when there is none.
	 */
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
					return response;
				}
			}
			if (request.getEndpoint().startsWith(PaymentStripe.ENDPOINT + 'events/')) {
				String stored = storedStripeEvent(
					EncodingUtil.urlDecode(
						request.getEndpoint().substringAfterLast('/events/'),
						'UTF-8'
					)
				);
				if (stored != null) {
					response.setStatusCode(200);
					response.setBody(stored);
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

	/** The payload of the stored Stripe event with this id, as Stripe would return it. */
	private static String storedStripeEvent(String eventId) {
		for (Payment_Event__c stored : [
			SELECT Payload__c
			FROM Payment_Event__c
			WHERE Processor__c = :PaymentService.STRIPE
			WITH SYSTEM_MODE
		]) {
			if (PaymentStripe.text(PaymentStripe.parse(stored.Payload__c).get('id')) == eventId) {
				return stored.Payload__c;
			}
		}
		return null;
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
