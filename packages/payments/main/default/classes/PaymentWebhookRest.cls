/**
 * The webhook receiver (ADR-NEXT `NEXT-payments-module.md`, decisions 4 and 5; R-PEV1, R-PEV3),
 * on the org's Salesforce Site for its guest user (`Payments_Webhook_Guest`):
 *
 *   POST <site URL>/services/apexrest/barncrm/payments/v1/stripe
 *   POST <site URL>/services/apexrest/barncrm/payments/v1/paypal
 *
 * It only stores: one Payment Event, Received, in system mode (the guest has no object access).
 * A Stripe event is stored only when its Stripe-Signature verifies, under its unique key, so a
 * resend is a duplicate and answered 200. A PayPal event is stored with its transmission headers
 * and verified with PayPal by the processing job. It reads no record, returns no identifier and
 * answers every outcome with an empty body.
 *
 * `global` because the platform requires it of a REST resource.
 */
@RestResource(urlMapping='/barncrm/payments/v1/*')
global with sharing class PaymentWebhookRest {
	/** Bodies over this are refused: processor events are a few kilobytes. */
	@TestVisible
	private static final Integer MAX_BYTES = 65536;
	/** Events stored in the last hour before more are refused (a processor retries later). */
	@TestVisible
	private static final Integer HOURLY_LIMIT = 500;
	private static final String CONTEXT = 'PaymentWebhookRest';

	@HttpPost
	global static void receive() {
		RestResponse response = RestContext.response;
		response.addHeader('Content-Type', 'application/json');
		response.responseBody = Blob.valueOf('{}');
		try {
			response.statusCode = store(RestContext.request, Datetime.now().getTime() / 1000);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT);
			response.statusCode = 500;
		}
	}

	/** Stores the request as an event; returns the status code to answer. */
	@TestVisible
	private static Integer store(RestRequest request, Long nowSeconds) {
		String path = request.requestURI == null ? '' : request.requestURI.removeEnd('/');
		String processor = path.endsWith('/stripe')
			? PaymentService.STRIPE
			: (path.endsWith('/paypal') ? PaymentService.PAYPAL : null);
		if (processor == null) {
			return 404;
		}
		if (request.requestBody == null || request.requestBody.size() > MAX_BYTES) {
			return 400;
		}
		String raw = request.requestBody.toString();
		Map<String, Object> body = PaymentStripe.parse(raw);
		String eventId = PaymentStripe.text(body.get('id'));
		if (String.isBlank(eventId) || eventId.length() > 200) {
			return 400;
		}
		Payment_Event__c event = new Payment_Event__c(
			Processor__c = processor,
			Status__c = 'Received',
			Event_Id__c = eventId,
			Event_Type__c = PaymentStripe.text(
					body.get(processor == PaymentService.STRIPE ? 'type' : 'event_type')
				)
				?.left(100),
			Payload__c = raw
		);
		if (processor == PaymentService.STRIPE) {
			if (!PaymentStripe.verify(raw, header(request, 'stripe-signature'), nowSeconds)) {
				return 400;
			}
			event.Event_Key__c = 'stripe:' + eventId;
		} else {
			Map<String, String> kept = new Map<String, String>();
			for (String name : PaymentPayPal.HEADERS) {
				String value = header(request, name);
				if (String.isBlank(value) || value.length() > 700) {
					return 400;
				}
				kept.put(name, value);
			}
			event.Headers__c = JSON.serialize(kept);
		}
		Datetime hourAgo = Datetime.now().addHours(-1);
		if (
			[SELECT COUNT() FROM Payment_Event__c WHERE CreatedDate > :hourAgo WITH SYSTEM_MODE] >=
			HOURLY_LIMIT
		) {
			return 429;
		}
		Database.SaveResult saved = Database.insert(event, false, AccessLevel.SYSTEM_MODE);
		if (saved.isSuccess()) {
			return 200;
		}
		// The same event again: already stored, so the processor can stop sending it.
		return saved.getErrors()[0].getStatusCode() == StatusCode.DUPLICATE_VALUE ? 200 : 500;
	}

	/** A header by name, whatever its case. */
	private static String header(RestRequest request, String name) {
		for (String key : request.headers.keySet()) {
			if (key.equalsIgnoreCase(name)) {
				return request.headers.get(key);
			}
		}
		return null;
	}
}
