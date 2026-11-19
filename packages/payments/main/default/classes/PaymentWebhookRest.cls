/**
 * The webhook receiver (ADR-0201 `0201-payments-module.md`, decisions 4 and 5; R-PEV1, R-PEV3),
 * on the org's Salesforce Site for its guest user (`Payments_Webhook_Guest`):
 *
 *   POST <site URL>/services/apexrest/barncrm/payments/v1/stripe?token=<token>
 *   POST <site URL>/services/apexrest/barncrm/payments/v1/paypal?token=<token>
 *
 * The token is a random value BarnCRM makes (Payments Setup shows the full address, ADR-0229
 * amended); a post without it, or with another, is answered 404 and stores nothing.
 *
 * It only stores: one Payment Event, Received, in system mode (the guest has no object access),
 * and makes no callout, so the guest needs no credential to receive. Neither processor's post is
 * trusted: the processing job, as the admin who scheduled it, fetches a Stripe event back from
 * Stripe by its id through the `Barn_Stripe` Named Credential and uses only that copy, and asks
 * PayPal to verify a PayPal event (R-PEV2). Before that only cheap checks are possible, so a post
 * is refused while its processor is not connected, without an event id (Stripe: `evt_...`), or
 * (PayPal) without every signing header or a resource, and one of a type the job does not act on
 * is answered 200 and not stored. A Stripe event is stored under its unique key, so a resend is a
 * duplicate and answered 200. The hourly cap is per processor. It reads no record, returns no
 * identifier and answers every outcome with an empty body.
 *
 * `global` because the platform requires it of a REST resource.
 */
@RestResource(urlMapping='/barncrm/payments/v1/*')
global with sharing class PaymentWebhookRest {
	/** Bodies over this are refused: processor events are a few kilobytes. */
	@TestVisible
	private static final Integer MAX_BYTES = 65536;
	/** One processor's events stored in the last hour before more are refused (it retries later). */
	@TestVisible
	private static final Integer HOURLY_LIMIT = 500;
	private static final String CONTEXT = 'PaymentWebhookRest';

	@HttpPost
	global static void receive() {
		RestResponse response = RestContext.response;
		response.addHeader('Content-Type', 'application/json');
		response.responseBody = Blob.valueOf('{}');
		try {
			response.statusCode = store(RestContext.request);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT);
			response.statusCode = 500;
		}
	}

	/** Stores the request as an event; returns the status code to answer. */
	@TestVisible
	private static Integer store(RestRequest request) {
		String path = request.requestURI == null ? '' : request.requestURI.removeEnd('/');
		String processor = path.endsWith('/stripe')
			? PaymentService.STRIPE
			: (path.endsWith('/paypal') ? PaymentService.PAYPAL : null);
		if (processor == null || !PaymentService.tokenMatches(request.params.get('token'))) {
			return 404;
		}
		if (request.requestBody == null || request.requestBody.size() > MAX_BYTES) {
			return 400;
		}
		// An unconnected processor has nothing to check an event against: anything posted is refused.
		if (!PaymentService.isReady(processor)) {
			return 400;
		}
		String raw = request.requestBody.toString();
		Map<String, Object> body = PaymentStripe.parse(raw);
		String eventId = PaymentStripe.text(body.get('id'));
		if (
			String.isBlank(eventId) ||
			eventId.length() > 200 ||
			(processor == PaymentService.STRIPE && !eventId.startsWith('evt_'))
		) {
			return 400;
		}
		if (processor == PaymentService.PAYPAL) {
			if (!(body.get('resource') instanceof Map<String, Object>)) {
				return 400;
			}
		}
		// A type the processing job does not act on is acknowledged and not stored.
		Set<String> acted = processor == PaymentService.PAYPAL ? PaymentPayPal.EVENT_TYPES : PaymentStripe.EVENT_TYPES;
		if (!acted.contains(PaymentStripe.text(body.get(processor == PaymentService.STRIPE ? 'type' : 'event_type')))) {
			return 200;
		}
		Payment_Event__c event = new Payment_Event__c(
			Processor__c = processor,
			Status__c = 'Received',
			Event_Id__c = eventId,
			Event_Type__c = PaymentStripe.text(body.get(processor == PaymentService.STRIPE ? 'type' : 'event_type'))
				?.left(100),
			Payload__c = raw
		);
		if (processor == PaymentService.STRIPE) {
			// Keyed on arrival so a resend is dropped; the job keys it again from Stripe's copy.
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
		// Counted per processor, so posts to one address never hold up the other's events.
		Datetime hourAgo = Datetime.now().addHours(-1);
		if (
			[
				SELECT COUNT()
				FROM Payment_Event__c
				WHERE CreatedDate > :hourAgo AND Processor__c = :processor
				WITH SYSTEM_MODE
			] >= HOURLY_LIMIT
		) {
			if (PaymentService.noteCapHit()) {
				ErrorLogger.logMessage(
					'The Payments receiver reached its hourly limit of ' +
						HOURLY_LIMIT +
						' events for ' +
						processor +
						' and is refusing more until the hour passes.',
					CONTEXT,
					ErrorLogger.SEVERITY_WARNING
				);
			}
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
